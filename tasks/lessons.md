# Lessons for working in this repo

Patterns to follow (and mistakes to avoid) when editing the setup scripts.
Update this file whenever a correction reveals a rule worth keeping.

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

## General conventions (enforced)

- Tabs for indentation in shell scripts (not spaces).
- Every setup function starts with `print_function_name`.
- Make functions idempotent — check `command -v` / file existence before acting;
  re-running setup must be safe.
- Register new functions with `run_function <name>` in `main()` so a failure is
  collected and reported at the end instead of aborting the whole run.
- Lint before done: `shellcheck` and `shfmt -d` must be clean on every edited
  script (see CLAUDE.md for the exact command).
