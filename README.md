# Serpantinum (TheFlyingHedgehog's fork)

My fork of [ilyamiro/serpantinum](https://github.com/ilyamiro/serpantinum), the Quickshell desktop shell, as I run it on a ThinkPad T470 with Arch and Hyprland. It's based on upstream 2.5.1 (commit `73b1cb7`). For everything that isn't listed here, see the original project and [serpantinum.dev](https://serpantinum.dev).

## What I changed

### Hyprland (`compositors/hyprland`)

- Super+W closes a window, Super+Space opens the launcher.
- Clipboard, music, system, calendar, network, volume and settings panels are toggled over Quickshell IPC instead of the `serpantinum` script, which adds about 0.7s to every keypress.
- Super+1-0 switch workspaces through Hyprland directly.
- Monitor scale 1.25 for the T470 panel.

### Bar

- Autohide waits until the cursor has rested on the edge for `bar.revealDelay` ms (200 by default) before showing the bar, so it doesn't pop up when I go for browser tabs. In fill style the hidden bar no longer keeps a full-height hover zone.
- Clicking bar modules opens their popups over IPC instead of `scripts/qs_manager.sh` (about 0.08s instead of 0.7s).
- New brightness module: scroll changes brightness by 5%, click opens the system panel. Button and text styles, like volume.
- The T470 has two batteries. The battery module still shows the total, and hovering it lists the internal and external battery separately.

### Launcher

Apps, files, emoji and calculator results are in one ranked list instead of tabs. `>` runs a command, `>>` runs it in a terminal that stays open, `?` searches the web. Tab and Shift+Tab move through the list.

### Widgets

- Arch updates: pending repo and AUR updates. Update everything, or tick the packages you want. The widget asks for the sudo password itself and shows a progress bar, with the full log in the dropdown. No terminal.
- Git repos: how many repos under `~/Code` have uncommitted changes or unpushed commits, and which. Tick repos to commit and push them from the widget; it asks for the commit message in the face. Folders are set in `~/.config/serpantinum/gitrepos.conf`.
- Obsidian: search the vault, create a note, open bookmarks. Folders open inside the widget.
- Google agenda: events for the next 7 days and open tasks. Click the circle to complete a task, + to add one. Uses a small standard-library Python helper (`gsync.py`). You need your own OAuth "Desktop app" client from Google Cloud saved as `~/.config/serpantinum/google/client_secret.json`.
- Battery "Devices" style: laptop and Bluetooth device batteries as rings or a list, with one ring per battery on the T470.
- Widget editor: content inside a widget no longer swallows clicks while editing, and the selected widget has a move handle you can press and drag.

### Lock screen

The battery pill shows both batteries, internal first (`82% · 24%`).

### SDDM login theme (`config/sddm/themes/serpantinum-lock`)

A login screen that copies the lock screen: same layout, blur, colours and widgets, with live CPU, RAM, temperature, battery and weather. `install.sh` builds it from your current Serpantinum wallpaper, theme, font, avatar and lock layout.

```sh
cd config/sddm/themes/serpantinum-lock
./install.sh --preview   # test window, installs nothing
./install.sh             # install and set it as SDDM's theme
```

Run it again after changing the wallpaper, theme or lock layout. It also sets `QML_XHR_ALLOW_FILE_READ=1` for the greeter in `/etc/sddm.conf.d/99-serpantinum.conf`, which the live stats need.

## Installing

Clone the fork and run the upstream installer from the checkout, so it uses these files:

```sh
git clone https://github.com/theflyinghedgehog/serpantinum
cd serpantinum
./install/install.sh
```

The Hyprland config is in `compositors/hyprland`. Copy `hyprland.lua` and `config/` to `~/.config/hypr` if you want my keybinds.

## Updating from upstream

```sh
git remote add upstream https://github.com/ilyamiro/serpantinum
git fetch upstream --tags
git rebase upstream/master
git push --force-with-lease
```

## License

AGPL-3.0, same as upstream (see `LICENSE.md`). The shell itself is ilyamiro's work.
