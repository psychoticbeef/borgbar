import Foundation

@MainActor
protocol BorgBarModelIntegrationPort: AnyObject {
    func fullDiskAccessDiagnostics() async -> FullDiskAccessDiagnostics
}

@MainActor
final class DefaultBorgBarModelIntegrationPort: BorgBarModelIntegrationPort {
    private let fullDiskAccess: FullDiskAccessService

    init(fullDiskAccess: FullDiskAccessService = FullDiskAccessService()) {
        self.fullDiskAccess = fullDiskAccess
    }

    func fullDiskAccessDiagnostics() async -> FullDiskAccessDiagnostics {
        await fullDiskAccess.diagnostics()
    }
}
