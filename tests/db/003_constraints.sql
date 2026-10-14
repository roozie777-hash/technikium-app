begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
truncate public.content_exercise_answers, public.attempts, public.progress,
  public.xp_ledger, public.streaks, public.profiles, public.content_exercises,
  public.content_lessons, public.content_units;

insert into auth.users (id) values ('10000000-0000-0000-0000-000000000001');
insert into auth.users (id) values ('10000000-0000-0000-0000-000000000002');
insert into public.profiles (id,username) values ('10000000-0000-0000-0000-000000000001','tester_a');
insert into public.content_units (id,title,position) values ('20000000-0000-0000-0000-000000000001','Jednostka testowa',1);
insert into public.content_lessons (id,unit_id,title,position) values
  ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Lekcja testowa',1);
insert into public.content_exercises (id,lesson_id,exercise_type,position,payload) values
  ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','multiple_choice',1,'{}');
insert into public.content_exercise_answers (exercise_id,answer,explanation) values
  ('40000000-0000-0000-0000-000000000001','"a"','Wyjaśnienie testowe.');
insert into public.progress (user_id,lesson_id,best_accuracy) values
  ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',0);
insert into public.attempts (user_id,exercise_id,is_correct) values
  ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',false);
insert into public.xp_ledger (user_id,amount,reason) values
  ('10000000-0000-0000-0000-000000000001',1,'test_fixture');
insert into public.streaks (user_id) values ('10000000-0000-0000-0000-000000000001');

select throws_ok($$insert into public.profiles (id,username) values
  ('10000000-0000-0000-0000-000000000002','TESTER_A')$$,
  '23505', null, 'username uniqueness ignores case');
select throws_ok('update public.profiles set username = ''ab''', '23514', null, 'username needs at least three characters');
select throws_ok('update public.profiles set daily_goal = ''unknown''', '23514', null, 'daily goal limited to allowed values');
select throws_ok('update public.profiles set theme = ''unknown''', '23514', null, 'theme limited to allowed values');

select throws_ok($$insert into public.content_units (title,position) values ('Druga',1)$$,
  '23505', null, 'unit positions unique globally');
select throws_ok($$insert into public.content_lessons (unit_id,title,position) values
  ('20000000-0000-0000-0000-000000000001','Druga',1)$$,
  '23505', null, 'lesson positions unique within unit');
select throws_ok($$insert into public.content_exercises (lesson_id,exercise_type,position,payload) values
  ('30000000-0000-0000-0000-000000000001','multiple_choice',1,'{}')$$,
  '23505', null, 'exercise positions unique within lesson');
-- PostgreSQL 18 distinguishes RESTRICT from generic FK violations (17: 23503).
select throws_ok('delete from public.content_units',
  case when current_setting('server_version_num')::integer >= 180000 then '23001' else '23503' end,
  null, 'unit deletion restricted by lesson');
select throws_ok('delete from public.content_lessons',
  case when current_setting('server_version_num')::integer >= 180000 then '23001' else '23503' end,
  null, 'lesson deletion restricted by exercise/progress');
select throws_ok('delete from public.content_exercises',
  case when current_setting('server_version_num')::integer >= 180000 then '23001' else '23503' end,
  null, 'exercise deletion restricted by answer/attempt');

select throws_ok(format('update public.%I set is_published = true', tab),
  '23514', null, format('%s publication requires published_at',tab))
from (values ('content_units'),('content_lessons'),('content_exercises')) t(tab);
select throws_ok(format('update public.content_exercises set payload = %L::jsonb', payload),
  '23514', null, format('solution field rejected: %s', label))
from (values
  ('{"answer":"a"}', 'answer'),
  ('{"correct_answer":"a"}', 'correct_answer'),
  ('{"options":[{"id":"a","is_correct":true}]}', 'nested is_correct'),
  ('{"options":[{"id":"a","isCorrect":true}]}', 'nested isCorrect'),
  ('{"nested":{"correctAnswer":"a"}}', 'nested correctAnswer'),
  ('{"explanation":"Ukryte"}', 'explanation'),
  ('{"tolerance":0.01}', 'tolerance'),
  ('[]', 'non-object payload')
) t(payload,label);
select throws_ok('update public.progress set best_accuracy = -1', '23514', null, 'accuracy cannot be negative');
select throws_ok('update public.progress set best_accuracy = 101', '23514', null, 'accuracy cannot exceed 100');
select lives_ok('update public.progress set best_accuracy = 100', 'accuracy accepts 100');
select throws_ok('update public.xp_ledger set amount = 0', '23514', null, 'XP must be positive');
select throws_ok('update public.streaks set hearts = 6', '23514', null, 'hearts cannot exceed five');
select throws_ok('update public.streaks set hearts = -1', '23514', null, 'hearts cannot be negative');
select throws_ok('update public.streaks set gems = -1', '23514', null, 'gems cannot be negative');
select throws_ok('update public.streaks set current_streak = 1', '23514', null, 'longest streak cannot be shorter than current');
select ok((select hearts_updated_at is not null from public.streaks), 'hearts regeneration timestamp initialized');
select is((select count(*) from information_schema.columns where table_schema = 'public'
  and table_name = 'content_exercise_answers' and column_name in ('is_published','published_at')),
  0::bigint, 'answers do not have independent publication');

-- Account deletion cascades through private records without deleting shared content.
delete from auth.users where id = '10000000-0000-0000-0000-000000000001';
select is((select count(*) from public.profiles), 0::bigint, 'account deletion removes profile');
select is((select count(*) from public.progress), 0::bigint, 'account deletion removes progress');
select is((select count(*) from public.attempts), 0::bigint, 'account deletion removes attempts');
select is((select count(*) from public.xp_ledger), 0::bigint, 'account deletion removes XP');
select is((select count(*) from public.streaks), 0::bigint, 'account deletion removes streak');
select is((select count(*) from public.content_exercises), 1::bigint, 'account deletion preserves shared content');
select * from finish();
rollback;
