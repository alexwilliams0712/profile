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
