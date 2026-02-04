#!/bin/bash
# Not using set -euo pipefail: when launched from file manager (no terminal) any early
# exit (e.g. unset var, failed pipeline) would exit silently with no error shown.

# Script version
VERSION="0.1.8"

# Constants
MAX_VBOX_SHARES=20
MAX_CONFIG_SHARES=10

# Debug: only print when VB_LAUNCHER_DEBUG is set (e.g. VB_LAUNCHER_DEBUG=1 ./script.sh)
debug() {
    [[ -n "${VB_LAUNCHER_DEBUG:-}" ]] && echo "Debug: $*" >&2
}

# Function to display version
show_version() {
    echo "vbox_windows_app_launcher version $VERSION"
    exit 0
}

# Function to display help
show_help() {
    echo "Usage: $(basename "$0") [OPTION] [FILE|DIRECTORY]"
    echo
    echo "Launch Windows applications in a VirtualBox VM to open files or directories."
    echo
    echo "Options:"
    echo "  -h, --help     Display this help message and exit"
    echo "  -v, --version  Display version information and exit"
    echo
    echo "Examples:"
    echo "  $(basename "$0") document.docx     Open document.docx with the associated Windows application"
    echo "  $(basename "$0") ~/Pictures/       Open the Pictures directory in Windows Explorer"
    echo
    echo "Configuration file: \$XDG_CONFIG_HOME/vbox_windows_app_launcher.conf (default: ~/.config/vbox_windows_app_launcher.conf)"
    exit 0
}

# Check for version or help flags
if [ "$1" = "-v" ] || [ "$1" = "--version" ]; then
    show_version
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
elif [ -z "$1" ]; then
    echo "Error: No file or directory specified."
    echo "Try '$(basename "$0") --help' for more information."
    exit 1
fi

# Convert file:// URL to path (file managers like Nautilus may pass file:///path)
INPUT_PATH="$1"
if [[ "$INPUT_PATH" == file://* ]]; then
    INPUT_PATH="${INPUT_PATH#file://}"
    # Decode %XX (e.g. %20 -> space)
    INPUT_PATH=$(printf '%b' "$(echo -n "$INPUT_PATH" | sed 's/%/\\x/g')")
fi
# Resolve to absolute path so shared-folder matching works (e.g. when opened with relative path from file manager)
if [[ "$INPUT_PATH" != /* ]]; then
    INPUT_PATH="$PWD/$INPUT_PATH"
fi
set -- "$INPUT_PATH"

# XDG config directory; fall back to $HOME/.config if unset
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Config file path and notification setup (needed before config load for permission-error notification)
CONFIG_FILE="$XDG_CONFIG_HOME/vbox_windows_app_launcher.conf"

# Check if dunstify is available
if command -v dunstify >/dev/null 2>&1; then
    DUNSTIFY_AVAILABLE=true
else
    DUNSTIFY_AVAILABLE=false
fi

# Check if notify-send is available
if command -v notify-send >/dev/null 2>&1; then
    NOTIFY_SEND_AVAILABLE=true
else
    NOTIFY_SEND_AVAILABLE=false
fi

# Function to show error notification (dunstify/notify-send, else zenity/kdialog so file-manager launches still see errors)
show_error_notification() {
    local error_message="$1"
    local err_timeout="${ERROR_NOTIFICATION_TIMEOUT:-15000}"
    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        dunstify -u critical -t "$err_timeout" "VB App Error" "$error_message"
    elif [ "$NOTIFY_SEND_AVAILABLE" = true ]; then
        notify-send -u critical -t "$err_timeout" "VB App Error" "$error_message"
    elif command -v zenity >/dev/null 2>&1; then
        zenity --error --title "VB App Error" --text "$error_message" 2>/dev/null || true
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title "VB App Error" --error "$error_message" 2>/dev/null || true
    else
        echo "Error: $error_message"
    fi
}

# Load configuration from XDG_CONFIG_HOME (or ~/.config)
if [ ! -f "$CONFIG_FILE" ]; then
    show_error_notification "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Require config file not readable by others (contains password)
config_perms=$(stat -c %a "$CONFIG_FILE" 2>/dev/null) || config_perms=""
others_perm=$(( ${config_perms: -1} + 0 )) 2>/dev/null || others_perm=4
if [ -z "$config_perms" ] || [ "$others_perm" -ne 0 ]; then
    show_error_notification "Config file has insecure permissions (readable by others). Fix: chmod 600 $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Optional config with defaults (so existing configs keep working)
SCRIPT_TIMEOUT="${SCRIPT_TIMEOUT:-6}"
NOTIFICATION_TIMEOUT="${NOTIFICATION_TIMEOUT:-$((SCRIPT_TIMEOUT * 1000))}"
VM_START_TIMEOUT="${VM_START_TIMEOUT:-300}"
VM_START_POLL_INTERVAL="${VM_START_POLL_INTERVAL:-5}"
ERROR_NOTIFICATION_TIMEOUT="${ERROR_NOTIFICATION_TIMEOUT:-15000}"
NOTIFICATION_FOCUS_DELAY="${NOTIFICATION_FOCUS_DELAY:-0}"
VM_POWERSHELL_EXE="${VM_POWERSHELL_EXE:-C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe}"

# Check if wmctrl is available
if command -v wmctrl >/dev/null 2>&1; then
    WMCTRL_AVAILABLE=true
else
    WMCTRL_AVAILABLE=false
fi

# Output "path|drive" (one per line) for every defined config share (VM_SHARE_PATH/VM_DRIVE_LETTER and VM_SHARE_PATH_2.._N).
config_share_list() {
    local i path_var drive_var path drive
    if [[ -n "${VM_SHARE_PATH:-}" && -n "${VM_DRIVE_LETTER:-}" ]]; then
        path="${VM_SHARE_PATH%/}"
        drive="${VM_DRIVE_LETTER%:}"
        printf '%s|%s\n' "$path" "$drive"
    fi
    for i in $(seq 2 "$MAX_CONFIG_SHARES"); do
        path_var="VM_SHARE_PATH_$i"
        drive_var="VM_DRIVE_LETTER_$i"
        path="${!path_var:-}"
        drive="${!drive_var:-}"
        [[ -z "$path" || -z "$drive" ]] && continue
        path="${path%/}"
        drive="${drive%:}"
        printf '%s|%s\n' "$path" "$drive"
    done
}

# Format Windows path: given share_path (unix), drive_letter (G or G:), and full unix_path. Echoes e.g. G:\rest\path.
format_windows_path() {
    local share_path="$1" drive_letter="$2" unix_path="$3" rest
    drive_letter="${drive_letter%:}"
    rest="${unix_path#$share_path}"
    rest="${rest#/}"
    echo "${drive_letter}:\\$(echo "$rest" | sed 's|/|\\|g')"
}

# Query the guest for existing \\vboxsvr drive mappings via "net use" (same session that runs Invoke-Item).
# Output: "sharename|letter" (e.g. g|G), one per line.
get_guest_vbox_drive_mappings() {
    local ps_cmd out
    # UNC in net use is \\VBoxSvr\share — need two backslashes in regex (\\\\\\\\ in PowerShell string)
    ps_cmd="net use | Where-Object { \$_ -like '*vboxsvr*' } | ForEach-Object { if (\$_ -match '^\s+([A-Za-z]):\s+\\\\\\\\[^\\\\]+\\\\([^\s\\\\]+)') { Write-Output (\$matches[2] + '|' + \$matches[1]) } }"
    out=$(LC_ALL=C.UTF-8 VBoxManage guestcontrol "$VM_NAME" run --exe "$VM_POWERSHELL_EXE" --username "$VM_USER" --password "$VM_PASSWORD" --quiet -- -NoProfile -Command "$ps_cmd" 2>&1) || true
    # Strip CR (Windows line endings) so grep matches
    out="${out//$'\r'/}"
    echo "$out" | grep -E '^[^|]+\|[A-Za-z]$' || true
}

# Get VBox shared folders (path|name only), longest path first. No drive letters.
get_vbox_shared_folders_raw() {
    local vbox_info path name i len
    vbox_info=$(VBoxManage showvminfo "$VM_NAME" --machinereadable 2>/dev/null) || return 1
    for i in $(seq 1 "$MAX_VBOX_SHARES"); do
        path=$(echo "$vbox_info" | grep "SharedFolderPathMachineMapping$i=" | sed 's/.*="\(.*\)"/\1/') || path=""
        name=$(echo "$vbox_info" | grep "SharedFolderNameMachineMapping$i=" | sed 's/.*="\(.*\)"/\1/') || name=""
        [[ -z "$path" || -z "$name" ]] && break
        path="${path%/}"
        len=${#path}
        printf '%d|%s|%s\n' "$len" "$path" "$name"
    done | sort -t'|' -k1 -rn 2>/dev/null | cut -d'|' -f2-
}

# Get shared folders with drive letters from guest (guestcontrol "net use"). Output: "path|name|letter". Longest path first.
get_vbox_shared_folders_with_guest_letters() {
    local guest_map sharename letter path name
    declare -A guest_map
    while IFS='|' read -r sharename letter; do
        [[ -z "$sharename" || -z "$letter" ]] && continue
        guest_map["$sharename"]="$letter"
    done < <(get_guest_vbox_drive_mappings)
    while IFS='|' read -r path name; do
        [[ -z "$path" || -z "$name" ]] && continue
        letter="${guest_map[$name]:-}"
        [[ -z "$letter" ]] && continue
        printf '%s|%s|%s\n' "$path" "$name" "$letter"
    done < <(get_vbox_shared_folders_raw)
}

# Get share name in VBox for a given host path (for config mode: we need share name to build "net use").
get_vbox_share_name_for_path() {
    local search_path="$1" path name
    search_path="${search_path%/}"
    while IFS='|' read -r path name; do
        [[ -z "$path" || -z "$name" ]] && continue
        # Config path must match this share's path (exact or share is prefix of config path)
        if [[ "$search_path" == "$path" || "$search_path" == "$path"/* ]]; then
            echo "$name"
            return 0
        fi
    done < <(get_vbox_shared_folders_raw)
    return 1
}

# Build PowerShell "net use" commands. When config has shares: use config_share_list + VBox share names. When not: use guest-discovered path|name|letter.
build_net_use_ps() {
    local path drive share_name
    if config_share_list | grep -q .; then
        while IFS='|' read -r path drive; do
            [[ -z "$path" || -z "$drive" ]] && continue
            share_name=$(get_vbox_share_name_for_path "$path")
            [[ -z "$share_name" ]] && continue
            printf 'net use %s: \\\\vboxsvr\\\\%s 2>\$null; ' "$drive" "$share_name"
        done < <(config_share_list)
        return 0
    fi
    while IFS='|' read -r path name letter; do
        [[ -z "$path" || -z "$name" || -z "$letter" ]] && continue
        printf 'net use %s: \\\\vboxsvr\\\\%s 2>\$null; ' "$letter" "$name"
    done < <(get_vbox_shared_folders_with_guest_letters)
}

# Convert Unix path to Windows path.
# 1) If config has any VM_SHARE_PATH/VM_DRIVE_LETTER: use only those, no guest discovery.
# 2) Else: use only guest-discovered \\vboxsvr mappings (autodiscover).
# Returns 0 and echoes path on success; returns 1 on failure (caller must exit).
unix_to_windows_path() {
    local unix_path="$1"
    local path drive name letter config_list
    config_list=$(config_share_list)

    # 1) Config shares: use only config list
    if [[ -n "$config_list" ]]; then
        while IFS='|' read -r path drive; do
            [[ -z "$path" || -z "$drive" ]] && continue
            if [[ "$unix_path" == "$path"/* || "$unix_path" == "$path" ]]; then
                format_windows_path "$path" "$drive" "$unix_path"
                return 0
            fi
        done <<< "$config_list"
    else
        # 2) No config shares: use only guest-discovered mappings (autodiscover)
        while IFS='|' read -r path name letter; do
            [[ -z "$path" || -z "$name" || -z "$letter" ]] && continue
            if [[ "$unix_path" == "$path"/* || "$unix_path" == "$path" ]]; then
                format_windows_path "$path" "$letter" "$unix_path"
                return 0
            fi
        done < <(get_vbox_shared_folders_with_guest_letters)

        # File under a VBox share that has no drive letter (guest discovery)?
        while IFS='|' read -r path name; do
            [[ -z "$path" || -z "$name" ]] && continue
            if [[ "$unix_path" == "$path"/* || "$unix_path" == "$path" ]]; then
                show_error_notification "Share '$name' has no drive letter from guest (net use). Map it in Windows."
                echo "Error: Share $name has no drive letter from guest discovery" >&2
                return 1
            fi
        done < <(get_vbox_shared_folders_raw)
    fi

    show_error_notification "File is not under any shared folder. Add the path in VirtualBox (VM → Settings → Shared Folders), or set VM_SHARE_PATH / VM_DRIVE_LETTER in config."
    echo "Error: File $unix_path is not under any shared folder for this VM" >&2
    return 1
}

# Function to open a file using ShellExecute
open_file_with_shell_execute() {
    local windows_file="$1"
    # Use base64 so path with non-ASCII (e.g. umlauts) is passed correctly through VBoxManage
    local encoded net_use_ps powershell_command
    encoded=$(echo -n "$windows_file" | base64 -w 0 2>/dev/null || echo -n "$windows_file" | base64)
    # If path uses a drive letter (e.g. G:\...), map UNC in same session so "net use G: \\vboxsvr\share" runs before Invoke-Item
    net_use_ps=$(build_net_use_ps)
    powershell_command="${net_use_ps}\$p=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$encoded')); Invoke-Item -LiteralPath \$p"
    debug "Running PowerShell command for path (length ${#windows_file})"

    # Ensure UTF-8 when passing to VBoxManage
    output=$(LC_ALL=C.UTF-8 VBoxManage guestcontrol "$VM_NAME" run --exe "$VM_POWERSHELL_EXE" --username "$VM_USER" --password "$VM_PASSWORD" --quiet -- -Command "$powershell_command" 2>&1)
    exit_code=$?

    # Check for password or account issues
    if [ $exit_code -ne 0 ]; then
        if [[ "$output" == *"account on the guest is restricted"* ]] || [[ "$output" == *"can't be used to logon"* ]] || [[ "$output" == *"was not able to logon on guest"* ]]; then
            show_error_notification "Windows user account issue detected. Your password may have expired or the account is restricted. Please reset your password in Windows."
            echo "Error: Windows user account issue detected. Your password may have expired or the account is restricted." >&2
            echo "Please reset your password in Windows and update it in $CONFIG_FILE" >&2
            exit 1
        elif [[ "$output" == *"Authentication failure"* ]]; then
            show_error_notification "Authentication failed. Your password may be incorrect. Please check your password in the configuration file."
            echo "Error: Authentication failed. Your password may be incorrect." >&2
            echo "Please check your password in $CONFIG_FILE" >&2
            exit 1
        else
            show_error_notification "Error executing command in Windows VM: $output"
            echo "Error executing command in Windows VM: $output" >&2
            exit 1
        fi
    fi

    if [ -n "${APP_LOAD_DELAY:-}" ] && [ "$APP_LOAD_DELAY" -gt 0 ]; then
        debug "Sleeping for APP_LOAD_DELAY: $APP_LOAD_DELAY seconds"
        sleep "$APP_LOAD_DELAY"  # Wait for the specified delay
    fi
}

# Function to focus the VM window
focus_vm() {
    if [ "$WMCTRL_AVAILABLE" = true ]; then
        window_id=$(wmctrl -l | grep "$VM_NAME" | awk '{print $1}' | head -1) || true
        if [ -n "$window_id" ]; then
            wmctrl -ia "$window_id"
        fi
    fi
}

# Function to check if a user is logged in
check_user_logged_in() {
    local user_activity=$(VBoxManage guestproperty get "$VM_NAME" "/VirtualBox/GuestInfo/OS/LoggedInUsers" 2>/dev/null)
    if [[ "$user_activity" == *"Value: 1"* ]]; then
        return 0
    else
        return 1
    fi
}

# Function to start VM and wait for it to be ready
start_vm_and_wait() {
    if ! ( VBoxManage showvminfo "$VM_NAME" | grep -c "running (since" ) > /dev/null 2>&1; then
        debug "Starting VM with GUI"
        VBoxManage startvm "$VM_NAME" --type gui > /dev/null

        start_time=$(date +%s)

        # Wait for VM to be running and user to be logged in
        while true; do
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))

            if [ $elapsed -ge "$VM_START_TIMEOUT" ]; then
                show_error_notification "Timeout waiting for VM to start and user to log in (${VM_START_TIMEOUT}s)"
                echo "Timeout waiting for VM to start and user to log in"
                exit 1
            fi

            vm_state=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep ^VMState=) || vm_state=""

            if [[ "$vm_state" == 'VMState="running"' ]] && check_user_logged_in; then
                debug "VM is running and user is logged in"
                break
            fi

            sleep "$VM_START_POLL_INTERVAL"
        done
    else
        debug "VM is already running"
    fi
}

# Show success notification; only block/sleep when AUTO_FOCUS=true (short delay before focus so user sees notification)
handle_notification() {
    app_name=$(basename "$1")
    debug "Showing notification for app: $app_name"

    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        dunstify -A "default,Focus VM" -t "$NOTIFICATION_TIMEOUT" "VB App" "Virtualbox ${app_name} is ready."
    elif [ "$NOTIFY_SEND_AVAILABLE" = true ]; then
        notify-send -t "$NOTIFICATION_TIMEOUT" "VB App" "Virtualbox ${app_name} is ready."
    fi

    if [ "$AUTO_FOCUS" = true ] && [ "$WMCTRL_AVAILABLE" = true ]; then
        delay="${NOTIFICATION_FOCUS_DELAY:-0}"
        if [[ -n "$delay" && "$delay" -gt 0 ]]; then
            debug "Sleeping ${delay}s before focus"
            sleep "$delay"
        fi
        debug "Focusing VM window"
        focus_vm
        debug "VM window focused"
    fi
}

# Single code path for file or directory: resolve path, start VM, convert path, open in guest, notify
if [[ -f "$1" || -d "$1" ]]; then
    start_vm_and_wait
    WINDOWS_PATH=$(unix_to_windows_path "$1") || exit 1
    debug "Starting launch"
    open_file_with_shell_execute "$WINDOWS_PATH"
    debug "Launch command sent"
    handle_notification "$1"
    debug "Script completed"
else
    show_error_notification "File or directory not found: $1"
    exit 1
fi

exit 0
