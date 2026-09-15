//
//  main.swift
//  Dowey
//
//  Explicit entry point: no storyboard, no nib, no Dock icon. `.accessory`
//  mirrors LSUIElement in Info.plist and keeps the app out of the app switcher.
//

import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
