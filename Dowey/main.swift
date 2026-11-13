//
//  main.swift
//  Dowey
//
//  Explicit entry point: no storyboard, no nib, no Dock icon. `.accessory`
//  mirrors LSUIElement in Info.plist and keeps the app out of the app switcher.
//

import AppKit

let application = NSApplication.shared
// Top-level code runs on the main thread; this says so to the compiler,
// since AppDelegate is main-actor isolated.
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
