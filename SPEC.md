# SPEC.md - Technikium

Status: v2 (online, with backend). Read `AGENTS.md` for working rules.

## 1. Product

A Duolingo-style learning platform for first and second year electrical engineering, electronics and automation students. Each lesson is 8-12 short exercises. Users earn XP, keep a daily streak, lose hearts for wrong answers, and compete on a weekly leaderboard.

Goals for the MVP:
- Register, log in, and continue learning on any device with the same progress.
- Complete two Units of content (see section 6).
- Feel close to Duolingo in flow and visual language, but with its own brand (purple, original mascot).

Out of scope for the MVP: payments, social features beyond the leaderboard, native mobile apps, teacher accounts, user-generated content, streak freezes, gems shop.

Language: all UI text and all content is Polish, using Polish university electronics terminology (e.g. "prawo Ohma", "dzielnik napięcia", "wzmacniacz operacyjny", "tranzystor MOSFET").

## 2. Architecture

- Frontend: static single-page app, Vite + vanilla JavaScript (ES modules), HTML and CSS.
- Backend: Supabase (managed Postgres, Auth, Row Level Security). No custom server in the MVP.
- Hosting: any static host over HTTPS (Netlify, Vercel or GitHub Pages).
- Trusted logic: XP, hearts, streaks, answer checking and leaderboard totals live in Postgres functions and views, never only in the browser.
- Local cache: localStorage may cache the last known progress for fast startup. The database is the source of truth. Writes made while offline are queued and synced when the connection returns.
- Supabase client: `@supabase/supabase-js`, pinned to an exact version.

## 3. Accounts and authentication

Screens:
- Welcome: "ZAREJESTRUJ SIĘ" (primary) and "MAM JUŻ KONTO" (secondary). Shown when there is no session.
- Register: username, e-mail, password, repeat password, show/hide password toggle. Username: 3-20 characters, letters, digits and underscore, unique. Password: at least 8 characters. Passwords must match.
- After registration: "Sprawdź skrzynkę e-mail, aby potwierdzić konto", with a "Wyślij ponownie" button and a cooldown.
- Log in: e-mail and password, "Zaloguj". Error text is always generic: "Nieprawidłowy e-mail lub hasło".
- Password reset: "Nie pamiętam hasła" sends a reset e-mail, followed by a reset screen.
- Log out: in Profil, with a confirmation dialog.
- Delete account: in Profil, requires re-entering the password. Removes the auth user and, through cascade, all user data.

Rules:
- Supabase Auth handles password storage. The app never stores or logs passwords.
- E-mail confirmation is required before first login.
- Session refresh is automatic. Log out clears the session everywhere.
- Auth screens block the app: no lesson, leaderboard or profile without a confirmed session.
- Forms are keyboard accessible: Enter submits, errors are linked to inputs with `aria-describedby`.

## 4. Data model

All nine tables live in the `public` schema and have RLS enabled. IDs are UUIDs;
content IDs and event IDs default to `gen_random_uuid()`. Timestamps are
`timestamptz` (stored as instants, independent of session timezone).

- `profiles`: `id` (references auth.users, primary key), `username` (3-20 letters, digits or underscores; unique through an index on `lower(username)`), `created_at` (defaults to now), `daily_goal` (luzik, regularnie, powazne, intensywnie; default regularnie), `theme` (light, dark, system; default system), `sound_muted` (boolean, default false). Username is set by trusted registration logic and cannot be changed by the client. Registration logic is outside the section 4 implementation.
- `progress`: `user_id`, `lesson_id`, `status` (locked, available, completed; default locked), `best_accuracy` (nullable numeric, 0-100), `completed_at` (nullable). Primary key (user_id, lesson_id).
- `attempts`: append-only answer log: `id` (primary key), `user_id`, `exercise_id`, `is_correct`, `answered_at` (defaults to now). Used by the "Błędy" review mode. Does not store submitted answers.
- `xp_ledger`: append-only XP events: `id` (primary key), `user_id`, `amount` (positive integer), `reason` (nonempty text), `created_at` (defaults to now). Total XP is a sum of this table.
- `streaks`: `user_id` (primary key), `current_streak` (nonnegative, default 0), `longest_streak` (at least current_streak, default 0), `last_activity_date` (nullable Europe/Warsaw date), `hearts` (0-5, default 5), `hearts_updated_at` (timestamptz, defaults to now), `gems` (nonnegative integer, default 0). Regeneration will use hearts_updated_at in section 5; it is not implemented in section 4.
- `content_units`: `id` (primary key), `title` (nonempty), `description` (default empty string), `position` (positive integer, globally unique), `is_published` (default false), `published_at` (nullable).
- `content_lessons`: `id` (primary key), `unit_id`, `title` (nonempty), `position` (positive integer), `is_published` (default false), `published_at`. Unique (unit_id, position).
- `content_exercises`: `id` (primary key), `lesson_id`, `exercise_type` (multiple_choice, pick_diagram, match_pairs, arrange_tokens, fill_blank, numeric_calculation, true_false, spot_error), `position` (positive integer), `payload` (jsonb object), `is_published` (default false), `published_at`. Unique (lesson_id, position).
- `content_exercise_answers`: `exercise_id` (primary key), `answer` (non-null jsonb, including server-only matching rules/tolerance), `explanation` (nonempty text). No independent publication flags: publication is determined by the exercise and its ancestors. The future submit_answer function reads this table as its owner.

All private user references point to auth.users with `on delete cascade`.
All content foreign keys, including progress.lesson_id and attempts.exercise_id,
use `on delete restrict`. A published content row requires published_at;
unpublishing may retain the timestamp. Content order unique indexes cover parent
foreign keys; additional indexes cover progress.lesson_id, attempts.exercise_id,
attempts(user_id, answered_at), xp_ledger(user_id, created_at), and
xp_ledger(created_at, user_id) including amount.

Public exercise payloads contain prompts, options and diagrams, never solution
metadata. A recursive JSON key constraint rejects answer/answers, correct*,
is_correct/isCorrect, solution, explanation, tolerance, accepted* and expected*
(case-insensitively). This is defense in depth, not a substitute for reviewing
seed content: arbitrary text or differently named fields can encode an answer.
Per-type payload/answer formats will be documented when content seeds are added.

View `leaderboard_weekly` exposes exactly `username text` and `xp bigint`.
It uses `security_invoker = true` over the no-argument `get_leaderboard_weekly()`
SQL function, which uses `security definer`, an empty fixed search_path and
schema-qualified relations. Only authenticated clients can execute the function;
without auth.uid() it returns no rows. This intentionally allows aggregate
cross-user ranking without granting access to other users' raw XP or profiles.
The current ISO week starts at
`date_trunc('week', now() at time zone 'Europe/Warsaw')`. Both local boundaries
are independently converted to timestamptz; the range includes the start and
excludes the next Monday. Results are ordered by XP descending, then
`min(created_at)` within that week, then username for a deterministic final tie.
The function exposes no IDs, e-mails, or internal tie-break timestamps.

### Row Level Security

- Own-row tables: authenticated clients can SELECT only their own rows (`profiles.id = auth.uid()`, or `user_id = auth.uid()` for other tables).
- `profiles`: UPDATE policy has both USING and WITH CHECK ownership conditions. Column privileges use `grant update (daily_goal, theme, sound_muted)`; no client INSERT or DELETE and no client modification of username, id or created_at.
- `progress`, `attempts`, `xp_ledger`, `streaks`: no client INSERT, UPDATE or DELETE privileges or write policies. Trusted database functions perform writes; those gameplay functions remain outside this implementation. Logs are append-only in normal gameplay; trusted reset/account deletion may remove them.
- `leaderboard_weekly`: readable by authenticated users only, with no client writes. The backing function has no PUBLIC or anon EXECUTE permission.
- Content: authenticated SELECT only for published units; lessons additionally require a published unit; exercises explicitly require a published exercise, lesson and unit. No client writes.
- `content_exercise_answers`: no client privileges and no SELECT/ALL policy. An explicit always-false INSERT policy documents denial; all client reads and writes remain denied.
- Table privileges are explicitly revoked from PUBLIC, anon and authenticated before the narrow grants above, overriding Supabase default grants.
- Tests in `tests/db/` cover each policy, A/B isolation, anonymous denial, direct client writes, publication inheritance, returned payloads, ranking columns, Warsaw week boundaries, and schema constraints. Tests use client database roles/JWT claims; HTTP/PostgREST behavior requires a separate integration check.

## 5. Game logic (database functions)

- `submit_answer(exercise_id, answer)`: checks the answer on the server, records the attempt, awards XP, updates hearts and streak, and returns: correct flag, correct answer, explanation, new XP, hearts. The correct answer is returned only after submission.
- `complete_lesson(lesson_id)`: checks the lesson is finished, awards the bonus for a perfect lesson, unlocks the next lesson, and updates progress.
- `reset_progress()`: clears progress, attempts, XP ledger and streak for the current user. Keeps the profile.
- Streak: one streak day per local calendar day (Europe/Warsaw). A fully missed day resets the streak.
- Hearts: maximum 5. A wrong answer costs one heart. One heart regenerates every 4 hours, calculated on the server from `hearts_updated_at`.
- Lesson failure: at 0 hearts the lesson ends with "Poćwicz, aby odzyskać serca". The user may practise a completed lesson to regain hearts.
- Wrong answers inside a lesson are re-queued at the end until answered correctly.
- Quitting mid-lesson keeps completed answers and gives no lesson bonus.
- Numeric answers: parsed and compared with the shared normalization rules in section 7.

## 6. Learning content

Start with exactly two Units, five lessons each, 8-12 exercises per lesson, with difficulty rising inside and across units.

- Unit 1: Obwody prądu stałego. Charge, current, voltage, resistance, Ohm's law, power and energy, series and parallel connections, voltage and current dividers, Kirchhoff's laws, Thevenin and Norton basics, capacitors and inductors in DC.
- Unit 2: Elementy półprzewodnikowe i układy analogowe. Semiconductors, diodes and their applications, LED, Zener diode, BJT and MOSFET basics and biasing, ideal op-amp, inverting and non-inverting amplifiers, simple filters.

Content rules:
- Every exercise has exactly one correct answer and a one-to-two sentence explanation.
- Content is technically correct, unambiguous, free of trick questions. Use E-series resistor values and realistic numbers.
- Every numeric answer is recomputed and covered by a unit test before seeding.
- Content is stored in the database via versioned seed files in `supabase/seed/`. The payload schema for each exercise type is documented at the top of the seed file.
- Adding a Unit is a data change, not a code change.

## 7. Exercise types

Implement all of them, each with its own UI and validation:

1. Multiple choice: 2-4 text options. Formulas render cleanly (HTML/CSS or inline SVG).
2. Pick the diagram: choose the correct circuit symbol, topology, waveform or logic gate. All diagrams are inline SVG.
3. Match pairs: term to definition, symbol to name, unit to quantity. Tap to pair, highlight on selection, shake on mismatch.
4. Arrange tokens: build a formula or sentence from shuffled chips, similar to Duolingo's word bank.
5. Fill in the blank: type a number with units, or pick from a chip bank.
6. Numeric calculation: a small circuit problem, the user types the result. Accepts variants such as "4,7k", "4.7 kΩ", "4700", and the Polish decimal comma. Uses the server-only tolerance defined in content_exercise_answers.answer.
7. True or false with a short justification.
8. Spot the error: an SVG schematic with a mistake (e.g. LED without resistor, reversed diode). The user clicks the faulty element.

Normalization (`src/lib/normalize.js`, mirrored in the database function, same test cases in `tests/normalize.test.js`):
- Replace decimal comma with dot.
- Accept SI prefixes k, M, m, µ, u, n, p with or without the unit symbol.
- Strip whitespace and the unit symbol (Ω, V, A, W, F, H).
- Compare with relative tolerance from content_exercise_answers.answer (default 1%).

JavaScript contract: `normalize(input)` returns a finite base-unit number or
`null` for invalid input; `isWithinRelativeTolerance(input, expected, tolerance)`
uses that same parser for both values. SI prefixes are case-sensitive. Parsing
accepts signed decimal strings or finite numbers, and rejects malformed strings,
unsupported units/prefixes and scientific notation. Unit symbols are stripped;
dimensional validation is not part of this parser. Relative tolerance is a finite
nonnegative fraction (0.01 = 1%); its endpoints are inclusive with a machine-epsilon
roundoff allowance. A zero reference or zero tolerance requires exact equality.
Invalid inputs/tolerances return false. Tests live in `tests/normalize.test.js`.
Only the pure JavaScript helper is currently implemented; database mirroring
and authoritative answer checking remain pending section 5. Correct answers
must never be supplied to the browser to use this helper before submission.

## 8. Screens and layout

- Learning path: vertical zigzag of lesson nodes, grouped in Units with coloured banner headers. Node states: locked (grey), available (purple, pulsing, "START" bubble), completed (gold with checkmark), practice (crown). State is computed from `progress`.
- Desktop: left sidebar (Nauka, Ćwiczenia, Ranking, Misje, Profil) and right sidebar (streak, daily goal, XP progress, daily quest). Mobile: bottom tab bar.
- Top bar: streak flame, gems, XP, hearts. Values come from the server.
- Lesson screen: thin rounded progress bar, X to quit, bottom action bar with "SPRAWDŹ". Green or red feedback sheet with explanation and "DALEJ".
- Lesson end: XP earned, accuracy, time, confetti, mascot celebration.
- Leaderboard: weekly XP ranking. Ties broken by the earliest XP event. The user's own position is always shown, even outside the top list.
- Profile: daily goal (Luzik, Regularnie, Poważnie, Intensywnie), theme, mute, reset progress, log out, delete account.

## 9. Visual design

- Duolingo-like: rounded, chunky, friendly. Bold rounded sans-serif (Nunito or a system fallback). Large buttons with a 3D bottom border that depresses on click. 2px light-grey card borders. Generous spacing.
- Palette: primary purple around #7B3FF2 / #8A4DFF, darker #5B2BC4 for button edges, lavender backgrounds, white cards. Green for correct, red for wrong, gold for completed and crowns, orange for the streak flame.
- Micro-interactions: button press, option bounce on select, shake on wrong answer, pop on correct, progress bar fill, confetti on lesson complete. Respect `prefers-reduced-motion`.
- Sounds: WebAudio-generated, no audio files. Select, correct, wrong, combo, lesson complete, unlock. Mute toggle. Audio starts only after the first user interaction.
- Themes: light by default, dark mode toggle, first launch follows `prefers-color-scheme`. Diagrams and mascot use `currentColor` and CSS variables.
- Responsive: desktop, tablet and mobile layouts. Keyboard: Enter for Sprawdź and Dalej, keys 1-4 select options.
- Accessibility: WCAG AA contrast, visible focus states.

## 10. Mascot

An original friendly mascot (e.g. a purple owl or robot with a hard hat and safety goggles). Drawn as inline SVG. Expressions: happy, cheering, sad, thinking. Idle animations: blink and bob. Must not resemble Duolingo's owl or logo.

## 11. Privacy and security

- Collected data: e-mail, username, learning data. Nothing else.
- A privacy policy and terms (Polish and English) must be published before launch. Account deletion must be described there.
- No e-mail or user id is shown publicly.
- Auth endpoints use Supabase rate limits. `submit_answer` rejects bursts of more than a few requests per second per user.
- Logs never contain tokens, passwords, e-mails, or answers linked to user ids.
- Backups: daily Supabase backups enabled, or a documented manual export.
- Separate Supabase projects for `dev` and `prod`. Schema changes only through migrations in `supabase/migrations/`.

## 12. Acceptance criteria (MVP)

- A new user can register, confirm e-mail, log in, complete one lesson, and see the progress on a second browser.
- Each exercise type works end to end at least once.
- Hearts, streak rollover at local midnight, and leaderboard tie-break behave as specified in section 5.
- RLS tests pass: no user can read or write another user's private rows.
- No correct answer is visible in the network response before submission.
- Dark mode, mute, reset progress, and account deletion work.
- Offline writes are queued and sync after reconnection.
- Lighthouse accessibility score and contrast checks pass on the main screens.
