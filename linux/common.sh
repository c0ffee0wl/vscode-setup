#!/bin/bash

# vscode-setup — shared helpers
# Lifted (near-verbatim) from /opt/linux-setup/linux-setup.sh. Sourced by
# setup.sh; runs in the regular user's context.

# Colors for output (suppressed when not a TTY or when NO_COLOR is set)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Prompt user with yes/no question (honors FORCE_MODE / NO_MODE set by setup.sh)
# Usage: prompt_yes_no "Question?" "Y"   (or "N" for default No)
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local response

    if [[ "${FORCE_MODE:-false}" == "true" ]]; then
        log "Force mode: Auto-answering 'Yes' to: $prompt"
        return 0
    fi
    if [[ "${NO_MODE:-false}" == "true" ]]; then
        log "No mode: Auto-answering 'No' to: $prompt"
        return 1
    fi

    if [[ "$default" == "Y" ]]; then
        read -p "$prompt (Y/n): " response
        response=${response:-Y}
    else
        read -p "$prompt (y/N): " response
        response=${response:-N}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# Check if we're on Kali Linux
is_kali_linux() {
    grep -q "Kali" /etc/os-release 2>/dev/null
}

# Update or add a single export in ~/.profile (idempotent)
# Usage: update_profile_export <var_name> <var_value>
update_profile_export() {
    local var_name="$1"
    local var_value="$2"
    local profile_file="$HOME/.profile"

    [ ! -f "$profile_file" ] && touch "$profile_file"

    local escaped_value="$var_value"
    escaped_value="${escaped_value//\\/\\\\}"
    escaped_value="${escaped_value//\"/\\\"}"
    escaped_value="${escaped_value//\$/\\\$}"
    escaped_value="${escaped_value//\`/\\\`}"

    local sed_value="$escaped_value"
    sed_value="${sed_value//&/\\&}"

    if grep -q "^export ${var_name}=" "$profile_file" 2>/dev/null; then
        sed -i "s|^export ${var_name}=.*|export ${var_name}=\"${sed_value}\"|" "$profile_file"
    else
        echo "export ${var_name}=\"${escaped_value}\"" >> "$profile_file"
    fi
}

# Ensure ~/.zprofile sources ~/.profile (ZSH doesn't read ~/.profile by default)
ensure_zprofile_sources_profile() {
    is_kali_linux && return 0

    local zprofile="$HOME/.zprofile"
    local source_line='[[ -f ~/.profile ]] && emulate sh -c "source ~/.profile"'

    [ ! -f "$zprofile" ] && touch "$zprofile"

    if ! grep -qF "$source_line" "$zprofile" 2>/dev/null; then
        echo "" >> "$zprofile"
        echo "# Source ~/.profile for environment variables (added by vscode-setup)" >> "$zprofile"
        echo "$source_line" >> "$zprofile"
    fi
}

# Check if a desktop environment is available (informational only)
has_desktop_environment() {
    if [ -d /usr/share/xsessions ] && [ -n "$(ls -A /usr/share/xsessions 2>/dev/null)" ]; then
        return 0
    fi
    if [ -d /usr/share/wayland-sessions ] && [ -n "$(ls -A /usr/share/wayland-sessions 2>/dev/null)" ]; then
        return 0
    fi
    if [ -f /etc/X11/default-display-manager ] && [ -s /etc/X11/default-display-manager ]; then
        return 0
    fi
    if dpkg -l 2>/dev/null | grep -qE '^ii\s+(xfce4|gnome-shell|kde-plasma-desktop|plasma-desktop|lxde-core)'; then
        return 0
    fi
    return 1
}
