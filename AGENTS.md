# Setup diagnostics

When investigating a setup failure, inspect the latest private log first:

```bash
less -R "${XDG_STATE_HOME:-$HOME/.local/state}/profile/setup/latest.log"
```

If `PROFILE_SETUP_LOG_DIR` was set for the run, use that absolute directory
instead. Logs may contain local paths or account identifiers. Summarise only
the relevant evidence and never commit a log.

Follow `CLAUDE.md` for the repository's architecture, workflow, and checks.
