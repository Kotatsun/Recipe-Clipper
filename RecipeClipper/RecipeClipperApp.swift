import SwiftUI
import SwiftData

@main
struct RecipeClipperApp: App {
    var body: some Scene {
        WindowGroup {
            RecipeListView()
        }
        .modelContainer(for: [Recipe.self, CookLog.self])
    }
}
