# 💻 Essentials Programming Pack

[![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Project Status](https://img.shields.io/badge/status-Active%20%7C%20v5.3-brightgreen.svg)](https://github.com/Hey-Reymond/EssentialsPPack)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20WSL-lightgrey.svg)](#-installation--usage)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-orange.svg)](https://github.com/Hey-Reymond/EssentialsPPack/issues)

> **Transform your fresh OS into a fully-equipped development powerhouse in minutes!**

An open-source automation suite that configures a complete professional environment for **Software Development**, **DevOps**, and **Cybersecurity/Bug Bounty** across Windows, Linux, and WSL platforms. One command, 100+ essential tools, zero hassle.

---

## ✨ Key Features

**Why Choose Essentials Programming Pack?**

- 🚀 **One-Click Setup** - Transform a clean OS into a fully-equipped workstation with a single command
- 📦 **100+ Essential Tools** - Comprehensive collection of development, DevOps, and security tools
- 🔄 **Smart Installation** - Intelligent package existence checks prevent redundant installations
- 🎯 **JSON-Based Configuration** - Easy package management without touching the scripts
- 🔧 **Hybrid Package Management** - Automatic fallback between package managers for reliability
- 🐧 **Cross-Platform** - Native support for Windows, Linux, and WSL 2 environments
- 🛡️ **Security-Focused** - Pre-configured with essential cybersecurity and pentesting tools
- 🔄 **Easy Maintenance** - Dedicated update scripts keep everything current
- 📊 **Clear Reporting** - Visual feedback with success/failure tracking

---

## 🛠️ Arsenal of Tools

### 💻 Windows Host & WSL 2 (`setup_windows.ps1`) - v5.3

**What's New in v5.0:**
- 🎯 **JSON-based package configuration** - All packages in `packages_windows.json` for easy maintenance
- 🔄 **Hybrid installation strategy** - Intelligent fallback from winget to chocolatey
- ✅ **Smart existence checks** - Skips already installed packages for faster re-runs
- 📦 **Expanded arsenal** - Added HxD (hex editor), CLOC (code counter), and WinRAR

This PowerShell script seamlessly integrates your Windows environment with Linux via WSL 2, handling system updates and cleanup automatically.

**Tool Categories:**

| Category | Tools & Technologies |
|----------|----------------------|
| **💼 Core Development** | VS Code, Neovim, Python 3, Temurin JDK 25 (+ JRE 8), .NET SDK 10, MSYS2 (MinGW toolchain), CMake, Ninja, Eclipse |
| **🌐 Web & Runtimes** | Node.js (LTS), Bun (Ultra-fast JS/TS Runtime), MariaDB, Nginx |
| **☁️ DevOps & Cloud** | VirtualBox, Git, GitHub CLI, AWS CLI, Azure CLI, Terraform, kubectl (Docker runs inside WSL) |
| **🔒 Cybersecurity & RE** | Nmap, Wireshark, Burp Suite Free, Ghidra, Volatility3, Cheat Engine, IDA Free, Rizin-Cutter, OllyDbg, HxD |
| **⚡ Productivity & Quality of Life** | Windows Terminal, PowerShell 7, gsudo, eza, bat, zoxide, delta (Enhanced Git diff), DevToys, WinRAR |

### 🐧 Linux & WSL Environment (`wsl_ubuntu.sh` / `setup_linux.sh`) - v5.0 / v2.0

**What's New in v5.0 (wsl_ubuntu.sh):**
- 🎯 **JSON-based package configuration** - All packages defined in `packages_linux.json`
- 🧩 **Modular architecture** - Clean, maintainable code with dedicated functions
- ✅ **Smart existence checks** - Prevents redundant package installations
- 🔧 **Radare2 reintroduced** - Installed via official source method
- 📊 **Enhanced reporting** - Clear summary of successes and failures

These Bash scripts deliver a modern CLI experience with comprehensive language version management and a complete pentesting arsenal.

**Tool Categories:**

| Category | Tools & Technologies |
|----------|----------------------|
| **🔤 Language Managers** | SDKMAN (Java, Kotlin, Scala, Dart, Elixir), Pyenv (Python 3.11), NVM (Node.js), Rbenv (Ruby), Miniconda (Conda/Data Science) |
| **🎨 Shell & Quality of Life** | Zsh, Oh My Zsh, Powerlevel10k, Starship (Modern Prompt), tmux, bpytop, LinuxToys, gum (interactive terminal scripts) |
| **🔐 DevSecOps & Containers** | Docker, Helm, Terraform, Trivy (Vulnerability Scanner), Hadolint, pre-commit, LazyGit, Lazydocker, Go Witness |
| **🛡️ Cybersecurity & Recon** | Metasploit, John the Ripper, Seclists, Nuclei, sslyze (SSL/TLS Analysis), semgrep (SAST), pwncat-cs, interlace, Gf (Go Templates) |

---

## 📥 Installation & Usage

### Prerequisites

Before you begin, ensure you have:
- A fresh installation of **Windows 10/11** or **Ubuntu/Debian Linux**
- **Git** installed on your system
- Administrative privileges on your machine

### 🪟 Windows (Host & WSL 2)

The Windows script is your main entry point and automatically triggers WSL setup.

**Step 1: Clone the Repository**
```bash
git clone https://github.com/Hey-Reymond/EssentialsPPack
cd EssentialsPPack/Windows
```

**Step 2: Execute the Setup Script**
```powershell
# Run as Administrator (the script will handle elevation via 'gsudo' if available)
.\setup_windows.ps1

# Optional: Specify a different WSL distribution
.\setup_windows.ps1 -WslDistro Debian
```

**Step 3: Follow the Prompts**
- The script will install WSL if needed (may require a system reboot)
- You'll be prompted for your **Linux (sudo) password** to execute the WSL setup script (`wsl_ubuntu.sh`)
- Sit back and watch the magic happen! ☕

### 🐧 Linux (Native - Debian/Ubuntu)

For native Linux environments, use the dedicated setup script.

**Step 1: Clone the Repository**
```bash
git clone https://github.com/Hey-Reymond/EssentialsPPack
cd EssentialsPPack/Linux
```

**Step 2: Make the Script Executable and Run**
```bash
chmod +x setup_linux.sh
sudo ./setup_linux.sh
```

**Step 3: Wait for Completion**
- The script will automatically handle all installations
- Review the summary at the end to see what was installed successfully

---

## ⚙️ Package Configuration

**New in v5.0:** JSON-based configuration makes package management a breeze!

### 📄 `packages_windows.json`

Organizes all Windows packages by package manager:
- **winget**: Preferred installation method (Windows Package Manager)
- **choco**: Chocolatey-only packages
- **msys2**: packages installed inside MSYS2 via `pacman`
- **portable_apps**: executables downloaded to a fixed folder

A `winget` entry can be a plain ID or an object `{ "name", "winget", "choco" }`. The Chocolatey fallback only runs for entries that define a `choco` name (winget IDs don't exist on Chocolatey).

> ⚠️ Keep the files as **pure JSON** — `//` comments break `ConvertFrom-Json` on Windows PowerShell 5.1.

**Example - Adding/Removing Packages:**
```json
{
  "winget": [
    "Microsoft.VisualStudioCode",
    "Git.Git",
    { "name": "WinRAR", "winget": "RARLab.WinRAR", "choco": "winrar" }
  ],
  "choco": [
    "neovim",
    "7zip",
    "hxd"
  ]
}
```

### 📄 `packages_linux.json`

Organizes all Linux packages by installation method:
- **apt**: System packages (apt-get)
- **snap**: Snap packages
- **pip**: Python CLI tools (installed via pipx)
- **pip_libs**: Python libraries without a CLI (installed into `~/.venvs/essentials`)
- **git**: Git repositories to clone

**Example - Adding/Removing Packages:**
```json
{
  "apt": ["zsh", "nmap", "docker-ce"],
  "snap": ["kubectl"],
  "pip": ["pwntools", "semgrep"],
  "git": {
    "seclists": "https://github.com/danielmiessler/SecLists.git"
  }
}
```

**Benefits:**
- ✅ **Easy maintenance** - Just edit JSON files, no script modification needed
- ✅ **Clear organization** - Packages grouped by installation method
- ✅ **Version control friendly** - Track changes easily in Git
- ✅ **No coding required** - Simple JSON syntax anyone can edit

---

## 🔄 Maintenance & Updates

Keep your environment up-to-date with the dedicated update scripts. These will refresh all package managers and installed tools.

### 🪟 Windows Update

```powershell
# Updates Chocolatey, Winget packages, and cleans system cache
.\update_windows.ps1
```

**What it does:**
- Updates all Chocolatey packages
- Updates all Winget packages
- Cleans package manager caches
- Removes temporary files

### 🐧 Linux Update

```bash
# Updates APT, Snap, Go, Pipx, Flatpak, and version managers
chmod +x update_linux.sh
./update_linux.sh
```

**What it does:**
- Updates APT packages
- Updates Snap packages
- Updates language version managers (SDKMAN, Pyenv, NVM, Rbenv)
- Updates Go modules, Pipx tools, and Flatpak apps
- Cleans package caches

---

## ⚠️ Stability Status & Important Notes

This project is built for automation and learning in **C/C++**, **Java**, **Web Development (JS/PHP)**, and **Python**, aligning with modern development and cybersecurity workflows.

| Script | Version | Status | Notes |
|--------|---------|--------|-------|
| `setup_windows.ps1` | **v5.3** | ✅ **Stable/Mature** | Refactored with JSON config, hybrid install, and smart checks. Extensively tested with Windows 10/11 + WSL 2. |
| `wsl_ubuntu.sh` | **v5.3** | ✅ **Stable/Mature** | Refactored with modular functions, JSON config, and existence checks. Tested on various Ubuntu versions within WSL 2. |
| `setup_linux.sh` | **v2.0** | ⚠️ **BETA** | Native Linux installer has not been 100% tested across all desktop environments. May encounter failures with external repos/snaps. **Use with caution.** |

### 🔒 Security Note

Always review scripts before running them with elevated privileges. This project is open-source and transparent - feel free to inspect all scripts in this repository.

---

## 🤝 Contributing

Contributions are welcome! Whether it's:
- 🐛 Bug reports
- 💡 Feature requests
- 📝 Documentation improvements
- 🔧 Code contributions

Feel free to open an issue or submit a pull request.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Special thanks to all the amazing open-source projects and tools that make this automation possible. This pack stands on the shoulders of giants.

---

<div align="center">

**⭐ If this project helped you, consider giving it a star! ⭐**

Made with ❤️ for developers, by developers

</div> 
