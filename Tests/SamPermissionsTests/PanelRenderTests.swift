import AppKit
@testable import PermissionFlow
import SwiftUI
import Testing
@testable import SamPermissions

/// Renders the guide panel beside PermissionFlow's real panel at 2x in Light and Dark, offscreen.
/// Runs only with SAM_RENDER_DIR set, such as `SAM_RENDER_DIR=/tmp/out swift test --filter PanelRender`.
@MainActor
struct PanelRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SAM_RENDER_DIR"] != nil))
    func renderPanels() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SAM_RENDER_DIR"]!)
        let app = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SAM_RENDER_APP"] ?? "/System/Applications/Calendar.app")
        let controller = PermissionFlowController(configuration: .init(requiredAppURLs: [app]))
        controller.isSettingsFrontmost = true
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        let name = SettingsPage.appName(at: app)
        for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let column = VStack(alignment: .leading, spacing: 18) {
                Text("PermissionFlow (real)").font(.caption).foregroundStyle(.secondary)
                PermissionFlowPanelView(controller: controller)
                Text("SamPermissions guide: Login Items").font(.caption).foregroundStyle(.secondary)
                GuidePanelView(page: .loginItems, app: name, icon: icon, close: {})
                Text("SamPermissions guide: Automation").font(.caption).foregroundStyle(.secondary)
                GuidePanelView(page: .automation(target: "com.apple.finder"), app: name, icon: icon, close: {})
                Text("SamPermissions guide: Camera").font(.caption).foregroundStyle(.secondary)
                GuidePanelView(page: .permission(.camera), app: name, icon: icon, close: {})
            }
            .padding(24)
            .frame(width: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: column)
            host.appearance = NSAppearance(named: appearance)
            host.setFrameSize(host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("panels-\(label).png"))
        }
    }
}
