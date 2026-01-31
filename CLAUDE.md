# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal dotfiles and automated development environment setup for macOS and Ubuntu/Linux. Provisions machines with shell configurations, development tools, and application installations via a single entry point.

## Running the Setup

```bash
source setup_entry.sh
```

This detects the OS (`uname`), pulls the latest from `origin/main`, then dispatches to `tools/setup_macos.sh` or `tools/setup_ubuntu.sh`.

## Linting Shell Scripts

```bash
shellcheck tools/setup_macos.sh tools/setup_ubuntu.sh tools/common.sh setup_entry.sh
shfmt -d tools/setup_macos.sh tools/setup_ubuntu.sh tools/common.sh setup_entry.sh
```

There is no test suite.

## Architecture

### Entry Point Flow

`setup_entry.sh` → OS detection → `tools/setup_macos.sh` or `tools/setup_ubuntu.sh` → both source `tools/common.sh` for shared utilities.

### Key Components

- **`tools/common.sh`** — Shared functions: `run_function()` (error-handling wrapper), `handle_error()`, `log()`, `collect_user_input()`, `set_git_config()`. Every setup function is wrapped with `run_function` so failures are collected and reported at the end without aborting.
- **`tools/setup_macos.sh`** — macOS setup. Installs Homebrew, runs `brew bundle` from `tools/Brewfile`, sets Homebrew's bash 5+ as default shell, configures pyenv (Python 3.14), rustup, node, go, Docker, VS Code, Espanso, Tailscale, Terraform, AI tools (Claude Code, shell-gpt, Gemini CLI). Copies dotfiles to `$HOME`. Uses `set -e` and `set -o pipefail`.
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
