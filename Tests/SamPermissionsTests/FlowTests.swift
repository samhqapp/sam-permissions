import PermissionFlow
import Testing
@testable import SamPermissions

struct FlowTests {
    @Test func preflightWins() {
        #expect(Flow.access(Reading(preflight: true, titledWindows: 0), asked: true, reopenedForGrant: true) == .granted)
    }

    @Test func titlesWithoutPreflightMeanReopen() {
        #expect(Flow.access(Reading(preflight: false, titledWindows: 3), asked: true, reopenedForGrant: false) == .needsRelaunch)
    }

    @Test func noReopenLoopAfterOwnReopen() {
        #expect(Flow.access(Reading(preflight: false, titledWindows: 3), asked: true, reopenedForGrant: true) == .denied)
    }

    @Test func neverAskedPrompts() {
        let access = Flow.access(Reading(preflight: false, titledWindows: 0), asked: false, reopenedForGrant: false)
        #expect(access == .notAsked)
        #expect(Flow.step(access, pane: .screenRecording, identityChanged: false, tries: 0, settingsChanged: false) == .prompt)
    }

    @Test func grantedDoesNothing() {
        #expect(Flow.step(.granted, pane: .screenRecording, identityChanged: true, tries: 2, settingsChanged: true) == .nothing)
    }

    @Test func staleProcessReopensNeverResets() {
        #expect(Flow.step(.needsRelaunch, pane: .screenRecording, identityChanged: true, tries: 1, settingsChanged: true) == .reopen)
        #expect(Flow.step(.denied, pane: .screenRecording, identityChanged: true, tries: 1, settingsChanged: true) == .reopen)
    }

    @Test func oldSignatureResets() {
        #expect(Flow.step(.denied, pane: .screenRecording, identityChanged: true, tries: 0, settingsChanged: false) == .reset)
        #expect(Flow.step(.denied, pane: .accessibility, identityChanged: false, tries: 1, settingsChanged: false) == .reset)
    }

    @Test func firstDeniedClickOnlyGuides() {
        #expect(Flow.step(.denied, pane: .accessibility, identityChanged: false, tries: 0, settingsChanged: false) == .openPane)
    }

    @Test func loopStopsResetting() {
        #expect(Flow.step(.denied, pane: .screenRecording, identityChanged: true, tries: 2, settingsChanged: false) == .openPane)
    }

    @Test func launchArgument() {
        #expect(SamPermissions.pane(after: "--sam-permission-ask", in: ["app", "--sam-permission-ask", "screenRecording"]) == .screenRecording)
        #expect(SamPermissions.pane(after: "--sam-permission-ask", in: ["app", "--sam-permission-ask"]) == nil)
    }
}
