# AGENTS.md

Instructions for coding agents working in this repository. Read this file first, then `SPEC.md` for the product and technical requirements, then `README.md` for setup.

## Project in one paragraph

Technikium is a Duolingo-style learning web app for electronics engineering students. Users are in Poland, so all UI text and lesson content is in Polish. Code identifiers and comments are in English. The backend is Supabase (Postgres, Auth, Row Level Security). The frontend is a static app built with Vite and vanilla JavaScript (ES modules).

## Setup and commands

Run these from the repository root. If a command is missing, add it to `package.json` and document it in `README.md`.

- Install: `npm install`
- Dev server: `npm run dev`
- Unit tests: `npm test`
- Build: `npm run build`
- Database tests (RLS and functions): `npm run test:db`. Requires a local Supabase instance (`npx supabase start`)
- End-to-end tests: `npm run test:e2e`

## Working rules

1. Read `SPEC.md` before changing behavior. If the spec and the request conflict, stop and ask the user. Do not silently pick one.
2. Work in small steps. For each step: plan briefly, implement, run the relevant tests, then report what changed.
3. Keep the spec in sync. If you change behavior, update `SPEC.md` in the same change.
4. Prefer editing existing files over creating new ones. Put frontend code in `src/`, static assets in `assets/`, database work in `supabase/migrations/` and `supabase/seed/`, and tests in `tests/`.
5. Every new migration is a new numbered file. Never edit a migration that has already been applied.
6. Write every user-facing string in Polish, in a single i18n module (`src/i18n/pl.js`), not inline in components.
7. Code comments and identifiers are in English.

## Hard boundaries (never do these)

- Never put the Supabase service role key in any file under `src/`, in `assets/`, in tests that run in the browser, in logs, or in commits. Only the public anon key and project URL may appear on the client, and they come from environment variables (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`).
- Never commit `.env` files or any secret. Keep `.env.example` with placeholder values only.
- Never send the correct answer of an exercise to the client before the user answers. Answer checking happens in the `submit_answer` database function.
- Never write XP, hearts, streak or leaderboard values from client code directly. These are written only through database functions.
- Never disable Row Level Security on any table. A new table without RLS policies is a bug.
- Never store passwords, password hashes or e-mails in localStorage or in logs.
- Do not add a custom backend server in the MVP. Do not add a framework other than Vite and vanilla JS without asking first.
- Do not copy Duolingo's owl, logo or assets. The mascot must be original.

## Conventions

- JavaScript: ES modules, no `var`, small functions, JSDoc on exported functions.
- CSS: CSS variables for theme colors (light and dark), no hard-coded colors in components.
- SVG diagrams: inline SVG using `currentColor` so they stay readable in both themes.
- Dates: store in UTC in the database. Compute streak days in Europe/Warsaw.
- Numeric answers: all parsing and tolerance checks use one shared normalization function, in `src/lib/normalize.js` and mirrored in the database function. Both must pass the same test cases in `tests/normalize.test.js`.
- SQL: lowercase keywords, snake_case names, every table has RLS enabled and policies in the same migration.

## Definition of done

A task is done only when all of these are true:

- The relevant tests pass (`npm test`, and `npm run test:db` if the database changed)
- `npm run build` succeeds with no warnings about errors
- No console errors in the browser for the changed screens
- New user-facing text is in Polish and lives in `src/i18n/pl.js`
- `SPEC.md` matches the implemented behavior
- You have listed what you changed, what you tested, and anything you could not verify

## When you are unsure

Ask a short question with the options you see. Do not guess on: legal or privacy text, database policies, content answers (every numeric answer must be recomputed and checked), and anything that changes the architecture.
