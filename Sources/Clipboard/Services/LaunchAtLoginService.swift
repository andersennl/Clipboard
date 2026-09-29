import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginServing: AnyObject {
    var state: LaunchAtLoginService.State { get }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> LaunchAtLoginService.State
}

@MainActor
final class LaunchAtLoginService: LaunchAtLoginServing {
    enum State: Equatable {
        case enabled
        case requiresApproval
        case notRegistered

        var isOn: Bool {
            self != .notRegistered
        }
    }

    var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    /// Registers or removes the login item. Never throws: a refused registration must not
    /// take the app down, the reported state simply stays `notRegistered`.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> State {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if state.isOn {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fall through and report whatever macOS says the state is now.
        }

        return state
    }
}
