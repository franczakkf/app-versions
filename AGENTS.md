# app-versions

Public repository: one JSON file per app with its latest version number. Apps with private code
read it anonymously to tell the user a newer version exists. Purpose and file contract: `README.md`.

## Commands
- No build, tests or CI. Local gate: `pwsh -File ./check.ps1` (gitleaks secret scan of unpushed
  commits; gitleaks required), run by `.githooks/pre-push`. Per clone: `git config core.hooksPath .githooks`.

## Done =
- Every changed JSON parses, `version` matches `^\d+(\.\d+)*$`, and a new app has its row in the
  README table "Aplikacje".

## Non-obvious conventions
- `version` is digits and dots only. Reason: `1_0`, `+2` or non-ASCII digits can read as a higher
  version and send users to a release that does not exist; the app validates, the error starts here.
- Bumps usually come from each app's release pipeline. A manual edit skips that pipeline's
  validation, so check the number yourself.
- New app = new `<app-id>.json` + a row in the README table "Aplikacje".
- Commit message: `<app-id>: <version>`, e.g. `storytel-audio-manager: 0.4.2`.
- No workflows. Reason: a bump is one line of JSON; before adding one, state what cannot be done locally.

## Boundaries
- Everything here is public and served anonymously by `raw.githubusercontent.com`, including this
  file and `docs/notatki-agenta.md`. Commit only version numbers and short release notes — never the
  work environment, employer, clients, private repo or release addresses, secrets or user data.
  Check every new field, file or sentence for what it discloses.
- Field `url` (only in `storytel-audio-manager.json`) points to a release page, against
  the README contract. Owner decision pending: the app follows this link, so removing it changes the
  app contract. Do not decide it yourself and do not copy `url` to other files.

## Notes
Read `docs/notatki-agenta.md` before a larger change; record lessons there — it is public too.
