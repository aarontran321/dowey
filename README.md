# Dowey

A tiny, native macOS window snapper. Hold the **Globe (🌐 / fn)** key, flick the mouse in a direction, release. The window snaps.

- Six directional zones (halves + quarters), selected by mouse *direction*, not position.
- Release without moving → maximize to the visible screen area.
- Escape → cancel, nothing moves.
- No Dock icon, no preferences, no polling, no third-party dependencies. Idles at 0.0% CPU.

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

| Zone | Angle range | Result |
|---|---|---|
| Right | −45° … 45° | Right half |
| Top-Right | 45° … 90° | Top-right quarter |
| Top-Left | 90° … 135° | Top-left quarter |
| Left | 135° … 225° | Left half |
| Bottom-Left | 225° … 270° | Bottom-left quarter |
| Bottom-Right | 270° … 315° | Bottom-right quarter |

Ranges are half-open — a boundary angle belongs to the zone that starts there, so an exact 45° diagonal is Top-Right and an exact 135° diagonal is Left. `DoweyTests` pins every boundary.

Two behaviors worth knowing:

- **Deadzone re-entry.** Moving back inside the 20 pt radius returns the ring to its neutral state and dismisses the preview, so releasing there maximizes. The circle at the center of the ring *is* that target — it is drawn at exactly the 20 pt deadzone radius, and it lights up whenever releasing would maximize.
- **Which screen.** On a multi-monitor setup, the target is whichever display the *cursor* is on when you release — not the one the window currently sits on. Rects are computed from `NSScreen.visibleFrame`, so the menu bar and Dock are already excluded.

Minimize is not implemented in v1. Zone angles, the trigger key, and the deadzone radius are hardcoded constants.

---

## Setup

Three things, in order. Steps 1 and 2 are required for Dowey to work at all.

### 1. Free up the Globe key

**System Settings → Keyboard → "Press 🌐 key to:" → Do Nothing.**

Dowey only *observes* the Globe key; it never consumes the event. If macOS still owns that key, your Emoji picker or Input-source switcher will fire on every gesture. This step is the whole reason Dowey can use a plain `NSEvent` monitor instead of a `CGEventTap`.

### 2. Grant two permissions

Both live in **System Settings → Privacy & Security**:

| Permission | Why | Pane |
|---|---|---|
| **Accessibility** | Reading and moving the frontmost window (`AXUIElement`) | Privacy & Security → Accessibility |
| **Input Monitoring** | Seeing the Globe key from a background app | Privacy & Security → Input Monitoring |

Dowey checks both at launch and shows one alert if either is missing. It does **not** poll for the grant — after you allow them, either relaunch Dowey or use **Recheck Permissions** in its menu-bar menu.

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

Dowey has no Dock icon (`LSUIElement`). Look for the window icon in the menu bar — that menu shows per-permission status, **Recheck Permissions**, and **Quit**.

Run the unit tests (pure geometry, no app launch, no permissions needed):

```bash
xcodebuild -project Dowey.xcodeproj -scheme Dowey -configuration Debug test
```

---

## Measured performance

CPU here is measured as exact process CPU-time from `proc_pid_rusage`, divided by
wall time, expressed against a single core. Each configuration was run three
times, alternating between builds so system drift could not favour either one.

| Scenario | CPU | What it means |
|---|---|---|
| Idle, no input | **0.0005%** | ~5 µs of CPU per second; 5 wakeups per 20 s |
| Idle, cursor moving (150 events/s) | **0.0000%** | Unmeasurable — 1 wakeup in 8 s |
| Active gesture, continuous sweep | **0.17%** | 2.27 ms of CPU per full six-zone sweep |

The active figure is deliberately pessimistic: it comes from a synthetic load of
1200 mouse events and 10 complete gestures inside 8 seconds, sweeping through all
six zones twice per gesture. Real use is nowhere near that. At 0.17% of one core
on a 10-core machine, that is 0.017% of total capacity.

The important idle result is the second row. A global `NSEvent` monitor registered
only for `flagsChanged` is *not* woken by mouse movement — the app stays blocked in
`mach_msg` and the window server never dispatches to it. Idle cost is therefore
independent of what the user is doing with the mouse.

### Before and after the Core Animation rewrite

Both overlays originally rasterized through `draw(_:)`, with the preview drawing
into a screen-sized view on every zone change. They now hold their appearance as
layer properties, and the preview *window* is sized to the destination rect, so a
zone change is a frame change plus two color assignments.

| Metric | Before | After | Change |
|---|---|---|---|
| Active gesture CPU | 0.208% | 0.175% | **−16%** |
| CPU per six-zone sweep | 2.71 ms | 2.27 ms | **−16%** |
| Interrupt wakeups per run | 569 | 261 | **−54%** |
| Resident memory | 64.4 MB | 41.5 MB | **−36%** |
| Idle CPU | 0.0005% | 0.0005% | unchanged |

Idle was already at the floor and did not move, which is the expected result —
there is no work to remove from a process that is asleep. The wakeup reduction
matters most for battery: wakeups, not raw CPU percentage, are what prevent the
package from staying in a low-power state.

## Checking it yourself in Activity Monitor

Open Activity Monitor, search for `Dowey`, select it, and watch the **% CPU**
column for about 30 seconds without touching anything. It should read `0.0` the
whole time. Anything that sits at a steady non-zero number means something is
polling and is a bug.

Then perform six or seven snaps in a row, sweeping the mouse around all six zones
so the highlight changes repeatedly. `% CPU` should stay well under 1% and drop
straight back to `0.0` the moment you release. Memory should settle near 40 MB and
stay flat across many gestures.

Why it costs nothing at rest: there is no timer anywhere in the codebase. While
idle, exactly one `flagsChanged` monitor is installed and both overlay windows are
ordered out of the window server. The mouse-move and Escape monitors are created
on Globe key-down and removed on release or cancel, so no mouse handler runs
between gestures.

## Code map

| File | Responsibility |
|---|---|
| `main.swift` | Entry point; `.accessory` activation policy (no Dock icon). |
| `AppDelegate.swift` | Launch-time permission check, status item and menu. |
| `GlobalEventMonitor.swift` | The state machine — Idle → Armed → Tracking → Commit/Cancel — and every event monitor's lifecycle. |
| `WindowEngine.swift` | Accessibility-API window manipulation; target-screen selection; Cocoa ↔ AX coordinate conversion. |
| `RadialHUDView.swift` | The ring: arc segments, highlight, center maximize circle, draw code. Also `OverlayWindow`, the shared borderless/click-through window used by both overlays. |
| `PreviewOverlayView.swift` | Destination outline and flat gray tint. |
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
