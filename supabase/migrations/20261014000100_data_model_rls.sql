begin;

create table public.content_units (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  description text not null default '',
  position integer not null unique check (position > 0),
  is_published boolean not null default false,
  published_at timestamptz,
  check (not is_published or published_at is not null)
);

create table public.content_lessons (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.content_units(id) on delete restrict,
  title text not null check (length(trim(title)) > 0),
  position integer not null check (position > 0),
  is_published boolean not null default false,
  published_at timestamptz,
  unique (unit_id, position),
  check (not is_published or published_at is not null)
);

create table public.content_exercises (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.content_lessons(id) on delete restrict,
  exercise_type text not null check (exercise_type in (
    'multiple_choice', 'pick_diagram', 'match_pairs', 'arrange_tokens',
    'fill_blank', 'numeric_calculation', 'true_false', 'spot_error'
  )),
  position integer not null check (position > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  is_published boolean not null default false,
  published_at timestamptz,
  unique (lesson_id, position),
  check (not is_published or published_at is not null),
  -- Defense in depth: also inspect keys inside nested objects and arrays.
  -- Seed review must still ensure that prompts/options do not encode solutions.
  constraint payload_has_no_answer_fields check (not jsonb_path_exists(
    payload,
    '$.**.keyvalue() ? (@.key like_regex "^(answers?|correct.*|is_?correct|solution|explanation|tolerance|accepted.*|expected.*)$" flag "i")',
    '{}'::jsonb, true
  ))
);

create table public.content_exercise_answers (
  exercise_id uuid primary key references public.content_exercises(id) on delete restrict,
  answer jsonb not null check (answer <> 'null'::jsonb),
  explanation text not null check (length(trim(explanation)) > 0)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (
    char_length(username) between 3 and 20 and username ~ '^[[:alnum:]_]+$'
  ),
  created_at timestamptz not null default now(),
  daily_goal text not null default 'regularnie'
    check (daily_goal in ('luzik', 'regularnie', 'powazne', 'intensywnie')),
  theme text not null default 'system' check (theme in ('light', 'dark', 'system')),
  sound_muted boolean not null default false
);
create unique index profiles_username_lower_key on public.profiles (lower(username));

create table public.progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references public.content_lessons(id) on delete restrict,
  status text not null default 'locked' check (status in ('locked', 'available', 'completed')),
  best_accuracy numeric check (best_accuracy between 0 and 100),
  completed_at timestamptz,
  primary key (user_id, lesson_id)
);
create index progress_lesson_id_idx on public.progress (lesson_id);

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_id uuid not null references public.content_exercises(id) on delete restrict,
  is_correct boolean not null,
  answered_at timestamptz not null default now()
);
create index attempts_user_answered_idx on public.attempts (user_id, answered_at desc);
create index attempts_exercise_id_idx on public.attempts (exercise_id);

create table public.xp_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check (amount > 0),
  reason text not null check (length(trim(reason)) > 0),
  created_at timestamptz not null default now()
);
create index xp_ledger_user_created_idx on public.xp_ledger (user_id, created_at);
create index xp_ledger_created_user_idx on public.xp_ledger (created_at, user_id) include (amount);

create table public.streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  longest_streak integer not null default 0 check (longest_streak >= current_streak),
  last_activity_date date,
  hearts integer not null default 5 check (hearts between 0 and 5),
  hearts_updated_at timestamptz not null default now(),
  gems integer not null default 0 check (gems >= 0)
);

alter table public.profiles enable row level security;
alter table public.progress enable row level security;
alter table public.attempts enable row level security;
alter table public.xp_ledger enable row level security;
alter table public.streaks enable row level security;
alter table public.content_units enable row level security;
alter table public.content_lessons enable row level security;
alter table public.content_exercises enable row level security;
alter table public.content_exercise_answers enable row level security;

-- Supabase default privileges may otherwise grant client writes automatically.
revoke all on public.profiles, public.progress, public.attempts, public.xp_ledger,
  public.streaks, public.content_units, public.content_lessons,
  public.content_exercises, public.content_exercise_answers from public, anon, authenticated;
grant select on public.profiles, public.progress, public.attempts, public.xp_ledger,
  public.streaks, public.content_units, public.content_lessons,
  public.content_exercises to authenticated;
grant update (daily_goal, theme, sound_muted) on public.profiles to authenticated;

create policy profiles_select_own on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy progress_select_own on public.progress for select to authenticated
  using (user_id = (select auth.uid()));
create policy attempts_select_own on public.attempts for select to authenticated
  using (user_id = (select auth.uid()));
create policy xp_ledger_select_own on public.xp_ledger for select to authenticated
  using (user_id = (select auth.uid()));
create policy streaks_select_own on public.streaks for select to authenticated
  using (user_id = (select auth.uid()));

create policy content_units_select_published on public.content_units
  for select to authenticated using (is_published);
create policy content_lessons_select_published on public.content_lessons
  for select to authenticated using (
    is_published and exists (
      select 1 from public.content_units u
      where u.id = unit_id and u.is_published
    )
  );
create policy content_exercises_select_published on public.content_exercises
  for select to authenticated using (
    is_published and exists (
      select 1 from public.content_lessons l
      join public.content_units u on u.id = l.unit_id
      where l.id = lesson_id and l.is_published and u.is_published
    )
  );
-- Deliberately no SELECT policy, including for authenticated clients.
-- Keep an explicit deny policy on this RLS-enabled table for auditability.
create policy content_exercise_answers_deny_insert on public.content_exercise_answers
  for insert to anon, authenticated with check (false);

create function public.get_leaderboard_weekly()
returns table (username text, xp bigint)
language sql stable security definer
set search_path = ''
as $$
  with week as (
    select date_trunc('week', now() at time zone 'Europe/Warsaw') as local_start
  )
  select p.username, sum(x.amount)::bigint as xp
  from public.xp_ledger x
  join public.profiles p on p.id = x.user_id
  cross join week w
  where (select auth.uid()) is not null
    and x.created_at >= (w.local_start at time zone 'Europe/Warsaw')
    and x.created_at < ((w.local_start + interval '1 week') at time zone 'Europe/Warsaw')
  group by p.id, p.username
  order by sum(x.amount) desc, min(x.created_at), p.username
$$;
revoke all on function public.get_leaderboard_weekly() from public, anon, authenticated;
grant execute on function public.get_leaderboard_weekly() to authenticated;

create view public.leaderboard_weekly with (security_invoker = true) as
  select username, xp from public.get_leaderboard_weekly();
revoke all on public.leaderboard_weekly from public, anon, authenticated;
grant select on public.leaderboard_weekly to authenticated;

commit;
