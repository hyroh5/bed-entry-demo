import SwiftData
import SwiftUI

@main
struct SleepDemoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings: SettingsStore
    @State private var controller: MeasurementController
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: MeasurementSession.self, SampleBatch.self, UserLabel.self, LocationRecord.self)
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _controller = State(initialValue: MeasurementController(settings: settings, context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(controller)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            controller.setAppActive(phase == .active)
        }
    }
}
