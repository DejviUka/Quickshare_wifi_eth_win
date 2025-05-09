 Wi-Fi Sharing Toggle Script

 SYNOPSIS:
   Toggle Windows Internet Connection Sharing (ICS) between a prioritized Wi-Fi adapter
   and a prioritized Ethernet adapter, based on MAC address lists.

 FILES:
   - wifishare.ps1       : PowerShell script implementing the toggle logic and auto-scan functions.
   - mac.txt             : Priority list of Wi-Fi and Ethernet MAC addresses.
   - run-wifishare.cmd   : Batch wrapper for launching the PowerShell script.
   - README.md           : This documentation file.

 PREREQUISITES:
   - Windows 8, 10, or 11
   - PowerShell (v5 or later)
   - Administrator privileges (script auto-elevates if needed)

 mac.txt FORMAT:
   Lines must start with 'wifi:' or 'ethernet:' followed by a MAC address.
   Accepts '-' or ':' separators, case-insensitive.

   Example:
     wifi:    XX:XX:XX:XX:XX:XX
     wifi:    A1:B2:C3:D4:E5:F6
     ethernet:XX:XX:XX:XX:XX:XX
     ethernet:02-AB-CD-EF-12-34

 USAGE:
   1. Place wifishare.ps1, mac.txt, run-wifishare.cmd, and README.md in the same folder.
   2. Edit mac.txt to define your adapter priority lists.
   3. Double-click run-wifishare.cmd (or execute it from a command prompt).
   4. A menu will prompt you to:
        1. Enable sharing
        2. Disable sharing
        3. Add a Wi-Fi MAC (manual entry)
        4. Add an Ethernet MAC (manual entry)
        5. Auto-add a Wi-Fi MAC (scan and select)
        6. Auto-add an Ethernet MAC (scan and select)
        Q. Quit the script

 LOGGING:
   - All operations and errors are logged to 'logps.txt' in the same folder.
   - Each run appends a timestamped header.

 BATCH WRAPPER (run-wifishare.cmd):
   @echo off
   pushd "%~dp0"     # Change to script directory
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "wifishare.ps1"
   popd
   pause              # Wait for user keypress to review output

 NOTES:
   - The script auto-elevates if not run as Administrator.
   - If no adapter matches the MAC list, the script will exit with an error.

 LICENSE:
   MIT License (or your preferred license).

 END OF README
