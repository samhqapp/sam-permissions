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

- **Repair an old grant.** If a signing change breaks Screen Recording access, Fix clears the old grant and helps the user allow access again.
- **Reopen once when needed.** If the running app can't see a new Screen Recording grant, SamPermissions reopens the app to pick it up.
- **Offer a report.** After three tries without access in ten minutes, your app gets a short report it can offer to the user.

## Installation

Requires macOS 14 or later and Swift 6.1 or later.

Add the package to your Swift Package Manager dependencies.

```swift
.package(url: "https://github.com/samhqapp/sam-permissions.git", exact: "0.1.2")
```

Add the product to your app target's dependencies.

```swift
.product(name: "SamPermissions", package: "sam-permissions")
```

## Usage

Call `handleLaunch()` once at app launch. Call `resolve(_:from:)` when the user presses Fix.

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

## Permissions

| Permission | When the app picks up a new grant |
| --- | --- |
| Accessibility | While the app is running. |
| Screen Recording | After one reopen if macOS keeps the old status for the running app. |

## Credits

SamPermissions builds on [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) by jaywcjlove (MIT). PermissionFlow opens the right pane in System Settings and shows the user what to do.

## License

SamPermissions is released under the [MIT license](LICENSE).
