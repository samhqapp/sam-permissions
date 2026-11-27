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
.package(url: "https://github.com/samhqapp/sam-permissions.git", exact: "0.3.2")
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
| Microphone | macOS prompt | Pane and guide panel | Live |
| Camera | macOS prompt | Pane and guide panel | Live |
| Calendars | macOS prompt | Pane and guide panel | Live |
| Reminders | macOS prompt | Pane and guide panel | Live |
| Bluetooth | None | Pane and panel | Live |
| Full Disk Access | None | Pane and panel | Live |
| App Management | None | Pane and panel | No status from macOS |
| Developer Tools | None | Pane and panel | No status from macOS |
| Media & Apple Music | None | Pane and panel | Live |

Microphone, camera, calendars, and reminders show only apps that asked, so they get SamPermissions' own panel instead of the drag panel: the same look, with one line such as "Turn on the switch next to Task Manager." For a pane with no status, `access(_:)` never reads granted; check by using the feature. Fix repairs an old-signature grant with a reset only for Accessibility and Screen Recording.

### Other Settings pages

Call `guide(_:from:)` to send the user to a page that is not a privacy pane. It opens the page and shows the guide panel under System Settings. The panel follows the window and closes when Settings closes or the status reads allowed.

| Page | Panel closes when |
| --- | --- |
| `.loginItems` | `SMAppService.mainApp` is enabled, or Settings closes |
| `.automation(target:)` | Apple Events to the target are allowed (checked without asking), or Settings closes |
| `.locationServices` | Location access is allowed, or Settings closes |
| `.localNetwork` | Settings closes (macOS gives no status) |
| `.notifications` | Notifications are allowed, or Settings closes |

```swift
SamPermissions.shared.guide(.automation(target: "com.apple.finder"), from: buttonFrame)
```

Pass `allowed` when your app reads the status itself, such as an `SMAppService.daemon` helper that waits in Login Items. The panel checks it once a second instead of its own read and closes when it returns true.

```swift
SamPermissions.shared.guide(.loginItems, from: buttonFrame) { helper.status == .enabled }
```

## Credits

SamPermissions builds on [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) by jaywcjlove (MIT). PermissionFlow opens the right pane in System Settings and shows the user what to do.

## License

SamPermissions is released under the [MIT license](LICENSE).
