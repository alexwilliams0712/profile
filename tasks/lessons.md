# Lessons for working in this repo

Patterns to follow (and mistakes to avoid) when editing the setup scripts.
Update this file whenever a correction reveals a rule worth keeping.

## Setup output

Interactive progress must stay separate from the private log. Keep completed
function rows, use an indeterminate state when a function exposes no measurable
progress, and reserve percentages for the exact overall function count. Suspend
or isolate animation so foreground prompts cannot be overwritten, and retain
plain output when no terminal is available.

A self-updating run can combine an old entry point in memory with new platform
scripts on disk. Shared terminal features must not rely solely on state exported
by the entry point. Treat a reserved progress descriptor as usable only when it
is a terminal; an SSH shell can inherit the same descriptor number for logging.

## Keep guards proportional

When asked to skip one installer in a particular context, add the direct guard
to that installer. Do not broaden it into prompts or package-manager state
coordination unless that wider behaviour is explicitly requested.

## Keep verification local

Do not add or retain a repository test suite. Verify changes with local,
throwaway checks plus Bash syntax, ShellCheck, and shfmt.

## Where a new install goes

Decide by whether the *exact same commands* work on both macOS and Ubuntu:

1. **Identical install on both OSes → `tools/common.sh`.**
   If a tool installs via the same official `curl | sh` (or git clone, etc.)
   on both platforms, add ONE `install_*` function to `common.sh` and call it
   from both `main()`s. Examples already there: `install_rust` (rustup),
   `install_foundry` (foundryup), `install_starship`, `install_pyenv`,
   `install_ai` (Claude Code / Codex / Gemini).

2. **Different install per OS → implement it in BOTH scripts.**
   If the install differs (Homebrew vs apt, different repo/keyring, different
   service manager), write a platform-appropriate `install_*` in
   `tools/setup_macos.sh` AND `tools/setup_ubuntu.sh`, and wire each into its
   own `main()`. Keep the function name the same across both for symmetry.
   Example: `install_syncthing` — macOS enables the brew service
   (`brew services start syncthing`, formula from the Brewfile); Ubuntu uses
   the official apt repo + a `systemctl --user` service.

   Always provide the second-OS path when it's feasible — don't leave a tool
   installed on only one platform just because that's the machine you're on.

## Ubuntu: avoid snap

Do NOT install anything via `snap` on Ubuntu. Prefer, in order:
official apt repo (keyring in `/etc/apt/keyrings` + a `sources.list.d/*.list`
entry, like `gh`/`docker`/`vscode`/`syncthing` here) → official `curl | sh`
installer → upstream `.deb` → GitHub release binary (see the `github_*`
helpers). Snap's confinement also sandboxes `$HOME` and breaks tools that need
to touch arbitrary paths (e.g. Syncthing).

## macOS: prefer the Brewfile

For macOS, add the package to `tools/Brewfile` (formula or cask) so
`brew bundle` handles the install; the `install_*` function then only does the
extra wiring (start a service, link a CLI, copy config). Don't shell out to a
manual installer on macOS when a maintained formula/cask exists.

Homebrew's negative boolean environment flags are enabled by their presence,
including when set to `0`. Unset `HOMEBREW_NO_INSTALL_FROM_API` to use the JSON
API. After untapping `homebrew/core`, inspect installed formulae with one
unnamed `brew list --formula`; a named lookup can clone the tap again.

Homebrew invalidates macOS sudo timestamps on every invocation. macOS setup
cannot safely guarantee a single password prompt with a timestamp keepalive.
Do not cache or broker the administrator password: Homebrew children could use
that credential to authorise arbitrary root commands. Use visible foreground
sudo for explicit recovery and accept Homebrew's own security boundary.

After validating application artefacts, exclude installed casks marked
`auto_updates` from `brew bundle` upgrades. Their own updater owns freshness,
and an upstream download outage must not block unrelated Brewfile installs.

Do not use `brew uninstall --cask --force` as an installation check: it succeeds
for absent casks, and aliases can target the same canonical cask twice. Snapshot
`brew list --cask` and match exact installed tokens before uninstalling.

## General conventions (enforced)

- Tabs for indentation in shell scripts (not spaces).
- `run_function` logs each setup step once; do not duplicate that inside setup functions.
- Make functions idempotent — check `command -v` / file existence before acting;
  re-running setup must be safe.
- Register new functions with `run_function <name>` in `main()` so a failure is
  collected and reported at the end instead of aborting the whole run.
- Lint before done: `shellcheck` and `shfmt -d` must be clean on every edited
  script (see CLAUDE.md for the exact command).
