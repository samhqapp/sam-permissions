import PermissionFlow
import Testing
@testable import SamPermissions

struct FlowTests {
    @Test func grantedHasNoReason() {
        #expect(Flow.reason(.granted, identityChanged: true) == nil)
    }

    @Test func neverAskedIsNotAllowed() {
        #expect(Flow.reason(.notAsked, identityChanged: false) == .notAllowed)
    }

    @Test func switchedOffOrResetIsNotAllowed() {
        #expect(Flow.reason(.denied, identityChanged: false) == .notAllowed)
    }

    @Test func oldSignatureIsStaleGrant() {
        #expect(Flow.reason(.denied, identityChanged: true) == .staleGrant)
    }

    @Test func switchOnBeforeStartNeedsRelaunch() {
        #expect(Flow.reason(.needsRelaunch, identityChanged: false) == .needsRelaunch)
    }

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

    @Test func requestAsksOnlyOnce() {
        var prompts = 0, asks = 0, marked = 0
        func run(_ access: Access, confirm: Bool = true, allow: Bool = false) -> Answer {
            Flow.request(access, confirm: { prompts += 1; return confirm }, ask: { asks += 1; return allow },
                         markAsked: { marked += 1 })
        }
        #expect(run(.notAsked) == .denied)
        #expect((prompts, asks, marked) == (1, 1, 1))
        // Denied, then the hotkey again: no app prompt and no macOS prompt, only the Fix banner.
        #expect(run(.denied) == .denied)
        #expect(run(.needsRelaunch) == .denied)
        #expect((prompts, asks) == (1, 1))
        #expect(run(.notAsked, confirm: false) == .cancelled)
        #expect((prompts, asks, marked) == (2, 1, 2))
        #expect(run(.granted) == .granted)
        #expect(run(.notAsked, allow: true) == .granted)
    }

    @Test func denyAtPromptThenFixOpensPane() {
        #expect(Flow.step(.denied, pane: .screenRecording, identityChanged: false, tries: 0, settingsChanged: true) == .openPane)
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

    @Test func paneWithoutRequestOpensPane() {
        for pane in PermissionFlowPane.allCases where !Flow.askable.contains(pane) {
            #expect(Flow.step(.notAsked, pane: pane, identityChanged: false, tries: 0, settingsChanged: false) == .openPane)
        }
        #expect(Flow.step(.notAsked, pane: .microphone, identityChanged: false, tries: 0, settingsChanged: false) == .prompt)
    }

    @Test func liveGrantPaneNeverResetsOrReopens() {
        for pane in PermissionFlowPane.allCases where !Flow.repairable.contains(pane) {
            #expect(Flow.step(.denied, pane: pane, identityChanged: true, tries: 1, settingsChanged: true) == .openPane)
        }
    }

    @Test @MainActor func panelNeverAsksForAccessibility() {
        #expect(SamPermissions.flowConfiguration.promptForAccessibilityTrust == false)
    }

    @Test func settingsPagesOpenTheRightPaneWithOneLine() {
        #expect(SettingsPage.loginItems.url.absoluteString == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        #expect(SettingsPage.automation(target: "com.apple.finder").url.absoluteString.hasSuffix("?Privacy_Automation"))
        #expect(SettingsPage.permission(.camera).url == PermissionFlowPane.camera.settingsURL)
        #expect(SettingsPage.loginItems.line(app: "Task Manager") == "Turn on the switch next to Task Manager.")
    }

    @Test func launchArgument() {
        #expect(SamPermissions.pane(after: "--sam-permission-ask", in: ["app", "--sam-permission-ask", "screenRecording"]) == .screenRecording)
        #expect(SamPermissions.pane(after: "--sam-permission-ask", in: ["app", "--sam-permission-ask"]) == nil)
    }

    @MainActor @Test func appStatusReplacesBuiltInRead() async {
        #expect(await SamPermissions.status(.loginItems, allowed: { false }) { _ in true } == false)
        #expect(await SamPermissions.status(.loginItems, allowed: { true }) { _ in false } == true)
        #expect(await SamPermissions.status(.permission(.camera), allowed: nil) { _ in true } == true)
        #expect(await SamPermissions.status(.localNetwork, allowed: nil) { _ in true } == nil)
    }
}
