import SwiftUI

public struct ContentView: View {
    @ObservedObject private var model: BorgBarModel
    private let openSettingsWindow: () -> Void

    public init(
        model: BorgBarModel,
        openSettingsWindow: @escaping () -> Void = {}
    ) {
        self.model = model
        self.openSettingsWindow = openSettingsWindow
    }

    public var body: some View {
        MenuBarView(
            orchestrator: model.orchestrator,
            openSettingsWindow: openSettingsWindow
        )
    }
}
