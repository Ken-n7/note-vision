#!/usr/bin/env bash
# Regenerates MuseScore's reference exports for test/musescore_parity.
# Usage: tool/musescore_reference.sh [case-name ...]   (default: every case)
# MSCORE overrides the MuseScore Studio executable or AppImage.
set -euo pipefail
cd "$(dirname "$0")/.."
mscore="${MSCORE:-$HOME/Applications/MuseScore-Studio-4.7.5.260831071-x86_64.AppImage}"
dir=test/musescore_parity
export QT_QPA_PLATFORM=offscreen APPIMAGE_EXTRACT_AND_RUN=1

if [ $# -eq 0 ]; then set -- $(cd "$dir/cases" && ls *.musicxml | sed 's/\.musicxml$//'); fi
jobs="$(mktemp --suffix=.json)"
trap 'rm -f "$jobs"' EXIT
{
  echo '['
  sep=''
  for name in "$@"; do
    printf '%s{"in":"%s","out":["%s","%s"]}\n' "$sep" \
      "$PWD/$dir/cases/$name.musicxml" \
      "$PWD/$dir/reference/$name.musicxml" "$PWD/$dir/reference/$name.mid"
    sep=','
  done
  echo ']'
} > "$jobs"

"$mscore" -j "$jobs"
"$mscore" --version 2>/dev/null | tail -1 > "$dir/reference/VERSION"
cat "$dir/reference/VERSION"
