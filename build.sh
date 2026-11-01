#!/usr/bin/env bash
# Build Cryptid Paparazzi: run the tests, then export.
#   ./build.sh 0.8                 -> ../build/CryptidPaparazzi-0.8.exe  (Windows, single file)
#   TARGET=android ./build.sh 0.8 8 -> signed APK (old phone build, kept around)
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64}"
SIGNER="${SIGNER:-/home/claude/godot/uber-apk-signer.jar}"
OUT="${OUT:-../build}"
TARGET="${TARGET:-windows}"
VNAME="${1:-}"; VCODE="${2:-}"

echo "== Import"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "== Tests"
"$GODOT" --headless --path . res://tests/test_main.tscn 2>&1 | grep -E "FAIL|RESULT"
"$GODOT" --headless --path . res://tests/test_main.tscn >/dev/null 2>&1 || { echo "Tests failed - not building."; exit 1; }

mkdir -p "$OUT"
if [[ "$TARGET" == "windows" ]]; then
  if [[ -n "$VNAME" ]]; then
    V4="$VNAME"; while [[ $(tr -cd '.' <<<"$V4" | wc -c) -lt 3 ]]; do V4="$V4.0"; done
    sed -i "s|^application/file_version=.*|application/file_version=\"$V4\"|; s|^application/product_version=.*|application/product_version=\"$V4\"|" export_presets.cfg
  fi
  NAME="CryptidPaparazzi${VNAME:+-$VNAME}.exe"
  echo "== Export Windows"
  rm -f "$OUT/$NAME"
  "$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/$NAME" >/dev/null 2>&1 || true
  [[ -f "$OUT/$NAME" ]] || { echo "Export failed."; exit 1; }
  echo "Built $OUT/$NAME ($(du -h "$OUT/$NAME" | cut -f1))"
  exit 0
fi

if [[ -n "$VNAME" ]]; then sed -i "s|^version/name=.*|version/name=\"$VNAME\"|" export_presets.cfg; fi
if [[ -n "$VCODE" ]]; then sed -i "s|^version/code=.*|version/code=$VCODE|" export_presets.cfg; fi
echo "== Export Android"
rm -f "$OUT/unsigned.apk"
"$GODOT" --headless --path . --export-release "Android" "$OUT/unsigned.apk" >/dev/null 2>&1
[[ -f "$OUT/unsigned.apk" ]] || { echo "Export failed."; exit 1; }
echo "== Sign"
NAME="CryptidPaparazzi-$(grep '^version/name=' export_presets.cfg | cut -d'"' -f2).apk"
rm -rf "$OUT/signed"
java -jar "$SIGNER" -a "$OUT/unsigned.apk" --ks keys/release.keystore --ksAlias cryptid \
  --ksPass "${KS_PASS:?set KS_PASS}" --ksKeyPass "${KS_PASS}" -o "$OUT/signed" 2>&1 | grep -E "verified|error" || true
mv "$OUT/signed/unsigned-aligned-signed.apk" "$OUT/$NAME"
rm -rf "$OUT/signed" "$OUT/unsigned.apk"
echo "Built $OUT/$NAME"
