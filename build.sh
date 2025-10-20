#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_DIR="${PROJECT_DIR:-"$SCRIPT_DIR/src/client/discord-scheduler"}"
DIST_DIR="${DIST_DIR:-"$SCRIPT_DIR/src/client/dist"}"
OUT_DIR="${OUT_DIR:-"$PROJECT_DIR/.build/web"}"

SHELL_HTML="${SHELL_HTML:-"$PROJECT_DIR/web/discord_activity_shell.html"}"
WEB_ASSETS_DIR="${WEB_ASSETS_DIR:-"$PROJECT_DIR/web/Assets"}"
WEB_VENDOR_SDK_DIR="${WEB_VENDOR_SDK_DIR:-"$PROJECT_DIR/web/vendor/discord-sdk"}"

SDK_SOURCE="${SDK_SOURCE:-npm}"
SDK_PACKAGE="${SDK_PACKAGE:-@discord/embedded-app-sdk}"
SDK_REF="${SDK_REF:-}"

MASCOT_URL="${MASCOT_URL:-https://finalbuildgames.com/mascotimproved.png}"
MASCOT_NAME="${MASCOT_NAME:-mascotimproved.png}"

EXPORT_PRESET="${EXPORT_PRESET:-Web}"

CLEAN_DIST="${CLEAN_DIST:-1}"
FORCE_CLEAN="${FORCE_CLEAN:-0}"

if [ -z "${GODOT_BIN:-}" ]; then
  for candidate in /usr/bin/godot godot godot4 godot-headless \
                    godot4-headless; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$candidate"
      break
    fi
  done
fi
: "${GODOT_BIN:?ERROR: Set GODOT_BIN to your Godot binary.}"

if [ -z "${PYTHON_BIN:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  else
    echo "ERROR: python3/python not found." >&2
    exit 1
  fi
fi

command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync not found"; exit 1; }
command -v curl  >/dev/null 2>&1 || { echo "ERROR: curl not found";  exit 1; }

if [ ! -d "$WEB_VENDOR_SDK_DIR" ] && [ "$SDK_SOURCE" != "none" ]; then
  command -v npm >/dev/null 2>&1 || {
    echo "ERROR: npm not found. Install Node/npm or vendor the SDK under"
    echo "$WEB_VENDOR_SDK_DIR and re-run."
    exit 1
  }
fi

[ -f "$PROJECT_DIR/project.godot" ] || {
  echo "ERROR: project.godot not found in $PROJECT_DIR"
  exit 1
}
[ -f "$SHELL_HTML" ] || {
  echo "ERROR: Shell HTML not found at $SHELL_HTML"
  exit 1
}

if [ "$CLEAN_DIST" = "1" ] && [ -d "$DIST_DIR" ]; then
  case "$DIST_DIR" in
    */dist|*/dist/) : ;;
    *) echo "Refusing to rm -rf non-'dist': $DIST_DIR"; exit 1;;
  esac
  if [[ "$DIST_DIR" == "$SCRIPT_DIR/src/client/dist" || \
        "$FORCE_CLEAN" = "1" ]]; then
    echo "==> Cleaning dist at $DIST_DIR"
    rm -rf "$DIST_DIR"
  else
    echo "Refusing to clean $DIST_DIR outside default path."
    echo "Set FORCE_CLEAN=1 to override."
    exit 1
  fi
fi
mkdir -p "$OUT_DIR" "$DIST_DIR"

echo "==> Exporting preset '$EXPORT_PRESET' -> $OUT_DIR"
set +e
"$GODOT_BIN" --headless \
  --path "$PROJECT_DIR" \
  --export-release "$EXPORT_PRESET" \
  "$OUT_DIR/index.html"
godot_rc=$?
set -e
if [ $godot_rc -ne 0 ]; then
  echo "ERROR: Godot export failed (code $godot_rc)."
  echo "Open the editor and install Web export templates, then retry."
  exit $godot_rc
fi

echo "==> Copying engine artifacts -> $DIST_DIR"
rsync -a \
  --include='*/' \
  --include='*.html' \
  --include='*.js' \
  --include='*.wasm' \
  --include='*.pck' \
  --include='*.png' \
  --include='*.ico' \
  --include='*.svg' \
  --include='*.json' \
  --include='*.webmanifest' \
  --exclude='*' \
  "$OUT_DIR"/ \
  "$DIST_DIR"/

if [ -d "$WEB_ASSETS_DIR" ]; then
  echo "==> Sync web/Assets -> $DIST_DIR/Assets"
  mkdir -p "$DIST_DIR/Assets"
  rsync -a "$WEB_ASSETS_DIR"/ "$DIST_DIR/Assets"/
fi

echo "==> Ensuring mascot -> $DIST_DIR/Assets/$MASCOT_NAME"
mkdir -p "$DIST_DIR/Assets"
curl -fLsS --retry 3 --retry-connrefused --retry-delay 1 \
  "$MASCOT_URL" -o "$DIST_DIR/Assets/$MASCOT_NAME"
[ -s "$DIST_DIR/Assets/$MASCOT_NAME" ] || {
  echo "ERROR: Failed to fetch mascot image"
  exit 1
}

sdk_target_dir="$DIST_DIR/vendor/discord-sdk"
if [ -d "$WEB_VENDOR_SDK_DIR" ]; then
  echo "==> Copy vendor SDK -> $sdk_target_dir"
  mkdir -p "$sdk_target_dir"
  rsync -a "$WEB_VENDOR_SDK_DIR"/ "$sdk_target_dir"/
else
  echo "==> Vendored SDK not found; acquiring ($SDK_SOURCE)…"
  TMP_WORKDIR="$(mktemp -d)"; trap 'rm -rf "$TMP_WORKDIR"' EXIT
  pushd "$TMP_WORKDIR" >/dev/null
  if [ "$SDK_SOURCE" = "github" ]; then
    ref_suffix=""
    [ -n "$SDK_REF" ] && ref_suffix="#$SDK_REF"
    npm pack "github:discord/embedded-app-sdk$ref_suffix" --silent
  else
    npm pack "$SDK_PACKAGE" --silent
  fi
  tarball_file="$(ls *.tgz | head -n1 || true)"
  [ -n "$tarball_file" ] || {
    echo "ERROR: Failed to download Embedded App SDK"
    exit 1
  }
  mkdir pkg && tar -xzf "$tarball_file" -C pkg
  pkg_root="pkg/package"
  sdk_esm_dir=""
  if [ -d "$pkg_root/output" ] && [ -f "$pkg_root/output/index.mjs" ]; then
    sdk_esm_dir="$pkg_root/output"
  elif [ -d "$pkg_root/dist" ] && [ -f "$pkg_root/dist/index.mjs" ]; then
    sdk_esm_dir="$pkg_root/dist"
  else
    esm_index_path="$(find "$pkg_root" -maxdepth 4 -type f -name index.mjs \
      | head -n1 || true)"
    [ -n "$esm_index_path" ] && sdk_esm_dir="$(dirname "$esm_index_path")"
  fi
  [ -n "$sdk_esm_dir" ] || {
    echo "ERROR: Could not locate SDK ESM entry (index.mjs)"
    exit 1
  }
  echo "==> Using SDK sources from: $sdk_esm_dir"
  mkdir -p "$sdk_target_dir"
  rsync -a "$sdk_esm_dir"/ "$sdk_target_dir"/
  popd >/dev/null
fi

export_index_path="$OUT_DIR/index.html"
[ -f "$export_index_path" ] || {
  echo "ERROR: Missing exported $export_index_path"
  exit 1
}

GODOT_LOADER_URL="$(
  grep -oE '<script[^>]+src="[^"]+\.js"' "$export_index_path" \
    | head -n1 \
    | sed -E 's/.*src="([^"]+)".*/\1/'
)"
[ -n "${GODOT_LOADER_URL:-}" ] || {
  echo "ERROR: Could not find loader .js"
  exit 1
}
loader_basename="$(basename "$GODOT_LOADER_URL")"
FINAL_GODOT_URL="./$loader_basename"

godot_config_json_path="$OUT_DIR/godot_config.json"
"$PYTHON_BIN" - "$export_index_path" "$godot_config_json_path" << 'PYCODE'
import sys

source_path, output_path = sys.argv[1], sys.argv[2]
html = open(source_path, "r", encoding="utf-8").read()

def find_matching_brace(s: str, open_idx: int) -> int:
    depth = 0
    in_string = False
    escape = False
    quote = ""
    for i in range(open_idx, len(s)):
        ch = s[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                in_string = False
        else:
            if ch in ("'", '"'):
                in_string = True
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
    return -1

anchor_positions = []
idx = html.find("GODOT_CONFIG")
if idx != -1:
    eq = html.find("=", idx)
    anchor_positions.append(eq if eq != -1 else idx)
idx = html.find("new Engine(")
if idx != -1:
    anchor_positions.append(idx)

json_obj = None
for anchor in anchor_positions:
    if anchor is None or anchor < 0:
        continue
    start_idx = html.find("{", anchor)
    if start_idx < 0:
        continue
    end_idx = find_matching_brace(html, start_idx)
    if end_idx != -1:
        json_obj = html[start_idx:end_idx + 1]
        break

if not json_obj:
    sys.exit(2)

open(output_path, "w", encoding="utf-8").write(json_obj)
PYCODE

[ -s "$godot_config_json_path" ] || {
  echo "ERROR: Failed to extract GODOT_CONFIG"
  exit 1
}
GODOT_CONFIG_INLINE="$(cat "$godot_config_json_path")"

PROJECT_NAME="$("$PYTHON_BIN" - "$PROJECT_DIR/project.godot" << 'PYCODE'
import sys, os, re

path = sys.argv[1]
lines = open(path, "r", encoding="utf-8").read().splitlines()

project_name = None
in_application = False

for raw_line in lines:
  line = raw_line.strip()
  if not line or line.startswith(";") or line.startswith("#"):
    continue
  if line.startswith("[") and line.endswith("]"):
    in_application = (line[1:-1].strip().lower() == "application")
    continue
  if in_application:
    match = re.match(r'config/name\s*=\s*(.+)$', line)
    if match:
      value = match.group(1).strip()
      if len(value) >= 2 and value[0] in "'\"" and value[-1] == value[0]:
        value = value[1:-1]
      project_name = value
      break

if not project_name:
  for raw_line in lines:
    match = re.search(r'config/name\s*=\s*(.+)$', raw_line)
    if match:
      value = match.group(1).strip()
      if len(value) >= 2 and value[0] in "'\"" and value[-1] == value[0]:
        value = value[1:-1]
      project_name = value
      break

if not project_name:
  project_name = os.path.basename(os.path.abspath(os.path.dirname(path)))

print(project_name or "Godot App")
PYCODE
)"

dist_index_path="$DIST_DIR/index.html"
echo "==> Writing $dist_index_path"
"$PYTHON_BIN" - "$SHELL_HTML" "$dist_index_path" << PYCODE
import sys

shell_path, out_path = sys.argv[1], sys.argv[2]
html = open(shell_path, "r", encoding="utf-8").read()
html = html.replace("\$GODOT_PROJECT_NAME", """$PROJECT_NAME""")
html = html.replace("\$GODOT_URL", """$FINAL_GODOT_URL""")
html = html.replace("\$GODOT_CONFIG", r'''$GODOT_CONFIG_INLINE''')
open(out_path, "w", encoding="utf-8").write(html)
PYCODE

echo "==> Done."
echo "Project: $PROJECT_DIR"
echo "Dist:    $DIST_DIR"
echo "Shell:   $dist_index_path"
echo "SDK:     $DIST_DIR/vendor/discord-sdk/"
echo "Assets:  $DIST_DIR/Assets/$MASCOT_NAME"
