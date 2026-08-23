# Omarchy Window Switcher

Windows-style Alt-Tab for Omarchy: MRU ordering, repeated-key cycling, type-to-filter search, and one live preview stream for the selected window.

## Requirements

- Omarchy with the Quickshell shell
- Hyprland with `hyprland-toplevel-export-v1` for previews

Without toplevel export, switching and search still work; the preview pane stays hidden.

## Install

```bash
omarchy plugin add https://github.com/piyush97/omarchy-window-switcher.git --enable
```

The repository is private, so Git must already have access to `piyush97` on GitHub.

## Windows-style Alt-Tab

Replace Omarchy's default direct-cycling bindings in `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

o.bind("ALT + TAB", "Window switcher", "omarchy-shell shell summon piyush.window-switcher '{\"mode\":\"cycle\",\"direction\":1}'")
o.bind("ALT + SHIFT + TAB", "Window switcher (reverse)", "omarchy-shell shell summon piyush.window-switcher '{\"mode\":\"cycle\",\"direction\":-1}'")
```

Repeated Alt+Tab cycles without resetting the overlay. Releasing Alt selects the highlighted window when Hyprland forwards the release event; Enter and clicking always work.

For searchable-picker mode, bind any free key to:

```bash
omarchy-shell shell toggle piyush.window-switcher
```

## Controls

- `Tab`, `Down`, `Right`: next window
- `Shift+Tab`, `Up`, `Left`: previous window
- Type: filter by title, application, or workspace
- `Backspace`: delete; `Ctrl+Backspace`: delete a word; `Ctrl+U`: clear
- `Enter` or click: focus
- `Esc` or click outside: close

## Implementation

- Reads `Hyprland.toplevels` directly; no polling
- Sorts by Hyprland's focus history, with the active window first
- Uses one `ScreencopyView`, bound only to the highlighted window's Wayland handle
- Uses native `Toplevel.activate()`, with `hyprctl focuswindow` as fallback
- Collapses to the list-only layout until a preview frame is available

## Development

```bash
node test_model.js
omarchy plugin validate .
omarchy-shell shell rescanPlugins
```

Saving files in `~/.config/omarchy/plugins/` hot-reloads the shell.

## Scope

One selected-window preview stream is intentional. Per-row streams, thumbnails for every window, and persistent history storage are omitted to keep switching fast and local.
