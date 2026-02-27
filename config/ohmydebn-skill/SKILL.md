---
name: OhMyDebn
description: >
  REQUIRED for ANY changes to Linux desktop, window manager, or system config.
  Use when editing ~/.config/cinnamon/, ~/.config/nemo/, ~/.config/gtk-3.0/,
  ~/.config/gtk-4.0/, ~/.config/terminator/, ~/.config/gnome-terminal/,
  ~/.config/mate-terminal/, ~/.config/xfce4-terminal/, ~/.config/rofi/,
  or ~/.config/ohmydebn/. Triggers: Cinnamon desktop, applets, desklets, extensions,
  panels, keybindings, themes, wallpapers, fonts, window management, terminal config,
  startup applications, notifications, power management, screensaver, rofi launcher,
  or any ohmydebn-* commands.
---

# OhMyDebn Skill

Manage OhMyDebn Linux systems - a debonair Linux platform that combines the stability of the Debian distro, the ease of use of the Cinnamon desktop, and the beauty of Omarchy.

## When This Skill MUST Be Used

**ALWAYS invoke this skill when the user's request involves ANY of these:**

- Editing ANY file in `~/.config/cinnamon/` (desklets, applets, extensions, panels, etc.)
- Editing ANY file in `~/.config/nemo/`, `~/.config/gtk-3.0/`, `~/.config/gtk-4.0/`
- Editing terminal configs (alacritty, terminator, gnome-terminal, mate-terminal, xfce4-terminal)
- Editing ANY file in `~/.config/rofi/`
- Editing ANY file in `~/.config/ohmydebn/`
- Editing shell configuration files (`~/.zshrc`, `~/.config/zsh/`, etc.)
- Window management, workspace behavior, panel configuration
- Desktop effects, animations, themes, wallpapers, fonts, appearance changes
- Any `ohmydebn-*` command (theme, pkg, reset-config, update, version)
- Screenshots, screen recording, power management, screensaver, startup applications
- Rofi launcher configuration and theming

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

## Critical Safety Rules

**NEVER modify anything in `/usr/share/ohmydebn/`** - but READING is safe and encouraged.

This directory contains OhMyDebn's source files managed by the ohmydebn deb package. Any changes will be:
- Lost on next `ohmydebn-update` or package upgrade
- Cause conflicts with upstream
- Break the system's package management

```
/usr/share/ohmydebn/          # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/                      # Source scripts (symlinked to PATH)
├── config/                   # Default config templates
└── install/                  # Installation scripts
```

**Reading these directories is SAFE and useful** - do it freely to:
- Understand how ohmydebn commands work: `cat $(which ohmydebn-theme-set)`
- See default configs before customizing: `cat /usr/share/ohmydebn/config/cinnamon/cinnamon-settings`
- Check stock theme files to copy for customization: `ls /usr/share/ohmydebn-themes/`
- Check original Omarchy themes: `ls /usr/share/ohmydebn-themes/`
- Reference default cinnamon settings from the config templates: `cat /usr/share/ohmydebn/config/cinnamon/*`

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/ohmydebn/themes/<custom-name>/` - Custom themes (must be real directories)

**OhMyDebn Features:**
- **Desktop Effects**: Enabled by default, disable via System Settings → Effects
- **OpenCode AI**: CLI (`opencode-cli`, `Super + A`) + GUI versions, update with `ohmydebn-update-opencode`
- **Apps Menu**: Rofi launcher, `Super + Space` or OhMyDebn Menu → Apps

## System Architecture

OhMyDebn is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Debian 13** | Base OS | `/etc/`, `~/.config/` |
| **Cinnamon** | Desktop environment | `~/.config/cinnamon/` |
| **Nemo** | File manager | `~/.config/nemo/` |
| **Cinnamon Panel** | Taskbar/applets | `~/.config/cinnamon/panels/` |
| **GTK3/GTK4** | Widget toolkit | `~/.config/gtk-3.0/`, `~/.config/gtk-4.0/` |
| **Rofi** | App launcher | `~/.config/rofi/` |
| **Alacritty** | Default terminal | `~/.config/alacritty/` |
| **gTile** | Advanced window tiling | System Settings → Extensions |
| **Cinnamon Screensaver** | Lock screen | `~/.config/cinnamon-screensaver/` |
| **Cinnamon Notification Daemon** | Notifications | System settings |

## Command Discovery

OhMyDebn provides commands following `ohmydebn-<category>-<action>` pattern.

```bash
# List all ohmydebn commands
ls /usr/share/ohmydebn/bin/ | grep ohmydebn-

# Find commands by category
ls /usr/share/ohmydebn/bin/ | grep ohmydebn-theme
ls /usr/share/ohmydebn/bin/ | grep ohmydebn-pkg

# Read a command's source to understand it
cat $(which ohmydebn-theme-set)
```

### Command Categories

| Prefix | Purpose | Example |
|--------|---------|---------|
| `ohmydebn-reset-config` | Reset all configs to defaults (backs up first) | `ohmydebn-reset-config` |
| `ohmydebn-theme-*` | Theme management | `ohmydebn-theme-set <name>` |
| `ohmydebn-pkg-*` | Package management | `ohmydebn-pkg-install <pkg>` |
| `ohmydebn-update-*` | System updates | `ohmydebn-update` |
| `ohmydebn-update-opencode` | Update OpenCode AI to latest | `ohmydebn-update-opencode [version]` |

## Configuration Locations

### Cinnamon Desktop Environment

```
~/.config/cinnamon/
├── cinnamon-settings       # Main settings configuration
├── panels/                 # Panel configurations
│   ├── panel1/            # Bottom panel settings
│   └── panel2/            # Top panel settings (if enabled)
├── applets/               # Applet configurations
├── desklets/              # Desklet configurations
├── extensions/            # Extension configurations
└── background-chooser.log # Background selection logs
```

**Key behaviors:**
- Cinnamon auto-reloads most settings changes (no restart needed)
- Use `Ctrl + Alt + Escape` to restart Cinnamon desktop
- Use `ohmydebn-reset-config` to reset all configs to defaults

### Nemo File Manager

```
~/.config/nemo/
├── nemo-actions          # Custom context menu actions
├── bookmarks             # Bookmarks
└── nemo_preferences      # File manager preferences
```

**Nemo auto-reloads on config save.**

### GTK Theme Configuration

```
~/.config/gtk-3.0/
├── settings.ini          # GTK3 settings
└── bookmarks             # GTK bookmarks

~/.config/gtk-4.0/
└── settings.ini          # GTK4 settings
```

**GTK applications reload themes automatically.**

### Alacritty (Default Terminal)

```
~/.config/alacritty/alacritty.yml    # Main configuration
```

The default terminal is Alacritty with:
- Caskaydia Nerd Fonts
- Zsh shell with Oh My Zsh
- Starship shell prompt
- Zoxide for smart cd command
- eza for beautiful directory listings
- bat for cat with syntax highlighting

Restart terminal applications by closing and reopening the window or using the application's restart functionality.

### Other Terminals

```
~/.config/terminator/config
~/.config/gnome-terminal/
├── accels                # Keyboard shortcuts
├── profiles/             # Terminal profiles
└── settings              # General settings
~/.config/mate-terminal/
├── profiles/             # Terminal profiles
└── mate-terminal.rc      # Configuration
~/.config/xfce4/terminal/
└── terminalrc            # Configuration
```

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| screenfetch | System command (no config) |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |
| rofi | `~/.config/rofi/` |
| zsh | `~/.zshrc`, `~/.config/zsh/` |
| oh my zsh | `~/.oh-my-zsh/` |
| zoxide | `~/.config/zoxide/` |
| eza | Configured via shell aliases |
| bat | `~/.config/bat/config` |
| cava | `~/.config/cava/config` |
| opencode | `~/.config/opencode/` |
| wallpapers | `~/.local/share/backgrounds/` |

## Safe Customization Patterns

### Pattern 1: Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config
cat ~/.config/cinnamon/cinnamon-settings

# 2. Backup before changes
cp ~/.config/cinnamon/cinnamon-settings ~/.config/cinnamon/cinnamon-settings.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Cinnamon: auto-reloads most settings (no restart needed)
# - Rofi: auto-reloads on config save
# - Terminals: restart by closing and reopening window
```

### Pattern 2: Make a new theme

1. Create a directory under ~/.config/ohmydebn/themes.
2. See how existing themes are done via:
   - `/usr/share/ohmydebn-themes/ohmydebn/` for the native OhMyDebn theme
   - `/usr/share/ohmydebn-themes/tokyo-night/` for original Omarchy themes (interpreted for Cinnamon)
3. Download a matching background (or several) from the internet and put them in ~/.config/ohmydebn/themes/[name-of-new-theme]
4. When done with the theme, run ohmydebn-theme-set "Name of new theme"

### Pattern 3: Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset all configured apps to defaults (creates backup automatically)
ohmydebn-reset-config

# The reset-config command:
# 1. Backs up current configs with timestamp
# 2. Copies defaults from /usr/share/ohmydebn/config/
# 3. Restarts affected components
```

## Common Tasks

### Themes

```bash
ohmydebn-theme-list              # Show available themes
ohmydebn-theme-current           # Show current theme
ohmydebn-theme-set <name>        # Apply theme (use "Tokyo Night" not "tokyo-night")
ohmydebn-theme-next              # Cycle to next theme
ohmydebn-theme-bg-next           # Cycle wallpaper
ohmydebn-theme-install <url>     # Install from git repo
```

**Theme Management:**
- GUI: OhMyDebn Menu → Style → Theme or hotkey `Ctrl + Super + T`
- Background switching: `Ctrl + Super + B` or "Next Background" in menu
- Build custom themes: `Ctrl + Shift + A` (Aether theme builder)
- Install all Omarchy extra themes via menu option
- Browse Aether themes collection via menu option

### Keybindings

Edit keyboard shortcuts through Cinnamon Settings or via `cinnamon-settings keyboard`. For manual editing:
```
~/.config/cinnamon/spices/keybindings/  # Custom keybinding configurations
```

View current bindings: 
- `gsettings list-keys org.cinnamon.desktop.keybindings`
- Check `/usr/share/ohmydebn/install/keybinding/*.txt` for existing OhMyDebn bindings

**IMPORTANT: When re-binding an existing key:**

1. First check existing bindings in `/usr/share/ohmydebn/install/keybinding/*.txt`
2. Check if the key is already bound to avoid conflicts
3. Inform the user what the key was previously bound to

Example - rebinding Super+F (which may be bound to files by default):
```bash
# Check current binding
gsettings get org.cinnamon.desktop.keybindings "show-desktop"

# Set new binding
gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom0/ name "Custom File Manager"
gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom0/ command "nemo"
gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom0/ binding "<Super>F"
```

Always tell the user: "Note: Super+F was previously bound to files. I've created a new custom keybinding."

### Display/Monitors

Configure through Cinnamon Settings > Displays or via command line:
```bash
# List displays
xrandr

# Configure display (example)
xrandr --output eDP-1 --mode 1920x1080 --pos 0x0 --output HDMI-A-1 --mode 2560x1440 --pos 1920x0
```

### Window Management

Cinnamon window management is configured through:
- **Cinnamon Settings > Windows**: Window behavior, tiling, workspaces
- **Cinnamon Settings > Workspaces**: Workspace configuration
- **Manual editing**: `~/.config/cinnamon/cinnamon-settings`

For advanced window management, additional extensions can be installed from Cinnamon Spices.

### Window Tiling

**Basic Window Tiling:**
- `Super + Left/Right/Up/Down`: Tile window to respective screen half
- Combine arrows for corner tiling (e.g., Super + Up then Right for upper right)
- No window gaps, maximizes screen area

**Advanced Window Tiling (gTile Extension):**
- `Ctrl + Shift + G`: Display gTile overlay
- Grid options: 2x2, 3x2, 4x4, or 6x6 (press 1, 2, 3, or 4 to select)
- Select tiles by pressing letter keys (e.g., 'a' then 'n' for left half in 4x4)
- Press same letter twice for single tile (e.g., 'a' twice for upper left corner)

**gTile Hotkeys with Window Gaps:**
- `Ctrl + Shift + 1/2/3 (numpad)`: Bottom corners/half with gaps
- `Ctrl + Shift + 4 (numpad) or H`: Left half with gaps
- `Ctrl + Shift + 5 (numpad) or Enter`: Full screen with gaps
- `Ctrl + Shift + 6 (numpad) or L`: Right half with gaps
- `Ctrl + Shift + 7/8/9 (numpad)`: Top corners/half with gaps

**Configure gTile:**
- System Settings → Extensions → gTile → Configure → Behavior tab

### Fonts

Fonts are managed through Cinnamon Settings > Fonts, which provides options to:
- Change interface font, document font, monospace font, and window title font
- Adjust font rendering settings (hinting, antialiasing, scaling factor)
- Set font sizes for different UI elements

**Caskaydia Nerd Font** is included by default for terminal icons and glyphs.

### OhMyDebn Utilities

Additional tools available in OhMyDebn:
- **OhMyDebn Logo**: `Ctrl + Shift + O` (display animated logo)
- **OhMyDebn Demo**: `Ctrl + Alt + D` (animated logo showcase)
- **System Summary**: GUI version of screenfetch via OhMyDebn menu or `Ctrl + Shift + S`
- **System Monitoring**: btop performance monitor via `Super + T`
- **Audio Visualization**: Cava via terminal or `Ctrl + Super + A`


### System

```bash
ohmydebn-update                  # Full system update
ohmydebn-version                 # Show OhMyDebn version
ohmydebn-update-opencode          # Update OpenCode AI to latest
```

System control (lock, shutdown, reboot) is handled through:
- Cinnamon Menu (power options) or OhMyDebn Menu
- Hotkeys: `Ctrl + Alt + L` (lock), `Ctrl + Alt + End` (shutdown), `Ctrl + Alt + Del` (logout)
- Standard system commands: `loginctl lock-session`, `shutdown now`, `reboot`

## Troubleshooting

```bash
# Reset all configured apps to defaults
ohmydebn-reset-config

# Full reinstall of OhMyDebn deb package
sudo apt install --reinstall ohmydebn
```

## Decision Framework

When user requests system changes:

1. **Is it a stock ohmydebn command?** Use it directly
2. **Is it a config edit?** Edit in `~/.config/`, never `~/.local/share/ohmydebn/`
3. **Is it a theme customization?** Create a NEW custom theme directory
4. **Is it a package install?** Use `apt` or `ohmydebn-pkg-install`
5. **Unsure if command exists?** Search with `ls /usr/share/ohmydebn/bin/ | grep ohmydebn`

## Development (AI Agents)

When contributing to OhMyDebn itself (e.g., fixing bugs, adding features), the install process is designed to be idempotent and can be run multiple times.

### Update Process

When a user runs `ohmydebn-update`, it first installs the latest ohmydebn package and then goes through the install process again so they get the new changes. The install process is idempotent, meaning:

- It can be safely run multiple times without causing issues
- It will only apply new changes needed
- Existing configurations are preserved unless explicitly updated
- Dependencies are checked and installed as needed

**Development workflow:**
1. Make changes to the OhMyDebn source code in `/usr/share/ohmydebn/`
2. Test the changes by running the install scripts
3. Users get updates by running `ohmydebn-update`
4. The install process automatically handles applying new settings, dependencies, and configurations

**Installation scripts** in `/usr/share/ohmydebn/install/` handle:
- Installing system dependencies via apt
- Setting up default configurations
- Creating necessary directories and symlinks
- Updating user configurations with new defaults

## Example Requests

- "Change my theme to catppuccin" -> `ohmydebn-theme-set catppuccin` or OhMyDebn Menu → Style → Theme
- "Add a keybinding for Super+E to open file manager" -> Check existing bindings first, then create custom keybinding in Cinnamon Settings
- "Configure my external monitor" -> Use Cinnamon Settings > Displays or `xrandr` command
- "Make the window animations faster" -> Edit Cinnamon Settings > Effects or modify `~/.config/cinnamon/cinnamon-settings`
- "Set up custom terminal prompt" -> Edit `~/.config/starship.toml` or use Starship presets
- "Build a theme from this wallpaper" -> `Ctrl + Shift + A` (Aether theme builder)
- "Install all Omarchy extra themes" -> OhMyDebn Menu → Style → Theme → "Install All Omarchy Extra Themes"
- "Reset all configurations to defaults" -> `ohmydebn-reset-config`
- "Take a screenshot of an area" -> `Shift + Print` or `Ctrl + Shift + Print` (to clipboard)
- "Show system information" -> `Ctrl + Shift + S` (screenfetch)
- "Open OhMyDebn menu" -> `Super + Alt + Space`
- "Launch AI assistant" -> `Super + A` (OpenCode CLI) or from Apps Menu
- "Update OpenCode to latest version" -> `ohmydebn-update-opencode`
- "Open apps menu" -> `Super + Space` (Rofi)
- "Show OhMyDebn logo" -> `Ctrl + Shift + O`
- "Show system summary" -> `Ctrl + Shift + S` (screenfetch GUI)
- "Monitor system performance" -> `Super + T` (btop)
- "Visualize audio" -> `cava` in terminal or `Ctrl + Super + A`
