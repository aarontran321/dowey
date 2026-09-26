# Dowey

A tiny, native macOS window snapper. Hold the **Globe (🌐 / fn)** key, flick the mouse in a direction, release. The window snaps.

- Eight directional zones (four halves + four quarters), selected by mouse *direction*, not position — or six, if you prefer the original ring.
- Release without moving → maximize to the visible screen area.
- Escape → cancel, nothing moves.
- Six ring designs, each with its own parameter, chosen from a gallery next to a live preview. Nothing to save; every control commits as you touch it.
- No Dock icon, no polling, no third-party dependencies. Idles at 0.0% CPU.

Requires macOS 13 or later. Not sandboxed — it moves other apps' windows, which the App Sandbox forbids.

---

## The gesture

| Step | What happens |
|---|---|
| Press and hold 🌐 | The radial ring appears at the cursor with its center circle lit, and the whole visible frame is outlined and tinted — release now and the window maximizes. No segment is lit yet. |
| Move more than 20 pt | The segment for your direction lights up, and the destination is outlined and tinted gray on screen. |
| Release 🌐 | The frontmost window moves to that destination. |
| Release inside the center circle | The frontmost window is centered and maximized to fill the visible frame. This is *not* macOS fullscreen: no Space switch, no green-button state, the menu bar and Dock stay put. |
| Press Escape at any point | Everything tears down immediately. No window is touched. |

Direction is measured as a standard math angle from where the cursor was when you pressed the key: 0° = right, increasing counterclockwise.

| Zone | Angle range | Width | Result |
|---|---|---|---|
| Right | −25° … 25° | 50° | Right half |
| Top-Right | 25° … 70° | 45° | Top-right quarter |
| Top | 70° … 110° | 40° | Top half |
| Top-Left | 110° … 155° | 45° | Top-left quarter |
| Left | 155° … 205° | 50° | Left half |
| Bottom-Left | 205° … 250° | 45° | Bottom-left quarter |
| Bottom | 250° … 290° | 40° | Bottom half |
| Bottom-Right | 290° … 335° | 45° | Bottom-right quarter |

The widths are unequal on purpose, and they are why eight zones fit where six
did. A blind flick's accuracy plateaus around ±20°, so the 90° that Left and
Right used to own was angle held for no return; at 50° they are still trivial
to hit, and the harvested degrees pay for Top and Bottom. The diagonals keep
45° — a diagonal is the hardest direction to estimate — and the vertical
halves take 40° rather than whatever was left over, because a vertical flick
comes from the arm rather than the wrist and a sloppy one would otherwise land
in a quarter. Nothing is narrower than ±20°.

Every direction you would actually aim at now sits in the *middle* of its zone.
Under the old six-zone table the exact diagonals fell on boundaries and
resolved by the half-open rule, so a perfect 135° flick snapped Left; that
surprise is gone. Ranges are still half-open — a boundary angle belongs to the
zone that starts there — and `DoweyTests` pins every boundary.

### Windows in macOS full screen

A window that is in macOS full screen — the green button, its own Space — also
answers the gesture. It cannot be moved while it is up there: a full-screen
window's position and size are not settable, so a snap that arrived while it
was would be silently dropped. Dowey asks the window to leave full screen
first, waits for the Space switch to finish and the window to stop moving, and
only then places it. That is the one path where the snap is not instant; the
wait is the system's animation, not a fixed delay, and it gives up after 1.5 s
if the app takes the request and ignores it.

Releasing inside the center circle does the same thing and then maximizes to
the visible frame — so it trades macOS full screen for Dowey's, which keeps the
menu bar, the Dock and the Space you were already on.

### Six zones, if you want them

**Settings → Six zones only** puts the original table back: halves at 90°,
quarters at 45°, no Top or Bottom. It exists because the eight-zone table buys
those two zones by narrowing everything else — if you never flick vertically,
you are paying for zones you do not want with tolerance on the ones you do.

| Zone | Six-zone range | Eight-zone range |
|---|---|---|
| Right | −45° … 45° | −25° … 25° |
| Top-Right | 45° … 90° | 25° … 70° |
| Top | — | 70° … 110° |
| Top-Left | 90° … 135° | 110° … 155° |
| Left | 135° … 225° | 155° … 205° |
| Bottom-Left | 225° … 270° | 205° … 250° |
| Bottom | — | 250° … 290° |
| Bottom-Right | 270° … 315° | 290° … 335° |

Switching is instant and affects the next gesture; the ring redraws itself from
whichever table is live, so no design has to know which layout it is showing.
In the six-zone layout a straight-up flick lands in a quarter — 90° is a
boundary there, so it resolves to Top-Left by the half-open rule.

Two behaviors worth knowing:

- **Deadzone re-entry.** Moving back inside the 20 pt radius returns the ring to its neutral state and dismisses the preview, so releasing there maximizes. The circle at the center of the ring *is* that target — it is drawn at exactly the 20 pt deadzone radius, and it lights up whenever releasing would maximize.
- **Which screen.** On a multi-monitor setup, the target is whichever display the *cursor* is on when you release — not the one the window currently sits on. Rects are computed from `NSScreen.visibleFrame`, so the menu bar and Dock are already excluded.

**Keyboard.** Hold 🌐 and press ↑ to maximize, ← / → for the left / right half. You can rebind each arrow (or turn the whole thing off) in Settings → Shortcuts. The arrow keys are swallowed, so the app underneath never sees them.

Minimize is not implemented in v1. Zone angles and the trigger key are hardcoded; the deadzone radius is the **Trigger distance** setting.

---

## Installing a release build

Downloading [a release](https://github.com/aarontran321/dowey/releases) gets you
a signed but **not notarized** app, because notarization requires the $99/year
Apple Developer Program and Dowey is not enrolled. macOS will block the first
launch. This is expected and it is a one-time step.

> On macOS 15 and later, right-click → Open **no longer works** for unnotarized
> apps. Apple removed that bypass. Use one of the two routes below.

**The one-liner.** Strip the quarantine flag macOS attached at download, then
open normally:

```bash
xattr -dr com.apple.quarantine /Applications/Dowey.app && open /Applications/Dowey.app
```

**Or through System Settings**, if you would rather not run a command:

1. Unzip and drag `Dowey.app` to `/Applications`.
2. Double-click it. macOS refuses and offers only **Done**. Click Done.
3. **System Settings → Privacy & Security**, scroll to Security. A line reads
   *"Dowey.app was blocked to protect your Mac."*
4. Click **Open Anyway**, authenticate, then confirm **Open Anyway** again.

Either way it is once per install, not once per launch. After that, Dowey still
needs the two permissions in [Setup](#2-grant-two-permissions) — those are
enforced by TCC and no signing certificate can waive them.

To build from source instead, which sidesteps all of the above, see
[Build and install](#build-and-install).

## Setup

Three things, in order. Steps 1 and 2 are required for Dowey to work at all.

### 1. Free up the Globe key

**System Settings → Keyboard → "Press 🌐 key to:" → Do Nothing.**

Dowey only *observes* the Globe key; it never consumes the event. If macOS still owns that key, your Emoji picker or Input-source switcher will fire on every gesture. This step is the whole reason the gesture can use a plain `NSEvent` monitor instead of a `CGEventTap`. (The Globe + arrow shortcuts do use a tap, because they have to keep the arrow key from reaching the app.)

### 2. Grant two permissions

Both live in **System Settings → Privacy & Security**:

| Permission | Why | Pane |
|---|---|---|
| **Accessibility** | Reading and moving the frontmost window (`AXUIElement`) | Privacy & Security → Accessibility |
| **Input Monitoring** | Seeing the Globe key from a background app | Privacy & Security → Input Monitoring |

Dowey checks both at launch and shows one alert if either is missing. It does **not** poll for the grant — the **General** section of its Settings window shows the current status, re-read each time Dowey becomes active, so returning from System Settings updates it.

> There are no `Info.plist` usage-description strings for these two. Unlike Camera or Microphone, Accessibility and Input Monitoring are approved in System Settings and take no `NSxxxUsageDescription` key. Adding one does nothing.

### 3. Sign it once, so you only approve it once

macOS ties those permissions to a specific bundle ID **+ code signature + install location**. Change any of the three and you get to approve the app all over again. So:

1. Open `Dowey.xcodeproj` → target **Dowey** → **Signing & Capabilities**.
2. Set **Team** to your personal Apple ID. The free tier is fine for local development.
3. Leave **Bundle Identifier** at `com.aaron.dowey` and never change it.
4. Always run the copy in `/Applications`, never the one in DerivedData.

Building without a team works (`CODE_SIGNING_ALLOWED=NO`), but the resulting binary is unsigned, so macOS will ask for both permissions again after every rebuild. Set the team — it takes a minute and saves that forever.

---

## Build and install

From the repository root:

```bash
xcodebuild -project Dowey.xcodeproj -scheme Dowey -configuration Release -derivedDataPath build DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

Then install to `/Applications` and launch from there:

```bash
rm -rf /Applications/Dowey.app && cp -R build/Build/Products/Release/Dowey.app /Applications/ && open /Applications/Dowey.app
```

Dowey has no Dock icon (`LSUIElement`). Look for the circle in the menu bar — that menu has **Settings…** and **Quit**. Launching Dowey again while it is already running (from Finder or Spotlight) also opens Settings.

Run the unit tests (pure geometry, no app launch, no permissions needed):

```bash
xcodebuild -project Dowey.xcodeproj -scheme Dowey -configuration Debug test
```

---

## Settings

Click the circle in the menu bar → **Settings…** (or ⌘, with the window focused; launching Dowey again opens it too).

Two even columns. On the left, what it looks like: the live preview on top, the design gallery under it, and the zone-layout switch at the bottom. On the right, the knobs for whatever is selected. Neither column is privileged — both take half the window. **There is no Save button** — each control writes to `UserDefaults` in its setter, and the next gesture reads it.

The preview is not an illustration. It is a `RadialHUDView` and a `PreviewOverlayView` — the same two classes the gesture draws with — on a miniature desktop, with directions resolved by the same `ZoneMath`. Move the pointer across it and it arms, picks zones and highlights destinations exactly as the real gesture does, at actual size. The gallery thumbnails are the same view again at a miniature scale, so a design cannot advertise itself as something other than what it draws.

### The six designs

Every design answers the same two questions — which of the eight directions is live, and is the maximize target selected — and each carries one parameter of its own. That parameter is remembered per design, so switching away and back does not reset how you had it tuned.

| Design | What it draws | Its own slider |
|---|---|---|
| **Segments** | Eight arcs; the live one thickens and tints. The original. | Segment gap |
| **Wedges** | Filled slices — the zones read as areas, not hints. | Fill |
| **Dots** | One dot per direction; the live one swells and fills. | Dot size |
| **Blade** | Only the center target until you commit, then one bar points the way. | Width |
| **Screen Map** | A miniature screen at the cursor with the destination tile lit. | Map corners |
| **Halo** | A hairline circle; the live arc glows. | Glow |

### Everything else

| Setting | Range | What it changes |
|---|---|---|
| **Color** | 9 swatches + a custom well | The live direction, the lit center target, and optionally the destination tint. `Accent Color` follows the system-wide accent. |
| **Size** | 32–84 pt | Ring radius — and the screen's width on Screen Map. |
| **Thickness** | 2–10 pt | Stroke width. The live element is always 2 pt thicker. |
| **Show at the pointer** | on/off | Turn the cursor overlay off entirely and snap by direction alone. |
| **Highlight the destination** | on/off | The tinted rectangle at the target. |
| **Opacity** | 0.1–1.0 | How solid that rectangle is. |
| **Corners** | 0–28 pt | Its corner radius. |
| **Use the ring color** | on/off | Tint the destination with your color instead of neutral gray. |
| **Trigger distance** | 8–48 pt | The deadzone: how far the pointer must travel before a direction is chosen, and the size of the center maximize target. |
| **Open at Login** | on/off | `SMAppService.mainApp`. |

**Restore Defaults** at the bottom puts every one of them back — including each design's own parameter — and greys itself out when nothing has been changed.

## The icon

Both the app icon and the menu bar button are the same circle — the center target the gesture puts under your cursor. `Dowey/DoweyGlyph.swift` is the only place it is drawn: the menu bar gets a template image at runtime, and the asset catalog is generated from the same code.

```bash
swiftc -O Dowey/DoweyGlyph.swift Tools/GenerateAppIcon.swift -o /tmp/dowey-icon && /tmp/dowey-icon
```

That rewrites `Dowey/Assets.xcassets/AppIcon.appiconset` in place. Edit the drawing, re-run it, rebuild.

---

## Measured performance

Two different numbers get called "memory" and they differ by 4x here, so this
section says which one it means. **Physical footprint** is what Activity Monitor
shows in its Memory column and what the system charges against you — it excludes
framework pages shared with every other app. `ri_resident_size` includes them,
which is why it reports 86 MB for a process whose footprint is 31 MB. Everything
below is footprint, from `vmmap --summary`.

CPU is exact process CPU-time from `proc_pid_rusage` divided by wall time,
against a single core. Measured on 1.3.0, three runs, quitting and relaunching
between each.

| Scenario | Footprint | CPU | Wakeups |
|---|---|---|---|
| Launched, Settings never opened | **10.5 MB** | **0.00029%** | 1 per 10 s |
| Settings window open | 36.1 MB | — | — |
| Settings closed again | 31.2 MB | 0.00029% | 1 per 10 s |

The app spends its life in the first row: a menu-bar item, a `flagsChanged`
monitor and nothing else. 0.00029% of one core is about 3 µs of CPU per second.
A global `NSEvent` monitor registered only for `flagsChanged` is not woken by
mouse movement, so idle cost does not depend on what the pointer is doing.
Those figures predate 1.4.0's Globe + arrow shortcuts, which add a key-down /
key-up event tap: it wakes once per keystroke, and turning the shortcuts off in
Settings → Shortcuts removes it.

**Opening Settings costs about 26 MB and closing it returns about 5.**  Dowey
drops the window and its whole SwiftUI hierarchy on close, which is what those
5 MB are. The rest is SwiftUI initializing itself — once up, it stays up for the
life of the process — plus pages the allocator holds rather than returns to the
system. `malloc_zone_pressure_relief` was measured here and recovered nothing
beyond noise, so it is not used. If footprint matters to you, the lever is not
visiting Settings, not anything the app can do after you have.

### The gesture itself

Cost per zone change, which is the only work a gesture does between key-down and
release. Measured in isolation over 2000 changes per design:

| Design | Per zone change |
|---|---|
| Segments | 0.13 µs |
| Blade | 0.13 µs |
| Dots | 0.20 µs |
| Halo | 0.26 µs |
| Wedges | 0.53 µs |
| Screen Map | 0.77 µs |

A full eight-zone sweep of the Segments ring is **0.001 ms**. There is nothing
to optimize here: an incremental highlight that touched only the two layers that
changed would save a fraction of a microsecond and cost real complexity, so the
highlight pass still walks every zone and assigns its colors outright.

### History: the Core Animation rewrite

Both overlays originally rasterized through `draw(_:)`, with the preview drawing
into a screen-sized view on every zone change. They now hold their appearance as
layer properties, and the preview *window* is sized to the destination rect, so a
zone change is a frame change plus two color assignments.

| Metric | Before | After | Change |
|---|---|---|---|
| Active gesture CPU | 0.208% | 0.175% | **−16%** |
| Interrupt wakeups per run | 569 | 261 | **−54%** |

Those two were measured on the six-zone build under a synthetic load of 1200
mouse events and 10 gestures in 8 seconds, against a whole running app rather
than the isolated ring. They are not comparable to the per-zone-change table
above and are kept only as a record of that change.

## Checking it yourself in Activity Monitor

Open Activity Monitor, search for `Dowey`, select it, and watch the **% CPU**
column for about 30 seconds without touching anything. It should read `0.0` the
whole time. Anything that sits at a steady non-zero number means something is
polling and is a bug.

Then perform six or seven snaps in a row, sweeping the mouse around all eight zones
so the highlight changes repeatedly. `% CPU` should stay well under 1% and drop
straight back to `0.0` the moment you release. Memory should stay flat across
many gestures — Activity Monitor's Memory column reads about **10 MB** if you
have not opened Settings this launch, and about **31 MB** if you have.

Why it costs nothing at rest: there is no timer anywhere in the codebase. While
idle, exactly one `flagsChanged` monitor (plus, with shortcuts on, one keyboard
event tap) is installed and both overlay windows are
ordered out of the window server. The mouse-move and Escape monitors are created
on Globe key-down and removed on release or cancel, so no mouse handler runs
between gestures.

## Code map

| File | Responsibility |
|---|---|
| `main.swift` | Entry point; `.accessory` activation policy (no Dock icon). |
| `AppDelegate.swift` | Launch-time permission check, status item and menu, reopen handling. |
| `Settings.swift` | The store: `RingDesign` and its per-design parameters, every other customizable value, UserDefaults persistence, the `Style` snapshot the overlays read, and the login item. |
| `SettingsView.swift` | The two-column window: preview and design gallery on the left, the selected design's controls on the right (SwiftUI). |
| `SettingsWindowController.swift` | Its window: transparent titlebar, vibrant background, ⌘W / ⌘Q. |
| `GesturePreviewView.swift` | The live preview — real ring, real destination tile, real zone math, on a miniature desktop. |
| `DoweyGlyph.swift` | The circle: menu bar template image and app icon artwork. |
| `GlobalEventMonitor.swift` | The state machine — Idle → Armed → Tracking → Commit/Cancel — and every event monitor's lifecycle. |
| `WindowEngine.swift` | Accessibility-API window manipulation; target-screen selection; leaving macOS full screen before a snap; Cocoa ↔ AX coordinate conversion. |
| `RadialHUDView.swift` | All six ring designs, built from `CAShapeLayer`s and driven by a `Style`. Also `OverlayWindow`, the shared borderless/click-through window used by both overlays. |
| `PreviewOverlayView.swift` | Destination outline and flat tint. |
| `ZoneMath.swift` | Pure geometry: angle from points, angle → zone, zone → rect, deadzone test. No AppKit state, fully unit-tested. |

One coordinate-system rule runs through all of it: everything is in Cocoa screen space (bottom-left origin, y-up) until the very last step, where `WindowEngine.cocoaToAccessibility` flips the rect for the Accessibility API, which is top-left origin and anchored on the primary display.

---

## Info.plist keys

| Key | Value | Why |
|---|---|---|
| `LSUIElement` | `true` | Menu-bar-only; no Dock icon, no app switcher entry. |
| `LSMinimumSystemVersion` | `13.0` | Deployment target. |
| `NSPrincipalClass` | `NSApplication` | No storyboard or nib; `main.swift` is the entry point. |
| `CFBundleIdentifier` | `com.aaron.dowey` | Must stay fixed — permissions are keyed to it. |

No entitlements file: App Sandbox is off (`ENABLE_APP_SANDBOX = NO`), which is required to move other apps' windows. Hardened Runtime is on, which does not interfere with Accessibility.
