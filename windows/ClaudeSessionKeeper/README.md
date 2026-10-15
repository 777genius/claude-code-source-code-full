# Claude Session Keeper (Windows)

Keeps a Claude Code **subscription login** from running into the banner

> ⚠ Your login expires in 1 day · run /login to renew

by letting Claude Code's **own** refresh logic run before the login lapses. The keeper only *reads*
credential metadata; it never writes `.credentials.json`, never calls the OAuth endpoint itself, and
never prints or logs tokens.

## How it works (verified against the source and the 2.1.300 binary)

Claude Code stores the login in `%USERPROFILE%\.claude\.credentials.json` (or `%CLAUDE_CONFIG_DIR%`) under
`claudeAiOauth`. Two different timestamps live there:

| Field | Meaning | Lifetime |
|---|---|---|
| `expiresAt` | **access** token expiry | hours; Claude Code refreshes it automatically when expired / within ~5 min |
| `refreshTokenExpiresAt` | **login** (refresh token) expiry | what the banner uses; shown while `0 < remaining <= 3 days` |

When any Claude Code request finds the access token expired it takes a lock on the config directory,
posts the refresh token to the token endpoint, and saves the rotated tokens with a compare-and-swap
(`src/utils/auth.ts` `checkAndRefreshOAuthTokenIfNeededImpl`, `src/services/oauth/client.ts`
`refreshOAuthToken`). The token response carries `refresh_token_expires_in`, which Claude Code stores as
`refreshTokenExpiresAt`.

So each scheduled run:

1. reads the metadata (retrying if Claude Code is mid-write),
2. acts only if the login expires within `-ThresholdHours` (default 72 = the banner window) **and** the
   access token is expired (that is the only moment Claude Code will refresh),
3. runs one tiny `claude -p` request (Haiku, no tools, no session saved, `--max-budget-usd 0.05`, auth
   override variables stripped) so Claude Code's refresh path runs under its own lock,
4. re-reads the metadata and reports whether the tokens were replaced/rotated and whether the login
   lifetime actually moved.

### What it cannot do

If the server returns a fixed lifetime (for example an organization/SSO session limit), a refresh succeeds
but `refreshTokenExpiresAt` does not move. The keeper detects and logs this
(`login expiry did NOT move`, plus a notification) - at that point only an interactive `/login` helps.
For headless/CI use where no browser is available, the documented alternative is `claude setup-token`
(a one-year, inference-only token supplied through `CLAUDE_CODE_OAUTH_TOKEN`).

## Usage

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Test-ClaudeSessionKeeper.ps1            # read-only diagnostic; compare its login expiry with the banner
.\Renew-ClaudeLogin.ps1 -WhatIf           # evaluate + log, make no request
.\Renew-ClaudeLogin.ps1                   # run once
.\Install-ClaudeSessionKeeper.ps1         # hourly + at logon, per-user, hidden window
.\Uninstall-ClaudeSessionKeeper.ps1 [-RemoveData]
```

Logs: `%LOCALAPPDATA%\ClaudeSessionKeeper\renewal.log` (rotated at 1 MB, 3 backups), `state.json`
(timestamps/counters only). Exit codes: `0` ok / nothing due, `1` error, `2` needs interactive `/login`
(no credential / refresh token), `3` login expired or rejected, `4` refresh not confirmed. The scheduled
task's *Last Run Result* shows these.

## Audit: what was wrong in the original scripts

| # | Problem | Fix |
|---|---|---|
| 1 | Checked `expiresAt` (access token, ~hours) against a 72 h threshold; the banner is driven by `refreshTokenExpiresAt`. The test was always true, so only the 24 h throttle limited it. | Uses `refreshTokenExpiresAt`; mirrors the banner rule exactly. |
| 2 | Renewed with `claude auth login` + `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`. That path is documented for *provisioning* and runs `performLogout()` (deletes credentials, clears account config) **before** saving the new tokens: a crash/timeout in between leaves you logged out, and it bypasses the refresh lock / CAS other sessions rely on. | Delegates to Claude Code's native refresh; the keeper never writes credentials. |
| 3 | Gated on grepping the npm bundle for the env-var names. Current npm installs ship a native binary (and 2.1.42 contains no such strings), so the check fails or is meaningless. | Removed; resolves the real executable and reports `claude --version`. |
| 4 | "Claude is running" check matched `claude-code` in command lines (misses `claude.exe`), blocked renewal forever for users with open sessions, and returned `true` on any CIM error. | Removed: Claude Code's own lock + CAS make concurrent sessions safe. Keeper-vs-keeper uses a named mutex. |
| 5 | A failed attempt wrote `lastAttemptUtc`, so the 24 h throttle blocked retries for a day. | Short cooldown (`-MinRetryMinutes`, 30) and failure counters. |
| 6 | `claude` resolved to the `.ps1` shim (execution-policy dependent). | Prefers `.exe`, then `.cmd` (run via `cmd.exe /d /s /c`). |
| 7 | Scheduled task: no `-AllowStartIfOnBatteries` (never ran on battery), 3 min limit, no network condition, visible window, no logon trigger, `Interactive`-only. | Battery/network/limit/restart settings, hidden window, at-logon trigger, optional `-RunWhetherLoggedOn` (S4U), passes `-ClaudePath`/`-ConfigDir`, ACL warning, `Unblock-File`. |
| 8 | Logging: unlocked append, unbounded growth, no levels, no redaction safety net. | Share-tolerant append with retry, rotation, levels, token-pattern redaction. |
| 9 | `ANTHROPIC_API_KEY` etc. in the environment would make `claude -p` use that instead of the login. | Stripped from the child process; the diagnostic warns about them. |
| 10 | Success judged only by "refresh token changed or expiry later". | Compares SHA-256 fingerprints of tokens (never values), detects lost credentials, concurrent-session refreshes, and no-extension. |
| 11 | State/JSON writes were non-atomic; `Get-Item` on a dot-file fails without `-Force`; `$null` coerced to `""` in `File.Replace`. | Atomic temp+replace; `FileInfo`; `[NullString]::Value`. |

## Verification status

* Parsed and exercised on PowerShell 7.4 against fake credentials and a stub `claude` (not-needed,
  waiting-for-access-expiry, refresh+extend, refresh without extension, rejected login + cooldown,
  credentials deleted mid-run, missing `refreshTokenExpiresAt`, timeout, dry run, concurrent runs,
  environment stripping, log redaction).
* **Not executed here** (needs Windows): scheduled-task registration, `taskkill` tree-kill, toast
  notifications, ACL checks, and Windows PowerShell 5.1 specifically (the code avoids 5.1-incompatible
  syntax, but run `Test-ClaudeSessionKeeper.ps1` and `Install-ClaudeSessionKeeper.ps1 -RunNow` on your machine first).
* Behavior of `refresh_token_expires_in` on a real server (sliding vs. fixed) is not observable offline;
  the keeper reports what it sees after each real refresh.
