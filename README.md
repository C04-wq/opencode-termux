# ⚡ opencode-termux

<p align="center">
  <a href="https://opencode.ai">
    <img src="opencode-logo.svg" alt="OpenCode Logo" height="42">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Termux-green?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/Architecture-aarch64-blue?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/npm/v/opencode-termux?style=for-the-badge&color=red" alt="npm version">
  <img src="https://img.shields.io/github/actions/workflow/status/C04-wq/opencode-termux/auto-update.yml?style=for-the-badge&label=auto-update" alt="Workflow status">
  <img src="https://img.shields.io/npm/dt/opencode-termux?style=for-the-badge&color=orange" alt="downloads">
</p>

<p align="center">
  <b>OpenCode AI assistant compiled for Android Termux (aarch64)</b><br>
  <sub>With automatic updates every time you run <code>opencode</code></sub>
</p>

---

## 🚀 Installation

```bash
npm install -g opencode-termux
```

Once installed, simply run:

```bash
opencode
```

> **That's it!** The wrapper handles everything: downloads the binary, sets up musl libraries, and launches OpenCode.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔧 **Auto-setup** | First run downloads and configures everything automatically |
| 🔄 **Auto-update** | Checks for new versions on every run and updates in the background |
| 🛡️ **Official updates disabled** | Prevents the official binary from breaking Termux compatibility |
| 📦 **No root required** | Works completely without root permissions |
| ⚡ **Fast** | Updates are silent and don't interrupt your workflow |

---

## 📁 Project Structure

```
opencode-termux/
├── .github/
│   └── workflows/
│       └── auto-update.yml    # GitHub Action: auto-publishes new versions
├── bin/
│   └── opencode              # Bash wrapper: auto-update + launches binary
├── install.js                # Installer: downloads binary + patchelf + symlinks
├── package.json              # npm config (version = opencode version)
└── README.md
```

---

## 🔍 How It Works

### Flow Diagram

```
opencode
    │
    ▼
┌─────────────────────────┐
│  Does lib/opencode      │
│  exist?                 │
└────────┬────────────────┘
         │
    NO ──┼── YES
    │    │
    ▼    ▼
┌──────────┐  ┌───────────────────────┐
│install.js│  │Is version outdated?   │
│downloads │  └────────┬──────────────┘
│everything│           │
└──────────┘  NO ──────┼── YES
                  │    │
                  ▼    ▼
               ┌────┐ ┌───────────────────────┐
               │exec│ │npm install -g latest   │
               │    │ │rm old binary           │
               │    │ │install.js → new        │
               │    │ │exec                    │
               └────┘ └───────────────────────┘
```

### 1️⃣ First Run

When you run `opencode` for the first time:

1. **`bin/opencode`** resolves symlinks to find the real package path
2. Detects that `lib/opencode` doesn't exist
3. Runs **`install.js`** which:
   - Downloads `opencode-termux-aarch64.tar.gz` from [GitHub Releases](https://github.com/C04-wq/opencode-termux/releases)
   - Extracts the binary and 5 musl libraries to `lib/`
   - Runs `patchelf` to configure the musl interpreter
   - Creates symlinks in `~/.opencode/lib/`
4. Launches the binary with the required environment variables

### 2️⃣ Subsequent Runs

```
bin/opencode
  → lib/opencode exists ✓
  → Local version == npm version ✓
  → exec lib/opencode (no changes)
```

### 3️⃣ When a New Version Is Available

**GitHub Action** (every 6 hours):
```
1. Detects new official opencode version
2. Downloads new binary + musl libs from previous release
3. Creates new tarball = new binary + musl libs
4. Publishes to npm (opencode-termux@vNewVersion)
5. Creates release on GitHub
6. Git commit + push
```

**On your phone** (next run):
```
bin/opencode
  → CURRENT=1.18.4 ≠ LATEST=1.18.5
  → "Installing update v1.18.5..."
  → npm install -g opencode-termux@latest
  → rm old binary
  → install.js downloads new binary
  → exec v1.18.5
```

---

## ⚙️ Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `OPENCODE_DISABLE_AUTOUPDATE` | `1` | Disables official opencode updates |
| `LD_PRELOAD` | `~/.opencode/lib/ld-musl-aarch64.so.1` | Loads the musl runtime |
| `LD_LIBRARY_PATH` | `~/.opencode/lib/` | Path to shared libraries |
| `SSL_CERT_FILE` | `/data/data/com.termux/files/usr/etc/tls/cert.pem` | Termux SSL certificates |

---

## 📋 Requirements

- **OS**: Android with [Termux](https://f-droid.org/en/packages/com.termux/)
- **Architecture**: ARM64 (aarch64)
- **Connection**: Internet (for installation and updates)
- **Node.js**: Installed in Termux (`pkg install nodejs`)
- **npm**: Included with Node.js

---

## 🛠️ Troubleshooting

### Binary not downloading

```bash
# Verify connection works
curl -s https://github.com | head -1

# Reinstall manually
cd ~/opencode-termux
node install.js
```

### patchelf error

```bash
# Install patchelf
pkg install patchelf

# Re-run
opencode
```

### Update failing

```bash
# Force clean reinstall
rm -rf ~/opencode-termux/lib
opencode
```

---

## 🔄 Manual Update

```bash
# Check current version
npm view opencode-termux version

# Force update
npm install -g opencode-termux@latest --force
rm -f ~/opencode-termux/lib/opencode
opencode
```

---

## 📄 License

[MIT](LICENSE)

---

<p align="center">
  <sub>Made with ❤️ for the Termux community</sub>
</p>
