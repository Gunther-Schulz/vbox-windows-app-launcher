#!/bin/bash

# -- CODE DEVELOPERS/CONTRIBUTORS -- andpy73, sbnwl, 3Pilif, TVG
# https://forums.virtualbox.org/viewtopic.php?t=91799&sid=fe97378eec124475e838cf6ea5ea79e3&start=15
# Dependencies: sudo pacman -S dunst

# TEST:_ ./vmc.sh /home/g/hidrive/Öffentlich\ Planungsbüro\ Schulz/Projekte/potenzialanalye\ vorlage.docx    

# Configuration variables
VM_NAME="Win11"
VM_USER="g"
VM_PASSWORD="pwd"
WORD_PATH="C:\\Program Files\\Microsoft Office\\root\\Office16\\WINWORD.EXE"
EXCEL_PATH="C:\\Program Files\\Microsoft Office\\root\\Office16\\EXCEL.EXE"
POWERPOINT_PATH="C:\\Program Files\\Microsoft Office\\root\\Office16\\POWERPNT.EXE"
VM_SHARE_PATH="/home/g/"
VM_DRIVE_LETTER="G:"
AUTO_FOCUS=false # Set to false if you don't want automatic focus
SCRIPT_TIMEOUT=6  # In seconds. We set this to the default timeout for notifications. this needs to be as long as the notification stays up.
NOTIFICATION_TIMEOUT=$((SCRIPT_TIMEOUT * 1000))  # Notification timeout in milliseconds. This seems to be ignore by dustify actually

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
get_office_app() {
    case "${1##*.}" in
        doc|docx) echo "$WORD_PATH" ;;
        xls|xlsx) echo "$EXCEL_PATH" ;;
        ppt|pptx) echo "$POWERPOINT_PATH" ;;
        *) echo "$WORD_PATH" ;; # Default to Word if extension is unknown
    esac
}

# Construct the VBoxManage command to start the appropriate Office application
OFFICE_PATH=$(get_office_app "$1")
cmd="VBoxManage guestcontrol \"$VM_NAME\" run --exe \"$OFFICE_PATH\" --username $VM_USER --password $VM_PASSWORD --wait-stdout --wait-stderr --timeout 30000"

if [ -f "$1" ]; then
    FILE=$(echo "$1" | sed "s|^$VM_SHARE_PATH|$VM_DRIVE_LETTER\\\\|; s|/|\\\\|g")
    cmd+=" -- \"$FILE\""
fi

# Run the command to start Word in the background
eval "$cmd" &>/dev/null &
word_pid=$!

# Check if Word started successfully
if [ $? -ne 0 ]; then
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
        app_name=$(basename "$OFFICE_PATH" .EXE)
        action=$(dunstify -A "focus,Focus VM" -t "$NOTIFICATION_TIMEOUT" "VB Office" "Virtualbox $app_name is starting...")
        
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

# Cleanup function
cleanup() {
    if [ "$DUNSTIFY_AVAILABLE" = true ]; then
        kill $notification_pid 2>/dev/null
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Wait for the timeout
if [ "$DUNSTIFY_AVAILABLE" = true ]; then
    end_time=$((SECONDS + SCRIPT_TIMEOUT))
    while [ $SECONDS -lt $end_time ]; do
        if ! kill -0 $notification_pid 2>/dev/null; then
            break
        fi
        sleep 1
    done
fi

exit 0