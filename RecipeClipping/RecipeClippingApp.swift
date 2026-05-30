//
//  RecipeClippingApp.swift
//  RecipeClipping
//
//  Created by こたつん on 2026/05/29.
//

import SwiftUI
import SwiftData

@main
struct RecipeClippingApp: App {
    private let containerResult: Result<ModelContainer, Error> = {
        do {
            let schema = Schema([Recipe.self, CookLog.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            RecipeDataDiagnostics.logCurrentState(container: container)
            return .success(container)
        } catch {
            print("RecipeClipper SwiftData container failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }()

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                RecipeListView()
                    .modelContainer(container)
            case .failure(let error):
                DataStoreErrorView(error: error)
            }
        }
    }
}

private enum RecipeDataDiagnostics {
    @MainActor
    static func logCurrentState(container: ModelContainer) {
        do {
            let context = container.mainContext
            let recipeCount = try context.fetchCount(FetchDescriptor<Recipe>())
            let cookLogCount = try context.fetchCount(FetchDescriptor<CookLog>())
            print("RecipeClipper data: \(recipeCount) recipes, \(cookLogCount) cook logs")
        } catch {
            print("RecipeClipper data count failed: \(error.localizedDescription)")
        }
    }
}

private struct DataStoreErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("データを開けませんでした", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("既存データ保護のため、ストアを初期化せず停止しています。Xcodeのログを確認してください。\n\(error.localizedDescription)")
        }
    }
}
