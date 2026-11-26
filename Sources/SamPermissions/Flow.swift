import Foundation
import PermissionFlow

public enum Access: String, Sendable, Codable {
    case granted, notAsked, denied
    /// The switch is on, but this process started before it. Screen Recording only; a reopen fixes it.
    case needsRelaunch
}

/// What macOS says right now. Reading never prompts.
public struct Reading: Equatable, Sendable {
    /// PermissionFlow's status read (`CGPreflightScreenCaptureAccess`, `AXIsProcessTrusted`).
    public var preflight: Bool
    /// Other apps' titled windows. macOS shows them at once after a Screen Recording grant, while the
    /// preflight stays false until the app restarts. nil: no other window to look at, or not Screen Recording.
    public var titledWindows: Int?

    public init(preflight: Bool, titledWindows: Int? = nil) {
        self.preflight = preflight
        self.titledWindows = titledWindows
    }
}

/// What one click on Fix does.
public enum Step: String, Sendable {
    case nothing, prompt, openPane, reset, reopen
}

/// The rules, with no system calls, so they are unit tested.
public enum Flow {
    /// Tries in a row with no change before the flow counts as stuck.
    public static let loopTries = 3
    public static let window: TimeInterval = 600

    public static func access(_ reading: Reading, asked: Bool, reopenedForGrant: Bool) -> Access {
        if reading.preflight { return .granted }
        // After our own reopen a new process must see the grant; titles without it mean the probe is wrong.
        if (reading.titledWindows ?? 0) > 0, !reopenedForGrant { return .needsRelaunch }
        return asked ? .denied : .notAsked
    }

    /// - Parameters:
    ///   - tries: earlier clicks in the last ten minutes with no change since.
    ///   - settingsChanged: macOS changed a privacy setting while this flow ran (tcc notification).
    public static func step(_ access: Access, pane: PermissionFlowPane, identityChanged: Bool, tries: Int,
                            settingsChanged: Bool) -> Step {
        switch access {
        case .granted: return .nothing
        case .needsRelaunch: return .reopen
        case .notAsked: return .prompt
        case .denied:
            if tries + 1 >= loopTries { return .openPane }
            // The switch may be on but unseen by this process: reopen first, never wipe a good grant.
            if pane == .screenRecording, settingsChanged { return .reopen }
            // A row from an old signature stays on but denies us; a second click without change repairs it.
            return identityChanged || tries >= 1 ? .reset : .openPane
        }
    }
}
