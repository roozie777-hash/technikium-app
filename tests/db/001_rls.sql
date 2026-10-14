begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

-- Isolate local fixtures, including installations that already contain seed data.
-- Every deletion and grant change is rolled back at the end of this file.
truncate public.content_exercise_answers, public.attempts, public.progress,
  public.xp_ledger, public.streaks, public.profiles, public.content_exercises,
  public.content_lessons, public.content_units;

-- Synthetic identities only; no real e-mails, tokens, or answer submissions.
insert into auth.users (id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002');
insert into public.profiles (id, username) values
  ('10000000-0000-0000-0000-000000000001', 'tester_a'),
  ('10000000-0000-0000-0000-000000000002', 'tester_b');
insert into public.content_units (id, title, position, is_published, published_at)
values ('20000000-0000-0000-0000-000000000001', 'Jednostka testowa', 1, true, now());
insert into public.content_lessons (id, unit_id, title, position, is_published, published_at)
values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
  'Lekcja testowa', 1, true, now());
insert into public.content_exercises (id, lesson_id, exercise_type, position, payload, is_published, published_at)
values ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001',
  'multiple_choice', 1, '{"prompt":"Wybierz opcję testową","options":[{"id":"a","text":"Opcja A"},{"id":"b","text":"Opcja B"}]}', true, now());
insert into public.content_exercise_answers (exercise_id, answer, explanation)
values ('40000000-0000-0000-0000-000000000001', '"a"', 'Wyjaśnienie testowe bez treści dydaktycznej.');
insert into public.progress (user_id, lesson_id)
select id, '30000000-0000-0000-0000-000000000001' from public.profiles;
insert into public.attempts (user_id, exercise_id, is_correct)
select id, '40000000-0000-0000-0000-000000000001', false from public.profiles;
insert into public.xp_ledger (user_id, amount, reason)
select id, 10, 'test_fixture' from public.profiles;
insert into public.streaks (user_id) select id from public.profiles;

select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
  and c.relname in ('profiles','progress','attempts','xp_ledger','streaks',
    'content_units','content_lessons','content_exercises','content_exercise_answers')),
  9::bigint, 'all nine tables have RLS enabled');
select is((select count(*) from pg_policies where schemaname = 'public'
  and tablename = 'content_exercise_answers' and cmd in ('SELECT', 'ALL')),
  0::bigint, 'answer table has no client SELECT policy');

-- Exercise both directions, with a real client role and request identity.
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is((select count(*) from public.profiles), 1::bigint, 'A sees only own profile');
select is((select count(*) from public.progress), 1::bigint, 'A sees only own progress');
select is((select count(*) from public.attempts), 1::bigint, 'A sees only own attempts');
select is((select count(*) from public.xp_ledger), 1::bigint, 'A sees only own XP');
select is((select count(*) from public.streaks), 1::bigint, 'A sees only own streak');
select is((select count(*) from public.profiles where id = '10000000-0000-0000-0000-000000000002'),
  0::bigint, 'A cannot read B profile');
select is((select count(*) from public.progress where user_id = '10000000-0000-0000-0000-000000000002'),
  0::bigint, 'A cannot read B progress');
select is((select count(*) from public.attempts where user_id = '10000000-0000-0000-0000-000000000002'),
  0::bigint, 'A cannot read B attempts');
select is((select count(*) from public.xp_ledger where user_id = '10000000-0000-0000-0000-000000000002'),
  0::bigint, 'A cannot read B XP');
select is((select count(*) from public.streaks where user_id = '10000000-0000-0000-0000-000000000002'),
  0::bigint, 'A cannot read B streak');
select lives_ok($$update public.profiles set daily_goal = 'luzik', theme = 'dark', sound_muted = true
  where id = '10000000-0000-0000-0000-000000000001'$$, 'A can change own settings');
select is((select daily_goal from public.profiles), 'luzik', 'own settings actually changed');
with changed as (update public.profiles set theme = 'light'
  where id = '10000000-0000-0000-0000-000000000002' returning id)
select is((select count(*) from changed), 0::bigint, 'A cannot update B settings');
select throws_ok($$update public.profiles set username = 'changed'$$,
  '42501', null, 'username is not client-writable');
select throws_ok($$update public.profiles set id = '10000000-0000-0000-0000-000000000002'$$,
  '42501', null, 'profile owner is not client-writable');
select throws_ok($$update public.profiles set created_at = now()$$,
  '42501', null, 'profile creation date is not client-writable');
select throws_ok($$insert into public.profiles (id, username)
  values ('10000000-0000-0000-0000-000000000001', 'forged')$$,
  '42501', null, 'client cannot insert profiles');
select throws_ok($$delete from public.profiles$$, '42501', null, 'client cannot delete profiles');

-- Own-row and forged B writes must fail at the privilege boundary, not merely affect zero rows.
select throws_ok($$insert into public.progress (user_id, lesson_id) values
  ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'client cannot insert own progress');
select throws_ok($$insert into public.attempts (user_id, exercise_id, is_correct) values
  ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',true)$$,
  '42501', null, 'client cannot insert own attempts');
select throws_ok($$insert into public.xp_ledger (user_id, amount, reason) values
  ('10000000-0000-0000-0000-000000000001',100,'forged')$$,
  '42501', null, 'client cannot insert own XP');
select throws_ok($$insert into public.streaks (user_id) values
  ('10000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'client cannot insert own streak');
select throws_ok(format('insert into public.progress (user_id, lesson_id) values (%L,%L)',
  '10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001'),
  '42501', null, 'client cannot insert B progress');
select throws_ok($$insert into public.attempts (user_id, exercise_id, is_correct) values
  ('10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001',true)$$,
  '42501', null, 'client cannot insert B attempts');
select throws_ok($$insert into public.xp_ledger (user_id, amount, reason) values
  ('10000000-0000-0000-0000-000000000002',100,'forged')$$,
  '42501', null, 'client cannot insert B XP');
select throws_ok($$insert into public.streaks (user_id) values
  ('10000000-0000-0000-0000-000000000002')$$,
  '42501', null, 'client cannot insert B streak');

select throws_ok(format('update public.%I set %I = %s where user_id = %L', tab, col, val, uid),
  '42501', null, format('client cannot update %s for %s', tab, label))
from (values ('progress','status',quote_literal('completed')),
  ('attempts','is_correct','true'), ('xp_ledger','amount','999'), ('streaks','hearts','0')) t(tab,col,val)
cross join (values ('10000000-0000-0000-0000-000000000001','A'),
  ('10000000-0000-0000-0000-000000000002','B')) u(uid,label);
select throws_ok(format('delete from public.%I', tab), '42501', null,
  format('client cannot delete %s', tab))
from (values ('progress'),('attempts'),('xp_ledger'),('streaks')) t(tab);

select is((select count(*) from public.content_units), 1::bigint, 'published unit readable');
select is((select count(*) from public.content_lessons), 1::bigint, 'published lesson readable');
select is((select count(*) from public.content_exercises), 1::bigint, 'published exercise readable');
-- Inspect the actual client SELECT result, including nested payload data.
select ok(not exists (
  select 1 from public.content_exercises e
  where jsonb_path_exists(e.payload,
    '$.**.keyvalue() ? (@.key like_regex "^(answers?|correct.*|is_?correct|solution|explanation|tolerance|accepted.*|expected.*)$" flag "i")',
    '{}'::jsonb, true)
), 'client exercise payload has no solution fields');
select is((select payload ->> 'prompt' from public.content_exercises),
  'Wybierz opcję testową', 'client payload assertion covers an actual visible row');
select throws_ok('select * from public.content_exercise_answers', '42501', null, 'client cannot read answer table');
select throws_ok('update public.content_units set is_published = false', '42501', null, 'client cannot update units');
select throws_ok('update public.content_lessons set is_published = false', '42501', null, 'client cannot update lessons');
select throws_ok('update public.content_exercises set payload = ''{}''', '42501', null, 'client cannot update exercises');
select throws_ok('update public.content_exercise_answers set answer = ''null''', '42501', null, 'client cannot update answers');
select throws_ok('insert into public.content_units (title, position) values (''Fałszywa'',99)', '42501', null, 'client cannot insert units');
select throws_ok($$insert into public.content_lessons (unit_id,title,position) values
  ('20000000-0000-0000-0000-000000000001','Fałszywa',99)$$, '42501', null, 'client cannot insert lessons');
select throws_ok($$insert into public.content_exercises (lesson_id,exercise_type,position,payload) values
  ('30000000-0000-0000-0000-000000000001','multiple_choice',99,'{}')$$, '42501', null, 'client cannot insert exercises');
select throws_ok($$insert into public.content_exercise_answers (exercise_id,answer,explanation) values
  ('40000000-0000-0000-0000-000000000001','true','Fałszywe')$$, '42501', null, 'client cannot insert answers');
select throws_ok(format('delete from public.%I', tab), '42501', null, format('client cannot delete %s',tab))
from (values ('content_units'),('content_lessons'),('content_exercises'),('content_exercise_answers')) t(tab);

reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select is((select username from public.profiles), 'tester_b', 'B sees own profile, not A');
select is((select count(*) from public.progress where user_id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'B cannot read A progress');
select is((select count(*) from public.attempts where user_id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'B cannot read A attempts');
select is((select count(*) from public.xp_ledger where user_id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'B cannot read A XP');
select is((select count(*) from public.streaks where user_id = '10000000-0000-0000-0000-000000000001'), 0::bigint, 'B cannot read A streak');
with changed as (update public.profiles set theme = 'light'
  where id = '10000000-0000-0000-0000-000000000001' returning id)
select is((select count(*) from changed), 0::bigint, 'B cannot update A settings');
reset role;
select is((select theme from public.profiles where username = 'tester_b'), 'system', 'B profile remained unchanged');
select is((select theme from public.profiles where username = 'tester_a'), 'dark', 'A profile remained unchanged by B');

-- Independently exercise WITH CHECK: even an accidental wider column grant
-- cannot transfer a visible profile to another (unused) auth identity.
insert into auth.users (id) values ('10000000-0000-0000-0000-000000000003');
grant update (id) on public.profiles to authenticated;
set local role authenticated;
select throws_ok($$update public.profiles set id = '10000000-0000-0000-0000-000000000003'
  where id = '10000000-0000-0000-0000-000000000002'$$,
  '42501', null, 'profile WITH CHECK prevents ownership transfer');
reset role;
revoke update (id) on public.profiles from authenticated;

-- Publication inheritance: own exercise flag is insufficient.
update public.content_units set is_published = false;
set local role authenticated;
select is((select count(*) from public.content_units), 0::bigint, 'draft unit hidden');
select is((select count(*) from public.content_lessons), 0::bigint, 'draft unit hides published lesson');
select is((select count(*) from public.content_exercises), 0::bigint, 'draft unit hides published exercise');
reset role;
update public.content_units set is_published = true;
update public.content_lessons set is_published = false;
set local role authenticated;
select is((select count(*) from public.content_lessons), 0::bigint, 'draft lesson hidden');
select is((select count(*) from public.content_exercises), 0::bigint, 'draft lesson hides published exercise');
reset role;
update public.content_lessons set is_published = true;
update public.content_exercises set is_published = false;
set local role authenticated;
select is((select count(*) from public.content_exercises), 0::bigint, 'draft exercise hidden');
reset role;

-- Even accidentally granting SELECT must not expose private rows to anon.
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(format('select * from public.%I', tab), '42501', null,
  format('anonymous SELECT denied on %s', tab))
from (values ('profiles'),('progress'),('attempts'),('xp_ledger'),('streaks'),
  ('content_units'),('content_lessons'),('content_exercises'),('content_exercise_answers'),('leaderboard_weekly')) t(tab);
select throws_ok('select * from public.get_leaderboard_weekly()', '42501', null, 'anonymous cannot bypass ranking view with RPC');
reset role;
grant select on public.profiles, public.progress, public.attempts, public.xp_ledger,
  public.streaks, public.content_units, public.content_lessons, public.content_exercises,
  public.content_exercise_answers to anon;
grant select on public.content_exercise_answers to authenticated;
set local role anon;
select is((select count(*) from public.profiles), 0::bigint, 'RLS itself hides anonymous profiles');
select is((select count(*) from public.progress), 0::bigint, 'RLS itself hides anonymous progress');
select is((select count(*) from public.attempts), 0::bigint, 'RLS itself hides anonymous attempts');
select is((select count(*) from public.xp_ledger), 0::bigint, 'RLS itself hides anonymous XP');
select is((select count(*) from public.streaks), 0::bigint, 'RLS itself hides anonymous streaks');
select is((select count(*) from public.content_units), 0::bigint, 'RLS itself hides anonymous units');
select is((select count(*) from public.content_lessons), 0::bigint, 'RLS itself hides anonymous lessons');
select is((select count(*) from public.content_exercises), 0::bigint, 'RLS itself hides anonymous exercises');
select is((select count(*) from public.content_exercise_answers), 0::bigint, 'RLS itself hides anonymous answers');
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is((select count(*) from public.content_exercise_answers), 0::bigint, 'answer RLS denies authenticated SELECT even with an accidental grant');
reset role;

select * from finish();
rollback;
