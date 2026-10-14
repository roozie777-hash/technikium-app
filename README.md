# Technikium

Duolingo-style learning app for electronics engineering students (Polish). Frontend: Vite and vanilla JavaScript. Backend: Supabase.

Documentation:
- `SPEC.md`: product and technical requirements
- `AGENTS.md`: rules for coding agents working in this repo

## Requirements

- Node.js 22.12 or newer (required by the pinned Vite toolchain)
- npm
- Docker (only for local database tests, through the Supabase CLI)
- A Supabase account (free tier is enough for the MVP)

## 1. Create the Supabase project

1. Create two projects in the Supabase dashboard: `technikium-dev` and `technikium-prod`.
2. In each project, go to Project Settings, then API. Copy the Project URL and the `anon` public key.
3. In Authentication, Providers, keep Email enabled and turn on "Confirm email".
4. In Authentication, URL Configuration, set the Site URL and redirect URLs for your local dev server and your production domain.

Never copy the `service_role` key into this repository or into any client-side file.

## 2. Environment variables

Copy the example file and fill in the dev values:

```bash
cp .env.example .env.local
```

`.env.local` must contain only:

```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-public-key
```

`.env.local` is git-ignored. Never commit it.

## 3. Install and run

```bash
npm install
npm run dev
```

The app runs at http://localhost:5173.

Current scope: database schema/RLS and a pure numeric-normalization helper. `index.html` and `src/main.js`
are empty Vite entry points, with no application UI. `npm test` uses the
built-in Node.js test runner for `tests/normalize.test.js`; these tests do not
validate database policies. `npm run build` checks only
the frontend toolchain. The Supabase CLI is pinned in `devDependencies`.

## 4. Database: migrations and seed

Migrations are versioned SQL files in `supabase/migrations/`. Apply them in order.

Link the CLI to the dev project and push the migrations:

```bash
npx supabase login
npx supabase link --project-ref <dev-project-ref>
npx supabase db push
```

Learning-content seed files are not implemented yet. Do not load answer data
into `content_exercises.payload`; answers belong in `content_exercise_answers`.

Repeat the same steps for `technikium-prod` only after the dev environment has been tested.

Never edit the production database by hand. Every change goes through a new migration file.

## 5. Tests

```bash
npm test          # unit tests (normalization, tolerance, helpers)
npm run test:db   # RLS and database function tests, needs local Supabase
npm run test:e2e  # end-to-end: register, log in, complete one lesson
npm run build     # production build
```

To run database tests locally:

```bash
npx supabase start
npx supabase migration up --local
npm run test:db
npx supabase stop
```

`test:db` runs pgTAP SQL files from `tests/db/` against the local Supabase
database, using real `authenticated` and `anon` roles and JWT claims. Each
test file rolls back its fixtures. Docker must be installed and running.
Never run these fixtures against a remote project. The E2E command currently
fails explicitly because authentication and UI are outside the implemented scope.
See [tests/db/README.md](tests/db/README.md) for suite coverage, actual verification
results, and the limitations of the supplemental embedded PostgreSQL check.

Remote verification is the project owner's separate step: after local tests,
link `technikium-dev`, inspect the migration, and apply it with `npx supabase db push`.
Local test success does not verify remote configuration, policies, or grants.

## Files added or changed for the data-model task

This inventory covers the initial schema task and its normalization/testing follow-up.
Generated node_modules/, dist/ and ignored .verification/ material are not source changes.

| File | Purpose |
| --- | --- |
| package.json | Adds the pinned Vite/Supabase toolchain and explicit development, build and test commands. |
| package-lock.json | Locks dependency versions for reproducible npm ci installs. |
| .gitignore | Excludes secrets, generated output, Supabase local state and temporary verification material. |
| index.html | Adds Vite's required HTML entry point so dev/build can run; it contains no application screen. |
| src/main.js | Supplies the empty ES-module entry referenced by index.html without implementing UI. |
| src/lib/normalize.js | Adds pure engineering-number parsing and relative-tolerance comparison. |
| tests/normalize.test.js | Adds 78 real JavaScript tests for parsing, invalid input and tolerance boundaries. |
| supabase/config.toml | Configures local Supabase/PostgreSQL 17 and disables nonexistent content seeds. |
| supabase/migrations/20261014000100_data_model_rls.sql | Creates the nine tables, constraints, indexes, narrow grants, RLS and weekly ranking. |
| tests/db/001_rls.sql | Tests user isolation, client write denial, anonymous access, publication inheritance and answer protection. |
| tests/db/002_leaderboard.sql | Tests ranking output, access control, tie ordering and Warsaw week boundaries. |
| tests/db/003_constraints.sql | Tests ordering uniqueness, foreign keys, payload protection, ranges and account deletion cascades. |
| tests/db/README.md | Records verification evidence, the auth stub limitation, Docker commands and result interpretation. |
| SPEC.md | Documents the agreed schema/security decisions and implemented normalization contract. |
| README.md | Documents setup, scope, commands, limitations and this file inventory. |

`.env.example` already existed and was preserved with placeholder values only;
it was not changed. AGENTS.md and .env.local were not modified.

## 6. Deploy the frontend

1. Connect the repository to Netlify, Vercel or GitHub Pages.
2. Build command: `npm run build`. Publish directory: `dist`.
3. Add the environment variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for the production project in the host's settings.
4. Add the production domain to the Supabase redirect URLs.

## 7. Before launch

- Publish a privacy policy and terms of use (Polish and English). They must describe how to delete an account.
- Confirm daily backups are enabled in Supabase.
- Run the full test suite on the production build.

## Project layout

```
technikium/
├── AGENTS.md          instructions for coding agents
├── SPEC.md            product and technical specification
├── README.md          this file
├── src/               frontend code
├── assets/            static assets (SVG mascot, icons, sounds if any)
├── supabase/
│   ├── migrations/    schema, RLS policies, database functions
│   └── seed/          learning content
└── tests/             unit, database and end-to-end tests
```
