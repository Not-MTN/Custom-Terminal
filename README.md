# Ghosty Terminal Studio

Ghosty is a Windows-focused terminal customization desktop app. It previews themes and, from its packaged Windows desktop app, can apply a selected palette to Windows Terminal and legacy Command Prompt, install Starship/eza/bat plus Clink and a Nerd Font with WinGet, and configure both PowerShell and CMD startup. It backs up Windows Terminal `settings.json` before changing it; close and reopen existing terminal windows to load the changes.

## Build the Windows app

Requires Node.js/npm and a Windows build environment (or a Linux host with access to Electron's Windows binaries):

```sh
npm install
npm run dist:win
```

The portable app is written to `release/Ghosty-1.0.0.exe`. Download and launch it, choose a theme and tools, then use **Apply to Windows** and confirm the native confirmation dialog. The app needs Windows Terminal and WinGet for all features; WinGet may show package prompts. Reopen PowerShell and Windows Terminal after applying.

## Development

```sh
npm install
npm run dev
```

The browser preview cannot modify the host PC. Actual local setup operations are only exposed through the Electron desktop bridge and are confirmed before execution.
