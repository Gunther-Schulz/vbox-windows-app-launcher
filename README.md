# vbox-windows-app-launcher

A tool for launching Windows applications in a VirtualBox environment.

## Description

vbox-windows-app-launcher is a utility designed to seamlessly launch Windows applications within a VirtualBox virtual machine. This tool is particularly useful for users who need to run Windows applications in an isolated environment or on systems where native installation is not possible or desired.

This adds a feature that I was missing since I moved over from Parallel Desktop on macOS to VirtualBox on Linux. Similar to the "Open in VM" feature in Parallel Desktop, this script allows you to open various documents in a VirtualBox VM directly from the host system's file manager.

## Attribution

This project was inspired by andpy73, sbnwl, 3Pilif, and TVG and is based on this forum thread: https://forums.virtualbox.org/viewtopic.php?t=91799&sid=fe97378eec124475e838cf6ea5ea79e3&start=15

## Features

- Easy launch of Windows applications in a VirtualBox VM
- Seamless integration with host system
- Configurable VM settings
- Automatic VM startup and user login detection
- Optional automatic window focus and desktop notifications
- Desktop integration for easy file opening

## Installation

1. Clone this repository or download the script files.
2. Make sure you have VirtualBox installed on your system.
3. Install the optional dependencies:
   ```
   sudo pacman -S dunst wmctrl
   ```
   - dunst: notification daemon used for desktop notifications
   - wmctrl: window manager control used for automatic window focus
4. Copy `vbox_windows_app_launcher.conf.sample` to `~/.config/vbox_windows_app_launcher.conf` and edit it with your settings.
5. Make the script executable:
   ```
   chmod +x vbox_windows_app_launcher.sh
   ```
6. Edit the `open-windows-app-in-vm.desktop` file:
   - Update the `Exec=` line with the correct path to your `vbox_windows_app_launcher.sh` script:
     ```
     Exec=/path/to/your/script/vbox_windows_app_launcher.sh %f
     ```
7. Install the desktop file for easy file opening:
   - For local installation (current user only):
     ```
     mkdir -p ~/.local/share/applications
     cp open-windows-app-in-vm.desktop ~/.local/share/applications/
     ```
   - For global installation (all users, requires sudo):
     ```
     sudo cp open-windows-app-in-vm.desktop /usr/share/applications/
     ```
8. Update the desktop database:
   ```
   update-desktop-database ~/.local/share/applications
   ```

## Usage

1. Configure your settings in `~/.config/vbox_windows_app_launcher.conf`.
2. Double-click on any file or folder to open it in the VM, or run the script directly:
   ```
   ./vbox_windows_app_launcher.sh /path/to/your/file_or_folder
   ```

The script will automatically use the appropriate application in the VM to open the file or folder.

## Configuration

Edit `~/.config/vbox_windows_app_launcher.conf` with your specific settings:

- `VM_NAME`: Name of your VirtualBox VM
- `VM_USER`: Username in the VM
- `VM_PASSWORD`: Password for the VM user
- `VM_SHARE_PATH`: Path to shared folder on host
- `VM_DRIVE_LETTER`: Drive letter for shared folder in VM
- `AUTO_FOCUS`: Set to true/false to enable/disable automatic window focus
- `SCRIPT_TIMEOUT`: Timeout for the script in seconds
- `NOTIFICATION_TIMEOUT`: Timeout for notifications in milliseconds

Check out the `vbox_windows_app_launcher.conf.sample` file for more details.

## Requirements

- VirtualBox
- Windows applications installed in a VirtualBox VM
- Bash shell

### Optional dependencies
- dunst (for notifications)
- wmctrl (for window management)

## Troubleshooting
If you encouter the following error:
```
VBoxManage: error: Waiting for guest process failed: The specified user account on the guest is restricted and can't be used to logon
VBoxManage: error: Details: code VBOX_E_IPRT_ERROR (0x80bb0005), component GuestSessionWrap, interface IGuestSession, callee nsISupports
VBoxManage: error: Context: "WaitForArray(ComSafeArrayAsInParam(aSessionWaitFlags), 30 * 1000, &enmWaitResult)" at line 770 of file VBoxManageGuestCtrl.cpp
```

That can potentially mean taht your password expired and that you need to reset it in the VM. You can do that while being logged in and in an administrator command prompt:
```bash
net user WindowsAccountName *
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. This project was initially developed with contributions from andpy73, sbnwl, 3Pilif, and TVG.

## License

This project is open-source. This has no specific license.

## Support

For support, please open an issue in the GitHub repository or contact the maintainers.

## Desktop Integration

The `open-windows-app-in-vm.desktop` file provides desktop integration for easy file opening. It associates common file types with the launcher script.