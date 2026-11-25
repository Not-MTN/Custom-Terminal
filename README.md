# Ghosty Terminal Studio

Ghosty is a Windows-focused terminal customization desktop app. It previews themes and, from its packaged Windows desktop app, can apply a selected palette to Windows Terminal, install Starship/eza/bat with WinGet, and configure the PowerShell profile. It backs up `settings.json` before changing it.

## Build the Windows installer

Requires Node.js/npm and a Windows build environment (or a Linux host with access to Electron's Windows binaries):

```sh
npm install
npm run dist:win
```

The installer is written to `release/Ghosty-Setup-1.0.0.exe`. Launch the app, choose a theme and tools, then use **Apply to Windows** and confirm the native confirmation dialog. The app needs Windows Terminal and WinGet for all features; WinGet may show package prompts. Reopen PowerShell and Windows Terminal after applying.

## Development

```sh
npm install
npm run dev
```

The browser preview cannot modify the host PC. Actual local setup operations are only exposed through the Electron desktop bridge and are confirmed before execution.
