#!/bin/bash

# Load configuration from ~/.config/vbox_windows_app_launcher.conf
CONFIG_FILE="$HOME/.config/vbox_windows_app_launcher.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Function to convert Unix path to Windows path
unix_to_windows_path() {
    local unix_path="$1"
    local windows_path=$(echo "$unix_path" | sed "s|^/home/g|$VM_DRIVE_LETTER|" | sed 's|/|\\|g')
    echo "$windows_path"
}

# Function to check if a file is already open
is_file_open() {
    local windows_file="$1"
    local check_command="Get-Process | Where-Object { \$_.MainWindowTitle -like \"*$windows_file*\" } | Select-Object -First 1"
    local result=$(VBoxManage guestcontrol "$VM_NAME" run --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" --username "$VM_USER" --password "$VM_PASSWORD" --quiet -- -Command "$check_command")
    if [ -n "$result" ]; then
        return 0
    else
        return 1
    fi
}

# Function to open a file using ShellExecute
open_file_with_shell_execute() {
    local windows_file="$1"
    if ! is_file_open "$windows_file"; then
        local powershell_command="[System.Diagnostics.Process]::Start('$windows_file')"
        VBoxManage guestcontrol "$VM_NAME" run --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" --username "$VM_USER" --password "$VM_PASSWORD" --quiet -- -Command "$powershell_command"
        sleep 2  # Add a small delay to allow the application to start
    else
        echo "File is already open: $windows_file"
    fi
}

if [ -f "$1" ]; then
    WINDOWS_FILE=$(unix_to_windows_path "$1")
    open_file_with_shell_execute "$WINDOWS_FILE"
else
    echo "File not found: $1"
    exit 1
fi

# Check if the application started successfully
if [ $? -ne 0 ]; then
    echo "Failed to start the Windows application"
    exit 1
fi

# Check if dunstify is available
if command -v dunstify >/dev/null 2>&1; then
    DUNSTIFY_AVAILABLE=true
else
    DUNSTIFY_AVAILABLE=false
fi

# Function to focus the VM window
focus_vm() {
    if [ "$WMCTRL_AVAILABLE" = true ]; then
        window_id=$(wmctrl -l | grep "$VM_NAME" | awk '{print $1;}' | head -1)
        sleep 1
        wmctrl -ia $window_id
    fi
}

# Update notification message
handle_notification() {
    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        app_name=$(basename "$APP_PATH" .EXE)
        action=$(dunstify -A "focus,Focus VM" -t "$NOTIFICATION_TIMEOUT" "VB App" "Virtualbox ${app_name} is starting...")
        
        if [ "$action" = "focus" ] && [ "$WMCTRL_AVAILABLE" = true ]; then
            focus_vm
        fi
    fi
}

# Start notification handling in background
if [ "$DUNSTIFY_AVAILABLE" = true ]; then
    handle_notification &
    notification_pid=$!
fi

# Focus the VM window if AUTO_FOCUS is true and wmctrl is available
if [ "$AUTO_FOCUS" = true ] && [ "$WMCTRL_AVAILABLE" = true ]; then
    focus_vm
fi

# Wait for the script timeout duration before exiting
sleep "$SCRIPT_TIMEOUT"

# Cleanup function
cleanup() {
    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        kill $notification_pid 2>/dev/null
    fi
}

# Set trap for cleanup
trap cleanup EXIT

exit 0