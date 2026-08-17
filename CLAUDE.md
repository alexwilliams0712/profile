# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal dotfiles and automated development environment setup for macOS and Ubuntu/Linux. Provisions machines with shell configurations, development tools, and application installations via a single entry point.

## Running the Setup

```bash
source setup_entry.sh
```

This detects the OS (`uname`), pulls the latest from `origin/main`, then dispatches to `tools/setup_macos.sh` or `tools/setup_ubuntu.sh`.

Every run writes a private log and prints its path. For diagnostics, inspect the
latest run first:

```bash
less -R "${XDG_STATE_HOME:-$HOME/.local/state}/profile/setup/latest.log"
# During a run:
tail -f "${XDG_STATE_HOME:-$HOME/.local/state}/profile/setup/latest.log"
```

Set `PROFILE_SETUP_LOG_DIR` to an absolute path to override the directory.
Logs and their parent directory are mode `600` and `700` respectively.
Treat them as private and never commit them.

Each platform's `main` defines its executable function plan. The shared runner
uses that plan as the progress total and pins one Rich-style bar below the live
terminal output. Cursor controls bypass the raw setup log.

Ubuntu retains its sudo timestamp keepalive. Homebrew deliberately invalidates
macOS sudo timestamps, so later privileged cask operations may request approval
again; never cache or broker the administrator password in setup code.

## Linting Shell Scripts

```bash
shellcheck tools/setup_macos.sh tools/setup_ubuntu.sh tools/common.sh tools/macos_helpers.sh setup_entry.sh
shfmt -d tools/setup_macos.sh tools/setup_ubuntu.sh tools/common.sh tools/macos_helpers.sh setup_entry.sh
bash tests/setup_logging/run.sh
bash tests/setup_macos/run.sh
bash tests/setup_progress/run.sh
```

Other focused regression scripts are available under `tests/`.

## Architecture

### Entry Point Flow

`setup_entry.sh` → private setup log → OS detection → `tools/setup_macos.sh`
or `tools/setup_ubuntu.sh` → both source `tools/common.sh` for shared
utilities. The platform script returns before `setup_entry.sh` closes the log,
then the entry point starts the replacement login shell.

### Key Components

- **`tools/common.sh`** — Shared functions: `run_function()` (error-handling wrapper), `handle_error()`, `log()`, `collect_user_input()`, `set_git_config()`, and shared installers used by both OS scripts (e.g. `install_pyenv()`, `install_rust()`, `install_ai()`). `install_ai()` installs the AI CLIs cross-platform: Claude Code and Codex via their official native curl installers, and Gemini CLI via npm (no native installer exists, so npm is the only non-Homebrew path). Every setup function is wrapped with `run_function` so failures are collected and reported at the end without aborting.
- **`tools/setup_macos.sh`** — macOS setup. Installs Homebrew, runs `brew bundle` from `tools/Brewfile`, sets Homebrew's bash 5+ as default shell, configures pyenv (Python 3.14), rustup, node, go, Docker, VS Code, Espanso, Tailscale, Terraform, and AI tools (via the shared `install_ai()` in `common.sh`). Copies dotfiles to `$HOME`. Uses `set -e` and `set -o pipefail`.
- **`tools/setup_ubuntu.sh`** — Ubuntu/Linux setup. Same workflow using apt/aptitude instead of Homebrew. Configures Terminator instead of iTerm2.
- **`tools/Brewfile`** — Declarative Homebrew package manifest (formulae, casks, Mac App Store apps).
- **`dotfiles/.bash_aliases`** — ~1,150 lines of shell functions and aliases covering git, Docker, Kubernetes, AWS, Python, Rust, system utilities. Sourced by `.bashrc`.
- **`dotfiles/.bashrc`** — Bash shell config (history, colors, pyenv init, prompt). Sources `.bash_aliases`.
- **`dotfiles/.profile`** — Login shell PATH setup with deduplication. Sources `.bashrc`.
- **`entrypoint.zsh`** — Zsh initialization (alternative shell entry).

### Shell Startup Chain

`.profile` → `.bashrc` → `.bash_aliases`

On macOS, `.bash_profile` sources `.bashrc` (setup script ensures this).

### Versioning

`VERSION` file holds the current semver. GitHub Actions (`.github/workflows/deploy.yaml`) auto-bumps on PR merge based on labels (`major`/`minor`/`patch`, defaults to patch). The version is copied to `$HOME/BASH_PROFILE_VERSION` and displayed on shell startup.

## Conventions

- All setup functions use `print_function_name` at the top for logging.
- Functions check tool existence before acting (idempotent).
- Architecture-aware: arm64 vs amd64 detection for Homebrew paths and binary downloads.
- Sudo keepalive pattern at the top of entry scripts (refresh every 30s).
- Indentation: tabs in shell scripts.
