import AppKit
import CoreLocation
import CoreServices
import PermissionFlow
import ServiceManagement
import SwiftUI
import UserNotifications

/// A System Settings page an app sends the user to. PermissionFlow's drag panel covers most privacy panes;
/// these pages get SamPermissions' own panel, which looks the same and shows one plain line instead of the drag card.
public enum SettingsPage: Equatable, Sendable {
    /// Login Items & Extensions, such as an `SMAppService` helper waiting for approval.
    case loginItems
    /// Apple Events to another app, by bundle id, such as `com.apple.finder`.
    case automation(target: String)
    case locationServices
    case localNetwork
    /// This app's own Notifications page.
    case notifications
    /// A privacy pane. Panes with PermissionFlow's drag panel show that panel; the rest show this one.
    case permission(PermissionFlowPane)

    var url: URL {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?"
        return switch self {
        case .loginItems: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        case .automation: URL(string: privacy + "Privacy_Automation")!
        case .locationServices: URL(string: privacy + "Privacy_LocationServices")!
        case .localNetwork: URL(string: privacy + "Privacy_LocalNetwork")!
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id="
                + (Bundle.main.bundleIdentifier ?? ""))!
        case .permission(let pane): pane.settingsURL
        }
    }

    var name: String {
        switch self {
        case .loginItems: "Login Items"
        case .automation: "Automation"
        case .locationServices: "Location Services"
        case .localNetwork: "Local Network"
        case .notifications: "Notifications"
        case .permission(let pane):
            ["camera": "Camera", "microphone": "Microphone", "calendars": "Calendars",
             "reminders": "Reminders"][pane.rawValue] ?? pane.rawValue
        }
    }

    func line(app: String) -> String {
        switch self {
        case .automation(let target): "Turn on \(Self.appName(bundleID: target)) under \(app)."
        case .notifications: "Turn on Allow notifications."
        default: "Turn on the switch next to \(app)."
        }
    }

    /// True once the user allowed it. nil: macOS gives no status, so the panel closes only with Settings.
    /// `.permission` is read by SamPermissions.
    func granted() async -> Bool? {
        switch self {
        // shortcut: reads the main app only; an app that waits on a helper's approval reads that service itself.
        case .loginItems: return SMAppService.mainApp.status == .enabled
        case .automation(let target): return await Task.detached { Self.canAutomate(target) }.value
        case .locationServices: return CLLocationManager().authorizationStatus == .authorizedAlways
        case .notifications:
            return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
        case .localNetwork, .permission: return nil
        }
    }

    /// Never asks: `askUserIfNeeded` is false.
    private static func canAutomate(_ bundleID: String) -> Bool {
        var target = AEAddressDesc()
        defer { AEDisposeDesc(&target) }
        let made = bundleID.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &target) }
        guard made == noErr else { return false }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard),
                                                     false) == noErr
    }

    static func appName(bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(appName(at:)) ?? bundleID
    }

    static func appName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// The panel under System Settings. It follows the window from window-server bounds (no Accessibility), never
/// takes focus, and closes when Settings closes or the status reads granted.
@MainActor
final class SettingsGuide {
    // Copied from PermissionFlow's FloatingDropPanel so both panels sit in the same place.
    private static let sidebarWidth: CGFloat = 230
    private static let screenInset: CGFloat = 12
    private var panel: NSPanel?
    private var watch: Task<Void, Never>?

    func show(_ page: SettingsPage, from source: CGRect?, granted: @escaping @MainActor () async -> Bool?) {
        close()
        let app = SettingsPage.appName(at: Bundle.main.bundleURL)
        let panel = Self.makePanel(GuidePanelView(page: page, app: app,
                                                  icon: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath),
                                                  close: { [weak self] in self?.close() }))
        self.panel = panel
        watch = Task { [weak self] in
            var last: CGRect?, misses = 0, movedAt = Date.distantPast, checkedAt = Date.distantPast
            let start = Date()
            while Date().timeIntervalSince(start) < 600 {
                guard let self, !Task.isCancelled else { return }
                if let frame = Self.settingsFrame() {
                    misses = 0
                    if frame != last { self.place(panel, under: frame, flyFrom: last == nil ? source : nil); movedAt = Date() }
                    last = frame
                } else {
                    misses += 1
                    if misses >= (last == nil ? 100 : 2) { break }
                }
                if Date().timeIntervalSince(checkedAt) >= 1 {
                    checkedAt = Date()
                    if await granted() == true { break }
                }
                let moving = last == nil || Date().timeIntervalSince(movedAt) < 1
                try? await Task.sleep(for: .milliseconds(moving ? 100 : 1000))
            }
            if !Task.isCancelled { self?.close() }
        }
    }

    func close() {
        watch?.cancel()
        watch = nil
        panel?.close()
        panel = nil
    }

    static func makePanel(_ view: GuidePanelView) -> NSPanel {
        let panel = GuidePanel(contentRect: CGRect(x: 0, y: 0, width: 420, height: 96),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    static func height(of panel: NSPanel, width: CGFloat) -> CGFloat {
        guard let host = panel.contentView else { return 96 }
        host.setFrameSize(NSSize(width: width, height: 4096))
        host.layoutSubtreeIfNeeded()
        return max(96, host.fittingSize.height)
    }

    private func place(_ panel: NSPanel, under settings: CGRect, flyFrom source: CGRect?) {
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) }?.visibleFrame ?? settings
        let width = min(max(240, settings.width - Self.sidebarWidth), screen.width - Self.screenInset * 2)
        let height = Self.height(of: panel, width: width)
        let x = max(screen.minX + Self.screenInset, min(settings.minX + Self.sidebarWidth,
                                                        screen.maxX - width - Self.screenInset))
        let y = max(screen.minY + Self.screenInset, min(settings.minY - height, screen.maxY - height - Self.screenInset))
        let target = CGRect(x: x, y: y, width: width, height: height)
        let firstShow = !panel.isVisible
        if let source, firstShow, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target.offsetBy(dx: source.midX - target.midX, dy: source.midY - target.midY), display: true)
            panel.alphaValue = 0.9
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
        }
    }

    /// System Settings' largest on-screen window, in AppKit coordinates. Same read as PermissionFlow's
    /// tracker without its Accessibility path.
    static func settingsFrame() -> CGRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
                .first(where: { $0.activationPolicy != .prohibited })?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let top = NSScreen.screens.first?.frame.maxY else { return nil }
        return windows
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int ?? 0) == 0
                && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .filter { $0.width > 320 && $0.height > 240 }
            .max { $0.width * $0.height < $1.width * $1.height }
            // Window-server rects start at the top left of the main screen; the 3 pt matches PermissionFlow.
            .map { CGRect(x: $0.minX, y: top - $0.maxY - 3, width: $0.width, height: $0.height) }
    }
}

private final class GuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// PermissionFlow's panel look (material, radii, header, app card), with one plain line in place of the drag card.
struct GuidePanelView: View {
    let page: SettingsPage
    let app: String
    let icon: NSImage
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                GuideArrow()
                Text(title)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .secondary.opacity(0.35))
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 8) {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32).cornerRadius(10)
                Text(page.line(app: app))
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.primary.opacity(0.085), lineWidth: 1))
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.14), lineWidth: 1))
        )
    }

    private var title: AttributedString {
        (try? AttributedString(markdown: "Allow **\(app)** in **\(page.name)**.")) ?? AttributedString(app)
    }
}

/// PermissionFlow's header arrow: it points up at the list and wiggles, still under Reduce Motion.
private struct GuideArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false

    var body: some View {
        Image(systemName: "arrowshape.up.fill")
            .font(.system(size: 14, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .rotationEffect(.degrees(reduceMotion ? 0 : (wiggle ? 12 : -12)))
            .offset(y: reduceMotion ? 0 : (wiggle ? -2 : 1))
            .animation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true), value: wiggle)
            .onAppear { wiggle = true }
    }
}
