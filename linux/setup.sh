#!/bin/bash

# vscode-setup
# Installs Visual Studio Code on a Debian-based system, applies local-LLM
# VS Code settings (vendored configure-vscode, run via uv), and optionally
# installs/updates a Copilot .vsix + writes the VSCODE_SKIP_BUILTIN_EXTENSIONS
# export to ~/.profile.
#
# Helpers (common.sh) and the VS Code install logic are lifted from
# /opt/linux-setup. Mirrors the linux/{common.sh,configs,scripts,setup.sh}
# layout of the sibling installers.

set -eo pipefail

VERSION="1.0"
FORCE_MODE=false
NO_MODE=false
COPILOT_VSIX=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

show_usage() {
    cat << EOF
vscode-setup v${VERSION}
Installs Visual Studio Code on a Debian-based system, applies local-LLM
settings, and optionally installs a Copilot .vsix extension.

Usage: $0 [OPTIONS]

Options:
  --copilot-vsix <path|dir>  Install/update a Copilot extension from the given
                             .vsix file, or from the highest-versioned
                             copilot*.vsix in the given directory. When a vsix
                             is found, also writes
                             export VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat"
                             to ~/.profile.
  --force, -f, --yes, -y     Non-interactive; answer 'Yes' to all prompts
  --no, -n                   Non-interactive; answer 'No' to all prompts
  --help, -h                 Display this help message and exit

Examples:
  $0
  $0 --yes
  $0 --yes --copilot-vsix /opt/ct-dfir-llm/linux/binaries/vscode

EOF
    exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f|--yes|-y)
            FORCE_MODE=true
            shift
            ;;
        --no|-n)
            NO_MODE=true
            shift
            ;;
        --copilot-vsix)
            [[ -z "$2" || "$2" == --* ]] && error "--copilot-vsix requires a path argument"
            COPILOT_VSIX="$2"
            shift 2
            ;;
        --copilot-vsix=*)
            COPILOT_VSIX="${1#*=}"
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Warn (do not abort) if running as root
if [[ $EUID -eq 0 ]]; then
    warn "This script should normally not be run as root. Please run as a regular user with sudo privileges."
fi

# Debian-based system is a hard requirement
if ! grep -qE "(debian|ID_LIKE.*debian)" /etc/os-release 2>/dev/null; then
    error "This script requires a Debian-based Linux distribution. Detected system is not compatible."
fi

#############################################################################
# Step 1: Install Visual Studio Code (lifted from linux-setup; unconditional)
#############################################################################
install_vscode() {
    if ! has_desktop_environment; then
        warn "No desktop environment detected - installing VS Code anyway (usable as CLI / remote host)."
    fi

    log "Installing Visual Studio Code..."
    if command -v code &> /dev/null; then
        log "Visual Studio Code is already installed"
        return 0
    fi

    sudo apt-get install -y gpg
    curl --proto '=https' --tlsv1.2 -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
    sudo install -m 644 /tmp/microsoft.gpg /usr/share/keyrings/microsoft.gpg
    rm -f /tmp/microsoft.gpg

    sudo install -m 644 "$CONFIGS_DIR/vscode.sources" /etc/apt/sources.list.d/vscode.sources

    sudo apt-get install -y apt-transport-https
    sudo apt-get update
    sudo apt-get install -y code
}

#############################################################################
# Step 2: Apply local-LLM VS Code settings via the vendored configure-vscode
#############################################################################
configure_vscode_settings() {
    if ! command -v uv &> /dev/null; then
        error "uv is required to run configure-vscode but was not found on PATH. Install uv: https://docs.astral.sh/uv/getting-started/installation/"
    fi
    # The vendored configure-vscode has NO --user flag; its default scope is
    # user settings (~/.config/Code/User/settings.json) — exactly what we want.
    log "Applying local-LLM VS Code settings (configure-vscode, user scope)..."
    uv run "$SCRIPTS_DIR/configure_vscode.py"
}

#############################################################################
# Step 3: Optional Copilot extension install + profile export
#############################################################################
install_copilot() {
    local arg="$1"
    local vsix=""

    [ -z "$arg" ] && return 0  # not requested

    if [ -f "$arg" ]; then
        vsix="$arg"
    elif [ -d "$arg" ]; then
        vsix="$(find "$arg" -maxdepth 1 -name 'copilot*.vsix' -type f 2>/dev/null | sort -V | tail -n1)"
        if [ -z "$vsix" ]; then
            warn "No copilot*.vsix found in '$arg' - skipping Copilot install and profile export."
            return 0
        fi
        local count
        count="$(find "$arg" -maxdepth 1 -name 'copilot*.vsix' -type f 2>/dev/null | wc -l)"
        if [ "$count" -gt 1 ]; then
            warn "Multiple copilot*.vsix in '$arg'; using highest version: $(basename "$vsix")"
        fi
    else
        warn "--copilot-vsix path '$arg' does not exist - skipping Copilot install and profile export."
        return 0
    fi

    if ! command -v code &> /dev/null; then
        warn "'code' not found on PATH - cannot install Copilot extension. Skipping."
        return 0
    fi

    log "Installing/updating Copilot extension from: $vsix"
    code --install-extension "$vsix" --force

    log "Writing VSCODE_SKIP_BUILTIN_EXTENSIONS to ~/.profile..."
    update_profile_export "VSCODE_SKIP_BUILTIN_EXTENSIONS" "GitHub.copilot-chat"
    ensure_zprofile_sources_profile
}

#############################################################################
# Main
#############################################################################
if [ -n "$COPILOT_VSIX" ]; then
    confirm_msg="Install VS Code, apply local-LLM settings, and install the Copilot extension. Continue?"
else
    confirm_msg="Install VS Code and apply local-LLM settings. Continue?"
fi
if ! prompt_yes_no "$confirm_msg" "Y"; then
    log "Aborted by user."
    exit 0
fi

install_vscode
configure_vscode_settings
install_copilot "$COPILOT_VSIX"

log "vscode-setup complete."
