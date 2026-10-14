# Database verification

Run the committed pgTAP suite against **local Supabase only**:

```sh
npm install
npx supabase start
npx supabase migration up --local
npm run test:db
```

The three SQL files cover 148 assertions: ownership isolation, profile column
privileges and WITH CHECK, direct write denial, anonymous access, publication
inheritance, actual client-role payload SELECTs, answer isolation, ranking
columns/results, weekly time boundaries, constraints and account cascades.
Each file temporarily truncates the nine application tables to isolate fixtures;
the transaction rolls back all fixtures, truncations and grant changes. Run
serially on a disposable local development instance, never a remote project.
The client queries here use PostgreSQL roles/JWT claims, not HTTP requests.

## Verification performed on 2026-10-14

- Initial `npm test`: completed with **0 JavaScript tests**. This was not database evidence.
- Follow-up `npm test`: **78/78 JavaScript tests passed**, covering decimal comma,
  SI prefixes, units, invalid inputs and relative tolerance, including boundaries,
  zero, negative values and overflow protection. These do not validate database RLS.
- `npm run build`: passed for the empty Vite entry point; no application UI exists.
- `supabase start`: failed because neither Docker nor Podman is installed/on PATH.
- `npm run test:db`: could not connect to local PostgreSQL at 127.0.0.1:54322;
  **the local Supabase suite did not execute**.
- Supplemental embedded check: migration applied and **148/148 pgTAP assertions
  passed** on PostgreSQL 17.5 via temporary PGlite 0.3.14. This matches the configured
  PostgreSQL major version, but is not a Supabase integration test.

**The embedded check used an auth stub, not real Supabase Auth.**
The supplemental bootstrap supplied synthetic anon/authenticated/service_role
roles, Supabase-like default table grants, an id-only auth.users table and an
auth.uid() function reading the request claim. It loaded upstream pgTAP SQL
directly instead of CREATE EXTENSION. Only that extension-install statement was
omitted from the committed test files; assertions were unchanged. PGlite was
installed temporarily without modifying package.json or package-lock.json.
Temporary verification material is ignored under `.verification/`.

Specifically, the stub contained only `auth.users(id uuid primary key)` and
`auth.uid()` implemented as
`nullif(current_setting('request.jwt.claim.sub', true), '')::uuid`.
It created anon and authenticated as NOLOGIN roles, service_role with BYPASSRLS,
and broad default table grants to exercise the migration's explicit revocations.
The assertions themselves ran with `set local role authenticated` or `anon`;
`set_config('request.jwt.claim.sub', ..., true)` selected a synthetic user.
These are real PostgreSQL role changes and RLS checks, but the auth objects are
**stubs**. There was no JWT creation, signature verification, session refresh,
GoTrue/Auth server, or real Supabase Auth schema/constraints/triggers.

In contrast, `npm run test:db` on Docker-backed Supabase does **not** create
these stubs: the committed SQL uses Supabase's own auth schema, auth.uid(),
and existing roles. It inserts synthetic user IDs as the test administrator
and impersonates clients through SET ROLE and request claims. Even this mode
tests SQL authorization, not HTTP/PostgREST or actual login/JWT verification.

pgTAP source: [official upstream SQL](https://github.com/theory/pgtap/blob/master/sql/pgtap.sql.in).
SHA-256 of the downloaded template:
`980d4e876b46c037e41f5957ba23641b875fa6388b3aa656897b3d1dc91c5fd1`.
The template's version/OS substitutions were used solely to load its SQL;
the assertions use no pgTAP version-specific behavior.

RESTRICT error expectations account for PostgreSQL 17 vs 18:
[PostgreSQL 17 source](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/utils/adt/ri_triggers.c),
[PostgreSQL 18 source](https://github.com/postgres/postgres/blob/REL_18_STABLE/src/backend/utils/adt/ri_triggers.c).

## Not verified

- Actual local Supabase startup, migration application and its installed pgTAP
  extension, Auth schema, API grants or PostgREST responses.
- Migration application on remote `technikium-dev`. This belongs to the project
  owner and requires their project access; no remote project was linked or changed.
- Browser flows, authentication, lesson logic, submit_answer, or regeneration:
  these are outside this task.

After Docker is available, run the local commands above first. Only then should
the owner review and apply the migration on `technikium-dev` using the README
instructions. Check that its PostgreSQL major version matches supabase/config.toml.

## Docker Desktop: exact PowerShell procedure

Open Docker Desktop, select Linux containers (WSL 2 backend), and wait for the
engine to be running. Open a new PowerShell so installed tools are on PATH.
Run each command separately and continue only if `$LASTEXITCODE` is 0:

```powershell
Set-Location 'C:\Users\Juliusz\Desktop\technikium\technikium'
node --version
npm.cmd --version
docker version
docker info --format '{{.OSType}}'
npm.cmd ci
npx.cmd supabase start
npx.cmd supabase migration up --local
npm.cmd run test:db
```

The Docker type must be `linux`. Node must be >=22.12.0. This repository already
has supabase/config.toml; do not run supabase init again. The first start may
download container images. Migration up applies only pending **local** migrations;
an up-to-date message is normal if start already applied them. No Supabase account,
remote project linking, or remote project keys are needed for these tests.

Afterward, optionally run the other checks and stop the stack:

```powershell
npm.cmd test
npm.cmd run build
npx.cmd supabase stop
```

`.cmd` explicitly selects the Windows command wrappers, avoiding PowerShell's
unsigned npm.ps1/npx.ps1 execution-policy errors. On a configured PowerShell,
`npx supabase start` and `npm run test:db` are the equivalent short forms.

| Result | Meaning / next action |
| --- | --- |
| docker version shows Client and Server; OSType is linux | Docker is ready; continue. |
| Command not found / not recognized | Install Node/Docker Desktop or correct PATH, then open a new terminal; tests have not run. |
| Cannot connect to Docker daemon / named pipe / engine stopped | Start Docker Desktop and resolve its WSL/virtualization error; tests have not run. |
| OSType is windows | Switch Docker Desktop to Linux containers before starting Supabase. |
| npm ci fails | Dependencies were not installed; resolve the reported Node, registry, network or permissions error before continuing. |
| start succeeds or says the stack is already running | Services started; this alone does not prove RLS. Continue with migration up and test:db. |
| Image download/TLS/proxy, port conflict, disk/memory or unhealthy-container error | The stack did not start cleanly; resolve the reported infrastructure error and rerun start; do not use --ignore-health-check. |
| migration up succeeds or says no pending migrations | The local schema is ready for testing; this alone does not prove RLS. |
| Migration SQL/history error | Stop and investigate the reported migration/history problem; the suite is not verified. Do not repair/reset the database blindly. |
| test:db exits 0, all 3 files / 148 tests, Result: PASS, no not ok | The committed SQL suite passed on real local Supabase; HTTP login and remote configuration remain unverified. |
| not ok / Failed tests / Result: FAIL / nonzero exit | At least one assertion failed; save the failing test and diagnostics. The task is not locally verified. |
| ECONNREFUSED / connection or container error | The suite did not run; verify Docker and Supabase startup first. |
| SQL error, missing relation, function or extension, permission denied during setup | The suite aborted or the environment/schema differs; inspect the preceding diagnostic, not just the assertion count. |
| No tests found, 0 tests, skipped tests, or incomplete TAP output | Not a passing verification, even if the wrapper exits 0; confirm tests/db paths and all expected assertions. |
| Unknown/unlisted error | A nonzero exit or incomplete output is unverified; keep the exact diagnostic for investigation. |

`$LASTEXITCODE` immediately after a native command reports its exit status.
The `.cmd` commands above are local-only: do not add --linked/--db-url, run db push,
or supply remote credentials. Test files temporarily truncate local application
tables inside rollback transactions; use a disposable development instance.

Sources: [Supabase local development](https://supabase.com/docs/guides/local-development),
[Supabase CLI reference](https://supabase.com/docs/reference/cli/supabase-test-db),
[Docker Desktop on Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
