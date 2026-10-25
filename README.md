# Kado

Kado is a native macOS window manager that arranges app windows as you work. It lives in the menu bar and keeps its preferences on your Mac.

## Features

- Arrange windows in **Grid** or **Columns** layouts, with one to four windows per display.
- Tile new windows automatically and fill the available space when a window closes.
- Adapt column widths to the minimum sizes applications accept. If the requested layout cannot fit, Kado falls back to Grid so windows remain visible.
- Swap windows with the mouse or keyboard, and stack extra windows in the active tile when there are more windows than available tiles.
- Keep independent layouts and window limits for each display.
- Use **Presentation** to expand the focused window across one display and cover the unused area.
- Use **Dim surroundings** to fade other windows while keeping the focused window, menu bar, and Dock visible.
- Open the **Window switcher** to select a window from the keyboard.
- Customize window borders, highlight colors, hover focus, app exclusions, and keyboard shortcuts.

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools with the Swift 6 toolchain.
- Accessibility permission, required for reading window geometry and moving windows.

Kado uses Accessibility to arrange windows. It does not read window contents or typed characters, and it does not send usage analytics. Settings are stored locally on the Mac.

## Install from source

1. Install the command line tools if needed:

   ```sh
   xcode-select --install
   ```

2. Clone this repository and build the app:

   ```sh
   git clone https://github.com/MrBalourd/kado-window-manager.git
   cd kado-window-manager
   ./build-app.sh
   ```

   The script creates `Kado.app` in the repository folder. It uses ad-hoc signing by default, so the build does not depend on a developer certificate tied to one computer.

3. Move `Kado.app` to **Applications** in Finder and open it. If macOS asks you to confirm an app from an unidentified developer, Control-click the app, choose **Open**, then confirm.

4. Allow window control in **System Settings → Privacy & Security → Accessibility**. Enable **Kado** in the list. If it is not listed, use the add button and select `/Applications/Kado.app`.

5. Open Kado from the menu bar and enable **Automatic tiling**.

## Build a ZIP package

Run:

```sh
./package-release.sh
```

This builds `Kado.app` and writes a ZIP file under `release/`. The ZIP is intended to be attached to a GitHub Release by a maintainer. It is not included in the source repository.

## Keyboard shortcuts

Shortcuts can be enabled or disabled in **Kado settings → Shortcuts**.

| Shortcut | Action |
| --- | --- |
| `⌃⌥⌘1`–`⌃⌥⌘4` | Arrange up to four windows |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | Swap the focused window |
| `⌥Tab` / `⇧⌥Tab` | Open or navigate the window switcher |
| `⌃⌥P` | Toggle Presentation |
| `⌃⌥D` | Toggle Dim surroundings |

`⌃` means Control, `⌥` Option, `⌘` Command, and `⇧` Shift.

## Troubleshooting

- **Windows do not move:** confirm that Kado is enabled under **System Settings → Privacy & Security → Accessibility**, then quit and reopen Kado.
- **A window stays larger than its tile:** some applications enforce a minimum window size. Kado redistributes column space and switches to Grid when the requested layout still cannot fit.
- **A shortcut does nothing:** check that shortcuts are enabled in **Kado settings → Shortcuts** and that another app is not using the same combination.
- **macOS blocks the first launch:** Control-click `Kado.app`, choose **Open**, and confirm the prompt. Locally built packages use ad-hoc signing and are not notarized.

## Contributing

Bug reports and improvement suggestions can be filed in the repository’s **Issues** tab. Please include your macOS version, the selected layout, and the steps needed to reproduce a problem. Do not attach screenshots that expose private window contents.

## License

No license has been added yet.
