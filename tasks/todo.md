# Repair pyenv setup on externally managed Python hosts

- [x] Detect and replace an incomplete pinned pyenv installation.
- [x] Install base packages into the pinned pyenv interpreter, not `/usr`.
- [x] Verify complete, incomplete, macOS, and failure paths locally.
- [x] Run Bash syntax, formatting, focused ShellCheck, and diff checks.
- [x] Review the final diff and record the outcome.

## Review

- [x] Setup now removes only the pinned pyenv version when its required
      `bin/python` is missing, reinstalls it, and rejects another incomplete
      result before changing the global version.
- [x] `uv` receives the pinned interpreter explicitly, avoiding Ubuntu's
      externally managed `/usr` Python and any unrelated active virtualenv.
- [x] A remote dry run on `alex-work-old` confirmed the explicit interpreter
      target. Throwaway complete, partial, failed-install, and macOS scenarios
      pass locally.
- [x] Bash 3.2 and current Bash syntax, shfmt, repository error-level
      ShellCheck, and `git diff --check` pass. Warning-level ShellCheck retains
      the same six existing findings as `main`.

# Show setup progress on the first post-update run

- [x] Confirm `ssh_current` allocates a terminal and diagnose the Ubuntu path.
- [x] Let the updated runner acquire the controlling terminal when the old
      entry point did not pass one through.
- [x] Preserve inherited file descriptors and the non-interactive fallback.
- [x] Run Bash 3.2, pseudo-terminal, no-terminal, formatting, and lint checks.
- [x] Obtain an independent review and resolve its findings.

## Review

- [x] Ubuntu's latest setup run predated the merged progress change, and the
      checkout therefore still contains the old renderer-free code.
- [x] The updated runner uses `/dev/tty` directly, leaving inherited logging
      and IPC descriptors intact. Non-interactive runs retain plain output.
- [x] Setup functions close descriptor 9 only when it is the marked progress
      terminal; direct-terminal and non-interactive functions preserve it.
- [x] Verified the old-entry pipeline in a Bash 3.2 pseudo-terminal, the
      deferred current-entry path, plain no-terminal output, and descriptor
      cleanup. Reproduced the missing bars through `ssh_current alex-work`,
      then verified the corrected animation in Ubuntu's non-interactive child
      and `tee` path with an inherited non-terminal descriptor 9. Bash syntax,
      shfmt, ShellCheck, and `git diff --check` pass.
- [x] An independent Ubuntu review found no remaining issue.

# Add professional setup progress

- [x] Inspect the current runner and earlier progress implementations.
- [x] Restore coloured per-function start, success, and failure states.
- [x] Show an animated row for each function and one live overall progress bar.
- [x] Keep full command output in the private log without terminal cursor codes.
- [x] Preserve prompts, failures, non-interactive output, and terminal cleanup.
- [x] Run local shell and pseudo-terminal verification.
- [x] Obtain an independent final review and resolve its findings.

## Review

- [x] Interactive terminals keep an animated function row and exact overall
      footer while ordinary output and prompts scroll above it; completed rows
      remain visible and the private log contains no cursor controls.
- [x] Verified success, failure continuation, foreground prompts, `NO_COLOR`,
      non-interactive fallback, narrow terminals, resizes, signal cleanup,
      deferred entry-point cleanup, log modes, and the absence of tracked tests.
- [x] Bash 3.2 syntax, shfmt, error-level ShellCheck, and `git diff --check` pass.
      Independent macOS and Ubuntu reviews found no remaining issue.

# Skip the Tailscale installer over SSH

- [x] Add one early SSH guard to Ubuntu's Tailscale installer.
- [x] Verify standard SSH markers and unchanged local behaviour.
- [x] Run shell checks and local verification.
- [x] Obtain an independent review.

## Review

- [x] Ubuntu's Tailscale installer returns immediately when any standard SSH
      marker is set; the local installer and configuration path is unchanged.
- [x] Local SSH-marker checks pass, as do Bash syntax, formatting, ShellCheck,
      and `git diff --check`.
- [x] Independent review found no production issue; inherited SSH variables
      are cleared so each marker is tested in isolation.

# Streamline the profile and add `ssh_current`

- [x] Inventory the tracked repository and identify clear duplication or dead code.
- [x] Add a small `ssh_current <host>` helper and verify its path quoting locally.
- [x] Consolidate exact cross-platform setup duplication.
- [x] Remove setup functions that are unreachable from the executable plans.
- [x] Run shell formatting, lint, and local verification.
- [x] Obtain an independent review and resolve its findings.
- [x] Include the changes in pull request #223.

## Review

- [x] `ssh_current` maps paths beneath the local home to the remote home, while
      retaining absolute paths elsewhere, then starts the remote login shell.
- [x] Shared dotfiles now have one installer; macOS no longer installs
      Brewfile-owned tools twice; Ubuntu installs one deduplicated package list.
- [x] Removed unreachable installers, redundant setup logging and service calls,
      unused shell code, one stray public key, and other single-use wrappers.
- [x] Verified Bash syntax, shell formatting, error-level ShellCheck,
      special-character path handling, and a clean temporary-home dotfile copy.
      Independent final reviews found no issues.

# Enable Ghostty copy-on-select on macOS

- [x] Confirm Ghostty's macOS clipboard setting and effective configuration.
- [x] Install the shared config at Ghostty's canonical macOS path.
- [x] Add focused regression coverage for both platform destinations.
- [x] Apply and validate the managed config on the current Mac.
- [x] Run shell checks and obtain an independent review.

## Review

- [x] macOS setup writes `config.ghostty` to Ghostty's higher-precedence
      Application Support directory, then removes only the old profile-managed
      XDG file so stale or additive settings are not loaded twice.
- [x] The current Mac uses the canonical file, validates it successfully, and
      resolves one config with `copy-on-select = clipboard`.
- [x] The preference, logging, macOS, and runner suites pass, as do Bash syntax,
      formatting, the changed-test ShellCheck, and `git diff --check`.
- [x] Repository-wide ShellCheck retains unrelated existing findings, including
      the Ubuntu `inline=false` error.
- [x] Independent review's migration and missing-file test findings were fixed;
      the final review found no remaining material issues.

# Use British date formatting on Ubuntu

- [x] Inspect the existing Ubuntu locale and GNOME preference setup.
- [x] Persist the British system locale and GNOME region during setup.
- [x] Add focused regression coverage.
- [x] Run repository shell checks and focused tests.
- [x] Obtain an independent review and resolve its findings.
- [x] Raise a pull request.

## Review

- [x] Added an idempotent Ubuntu setup step that generates `en_GB.UTF-8` only
      when absent, persists it with `update-locale`, and sets the GNOME region.
- [x] Verified the focused preference regression, Bash syntax, shell formatting,
      the British `%d/%m/%y` locale pattern, and the macOS and runner suites.
- [x] The repository-wide ShellCheck command retains unrelated existing findings.
      The logging suite retains its documented GNU `stat -f` portability failure.
- [x] Independent review found no correctness or idempotency issues. Added the
      focused preference regression to the repository's documented checks.
- [x] Raised pull request #221 and left merging to a human.

# Configure terminal input preferences

- [x] Confirm the working case-insensitive completion setting on this machine.
- [x] Manage the Readline preference consistently on Ubuntu and macOS.
- [x] Enable GNOME primary-selection paste during Ubuntu setup.
- [x] Add and run focused regression coverage.
- [x] Run repository shell checks.
- [x] Obtain an independent review and resolve its findings.
- [x] Raise a pull request.

## Review

- [x] Added one managed Readline file for both platforms and removed Ubuntu's
      ineffective system-wide mutation.
- [x] Added primary-selection paste to the existing idempotent GNOME settings.
- [x] Verified the focused preference regression, Readline's loaded value,
      Bash syntax, shell formatting, and all relevant existing tests.
- [x] Confirmed the changed scripts introduce no new ShellCheck finding codes;
      repository-wide lint retains unrelated existing findings.
- [x] `tests/setup_logging/run.sh` retains an unrelated GNU `stat -f`
      portability failure in this Linux environment.
- [x] Independent review found no correctness, scope, idempotence,
      cross-platform Readline, GNOME, test-quality, or prose issues.
- [x] Raised pull request #219 and left merging to a human.

# Simplify setup output and remove Julia cleanup

- [x] Remove loading and progress output from macOS and Ubuntu.
- [x] Preserve private logs, exact statuses, and function failure aggregation.
- [x] Keep safe macOS sudo and Command Line Tools recovery.
- [x] Delete the obsolete Julia cask migration.
- [x] Run focused and repository checks.
- [x] Obtain an independent final review.
- [x] Raise the follow-up pull request.

## Review

- [x] The monitored macOS run attempted all 21 functions. Command Line Tools
      recovery failed after Homebrew invalidated sudo, and an upstream WhatsApp
      HTTP 500 made the cask bundle report failure; later functions completed.
- [x] Removed the progress renderer and its terminal/state-file plumbing while
      retaining chronological private logs on both platforms.
- [x] macOS recovery uses visible foreground sudo without caching a password,
      prefers a valid full Xcode toolchain, and skips upgrades for installed
      self-updating casks after validating their application artefacts.
- [x] Confirmed `julia` aliases `julia-app` and forced Homebrew uninstall
      succeeds even when absent, which caused both false removal messages.
- [x] Verified macOS and Linux logging paths, Bash and Zsh sourcing, exact
      failure status, runner continuation, keepalive reaping, cask decisions,
      Bash syntax, formatting, focused lint, and repository regressions.
- [x] Independent review found no remaining production or test defects after
      Linux dispatch/log and EXIT-trap keepalive coverage were added.
- [x] Raised pull request #218; left merging to a human.

# Render one interactive setup progress bar

- [x] Replace per-step interactive progress lines with one in-place bar.
- [x] Clear the live bar before setup output and finish it with a newline.
- [x] Preserve newline-based ASCII progress for non-interactive runs.
- [x] Add focused rendering regressions and run the shell checks.
- [x] Obtain an independent review and prepare a follow-up pull request.

## Review

- [x] Interactive progress now redraws one bright-green line, preserves an
      aggregate failure state, and adapts to narrow UTF-8 and ASCII terminals.
- [x] Verified adjacent functions, parent-shell hooks, final newlines,
      non-interactive output, failure ordering, syntax, formatting, and lint.
- [x] The monitored run completed 20 of 21 functions. `install_packages` failed
      for separately diagnosed Homebrew API and stale CLT reasons.
- [x] Independent final review reported no remaining findings.

# Persist setup logs for diagnostics

- [x] Capture the complete entry-point and platform setup output without
      redirecting the caller after `source setup_entry.sh` returns.
- [x] Store private timestamped logs under the XDG state directory and maintain
      a stable `latest.log` symlink.
- [x] End logging before the platform setup hands off to a login shell.
- [x] Document the log location and override for users and future agents.
- [x] Show shared Rich-style progress for the actual macOS and Ubuntu setup
      functions, including completed count, total, and percentage.
- [x] Add focused source/execute, stream, status, permission, and symlink tests.
- [x] Add focused progress counting, rendering, and success/failure tests.
- [x] Run shell checks and obtain an independent review.

## Review

- [x] Added private timestamped logs with an atomic `latest.log` pointer,
      exact producer status capture, and a login-shell hand-off after logging.
- [x] Removed existing Git email and phone values from the persisted prompts.
- [x] Defined the platform function plans once, then used them for both
	  execution and shared progress totals: macOS 21 and Ubuntu 43.
- [x] Added bright-green Rich-style Unicode progress for interactive UTF-8
      terminals and stable ASCII/no-colour output for non-interactive runs.
- [x] Verified executed, Bash-sourced, and Zsh-sourced logging; stdout/stderr,
      failure status, modes, sequential logs, latest pointer, and caller state.
- [x] Verified progress phases, success/failure advancement, final setup status,
      Unicode/ASCII rendering, syntax, formatting, and existing focused tests.
- [x] Independent review found and verified fixes for completed-bar rendering,
      directory-shaped latest pointers, inherited shell options, and the fresh
      macOS preflight count. The final review reported no remaining findings.

# Fix monitored macOS package failures

- [x] Reproduce the cask resolution failure from Homebrew's negative API flag.
- [x] Enable API installs by leaving `HOMEBREW_NO_INSTALL_FROM_API` unset.
- [x] Validate CLT state after `softwareupdate` and fall back to active Xcode
      when a stale standalone installation remains.
- [x] Avoid cloning `homebrew-core` while checking unwanted installed formulae.
- [x] Add focused regressions and run shell checks.
- [x] Obtain an independent review and prepare a separate pull request.

## Review

- [x] Confirmed live that setting the negative API flag to `0` breaks cask
      lookup while leaving it unset resolves the same casks.
- [x] Added post-update CLT validation with a recoverable stale-directory
      backup only when full Xcode is valid and sufficient.
- [x] Covered current, missing, outdated, advisory, stale, Xcode-only, and
      standalone-required toolchain states with isolated stubs.
- [x] Verified all focused regressions, syntax, formatting, lint, and the live
      read-only cask and current-machine predicate checks.
- [x] Independent final review reported no remaining findings.

# Repair missing Homebrew cask applications

- [x] Reproduce the stale-receipt state where Homebrew reports a cask installed
      but its declared application artifact is absent.
- [x] Repair installed casks whose application artifacts are missing without
      repeatedly reinstalling non-application casks such as fonts.
- [x] Verify the focused behaviour and run `shellcheck` and `shfmt -d`.
- [x] Restore 1Password on the current Mac and confirm its application exists.
- [x] Obtain an independent review and resolve any material findings.

## Review

- [x] Added a shared application-artifact path resolver and completeness check;
      installed casks are reinstalled when any declared app is absent.
- [x] Covered present, missing, partial multi-app, font-only, renamed, absolute,
      unmanaged-app, and invalid-receipt cases with stubbed Homebrew responses.
- [x] Confirmed the live 1Password state was detected as incomplete, reinstalled
      8.12.33, verified its code signature, and confirmed the receipt and app.
- [x] `bash -n` and `shfmt -d` pass. The changed script adds no ShellCheck
      findings relative to `origin/main`; the repository-wide command retains
      unrelated pre-existing findings.
- [x] Existing `carclean` and `formatter` tests pass. The formatter test needs
      the native `/opt/homebrew` toolchain before the broken Intel Python.
- [x] Independent review found no material correctness, scope, or verification
      concerns.

# Fix espanso so it actually works (Ubuntu/Wayland)

## Environment (verified live)
- Ubuntu 26.04, amd64, GNOME on Wayland.
- espanso 2.3.0 already installed via `tools/setup_ubuntu.sh::install_espanso`.

## Root-cause diagnosis
espanso was installed but **not working**: `getcap /usr/bin/espanso` was empty and
the daemon was not running. On Wayland espanso needs `CAP_DAC_OVERRIDE` to read
`/dev/input/event*` (trigger detection) and write `/dev/uinput` (expansion injection).

The committed function applied `setcap` and `espanso service register` **only inside
the fresh-install branch** (`if [ "$installed" != "$latest" ]`). So:
- On a machine where espanso was already the latest version, those steps were skipped
  every run → a missing capability was never repaired.
- `apt` upgrades strip file capabilities, so even a previously-working install silently
  breaks after an update and re-running setup never fixes it.

## Fix (tools/setup_ubuntu.sh)
- [x] Moved `setcap` + `espanso service register` OUT of the install-only branch so they
      run on every invocation (idempotent).
- [x] Guarded `setcap` with a `getcap ... | grep -q cap_dac_override` check so it only
      re-applies when actually missing (and logs when it does).
- [x] Left install/config/start logic unchanged.

## Verification
- [x] shellcheck clean, `shfmt -d` clean.
- [x] Reproduced the bug: `setcap -r` + stop → getcap empty, "espanso is not running".
- [x] Ran the REAL `install_espanso` (extracted, with stubs) → detected already-installed,
      re-granted cap_dac_override, registered, reapplied config, restarted.
- [x] Final state: `getcap` = `cap_dac_override+p`, `espanso status` = running, and the
      worker process (non-root user, not in `input` group) holds `/dev/uinput` +
      `/dev/input/event3,event20` open — proving detection + injection work.

## Follow-up: explicit keyboard layout
- [x] espanso couldn't auto-detect the keyboard layout on Wayland (worker logged
      "unable to determine keyboard layout automatically" x2).
- [x] Added an idempotent step after the backend sed: detect the layout via
      `localectl` (X11 Layout = `gb` on this box) and append
      `keyboard_layout:\n  layout: "gb"` to the generated `default.yml` once,
      leaving the rest of espanso's template intact. Skipped if undetectable or
      already present.
- [x] Verified (rendered earlier this session): with `keyboard_layout: gb` set and
      espanso restarted, the "unable to determine keyboard layout" warnings dropped
      from 2 to 0 and the log had 0 WARN/ERROR lines.

## Notes
- Official espanso docs confirm `setcap "cap_dac_override+p" $(which espanso)` is the
  sanctioned Wayland mechanism (preferred over adding the user to the `input` group).
- `default.yml` is espanso's generated template (not empty); the backend sed works,
  so we append `keyboard_layout` rather than rewrite the file.
- macOS path (`brew` cask + `service register`/`start`) is correct and unchanged.

# Diagnose Espanso after the September setup run

- [x] Inspect the private setup log and live Espanso installation.
- [x] Check runtime configuration, dependencies, permissions and service state.
- [x] Explicitly enable expansions with `espanso cmd enable`.
- [x] Fix the independently reproduced fresh-install abort on a missing binary.
- [x] Verify absent, present and broken binary paths; review the final diff.

## Review

Espanso Wayland 2.4.1 is installed, with its service running and enabled at login.
The worker initialises keyboard detection and injection with the `gb` layout;
clipboard tools and the required capability are present. Alex subsequently
reported that expansion may now work. The earlier disabled state was not observed,
so enabling expansions is a possible explanation, not a proven root cause.
End-to-end expansion remains unverified. A separate fresh-install
defect was reproduced: the version check exited under `set -e` when Espanso
was absent. An explicit availability guard now lets installation proceed.
Throwaway checks cover absent, present and broken binaries, and reproduce the
base-branch failure. Bash syntax, shfmt and diff checks pass; ShellCheck reports
only the same pre-existing findings as the base revision.
The six reported setup failures are separate: five encountered package-manager
locks; Tailscale rejected omitted existing flags.

# Repair all six failed Ubuntu setup steps

- [x] Handle package-manager lock contention without interrupting other installers.
- [x] Repair package compatibility and review the browser, Python, formatter and VS Code paths.
- [x] Preserve existing Tailscale preferences when enabling its requested features.
- [x] Run focused regressions, package simulations and independent review.
- [ ] Rerun affected installers where authentication permits and record results.

## Review

Added bounded retries for actual APT/dpkg lock contention and removed the
upgrader's automatic repository deletion and PackageKit interruption.
Updated Ubuntu package names, switched Vivaldi to its signed APT repository,
preserved existing VS Code repositories and repaired Tailscale preference updates.
The live aliases matched the base revision and were updated with the repaired helper.

Focused existing/fresh/failure-path checks passed, including the real VS Code
configuration helper and a real APT lists-lock test in temporary directories.
The full base-package simulation and live base-package installation passed.
Bash syntax, shfmt, error-level repository ShellCheck and diff checks pass;
full ShellCheck adds no findings. Independent review reported no blocking issues.

The live six-step repair completed install_apt_packages. Administrator
authentication was then dismissed, blocking the remaining five steps.
A private retry-installs.sh beside the setup logs uses normal foreground sudo
and the existing timestamp keepalive to rerun those five steps from a terminal.
The pinned Python interpreter passes standard-library imports; Vivaldi and VS Code
report their installed versions. The old /usr/local pg_format remains at 5.10
until its source installer can rerun. No pending installer is claimed successful.

# Harden setup for fresh and repeat runs across machines

- [x] Audit entry-point updates, platform detection and invocation paths.
- [x] Fix reproducible fresh-install, repeat-run and failure-reporting defects in shared and platform installers.
- [x] Remove destructive assumptions that can affect unrelated local files or repositories.
- [x] Verify with isolated fresh/existing/failure scenarios and all shell checks.
- [x] Obtain independent review, reconcile findings and document remaining platform limits.

## Review

The entry point preserves local changes, commits and branches, updates clean main
only by fast-forward, resolves its location independently of the caller and
rejects unsupported platforms before authentication. Ubuntu now requires 24.04+;
22.04 failed real package simulation with missing lsd and wxWidgets packages.

Archive/build installers use owned temporary directories and no longer delete
unrelated working-directory files. Go validates its replacement before removing
the installed tree. Node and Tailscale vendor scripts share lock retry handling.
ClamAV resumes signature updates after a failed one-shot update. Flatpak and VS
Code partial failures now reach the setup summary. Installer PATH is refreshed
between subprocesses; pyenv no longer sources interactive shell configuration.

Espanso selects X11 or Wayland correctly, repairs dependencies on repeat runs,
defers headless/unsupported-architecture setup explicitly and renders contact
values as valid YAML. Independent review found Unicode separator/emoji defects
in the first renderer; exact libyaml roundtrip tests now pass after correction.
macOS uses architecture-independent Homebrew paths, preserves customised Ghostty
configuration and avoids resetting Brew repositories or ignoring dependencies.

Verification: base-package simulations passed in disposable Ubuntu 24.04 and
26.04 amd64 containers. Real temporary Git repositories cover dirty/local-commit,
topic-branch/detached and clean-fast-forward cases. Bash and real Zsh source tests
cover arbitrary caller directories and paths with spaces; caller cwd and private
logs are preserved. Focused fresh/existing/failure checks cover Espanso, VS Code,
shared PATH, archive cleanup, corrupt Go archives and actual APT lock contention.
Required repository ShellCheck, Bash syntax, shfmt and diff checks pass. Aliases
retain their pre-existing lint findings, with no additions from the lock helper.
Independent reviews are complete and all identified material concerns resolved.

Full installs on physical Macs and ARM machines remain unverified. The earlier
five live Ubuntu installer retries still require terminal sudo authentication;
this code-hardening pass does not claim those pending installs completed.

# Simplify setup and reduce repeat-run work

- [x] Pass 1: consolidate common platform behaviour and repeated summaries.
- [x] Pass 2: remove repeated package updates and unnecessary downloads/builds.
- [x] Pass 3: shorten redundant comments and output; review the integrated diff.
- [x] Run Bash syntax, ShellCheck and shfmt only; add no tests.

## Review

Shared Terraform, Node/npm, Go tools and final summaries replace platform copies.
Ubuntu now has one full-upgrade cycle. Matching Go/Terraform versions avoid repeat
downloads; existing package choices, source builds, installation locations,
Python plugin updates and VS Code extension updates are retained.

Three simplification passes and independent review are complete. Bash syntax,
required ShellCheck, shfmt and diff checks pass. No tests were added or run.
The pre-PR review restored the behaviours that the initial speed pass changed.

# Avoid redundant duf downgrades

- [x] Skip the upstream package when an installed duf package is current or newer.
- [x] Review the guard and run syntax, lint and formatting checks; add no tests.
- [x] Prepare the focused fix for a PR.

## Review

The log confirmed APT refused to downgrade Ubuntu's duf 0.9.1-1 to upstream
0.9.1. The installer now compares installed package versions with dpkg and
retains current or newer packages; missing or older packages still install.
Independent review, Bash syntax, ShellCheck, shfmt and diff checks pass.
No tests or full setup runs were performed.
