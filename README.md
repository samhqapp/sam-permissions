<h1 align="center">SamPermissions</h1>

<p align="center">
  <b>One Fix button for macOS privacy permissions.</b>
</p>

<p align="center">
  <a href="#installation">Installation</a> &nbsp;·&nbsp;
  <a href="#usage">Usage</a> &nbsp;·&nbsp;
  <a href="#permissions">Permissions</a>
</p>

## Why SamPermissions

- **Every privacy permission.** One flow for all of them: your short prompt once, the macOS request, then Fix opens the right pane with a drag panel beside System Settings.
- **Repair an old grant.** If a signing change breaks Screen Recording access, Fix clears the old grant and helps the user allow access again.
- **Reopen once when needed.** If the running app can't see a new Screen Recording grant, SamPermissions reopens the app to pick it up.
- **Offer a report.** After three tries without access in ten minutes, your app gets a short report it can offer to the user.

## Installation

Requires macOS 14 or later and Swift 6.1 or later.

Add the package to your Swift Package Manager dependencies.

```swift
.package(url: "https://github.com/samhqapp/sam-permissions.git", exact: "0.2.0")
```

Add the product to your app target's dependencies.

```swift
.product(name: "SamPermissions", package: "sam-permissions")
```

## Usage

Call `handleLaunch()` once at app launch. Call `resolve(_:from:)` when the user presses Fix. Pass the Fix button's frame in screen coordinates as `from`, and the panel flies out of the button.

```swift
import SamPermissions
import SwiftUI

@main
struct MyApp: App {
    init() {
        SamPermissions.shared.handleLaunch()
    }

    var body: some Scene {
        WindowGroup {
            Button("Fix Screen Recording") {
                SamPermissions.shared.resolve(.screenRecording)
            }
        }
    }
}
```

Set `SamPermissions.shared.onLoop` if you want your app to offer the report to the user.

Call `request(_:confirm:)` when a feature first needs access, such as a capture hotkey. Only the first call runs `confirm` (your own explanation) and the macOS request. SamPermissions remembers a Cancel or Deny, so later calls return `.denied` with no prompt, and your app shows Fix. Microphone, camera, calendars, and reminders answer later, so use `await requestAccess(_:confirm:)` for them to get the user's answer. Never call a macOS permission request yourself.

Call `reason(_:)` to pick the line you show beside Fix. It returns `nil` when access is granted, `.notAllowed` when the permission was never asked, switched off, or reset, `.staleGrant` when the switch is on for an old signature of the app, and `.needsRelaunch` when the switch is on but the app must restart to see it.

## Permissions

The panel next to System Settings needs no extra permission.

| Permission | First ask | Fix opens | New grant picked up |
| --- | --- | --- | --- |
| Accessibility | macOS prompt | Pane and panel | Live |
| Screen Recording | macOS prompt | Pane and panel | After one reopen if macOS keeps the old status |
| Input Monitoring | macOS prompt | Pane and panel | Live |
| Microphone | macOS prompt | Pane only | Live |
| Camera | macOS prompt | Pane only | Live |
| Calendars | macOS prompt | Pane only | Live |
| Reminders | macOS prompt | Pane only | Live |
| Bluetooth | None | Pane and panel | Live |
| Full Disk Access | None | Pane and panel | Live |
| App Management | None | Pane and panel | No status from macOS |
| Developer Tools | None | Pane and panel | No status from macOS |
| Media & Apple Music | None | Pane and panel | Live |

Microphone, camera, calendars, and reminders show only apps that asked, so their pane gets no drag panel. For a pane with no status, `access(_:)` never reads granted; check by using the feature. Fix repairs an old-signature grant with a reset only for Accessibility and Screen Recording.

## Credits

SamPermissions builds on [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) by jaywcjlove (MIT). PermissionFlow opens the right pane in System Settings and shows the user what to do.

## License

SamPermissions is released under the [MIT license](LICENSE).
