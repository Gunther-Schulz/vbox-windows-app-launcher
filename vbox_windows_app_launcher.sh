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

# Function to open a file using ShellExecute
open_file_with_shell_execute() {
    local windows_file="$1"
    local powershell_command="Start-Process '$windows_file'"
    echo "Debug: Running PowerShell command: $powershell_command" >&2
    VBoxManage guestcontrol "$VM_NAME" run --exe "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" --username "$VM_USER" --password "$VM_PASSWORD" --quiet -- -Command "$powershell_command"
    if [ -n "$APP_LOAD_DELAY" ] && [ "$APP_LOAD_DELAY" -gt 0 ]; then
        echo "Debug: Sleeping for APP_LOAD_DELAY: $APP_LOAD_DELAY seconds" >&2
        sleep "$APP_LOAD_DELAY"  # Wait for the specified delay
    fi
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
        echo "Debug: Starting VM with GUI" >&2
        VBoxManage startvm "$VM_NAME" --type gui > /dev/null
        
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
                echo "Debug: VM is running and user is logged in" >&2
                break
            fi
            
            sleep 5
        done
    else
        echo "Debug: VM is already running" >&2
    fi
}

# Function to update notification message
handle_notification() {
    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        app_name=$(basename "$1")
        echo "Debug: Showing notification for app: $app_name" >&2
        dunstify -A "default,Focus VM" -t "$NOTIFICATION_TIMEOUT" "VB App" "Virtualbox ${app_name} is ready."
        
        # Wait for notification timeout
        echo "Debug: Sleeping for NOTIFICATION_TIMEOUT: $((NOTIFICATION_TIMEOUT / 1000)) seconds" >&2
        sleep $((NOTIFICATION_TIMEOUT / 1000))
        
        if [ "$AUTO_FOCUS" = true ] && [ "$WMCTRL_AVAILABLE" = true ]; then
            echo "Debug: Focusing VM window" >&2
            focus_vm
            echo "Debug: VM window focused" >&2
        fi
    fi
}

if [ -f "$1" ]; then
    start_vm_and_wait
    WINDOWS_FILE=$(unix_to_windows_path "$1")
    echo "Debug: Starting application launch" >&2
    open_file_with_shell_execute "$WINDOWS_FILE"
    echo "Debug: Application launch command sent" >&2
    handle_notification "$1"
    echo "Debug: Notification handled" >&2
elif [ -d "$1" ]; then
    WINDOWS_PATH=$(unix_to_windows_path "$1")
    echo "Debug: Starting directory open" >&2
    open_file_with_shell_execute "$WINDOWS_PATH"
    echo "Debug: Directory open command sent" >&2
    handle_notification "$1"
    echo "Debug: Notification handled" >&2
else
    echo "File or directory not found: $1"
    exit 1
fi

echo "Debug: Script completed, exiting" >&2

exit 0