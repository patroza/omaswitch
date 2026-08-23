# Omarchy Window Switcher

Keyboard-first window switcher overlay for Omarchy (Quickshell).

Type to filter, Up/Down or j/k to move, Enter to focus, Esc to close.

## Install

```bash
omarchy plugin add https://github.com/piyush97/omarchy-window-switcher.git --enable
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
-- Replace the default SUPER+TAB (next workspace) with the switcher
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Window switcher", "omarchy-shell shell toggle piyush.window-switcher")
```

Or keep `ALT+TAB` (window cycle) and use this for the searchable picker.

## How it works

- Reads toplevels from the Quickshell `Hyprland` singleton (live, no polling)
- Refreshes on `activewindow` / `openwindow` / `closewindow` / `workspace` events
- Focuses via `hyprctl dispatch "hl.dsp.focus({ window = \"address:0x…\" })"` — the
  same dispatch Omarchy's own launch-or-focus helpers use, with `focuswindow` as
  the fallback path

## Development

```bash
omarchy plugin validate .
# symlink or copy to ~/.config/omarchy/plugins/piyush.window-switcher/
omarchy-shell shell rescanPlugins
```

Saving files under `~/.config/omarchy/plugins/` hot-reloads the shell.

## Scope (v1)

No thumbnails, no MRU ordering, no workspace grouping. All toplevels in one
list, filtered by typing. Add those when the base flow is proven.
