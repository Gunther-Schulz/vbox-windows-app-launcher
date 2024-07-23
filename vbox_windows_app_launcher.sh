#!/bin/bash

# Load configuration from ~/.config/vbox_windows_app_launcher.conf
CONFIG_FILE="$HOME/.config/vbox_windows_app_launcher.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Check if wmctrl is available
if command -v wmctrl >/dev/null 2>&1; then
    WMCTRL_AVAILABLE=true
else
    WMCTRL_AVAILABLE=false
fi

# Check if dunstify is available
if command -v dunstify >/dev/null 2>&1; then
    DUNSTIFY_AVAILABLE=true
else
    DUNSTIFY_AVAILABLE=false
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
    local powershell_command="Invoke-Item '$windows_file'"
    VBoxManage guestcontrol "$VM_NAME" run --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" --username "$VM_USER" --password "$VM_PASSWORD" --quiet -- -Command "$powershell_command"
    sleep 2  # Add a small delay to allow the application to start
}

# Function to focus the VM window
focus_vm() {
    if [ "$WMCTRL_AVAILABLE" = true ]; then
        window_id=$(wmctrl -l | grep "$VM_NAME" | awk '{print $1;}' | head -1)
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
        VBoxManage startvm "$VM_NAME" --type separate > /dev/null
        
        # Set a timeout (in seconds)
        TIMEOUT=300  # 5 minutes
        start_time=$(date +%s)
        
        # Wait for VM to be running and user to be logged in
        while true; do
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            
            if [ $elapsed -ge $TIMEOUT ]; then
                echo "Timeout waiting for VM to start and user to log in"
                exit 1
            fi
            
            vm_state=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep ^VMState=)

            if [[ "$vm_state" == 'VMState="running"' ]] && check_user_logged_in; then
                break
            fi
            
            sleep 5
        done
    fi
}

# Start VM and wait for it to be ready before proceeding
start_vm_and_wait

if [ -f "$1" ]; then
    start_vm_if_needed  # Add this line to start the VM if needed
    WINDOWS_FILE=$(unix_to_windows_path "$1")
    open_file_with_shell_execute "$WINDOWS_FILE"
elif [ -d "$1" ]; then
    WINDOWS_PATH=$(unix_to_windows_path "$1")
    open_file_with_shell_execute "$WINDOWS_PATH"
else
    echo "File or directory not found: $1"
    exit 1
fi

# Check if the application started successfully
if [ $? -ne 0 ]; then
    echo "Failed to start the Windows application"
    exit 1
fi

# Update notification message
handle_notification() {
    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        app_name=$(basename "$1")
        action=$(dunstify -A "focus,Focus VM" -t "$NOTIFICATION_TIMEOUT" "VB App" "Virtualbox ${app_name} is starting...")
        
        if [ "$action" = "focus" ]; then
            if [ "$WMCTRL_AVAILABLE" = true ]; then
                focus_vm
            fi
        fi
    fi
}

# Start notification handling in background
if [ "$DUNSTIFY_AVAILABLE" = true ]; then
    handle_notification "$1" &
    notification_pid=$!
fi

# Focus the VM window if AUTO_FOCUS is true and wmctrl is available
if [ "$AUTO_FOCUS" = true ]; then
    if [ "$WMCTRL_AVAILABLE" = true ]; then
        focus_vm
    fi
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