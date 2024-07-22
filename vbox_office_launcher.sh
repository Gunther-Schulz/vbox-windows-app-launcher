#!/bin/bash

# Load configuration from ~/.config/vbox_office_launcher.conf
CONFIG_FILE="$HOME/.config/vbox_office_launcher.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# -- CODE DEVELOPERS/CONTRIBUTORS -- andpy73, sbnwl, 3Pilif, TVG
# https://forums.virtualbox.org/viewtopic.php?t=91799&sid=fe97378eec124475e838cf6ea5ea79e3&start=15
# Dependencies: sudo pacman -S dunst

# clear

# Function to check if a user is logged in
check_user_logged_in() {
    local user_activity=$(VBoxManage guestproperty get "$VM_NAME" "/VirtualBox/GuestInfo/OS/LoggedInUsers" 2>/dev/null)
    if [[ "$user_activity" == *"Value: 1"* ]]; then
        return 0
    else
        return 1
    fi
}

# Check if wmctrl is available
if command -v wmctrl >/dev/null 2>&1; then
    WMCTRL_AVAILABLE=true
else
    WMCTRL_AVAILABLE=false
    AUTO_FOCUS=false  # Disable auto-focus if wmctrl is not available
fi

# Start VM and wait for it to be ready
if ! ( vboxmanage showvminfo "$VM_NAME" | grep -c "running (since" ) > /dev/null 2>&1; then
    vboxmanage startvm "$VM_NAME" --type separate > /dev/null
    
    # Set a timeout (in seconds)
    TIMEOUT=300  # 5 minutes
    start_time=$(date +%s)
    
    # Wait for VM to be running and user to be logged in
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $TIMEOUT ]; then
            exit 1
        fi
        
        vm_state=$(vboxmanage showvminfo "$VM_NAME" --machinereadable | grep ^VMState=)

        if [[ "$vm_state" == 'VMState="running"' ]] && check_user_logged_in; then
            break
        fi
        
        sleep 5
    done
fi

# Function to determine the Office application based on file extension
get_windows_app() {
    local extension="${1##*.}"
    if [[ -n "${CUSTOM_APPS[".$extension"]}" ]]; then
        echo "${CUSTOM_APPS[".$extension"]}"
    else
        echo "${CUSTOM_APPS[".doc"]}"  # Default to Word if extension is unknown
    fi
}

# Function to convert Unix path to Windows path
unix_to_windows_path() {
    local unix_path="$1"
    # Replace /home/g with G:
    local windows_path=$(echo "$unix_path" | sed "s|^/home/g|$VM_DRIVE_LETTER|")
    # Replace remaining forward slashes with backslashes
    windows_path=$(echo "$windows_path" | sed 's|/|\\|g')
    echo "$windows_path"
}

# Construct the VBoxManage command to start the appropriate Windows application
APP_PATH=$(get_windows_app "$1")
cmd="VBoxManage guestcontrol \"$VM_NAME\" run --exe \"$APP_PATH\" --username $VM_USER --password $VM_PASSWORD --quiet"

if [ -f "$1" ]; then
    WINDOWS_FILE=$(unix_to_windows_path "$1")
    cmd+=" -- \"$WINDOWS_FILE\""
fi

# Run the command to start Word in the background
eval "$cmd &"

# Check if Word started successfully
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
        action=$(dunstify -A "focus,Focus VM" -t "$NOTIFICATION_TIMEOUT" "VB Office" "Virtualbox ${app_name} is starting...")
        
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