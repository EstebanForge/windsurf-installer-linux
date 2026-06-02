# PROJECT KNOWLEDGE BASE

**Generated:** 2026-06-02

## OVERVIEW
Project: **windsurf-installer-linux** (repo name kept for continuity)
Stack: Bash (POSIX-compatible), Shell scripting
Purpose: Install, update, and uninstall [Devin Desktop](https://devin.ai/blog/windsurf-is-now-devin-desktop) (formerly Windsurf Code Editor) on non-Debian Linux distributions (Arch, Fedora, etc.)
Author: Esteban Cuevas (EstebanForge)
License: MIT

## STRUCTURE
```
.
├── install-devin-desktop.sh     # Main installer (download, verify, extract, symlink, desktop entry)
├── uninstall-devin-desktop.sh   # Uninstaller (remove files, symlinks, desktop entry, update helper)
├── devin-desktop-logo.png       # App icon (PNG fallback)
├── devin-desktop-logo.svg       # App icon (SVG primary)
├── screenshot-terminal.png      # README screenshot
├── LICENSE                      # MIT
└── README.md                    # User-facing docs
```

## COMMANDS
| Action | Command |
|--------|---------|
| Install | `bash install-devin-desktop.sh` |
| Update | `devin-desktop-update` (generated helper) or re-run installer |
| Uninstall | `bash uninstall-devin-desktop.sh` |
| Lint | `shellcheck install-devin-desktop.sh uninstall-devin-desktop.sh` |

No build step. No test suite. No dependencies beyond standard Linux utils (curl, tar, sha256sum, rsync).

## CODING STANDARDS
* **Language**: Bash 5.x+. `set -e` for error propagation. No `set -euo` (piped stdin + interactive reads conflict with `-u`)
* **Style**: Clean, well-commented. Colored output via ANSI escape sequences. Function-level comments explain intent
* **Error handling**: Early exits on failure. Checksum verification (SHA256). Icon extracted from tarball with SVG primary / PNG fallback
* **Privilege model**: Dual-path install. Root = system-wide (`/opt/devin-desktop`). User = local (`~/.local/share/devin-desktop`). Auto-detected via `$EUID`
* **Input**: Interactive prompts read from `/dev/tty` (not stdin) to support piped curl invocation
* **JSON parsing**: No jq dependency. Uses `grep -o` + `cut` for robustness across distros
* **Traps**: Temp directory cleanup via `trap ... EXIT`

## WHERE TO LOOK
* **Installer logic**: `install-devin-desktop.sh` (single file, ~380 lines)
* **Uninstaller logic**: `uninstall-devin-desktop.sh` (single file, ~120 lines)
* **User docs**: `README.md`

## KEY BEHAVIORS
* **Version API**: `https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest` returns JSON with `url`, `windsurfVersion`, `sha256hash`. Note: upstream API still uses `windsurfVersion` field name despite the rebrand
* **Binary name**: `devin-desktop` (extracted folder is `Devin/`)
* **Upgrade detection**: Reads `$INSTALL_DIR/resources/app/product.json` for current `windsurfVersion`, compares to remote
* **Migration**: Installer auto-detects old Windsurf paths (`/opt/windsurf`, `~/.local/share/windsurf`) and cleans them up
* **Logo extraction**: Extracts `out/media/code-icon.svg` from tarball as primary. Falls back to `resources/linux/code.png`. Both also stored in repo as safety net
* **Desktop entry**: Creates XDG `.desktop` file with MimeType, Categories, StartupWMClass=`devin-desktop`
* **Update helper**: Generates `~/.local/bin/devin-desktop-update` script that re-runs the installer via curl
* **Architecture gate**: Only x86_64 supported. Exits on ARM/32-bit

## NOTES
* No CI/CD. Manual release via git push. Icon extracted from upstream tarball at install time; repo copies are safety net.
* `shellcheck` is the primary linting tool. Run before changes.
* Scripts are consumed via piped curl (`curl -fsSL ... | bash`). All interactive prompts must use `read < /dev/tty`.
* Tested on Fedora 41/42. Community-tested on Arch.
