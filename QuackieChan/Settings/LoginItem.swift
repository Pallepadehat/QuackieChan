import Observation
import ServiceManagement

/// Starting Quackie Chan when you log in. macOS keeps the real switch (it shows up in System Settings → General →
/// Login Items too), so this reads it from there rather than saving its own copy.
@MainActor
@Observable
final class LoginItem {
    static let shared = LoginItem()

    private(set) var isOn = SMAppService.mainApp.status == .enabled
    /// macOS wants you to approve it in System Settings first.
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval
    private(set) var problem: String?

    func set(_ on: Bool) {
        problem = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = "macOS said no: \(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isOn = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
