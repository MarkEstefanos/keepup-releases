// What keepup is doing, seen from outside, for run.sh:
//   probe state    "pid=N policy=regular|accessory windows=N" (pid=0 when it isn't running)
//   probe quit     asks keepup to quit the way the Dock's Quit does (a quit event, which Presence turns down)
//   probe active   "true" when keepup is the active app (in front)

import AppKit

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.markestefanos.keepup.mac")

switch CommandLine.arguments.dropFirst().first {
case "quit":
    for app in apps { print("   quit sent to \(app.processIdentifier): \(app.terminate())") }
case "active":
    print(apps.contains { $0.isActive })
default:
    guard let app = apps.first else {
        print("pid=0 policy=none windows=0")
        exit(0)
    }
    let policy = app.activationPolicy == .regular ? "regular" : app.activationPolicy == .accessory ? "accessory" : "prohibited"
    let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // layer 0: ordinary windows, not the mark in the menu bar or its menu
    let windows = onScreen.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    print("pid=\(app.processIdentifier) policy=\(policy) windows=\(windows.count)")
}
