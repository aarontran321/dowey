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
| Press and hold 🌐 | The radial ring appears at the cursor with its center circle lit — release now and the window maximizes. No segment is lit yet. |
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

## Verifying it stays cheap

Dowey should be invisible in the process list. To confirm:

**Idle.** Open Activity Monitor, search for `Dowey`, select it, and watch the **% CPU** column for about 30 seconds without touching the keyboard or mouse. It should read `0.0` the entire time, with occasional blips no higher than `0.1`. Anything that sits at a steady non-zero number means something is polling and is a bug.

**During a gesture.** Keep Dowey selected in Activity Monitor and perform six or seven snaps in a row — hold 🌐, sweep the mouse around all six zones so the highlight changes repeatedly, release, repeat. `% CPU` should stay under 1% and drop straight back to `0.0` the moment you release. The redraw path only fires when the *active zone changes*, not on every mouse-moved event, so sweeping fast is not meaningfully more expensive than sweeping slowly.

**Memory** should settle around 45 MB and stay flat across many gestures. The two overlay windows are created on first use and then reused; they are `orderOut`'d (not just made transparent) whenever Dowey is idle, so nothing is left warm in the window server.

Why it costs nothing at rest: there is no timer anywhere in the codebase. While idle, exactly one `flagsChanged` monitor is installed. The mouse-move and Escape monitors are created on Globe key-down and removed on release or cancel, so no mouse handler runs between gestures.

---

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
