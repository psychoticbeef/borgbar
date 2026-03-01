import Foundation

enum TerminationStartDecision {
    case terminateNow
    case terminateCancel
    case needsUserConfirmation
}

struct AppTerminationPolicy {
    func startDecision(terminationInFlight: Bool, backupRunning: Bool) -> TerminationStartDecision {
        if terminationInFlight {
            return .terminateCancel
        }
        if !backupRunning {
            return .terminateNow
        }
        return .needsUserConfirmation
    }

    func shouldQuitAfterForceChoice(userChoseForceQuit: Bool) -> Bool {
        return userChoseForceQuit
    }
}
