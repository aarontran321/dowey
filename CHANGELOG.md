# Changelog

All notable changes to Dowey are documented here. Versions follow
[Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. From 1.0.0 on,
the public shape — the gesture, the six zones, and the names and meanings of
the settings — is stable: a breaking change to any of them takes a major bump.

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
