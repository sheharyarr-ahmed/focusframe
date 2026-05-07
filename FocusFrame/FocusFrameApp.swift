import SwiftData
import SwiftUI

@main
struct FocusFrameApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Session.self,
            Goal.self,
            Insight.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootContainer(modelContext: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}

private struct RootContainer: View {
    @State private var appState: AppState

    init(modelContext: ModelContext) {
        _appState = State(wrappedValue: AppState(modelContext: modelContext))
    }

    var body: some View {
        RootView()
            .environment(appState)
            .preferredColorScheme(.dark)
    }
}
