import Foundation
@_exported import PermissionFlow

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

/// Why access is missing, for the line the app shows beside Fix.
public enum Reason: String, Sendable {
    /// Never asked, switched off, or reset.
    case notAllowed
    /// The switch is on for an old signature of this app, so macOS still denies access.
    case staleGrant
    /// The switch is on, but this process started before it.
    case needsRelaunch
}

/// What one click on Fix does.
public enum Step: String, Sendable {
    case nothing, prompt, openPane, reset, reopen
}

/// The rules, with no system calls, so they are unit tested.
/// The result of a first-use request.
public enum Answer: String, Sendable {
    case granted, cancelled, denied
}

public enum Flow {
    /// Tries in a row with no change before the flow counts as stuck.
    public static let loopTries = 3
    public static let window: TimeInterval = 600
    /// Panes with a macOS request. Every other pane goes straight to System Settings.
    public static let askable: Set<PermissionFlowPane> = [.accessibility, .screenRecording, .inputMonitoring,
                                                          .microphone, .camera, .calendars, .reminders]
    /// Panes whose old-signature grant Fix repairs with a reset. Every other pane picks up a grant live
    /// and never resets or reopens.
    public static let repairable: Set<PermissionFlowPane> = [.accessibility, .screenRecording]

    public static func access(_ reading: Reading, asked: Bool, reopenedForGrant: Bool) -> Access {
        if reading.preflight { return .granted }
        // After our own reopen a new process must see the grant; titles without it mean the probe is wrong.
        if (reading.titledWindows ?? 0) > 0, !reopenedForGrant { return .needsRelaunch }
        return asked ? .denied : .notAsked
    }

    /// First use of a feature. Only a never-asked app explains (`confirm`) and asks macOS (`ask`);
    /// after any Cancel or Deny it returns `.denied` at once, so the app shows its Fix banner.
    public static func request(_ access: Access, confirm: () -> Bool, ask: () -> Bool,
                               markAsked: () -> Void) -> Answer {
        gate(access, confirm: confirm, markAsked: markAsked) ?? (ask() ? .granted : .denied)
    }

    /// The answer without asking macOS, or nil when the app should ask macOS now.
    public static func gate(_ access: Access, confirm: () -> Bool, markAsked: () -> Void) -> Answer? {
        switch access {
        case .granted: return .granted
        case .denied, .needsRelaunch: return .denied
        case .notAsked:
            markAsked()
            return confirm() ? nil : .cancelled
        }
    }

    /// nil when granted.
    public static func reason(_ access: Access, identityChanged: Bool) -> Reason? {
        switch access {
        case .granted: return nil
        case .needsRelaunch: return .needsRelaunch
        case .notAsked: return .notAllowed
        case .denied: return identityChanged ? .staleGrant : .notAllowed
        }
    }

    /// - Parameters:
    ///   - tries: earlier clicks in the last ten minutes with no change since.
    ///   - settingsChanged: macOS changed a privacy setting while this flow ran (tcc notification).
    public static func step(_ access: Access, pane: PermissionFlowPane, identityChanged: Bool, tries: Int,
                            settingsChanged: Bool) -> Step {
        switch access {
        case .granted: return .nothing
        case .needsRelaunch: return .reopen
        case .notAsked: return askable.contains(pane) ? .prompt : .openPane
        case .denied:
            if tries + 1 >= loopTries || !repairable.contains(pane) { return .openPane }
            // A row from an old signature stays on but denies us; a second click without change repairs it.
            guard identityChanged || tries >= 1 else { return .openPane }
            // The switch may be on but unseen by this process: reopen before a reset, never wipe a good grant.
            // A Deny answer to the system prompt also changes settings, so the first click still opens the pane.
            return pane == .screenRecording && settingsChanged ? .reopen : .reset
        }
    }
}
