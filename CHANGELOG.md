# Changelog

All notable changes to Dowey are documented here. Versions follow
[Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. From 1.0.0 on,
the public shape — the gesture, the zone layouts, and the names and meanings
of the settings — is stable: a breaking change to any of them takes a major
bump.

## [1.3.0] — 2026-09-23

### Added
- **Six zones only.** A switch in Settings drops Top and Bottom and restores
  the original table — halves at 90°, quarters at 45°. The eight-zone layout
  buys its two extra zones by narrowing everything else; this is the way out
  for anyone who never flicks vertically. The ring, the lookup and every design
  read one table, so nothing can disagree about where a zone begins.

### Changed
- The settings window is two even columns again. The left holds the preview,
  the gallery and the new zone switch; the right holds the controls. Gallery
  thumbnails grew from 68 to 104 pt, and inspector rows stack their label above
  the control.

### Fixed
- Install instructions said to right-click → Open, which macOS 15 removed for
  unnotarized apps. The README now documents the `xattr` one-liner and the
  System Settings route, and says plainly that Dowey is not notarized and why.

## [1.2.0] — 2026-09-23

### Added
- **Top and Bottom zones.** The ring now has eight directions: a flick straight
  up snaps to the top half of the screen, straight down to the bottom half.

### Changed
- The arc table was re-cut to pay for them. Left and Right drop from 90° to
  50° — accuracy on a blind flick plateaus around ±20°, so the rest was angle
  held for no return — the quarters give up 5° each to 45°, and Top and Bottom
  take 40°. No zone is narrower than ±20°.
- Exact diagonals now land in their own corner zone. They used to sit *on* a
  boundary and resolve by the half-open rule, so a perfect 135° flick snapped
  Left; every direction a user aims at is now centered in its zone.
- Segment gap is clamped to a quarter of each arc, so the widest setting stays
  proportional across zones of different widths instead of gnawing the narrow
  ones down to stubs.
- Dot size is capped against the ring radius, so eight dots cannot collide on
  a small ring.

### Upgrading

Every zone from 1.1.0 still exists, under the same name, snapping to the same
rect. What changed is how much slop each one tolerates: Left and Right accept
±25° rather than ±45°. A flick you used to throw 30° above horizontal landed
on Right and now lands on Top-Right. If your aim is casual, expect a day of
recalibration — the ring shows the new boundaries while you hold the key.

## [1.1.0] — 2026-09-22

### Added
- Six ring designs, picked from a gallery beside the live preview: **Segments**
  (the original), **Wedges**, **Dots**, **Blade**, **Screen Map** and **Halo**.
  Each carries one parameter of its own — segment gap, fill, dot size, width,
  map corners, glow — remembered per design, so switching away and back does
  not reset how it was tuned.
- Gallery thumbnails are real `RadialHUDView`s at a miniature scale, so a
  design cannot advertise itself as something other than what it draws.

### Changed
- The settings window is two columns and 980 pt wide: preview and design
  gallery on the left in sidebar material, the selected design's controls on
  the right. The form no longer reads like a phone screen.
- "Show the ring" is now "Show at the pointer", because not every design is a
  ring.

### Fixed
- The transparent titlebar strip no longer shows through: SwiftUI insets for
  the titlebar safe area, so the column materials are painted behind the
  layout and told to ignore it.

## [1.0.0] — 2026-09-22

First stable release. Dowey is configurable now: the gesture from 0.1.0 is
unchanged, but every number behind it is yours to set.

### Added
- Settings window: one grouped form in System Settings' shape, on a vibrant
  background, opened from the menu bar (⌘,) or by launching Dowey again.
  Nothing to save — every control commits in its setter and the next gesture
  reads it.
- Customizable ring color (nine swatches, a custom color well, or the
  system accent), size, and thickness.
- Customizable destination highlight: opacity, corner radius, ring-color
  tint, and an off switch. The ring itself can be turned off too.
- Customizable trigger distance, which is both the deadzone and the size of
  the center maximize target.
- Live preview at the top of the window, built from the real `RadialHUDView`,
  `PreviewOverlayView` and `ZoneMath`: move the pointer across it and it
  arms, picks zones and highlights destinations exactly as the gesture does.
  The ring is shown at actual size.
- Open at Login (`SMAppService`), and permission status rows that re-read
  whenever Dowey becomes active.
- Restore Defaults.
- An app icon and a matching menu bar button — the same circle the gesture
  puts under the cursor — both drawn by `DoweyGlyph.swift`, with the asset
  catalog generated from that same code by `Tools/GenerateAppIcon.swift`.

### Changed
- The menu bar menu is now Settings… and Quit. Per-permission status and
  "Recheck Permissions" moved into the Settings window, which shows live
  status instead.
- `RadialHUDView` and `PreviewOverlayView` take a `Style` snapshot rather
  than hardcoded metrics; the overlays read one when a gesture begins.
- `ZoneMath.deadzoneRadius` is settable, written only by the settings store.

## [0.1.0] — 2026-09-22

Initial tagged release.

### Added
- Core window snapper: hold Globe (🌐/fn), flick the mouse in a direction,
  release to snap the frontmost window into one of six zones (halves +
  quarters), or release without moving to maximize.
- Radial HUD centered on the gesture origin, with a lit segment for the
  active zone and a lit center circle for the maximize target.
- Full-screen destination preview, outlining and tinting where the window
  will land before you release.
- Escape cancels the gesture with no window changes.
- Menu-bar-only presence (no Dock icon), with per-permission status,
  Recheck Permissions, and Quit.

### Performance
- Both overlays moved to Core Animation layer properties instead of
  `draw(_:)`, cutting active-gesture CPU and wakeups (~54% fewer wakeups,
  ~36% less resident memory).
- Idles at effectively 0% CPU: the only always-on listener is a single
  `flagsChanged` monitor for the Globe key.

### Fixed
- The gesture no longer gets stranded when Mission Control's "Show All
  Windows" swipe (4-finger swipe up) steals the Globe key's release event.
  The overlay windows are now hidden during Mission Control
  (`.transient` collection behavior), and a hardware-state watchdog polls
  the Globe key directly so the gesture always tears down even if no
  release event is ever delivered.
