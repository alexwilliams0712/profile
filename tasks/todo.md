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
- [x] Added Nova-coloured Unicode progress for interactive UTF-8 terminals and
      stable ASCII/no-colour output for non-interactive runs.
- [x] Verified executed, Bash-sourced, and Zsh-sourced logging; stdout/stderr,
      failure status, modes, sequential logs, latest pointer, and caller state.
- [x] Verified progress phases, success/failure advancement, final setup status,
      Unicode/ASCII rendering, syntax, formatting, and existing focused tests.
- [x] Independent review found and verified fixes for completed-bar rendering,
      directory-shaped latest pointers, inherited shell options, and the fresh
      macOS preflight count. The final review reported no remaining findings.

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
