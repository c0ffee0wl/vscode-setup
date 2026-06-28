#!/bin/bash
# Regression smoke test for the Copilot vsix "builtin metadata poisoning" bug.
#
# Verifies that install_copilot() in linux/setup.sh installs the
# GitHub.copilot-chat override vsix with CLEAN metadata (no isBuiltin /
# isApplicationScoped), so the extension is not dropped as an "obsolete builtin"
# when VSCODE_SKIP_BUILTIN_EXTENSIONS hides the bundled builtin at runtime.
#
# Requires: the official VS Code 'code' CLI on PATH, WITH the bundled
# GitHub.copilot-chat builtin present (Microsoft apt build). Uses throwaway HOME
# dirs only; it touches nothing real.
#
# Exit: 0 = PASS, 1 = FAIL, 2 = SKIP (cannot reproduce on this host).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/linux/setup.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
skip() { echo "SKIP: $*" >&2; exit 2; }

command -v code    >/dev/null 2>&1 || skip "'code' not on PATH"
command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH (needed to build the test vsix)"
[ -f "$SETUP" ] || fail "cannot find $SETUP"

# The bug only reproduces when a bundled builtin copilot-chat exists.
builtin_present=""
for base in /usr/share/code /opt/visual-studio-code /usr/lib/code; do
    for d in "$base"/resources/app/extensions/*copilot*; do
        [ -d "$d" ] && builtin_present="$d" && break 2
    done
done
[ -n "$builtin_present" ] || skip "no bundled GitHub.copilot-chat builtin found; cannot reproduce"

WORK="$(mktemp -d /tmp/cc-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# --- build a minimal GitHub.copilot-chat@99.0.0 vsix --------------------------
mkdir -p "$WORK/vsix/extension"
cat > "$WORK/vsix/extension/package.json" <<'JSON'
{ "name": "copilot-chat", "publisher": "GitHub", "version": "99.0.0",
  "displayName": "Copilot Chat (selftest)", "description": "selftest",
  "engines": { "vscode": "^1.120.0" }, "main": "./extension.js",
  "activationEvents": ["*"], "contributes": {} }
JSON
printf 'exports.activate=function(){};exports.deactivate=function(){};\n' \
    > "$WORK/vsix/extension/extension.js"
cat > "$WORK/vsix/extension.vsixmanifest" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="copilot-chat" Version="99.0.0" Publisher="GitHub" />
    <DisplayName>Copilot Chat (selftest)</DisplayName>
    <Description xml:space="preserve">selftest</Description>
    <Categories>Other</Categories>
    <GalleryFlags>Public</GalleryFlags>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.120.0" /></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" /></Assets>
</PackageManifest>
XML
cat > "$WORK/vsix/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
  <Default Extension=".js" ContentType="application/javascript"/>
</Types>
XML
VSIX="$WORK/copilot-chat-99.0.0.vsix"
python3 - "$WORK/vsix" "$VSIX" <<'PY'
import sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
PY
[ -f "$VSIX" ] || fail "could not build test vsix"

# --- helper: classify the copilot-chat entry in an extensions.json ------------
# prints one of: CLEAN | BUILTIN | MISSING | NOJSON
classify() {
    python3 - "$1" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("NOJSON"); sys.exit(0)
for e in data:
    if e.get("identifier", {}).get("id", "").lower() == "github.copilot-chat":
        m = e.get("metadata") or {}
        print("BUILTIN" if (m.get("isBuiltin") or m.get("isSystem")) else "CLEAN")
        break
else:
    print("MISSING")
PY
}

# --- helper: run the REAL install_copilot() against an isolated HOME ----------
run_install_copilot() {  # $1 = HOME dir
    (
        export HOME="$1"
        set --                       # so setup.sh's arg parser sees no args
        # shellcheck disable=SC1090
        source "$SETUP" || true      # Task 1 guard keeps main() from running
        set +e
        install_copilot "$VSIX" >/dev/null 2>&1
    )
}

echo "Using: code=$(command -v code)"
echo "Builtin: $builtin_present"

# --- Scenario 1: a fresh install_copilot() must produce CLEAN metadata --------
H1="$WORK/home1"; mkdir -p "$H1"
run_install_copilot "$H1"
got1="$(classify "$H1/.vscode/extensions/extensions.json")"
echo "Scenario 1 (fresh install_copilot): $got1"
[ "$got1" = "CLEAN" ] || fail "Scenario 1 expected CLEAN, got '$got1' (install_copilot poisons metadata)"

# --- Scenario 2: install_copilot() must REPAIR a previously poisoned profile --
H2="$WORK/home2"; mkdir -p "$H2"
# Recreate the bad state the legacy installer produced: install WITHOUT the var.
( export HOME="$H2"; unset VSCODE_SKIP_BUILTIN_EXTENSIONS
  code --install-extension "$VSIX" --force >/dev/null 2>&1 )
pre="$(classify "$H2/.vscode/extensions/extensions.json")"
echo "Scenario 2 precondition (legacy install): $pre"
[ "$pre" = "BUILTIN" ] || skip "could not reproduce poisoned state (got '$pre'); VS Code build may differ"
run_install_copilot "$H2"
got2="$(classify "$H2/.vscode/extensions/extensions.json")"
echo "Scenario 2 (after install_copilot repair): $got2"
[ "$got2" = "CLEAN" ] || fail "Scenario 2 expected CLEAN after repair, got '$got2'"

echo "PASS: install_copilot writes clean metadata and repairs poisoned installs."
exit 0
