# Compass Gate FTP

<p align="center">
  <img src="Compass%20Gate%20FTP/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="128" height="128" alt="Compass Gate FTP Logo" />
</p>

<p align="center">
  <strong>A modern, fast, and native SFTP, SSH, and FTP client designed specifically for macOS.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20(Sonoma%20%7C%20Sequoia)-000000.svg?logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-orange.svg" alt="Universal Binary" />
  <img src="https://img.shields.io/badge/Language-Swift%205.0-F05138.svg?logo=swift" alt="Swift 5" />
  <img src="https://img.shields.io/badge/Framework-SwiftUI%20%7C%20SwiftData-blue.svg" alt="SwiftUI & SwiftData" />
  <img src="https://img.shields.io/badge/Version-0.1.0-brightgreen.svg" alt="Version 0.1.0" />
</p>

---

## 🧭 Overview

**Compass Gate FTP** is built from the ground up using Apple's modern SwiftUI and SwiftData frameworks to provide a smooth, responsive, and aesthetically native file transfer experience on macOS. 

Whether you manage remote cloud instances, web servers, or NAS systems, Compass Gate FTP combines powerful connection management with dual-pane file browsing and integrated developer utilities.

---

## ✨ Features

### 🚀 Connection & Session Management
- **Multi-Protocol Support**: Seamlessly connect to remote servers via **SFTP**, **SSH**, and **FTP**.
- **Tabbed Browsing**: Open multiple active server sessions concurrently in independent tabs with automatic state persistence.
- **Server Bookmarks & Custom Groups**: Categorize your connections into custom color-coded groups (*Production*, *Staging*, *Personal*, etc.).
- **Quick Connect**: Jump into remote hosts quickly with automatic port negotiation and host history.

### 📂 Dual-Pane File Manager
- **Synchronized Dual Browsers**: View your local filesystem and remote server side-by-side.
- **Quick Look Integration**: Preview images, text files, source code, PDFs, and archives instantly by pressing <kbd>Space</kbd>.
- **Interactive Breadcrumb Navigation**: Navigate directories effortlessly using clickable path segments or directly enter destination paths.
- **Unified Table Layout**: Consistent column visibility, sorting, and file attributes (Size, Kind, Date Modified, Permissions).

### ⚡ Transfers & Background Operations
- **Activity & Transfer Queue**: Track upload/download speeds, transferred bytes, and active job queues with real-time feedback.
- **Drag-and-Drop Operations**: Drag files and folders between local and remote panes or directly from Finder.
- **Intelligent Error Diagnostics**: Clear, human-readable troubleshooting guidance for network timeouts, bad credentials, and permission denials.

### 🛠️ Developer & Power Tools
- **1-Click Terminal Launcher**: Launch interactive SSH sessions directly in **Terminal** or **iTerm2** with automated credential handling.
- **Server Resource Monitor**: Inspect remote server health (CPU load, memory consumption, and disk usage) straight from the session inspector.
- **Config & Profile Importer**: Effortlessly import saved servers and hosts from:
  - OpenSSH (`~/.ssh/config`)
  - FileZilla (`sitemanager.xml`, `recents.xml`)
  - Transmit & ForkLift JSON exports

### 🖥️ Native macOS Experience
- **Universal Binary**: Compiled natively for both **Apple Silicon** (M1/M2/M3/M4) and **Intel 64-bit** (`x86_64`) Macs.
- **macOS Design Language**: Embraces vibrant materials, native selection highlights, and dark/light mode adaptations.
- **Branded DMG Installer**: Includes a custom-styled drag-and-drop installer window.

---

## 📋 System Requirements

- **macOS Version**: macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later.
- **Hardware Architecture**:
  - Apple Silicon (M1, M2, M3, M4 series)
  - Intel 64-bit (`x86_64`)

---

## 📦 Installation

### From Pre-built Disk Image (Recommended)
1. Download [`Compass-Gate-FTP-0.1.0.dmg`](file:///Users/sukmadewa/Sites/projects/Compass%20Gate%20FTP/Compass-Gate-FTP-0.1.0.dmg).
2. Double-click the `.dmg` file to mount it.
3. Drag **Compass Gate FTP** into the **Applications** folder shortcut.
4. Launch the app from Launchpad, Spotlight, or the Applications directory.

---

## 🛠️ Building from Source

### Prerequisites
- macOS 14.0+
- Xcode 16.0+ with Command Line Tools installed

### Clone and Build
```bash
# Clone the repository
git clone https://github.com/bobbyrinaldo29/Compass-Gate-FTP.git
cd Compass-Gate-FTP

# Build Release Universal Binary (Apple Silicon + Intel)
xcodebuild -project "Compass Gate FTP.xcodeproj" \
  -scheme "Compass Gate FTP" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build CONFIGURATION_BUILD_DIR="$(pwd)/build/Release"
```

### Running Tests
Run the comprehensive test suite (Unit Tests and UI Tests):
```bash
xcodebuild test \
  -project "Compass Gate FTP.xcodeproj" \
  -scheme "Compass Gate FTP" \
  -destination 'platform=macOS'
```

---

## ⌨️ Useful Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| <kbd>Space</kbd> | Quick Look preview for selected file or folder |
| <kbd>⌘</kbd> + <kbd>N</kbd> | Open New Connection dialog |
| <kbd>⌘</kbd> + <kbd>T</kbd> | Open New Session Tab |
| <kbd>⌘</kbd> + <kbd>W</kbd> | Close Current Session Tab |
| <kbd>⌘</kbd> + <kbd>R</kbd> | Refresh directory listing |
| <kbd>⌘</kbd> + <kbd>,</kbd> | Open Settings / Preferences |

---

## 🏗️ Architecture & Open Source Dependencies

Compass Gate FTP leverages proven Swift libraries:
- **[Citadel](https://github.com/orlandos-nl/Citadel)**: Native Swift SSH & SFTP client framework.
- **[swift-nio](https://github.com/apple/swift-nio)**: Apple's asynchronous event-driven network application framework.
- **[swift-crypto](https://github.com/apple/swift-crypto)**: Cryptographic algorithms backing secure authentication.
- **[swift-collections](https://github.com/apple/swift-collections)** & **[swift-atomics](https://github.com/apple/swift-atomics)**: High-performance data structures.
