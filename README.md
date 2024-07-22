# vbox-office-launcher

A tool for launching Microsoft Office applications in a VirtualBox environment.

## Description

vbox-office-launcher is a utility designed to seamlessly launch Microsoft Office applications within a VirtualBox virtual machine. This tool is particularly useful for users who need to run Office applications in an isolated environment or on systems where native installation is not possible or desired.

## Attribution

This project was inspired by andpy73, sbnwl, 3Pilif, and TVG and is based on this forum thread: https://forums.virtualbox.org/viewtopic.php?t=91799&sid=fe97378eec124475e838cf6ea5ea79e3&start=15

## Features

- Easy launch of Microsoft Office applications in a VirtualBox VM
- Seamless integration with host system
- Configurable VM settings
- Support for Word, Excel, and PowerPoint
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
4. Copy `vbox_office_launcher.conf.sample` to `~/.config/vbox_office_launcher.conf` and edit it with your settings.
5. Make the script executable:
   ```
   chmod +x vbox_office_launcher.sh
   ```
6. Edit the `open-office-in-vm.desktop` file:
   - Update the `Exec=` line with the correct path to your `vbox_office_launcher.sh` script:
     ```
     Exec=/path/to/your/script/vbox_office_launcher.sh %f
     ```
7. Install the desktop file for easy file opening:
   - For local installation (current user only):
     ```
     mkdir -p ~/.local/share/applications
     cp open-office-in-vm.desktop ~/.local/share/applications/
     ```
   - For global installation (all users, requires sudo):
     ```
     sudo cp open-office-in-vm.desktop /usr/share/applications/
     ```
8. Update the desktop database:
   ```
   update-desktop-database ~/.local/share/applications
   ```

## Usage

1. Configure your settings in `~/.config/vbox_office_launcher.conf`.
2. Double-click on a supported Office document to open it in the VM, or run the script directly:
   ```
   ./vbox_office_launcher.sh /path/to/your/document.docx
   ```

## Configuration

Edit `~/.config/vbox_office_launcher.conf` with your specific settings:

- `VM_NAME`: Name of your VirtualBox VM
- `VM_USER`: Username in the VM
- `VM_PASSWORD`: Password for the VM user
- `WORD_PATH`, `EXCEL_PATH`, `POWERPOINT_PATH`: Paths to Office executables in the VM
- `VM_SHARE_PATH`: Path to shared folder on host
- `VM_DRIVE_LETTER`: Drive letter for shared folder in VM
- `AUTO_FOCUS`: Set to true/false to enable/disable automatic window focus
- `SCRIPT_TIMEOUT`: Timeout for the script in seconds
- `NOTIFICATION_TIMEOUT`: Timeout for notifications in milliseconds

## Requirements

- VirtualBox
- Microsoft Office installed in a VirtualBox VM
- Bash shell

### Optional dependencies
- dunst (for notifications)
- wmctrl (for window management)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. This project was initially developed with contributions from andpy73, sbnwl, 3Pilif, and TVG.

## License

This project is open-source. Please add your chosen license here.

## Support

For support, please open an issue in the GitHub repository or contact the maintainers.

## Desktop Integration

The `open-office-in-vm.desktop` file provides desktop integration for easy file opening. It associates common Office file types with the launcher script.