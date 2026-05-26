# Powershell Shortcuts Suite
A powershell tool to get the most out of windows "Run"

## Installation
`st install C:\Path\To\Install\Directory`

And that's it.

## Uninstallation
`st uninstall`

The system will not delete anything upon uninstallation, it just removes its directory from user's PATH

## Adding new shortcuts
`st new C:\Path\To\Program MyCommand`

And that creates a shortcut in the install directory with the name `MyCommand.lnk`.

You can call `Win+R` and type `MyCommand` to execute `C:\Path\To\Program` :)

## Listing shortcuts
`st list`

It generates a table-like view with every shortcut available in it's directory.

You can also pipe that result into other commands like `st list | findstr /i "foo"` and that will show you any command that has the keyword `foo`

---

New features will be added by demand.

Feel free to submit your own ideas in issues and pull requests 
