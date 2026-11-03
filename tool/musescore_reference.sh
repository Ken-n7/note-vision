#!/usr/bin/env bash
# Regenerates MuseScore's reference exports for test/musescore_parity.
# Usage: tool/musescore_reference.sh [case-name ...]   (default: every case)
# Also regenerates every transposition in transpositions.json (needs jq).
# MSCORE overrides the MuseScore Studio executable or AppImage.
set -euo pipefail
cd "$(dirname "$0")/.."
mscore="${MSCORE:-$HOME/Applications/MuseScore-Studio-4.7.5.260831071-x86_64.AppImage}"
dir=test/musescore_parity
export QT_QPA_PLATFORM=offscreen APPIMAGE_EXTRACT_AND_RUN=1
# The AppImage extracts itself (~550 MB) to $TMPDIR; /tmp can be a small
# RAM disk, so use a folder on disk.
export TMPDIR="${MUSESCORE_TMPDIR:-$HOME/.cache/musescore-appimage}"
mkdir -p "$TMPDIR"

# Cases are MusicXML, or MuseScore's own .mscx where MusicXML cannot say it
# (MuseScore imports D.C./D.S. markings from MusicXML as plain text).
if [ $# -eq 0 ]; then
  set -- $(cd "$dir/cases" && ls *.musicxml *.mscx | sed 's/\.[a-z]*$//')
fi
jobs="$(mktemp --suffix=.json)"
trap 'rm -f "$jobs"' EXIT
{
  echo '['
  sep=''
  for name in "$@"; do
    input="$dir/cases/$name.musicxml"
    [ -f "$input" ] || input="$dir/cases/$name.mscx"
    printf '%s{"in":"%s","out":["%s","%s"]}\n' "$sep" \
      "$PWD/$input" \
      "$PWD/$dir/reference/$name.musicxml" "$PWD/$dir/reference/$name.mid"
    sep=','
  done
  echo ']'
} > "$jobs"

"$mscore" -j "$jobs"

# Transposition references: MuseScore transposes the case, then exports.
mkdir -p "$dir/reference/transpose"
for name in $(jq -r 'keys[]' "$dir/transpositions.json"); do
  case_name=$(jq -r --arg n "$name" '.[$n].case' "$dir/transpositions.json")
  options=$(jq -c --arg n "$name" '.[$n].options' "$dir/transpositions.json")
  "$mscore" --transpose "$options" -o "$PWD/$dir/reference/transpose/$name.musicxml" \
    "$PWD/$dir/cases/$case_name.musicxml"
done
# New-score template references: MuseScore exports its own templates; the
# test compares Note Vision's templates' staves, clefs and sounds.
templates="$("$mscore" --version >/dev/null 2>&1; find "$TMPDIR" -path '*/share/mscore4portable-4.7/templates' -type d | head -1)"
mkdir -p "$dir/reference/templates"
for t in 01-General/01-Treble_Clef 01-General/02-Bass_Clef 01-General/03-Grand_Staff \
  02-Choral/01-SATB 02-Choral/03-SATB_+_Piano 02-Choral/07-Voice_+_Piano \
  03-Chamber_Music/01-String_Quartet 03-Chamber_Music/02-Wind_Quartet \
  03-Chamber_Music/03-Wind_Quintet 03-Chamber_Music/04-Saxophone_Quartet \
  03-Chamber_Music/05-Brass_Quartet 03-Chamber_Music/06-Brass_Quintet \
  04-Solo/01-Guitar 04-Solo/02-Guitar_+_Tablature 04-Solo/03-Guitar_Tablature 04-Solo/04-Piano \
  05-Jazz/01-Jazz_Lead_Sheet 06-Popular/01-Rock_Band; do
  "$mscore" -o "$PWD/$dir/reference/templates/${t#*/}.musicxml" "$templates/$t/${t#*/}.mscx"
done
"$mscore" --version 2>/dev/null | tail -1 > "$dir/reference/VERSION"
cat "$dir/reference/VERSION"
