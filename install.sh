#!/bin/bash
# Installs Quackie Chan, the tiny pixel duck that lives on your Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/Pallepadehat/QuackieChan/main/install.sh | bash
#
# It downloads the latest QuackieChan.dmg from GitHub Releases, puts the app in /Applications (replacing an older
# copy) and opens it. Releases are notarized by Apple; it also clears the "downloaded from the internet" flag, so even
# a disk image built without notarization opens without a warning.
#
# Options (after `bash -s --` when piping):
#   path/to/QuackieChan.dmg   install from a .dmg you already have instead of downloading
#   --no-open                 don't open the app afterwards
#
# QUACKIE_INSTALL_DIR overrides /Applications; QUACKIE_DMG_URL overrides where the .dmg comes from.
#
# Everything runs inside main(), so a download cut off half way can't run half a script.

set -euo pipefail

# Global, not local to main(): the clean-up below runs after main() has returned.
tmp=""

say() { printf '\033[1m🦆 %s\033[0m\n' "$*"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

main() {
  local repo="Pallepadehat/QuackieChan"
  local url="${QUACKIE_DMG_URL:-https://github.com/${repo}/releases/latest/download/QuackieChan.dmg}"
  local dest="${QUACKIE_INSTALL_DIR:-/Applications}"
  local app="Quackie Chan.app"
  local bundle_id="com.jakobsendevelopment.quackiechan"
  local open_after=1 dmg=""

  for arg in "$@"; do
    case "${arg}" in
      --no-open) open_after=0 ;;
      -h | --help) sed -n '2,18p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *.dmg) dmg="${arg}" ;;
      *) die "Unknown option: ${arg}" ;;
    esac
  done

  [[ "$(uname -s)" == "Darwin" ]] || die "Quackie Chan is a Mac app."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 14 )) || die "Quackie Chan needs macOS 14 or later (you have $(sw_vers -productVersion))."
  [[ "$(uname -m)" == "arm64" ]] || say "Heads up: on an Intel Mac the duck works, but its AI brain needs Apple silicon."

  tmp="$(mktemp -d)"
  # Clean up however it ends, keeping the real exit status.
  trap 'status=$?; hdiutil detach "$tmp/mount" -quiet -force >/dev/null 2>&1 || true; rm -rf "$tmp"; exit $status' EXIT

  if [[ -z "${dmg}" ]]; then
    say "Downloading Quackie Chan…"
    curl -fL --progress-bar "${url}" -o "$tmp/QuackieChan.dmg" \
      || die "Couldn't download ${url}. Is there a release with QuackieChan.dmg attached?"
    dmg="$tmp/QuackieChan.dmg"
  fi
  [[ -f "${dmg}" ]] || die "No such file: ${dmg}"

  hdiutil attach "${dmg}" -nobrowse -readonly -noautoopen -mountpoint "$tmp/mount" -quiet \
    || die "Couldn't open the disk image."
  [[ -d "$tmp/mount/${app}" ]] || die "The disk image doesn't have ${app} in it."

  # An older duck has to leave before the new one moves in.
  if pgrep -x "Quackie Chan" >/dev/null; then
    say "Asking the old duck to leave…"
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "Quackie Chan" >/dev/null || break; sleep 0.5; done
    pkill -x "Quackie Chan" 2>/dev/null || true
  fi

  say "Installing to ${dest}…"
  # Runs as you, or with sudo when the folder isn't yours to write (an empty array trips bash 3.2's `set -u`).
  local use_sudo=""
  if [[ -e "${dest}/${app}" && ! -w "${dest}/${app}" ]] || { [[ -d "${dest}" ]] && [[ ! -w "${dest}" ]]; }; then
    say "${dest} needs your password."
    use_sudo=1
  fi
  run() { if [[ -n "$use_sudo" ]]; then sudo "$@"; else "$@"; fi; }
  run mkdir -p "${dest}"
  run rm -rf "${dest}/${app}"
  run ditto "$tmp/mount/${app}" "${dest}/${app}"
  # Releases are notarized, but a disk image made without it would be blocked while it carries the download flag.
  run xattr -dr com.apple.quarantine "${dest}/${app}" 2>/dev/null || true

  say "Quackie Chan is installed in ${dest}. Quack!"
  if (( open_after )); then
    open "${dest}/${app}"
    say "It's dropping onto your screen now. Right-click it for settings."
  fi
}

main "$@"
