# Changelog

All notable changes to Dowey are documented here. Versions follow
[Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. The project is
pre-1.0, so the public shape (gesture, zones, deadzone radius) can still
change between minor versions without a major bump.

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
