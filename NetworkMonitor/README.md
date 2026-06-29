# NetworkMonitor - macOS Menu Bar Network Speed Monitor

A lightweight, minimal macOS menu bar app that shows real-time network upload/download speeds.

## Features
- 📊 Real-time download & upload speed display in menu bar
- 🚫 Hidden from Dock (runs as menu bar accessory)
- 💾 Tiny footprint: app bundle **124K**, DMG **28K**
- 🔋 Low memory usage (no WebKit/Electron - pure native Swift + AppKit)
- 🏗️ ARM64 native (Apple Silicon)

## Installation
1. Open `NetworkMonitor.dmg`
2. Drag `NetworkMonitor.app` to the `Applications` folder
3. Right-click `NetworkMonitor.app` → **Open** (first launch only, due to ad-hoc signing)
4. The app appears in the menu bar as `▼0 ▲0` and starts monitoring immediately

## Usage
- **Menu bar**: Shows `▼{down} ▲{up}` (e.g., ▼1.2M ▲340K)
- **Click menu**: Shows detailed speeds and total data transferred
- **Quit**: Click the menu item or press ⌘Q

## Uninstall
- Drag `NetworkMonitor.app` from Applications to Trash
