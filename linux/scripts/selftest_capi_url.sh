#!/bin/bash
# Selftest for configure_agent_host_capi_url() in linux/setup.sh.
#
# Verifies the --capi-url step writes the VSCODE_AGENT_HOST_CAPI_URL_OVERRIDE
# export to ~/.profile exactly once (idempotent), rewrites a changed URL in
# place rather than appending, and is a clean no-op when no URL is given.
# Runs against a throwaway HOME; needs neither VS Code nor network.
#
# Exit: 0 = PASS, 1 = FAIL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP="$REPO_ROOT/linux/setup.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$SETUP" ] || fail "cannot find $SETUP"

WORK="$(mktemp -d /tmp/capi-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

EXPORT_LINE='export VSCODE_AGENT_HOST_CAPI_URL_OVERRIDE'

# --- helper: run the REAL configure_agent_host_capi_url() in isolation -------
run_capi() {  # $1 = HOME dir, $2 = url ('' = not requested)
    (
        local url="$2"               # capture $2 before `set --` clears it
        export HOME="$1"
        set --                       # so setup.sh's arg parser sees no args
        # shellcheck disable=SC1090
        source "$SETUP" || true      # BASH_SOURCE guard keeps main() from running
        set +e
        configure_agent_host_capi_url "$url" >/dev/null 2>&1
    )
}

count_lines() {  # $1 = HOME dir
    grep -c "^${EXPORT_LINE}=" "$1/.profile" 2>/dev/null
}

# --- Scenario 1: fresh write ---------------------------------------------------
H="$WORK/home"; mkdir -p "$H"
run_capi "$H" "http://127.0.0.1:4000"
grep -qxF "${EXPORT_LINE}=\"http://127.0.0.1:4000\"" "$H/.profile" \
    || fail "Scenario 1: expected export line not found in ~/.profile"
[ "$(count_lines "$H")" = "1" ] || fail "Scenario 1: expected exactly 1 export line"
echo "Scenario 1 (fresh write): OK"

# --- Scenario 2: idempotent re-run --------------------------------------------
run_capi "$H" "http://127.0.0.1:4000"
[ "$(count_lines "$H")" = "1" ] || fail "Scenario 2: re-run duplicated the export line"
echo "Scenario 2 (idempotent re-run): OK"

# --- Scenario 3: changed URL rewrites in place --------------------------------
run_capi "$H" "http://127.0.0.1:5000"
grep -qxF "${EXPORT_LINE}=\"http://127.0.0.1:5000\"" "$H/.profile" \
    || fail "Scenario 3: changed URL was not written"
[ "$(count_lines "$H")" = "1" ] || fail "Scenario 3: changed URL appended instead of rewriting"
echo "Scenario 3 (rewrite in place): OK"

# --- Scenario 4: empty URL is a no-op ------------------------------------------
H2="$WORK/home2"; mkdir -p "$H2"
run_capi "$H2" ""
! grep -q "^${EXPORT_LINE}=" "$H2/.profile" 2>/dev/null \
    || fail "Scenario 4: empty URL still wrote an export"
echo "Scenario 4 (empty URL no-op): OK"

# --- Scenario 5: malformed URL is rejected at parse time -----------------------
# Executes setup.sh (rather than sourcing it): the ^https?:// guard sits right
# after the arg parser, so a bad literal must exit 1 before main() ever runs.
if HOME="$WORK/home3" "$SETUP" --capi-url notaurl >/dev/null 2>&1; then
    fail "Scenario 5: malformed --capi-url was accepted"
fi
echo "Scenario 5 (malformed URL rejected): OK"

echo "PASS: configure_agent_host_capi_url writes an idempotent, in-place profile export."
exit 0
