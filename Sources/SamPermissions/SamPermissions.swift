import AppKit
import ApplicationServices
import notify
import PermissionFlow
import PermissionFlowScreenRecordingStatus
import Security

/// One Fix button for Accessibility and Screen Recording. PermissionFlow opens the pane and shows its panel beside
/// System Settings; this layer adds stale-grant repair, the self-reopen, and the loop report.
@MainActor
public final class SamPermissions {
    public static let shared = SamPermissions()
    public static let askArgument = "--sam-permission-ask"
    public static let resumeArgument = "--sam-permission-resume"

    /// A stuck flow, with a short report that holds no user data. Called at most once a day.
    public var onLoop: ((PermissionFlowPane, String) -> Void)?
    /// Access changed: granted, lost, or the switch went on.
    public var onChange: ((PermissionFlowPane) -> Void)?
    /// Extra launch arguments for a reopen, such as `["--open", "text-extractor"]`.
    public var reopenArguments: (PermissionFlowPane) -> [String] = { _ in [] }
    /// False blocks the reopen (demo mode).
    public var canReopen: () -> Bool = { true }

    private let defaults = UserDefaults.standard
    private let flow = PermissionFlowController()
    private var resumed: PermissionFlowPane?
    private var settingsChanged = false
    private var watch: Task<Void, Never>?
    private var tccToken: Int32 = 0
    private var reopenWaiter: (process: Process, pane: PermissionFlowPane)?

    /// Call when the app refused the quit that a reopen asked for. Stops the waiting reopen, so a later
    /// quit does not start the app again, and returns the pane to tell the user about, or nil.
    public func cancelReopen() -> PermissionFlowPane? {
        guard let waiter = reopenWaiter else { return nil }
        reopenWaiter = nil
        waiter.process.terminate()
        return waiter.pane
    }

    private init() {
        PermissionFlowScreenRecordingStatus.register()
        notify_register_dispatch("com.apple.tcc.access.changed", &tccToken, .main) { _ in
            MainActor.assumeIsolated { SamPermissions.shared.settingsChanged = true }
        }
    }

    // MARK: Read

    public func access(_ pane: PermissionFlowPane) -> Access {
        let reading = Reading(preflight: PermissionStatusRegistry.provider(for: pane).authorizationState() == .granted,
                              titledWindows: pane == .screenRecording ? Self.titledWindows() : nil)
        let access = Flow.access(reading, asked: defaults.bool(forKey: key("asked", pane)),
                                 reopenedForGrant: resumed == pane)
        if access == .granted { remember(pane) }
        if resumed == pane, !reading.preflight, (reading.titledWindows ?? 0) > 0 {
            report(pane, "reopened but the grant is still unseen")
        }
        return access
    }

    // MARK: Fix

    /// The one Fix button. Picks the step for the current state. Call only from a click.
    public func resolve(_ pane: PermissionFlowPane, from source: CGRect? = nil) {
        let access = access(pane)
        let tries = recentTries(pane)
        let step = Flow.step(access, pane: pane, identityChanged: identityChanged(pane), tries: tries,
                             settingsChanged: settingsChanged)
        if access != .granted { defaults.set(tries + 1, forKey: key("tries", pane)) }
        defaults.set(Date().timeIntervalSince1970, forKey: key("triedAt", pane))
        if tries + 1 >= Flow.loopTries { report(pane, "\(tries + 1) tries in 10 min, state \(access.rawValue)") }
        switch step {
        case .nothing: return
        case .reopen: reopen(pane, [Self.resumeArgument, pane.rawValue])
        case .prompt: ask(pane, from: source)
        case .openPane: guide(pane, from: source)
        case .reset:
            Task {
                await Self.reset(pane)
                if pane == .screenRecording { reopen(pane, [Self.askArgument, pane.rawValue]) } else { ask(pane, from: source) }
            }
        }
    }

    /// Call once at launch with the process arguments.
    public func handleLaunch(_ arguments: [String] = CommandLine.arguments) {
        if let pane = Self.pane(after: Self.resumeArgument, in: arguments) { resumed = pane; follow(pane) }
        if let pane = Self.pane(after: Self.askArgument, in: arguments) { ask(pane, from: nil) }
    }

    private func ask(_ pane: PermissionFlowPane, from source: CGRect?) {
        defaults.set(true, forKey: key("asked", pane))
        switch pane {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        default: break
        }
        guide(pane, from: source)
    }

    private func guide(_ pane: PermissionFlowPane, from source: CGRect?) {
        settingsChanged = false
        flow.authorize(pane: pane, sourceFrameInScreen: source)
        follow(pane)
    }

    /// Reads once a second for 10 min. A Screen Recording switch that goes on reopens the app by itself.
    private func follow(_ pane: PermissionFlowPane) {
        watch?.cancel()
        let start = access(pane)
        watch = Task { [weak self] in
            for _ in 0..<600 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let now = self.access(pane)
                guard now != start else { continue }
                self.onChange?(pane)
                if now == .granted { self.flow.closePanel(); self.defaults.removeObject(forKey: self.key("tries", pane)) }
                if now == .needsRelaunch { self.reopen(pane, [Self.resumeArgument, pane.rawValue]) }
                return
            }
        }
    }

    // MARK: Repair parts

    nonisolated static func reset(_ pane: PermissionFlowPane) async {
        guard let service = ["accessibility": "Accessibility", "screenRecording": "ScreenCapture"][pane.rawValue],
              let id = Bundle.main.bundleIdentifier else { return }
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, id]
            try? process.run()
            process.waitUntilExit()
        }.value
    }

    /// Starts a new copy once this one has quit (one instance at a time), then quits. Waits up to 120 s for a slow quit.
    private func reopen(_ pane: PermissionFlowPane, _ arguments: [String]) {
        guard canReopen() else { return }
        let script = """
        pid=$1; app=$2; shift 2; i=0
        while /bin/kill -0 "$pid" 2>/dev/null; do i=$((i+1)); [ $i -gt 600 ] && exit 1; sleep 0.2; done
        exec /usr/bin/open -a "$app" --args "$@"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "reopen", String(getpid()), Bundle.main.bundlePath]
            + reopenArguments(pane) + arguments
        do { try process.run() } catch { return }
        reopenWaiter = (process, pane)
        // Not inline: terminate's wait loop would block the main actor that the quit steps need.
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    private func recentTries(_ pane: PermissionFlowPane) -> Int {
        let last = defaults.double(forKey: key("triedAt", pane))
        return Date().timeIntervalSince1970 - last < Flow.window ? defaults.integer(forKey: key("tries", pane)) : 0
    }

    private func remember(_ pane: PermissionFlowPane) {
        if let identity = Self.identity { defaults.set(identity, forKey: key("identity", pane)) }
        defaults.set(true, forKey: key("asked", pane))
    }

    private func identityChanged(_ pane: PermissionFlowPane) -> Bool {
        guard let saved = defaults.string(forKey: key("identity", pane)), let now = Self.identity else { return false }
        return saved != now
    }

    private func report(_ pane: PermissionFlowPane, _ what: String) {
        let sentKey = key("reportedAt", pane)
        guard Date().timeIntervalSince1970 - defaults.double(forKey: sentKey) > 86_400 else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: sentKey)
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        onLoop?(pane, "Permission loop: \(pane.rawValue), \(what). App \(version), macOS \(os).")
    }

    private func key(_ name: String, _ pane: PermissionFlowPane) -> String { "samPermissions.\(pane.rawValue).\(name)" }

    // MARK: System reads

    nonisolated static func pane(after flag: String, in arguments: [String]) -> PermissionFlowPane? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return PermissionFlowPane(rawValue: arguments[index + 1])
    }

    /// The code signature macOS binds a grant to.
    nonisolated static var identity: String? {
        var code: SecCode?, staticCode: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement, SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    /// Other apps' normal windows that show a title. macOS hides titles from apps without Screen Recording and shows
    /// them as soon as the switch goes on, while the preflight stays cached for this process.
    /// nil: no other window to look at.
    nonisolated static func titledWindows() -> Int? {
        let me = getpid()
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) != me && ($0[kCGWindowLayer as String] as? Int) == 0 }
        guard !windows.isEmpty else { return nil }
        return windows.filter { !(($0[kCGWindowName as String] as? String) ?? "").isEmpty }.count
    }
}
