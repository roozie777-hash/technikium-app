begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
truncate public.content_exercise_answers, public.attempts, public.progress,
  public.xp_ledger, public.streaks, public.profiles, public.content_exercises,
  public.content_lessons, public.content_units;

insert into auth.users (id) values
  ('10000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003');
insert into public.profiles (id, username) values
  ('10000000-0000-0000-0000-000000000001', 'tester_a'),
  ('10000000-0000-0000-0000-000000000002', 'tester_b'),
  ('10000000-0000-0000-0000-000000000003', 'tester_c');

-- Derive wall-clock fixtures from the current week, independent of test date.
-- Include both Sunday/Monday edges; the half-open upper bound is important.
with week as (select date_trunc('week', now() at time zone 'Europe/Warsaw') as start)
insert into public.xp_ledger (user_id, amount, reason, created_at)
select '10000000-0000-0000-0000-000000000001', amount, 'test_fixture',
  (start + delta) at time zone 'Europe/Warsaw'
from week cross join (values
  (1000, interval '-1 minute'),                 -- Previous Sunday 23:59: excluded.
  (7, interval '1 minute'),                     -- Monday 00:01: included.
  (3, interval '6 days 23 hours 59 minutes'),   -- Sunday 23:59: included.
  (2000, interval '7 days 1 minute')            -- Next Monday 00:01: excluded.
) event(amount, delta);
with week as (select date_trunc('week', now() at time zone 'Europe/Warsaw') as start)
insert into public.xp_ledger (user_id, amount, reason, created_at)
select '10000000-0000-0000-0000-000000000002', 10, 'test_fixture',
  (start + interval '2 minutes') at time zone 'Europe/Warsaw' from week;
with week as (select date_trunc('week', now() at time zone 'Europe/Warsaw') as start)
insert into public.xp_ledger (user_id, amount, reason, created_at)
select '10000000-0000-0000-0000-000000000003', 20, 'test_fixture',
  (start + interval '3 minutes') at time zone 'Europe/Warsaw' from week;

select results_eq($$select to_jsonb(column_name::text) from information_schema.columns
  where table_schema = 'public' and table_name = 'leaderboard_weekly' order by ordinal_position$$,
  $$values ('"username"'::jsonb), ('"xp"'::jsonb)$$, 'ranking columns are exactly username and XP');
select ok((select reloptions @> array['security_invoker=true']
  from pg_class where oid = 'public.leaderboard_weekly'::regclass), 'view uses invoker permissions');
select ok((select prosecdef and proconfig @> array['search_path=""']
  from pg_proc where oid = 'public.get_leaderboard_weekly()'::regprocedure),
  'ranking function uses definer permissions and a fixed empty search path');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is((select count(*) from public.xp_ledger), 4::bigint, 'raw ledger still exposes only A rows');
select results_eq('select to_jsonb(r) from public.leaderboard_weekly r',
  $$values ('{"username":"tester_c","xp":20}'::jsonb),
    ('{"username":"tester_a","xp":10}'::jsonb),
    ('{"username":"tester_b","xp":10}'::jsonb)$$,
  'ranking includes others, sums only Warsaw week and breaks ties by earliest weekly event');
select results_eq('select to_jsonb(r) from public.leaderboard_weekly r order by username',
  $$values ('{"username":"tester_a","xp":10}'::jsonb),
    ('{"username":"tester_b","xp":10}'::jsonb),
    ('{"username":"tester_c","xp":20}'::jsonb)$$,
  'actual client response contains only username and XP, without IDs or e-mails');
select throws_ok('select user_id from public.leaderboard_weekly', '42703', null, 'ranking has no user ID');
select throws_ok('select email from public.leaderboard_weekly', '42703', null, 'ranking has no e-mail');
select throws_ok('select id from public.leaderboard_weekly', '42703', null, 'ranking has no profile ID');
select ok(not has_table_privilege(current_user, 'public.leaderboard_weekly', 'update'),
  'client has no ranking UPDATE privilege');
select throws_ok('update public.leaderboard_weekly set xp = 100', '55000', null,
  'ranking view is not updatable');

-- A server/session timezone change must not move the Warsaw boundary.
set local timezone = 'Pacific/Honolulu';
select is((select xp from public.leaderboard_weekly where username = 'tester_a'),
  10::bigint, 'Warsaw Sunday 23:59 / Monday 00:01 boundary ignores session timezone');
reset role;

-- Explicit DST examples check conversion of both endpoints, not a fixed UTC duration.
select is((timestamp '2026-03-30 00:00' at time zone 'Europe/Warsaw') -
  (timestamp '2026-03-23 00:00' at time zone 'Europe/Warsaw'),
  interval '167 hours', 'spring Warsaw week spans 167 UTC hours');
select is((timestamp '2026-10-26 00:00' at time zone 'Europe/Warsaw') -
  (timestamp '2026-10-19 00:00' at time zone 'Europe/Warsaw'),
  interval '169 hours', 'autumn Warsaw week spans 169 UTC hours');

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select is((select count(*) from public.leaderboard_weekly), 0::bigint, 'missing identity gives no ranking rows');
reset role;
set local role anon;
select throws_ok('select * from public.leaderboard_weekly', '42501', null, 'anonymous ranking access denied');
select throws_ok('select * from public.get_leaderboard_weekly()', '42501', null, 'anonymous ranking RPC denied');
reset role;
select * from finish();
rollback;
