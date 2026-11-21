# Dowey

A small, native window snapper for macOS. Hold the **🌐 Globe** key, flick the mouse the way you want the window to go, and let go.

- Snap to halves, quarters or the full screen with one flick.
- Or use the keyboard alone: 🌐 + arrows snap, two arrows make a corner, and 🌐 + ⌥ + arrow picks which window to move.
- Lives in the menu bar. No Dock icon, nothing running in the background while idle.
- Updates itself.

Requires macOS 13 or later.

---

## How it works

### With the mouse

1. **Hold 🌐.** A ring appears at the pointer.
2. **Move the mouse** toward where the window should go. The matching part of the ring lights up and the destination is outlined on screen.
3. **Let go of 🌐.** The front window snaps there.

| Flick | Window goes to |
|---|---|
| Left / Right | Left or right half |
| Diagonals | That quarter of the screen |
| Up / Down | Top or bottom half (turn on **Eight zones** in Settings) |
| Don't move | Fills the screen |

Press **Esc** while holding 🌐 to cancel. The window snaps on whichever screen the pointer is on.

### With the keyboard

| Keys | What it does |
|---|---|
| 🌐 + ↑ | Fill the screen |
| 🌐 + ← / → | Left or right half |
| 🌐 + two arrows | A corner, e.g. ↑ + → for top-right |
| 🌐 + ⌥ + arrow | Bring the nearest window that way to the front |

To move a window without touching the mouse: hold 🌐, press ⌥ + an arrow until the window you want is outlined, let go of ⌥, then press an arrow (or two) to snap it.

Every arrow can be reassigned in **Settings → Shortcuts**.

---

## Install

1. Download the latest zip from [Releases](https://github.com/aarontran321/dowey/releases), unzip it and drag **Dowey** into **Applications**.
2. Dowey is signed but not notarized, so macOS blocks the first launch. Run this once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Dowey.app && open /Applications/Dowey.app
   ```

   Or open it once, click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

### Setup

1. **Free the Globe key:** System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**. Otherwise the emoji picker opens every time you snap.
2. **Allow two permissions** in System Settings → Privacy & Security:
   - **Accessibility**, to move windows
   - **Input Monitoring**, to see the Globe key

Dowey asks for both on first launch. Settings → General shows whether they're granted.

---

## Settings

Click the circle in the menu bar → **Settings…**. Changes apply immediately, so there's nothing to save.

- **Ring.** Pick a design (Segments, Halo, Dots or Screen Map), its color and size, how the destination is highlighted, and how far you have to move before a direction counts. A live preview shows exactly what the gesture will draw.
- **Shortcuts.** Turn the keyboard shortcuts on or off, reassign each arrow, and switch the corner and window-picking shortcuts.
- **General.** Open at Login, updates and permissions.

## Updates

When a new version is out, the menu bar menu and Settings → General offer to install it. Dowey downloads it, checks it's signed by the same developer, and relaunches. It checks GitHub at most every six hours, and only when you open Dowey or its menu. Turn off **Check for updates** to stop that.

---

## Build from source

```bash
xcodebuild -project Dowey.xcodeproj -scheme Dowey -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=YOUR_TEAM_ID
cp -R build/Build/Products/Release/Dowey.app /Applications/
```

Sign with your own team and always run the copy in Applications, so macOS keeps the permissions between builds. Run the tests with:

```bash
xcodebuild -project Dowey.xcodeproj -scheme Dowey test
```

Releases are cut with `Tools/release.sh`, and changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

See [LICENSE](LICENSE).
