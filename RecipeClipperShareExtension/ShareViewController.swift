import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = SharedURLModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ShareExtensionView(
            model: model,
            openAction: { [weak self] in self?.openMainApp() },
            cancelAction: { [weak self] in self?.extensionContext?.cancelRequest(withError: ShareExtensionError.cancelled) }
        )
        let host = UIHostingController(rootView: rootView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        Task {
            await model.load(from: extensionContext)
        }
    }

    private func openMainApp() {
        guard let sharedURL = model.url,
              let importURL = ShareURLTools.encodedImportURL(for: sharedURL) else {
            model.errorMessage = "URLが見つかりませんでした。"
            return
        }

        extensionContext?.open(importURL) { [weak self] didOpen in
            guard let self else { return }
            if didOpen {
                self.extensionContext?.completeRequest(returningItems: nil)
            } else {
                UIPasteboard.general.string = sharedURL.absoluteString
                Task { @MainActor in
                    self.model.errorMessage = "RecipeClipperを自動で開けなかったため、URLをクリップボードにコピーしました。RecipeClipperを手動で開いて貼り付けてください。"
                }
            }
        }
    }
}

private struct ShareExtensionView: View {
    @ObservedObject var model: SharedURLModel
    let openAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if model.isLoading {
                    ProgressView("URLを読み込み中")
                } else if let url = model.url {
                    Label("RecipeClipperに送ります", systemImage: "link")
                        .font(.headline)
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button {
                        openAction()
                    } label: {
                        Label("RecipeClipperで開く", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ContentUnavailableView(
                        "URLが見つかりません",
                        systemImage: "exclamationmark.magnifyingglass",
                        description: Text(model.errorMessage ?? "共有されたテキストの中にURLがありませんでした。")
                    )
                }
                Spacer()
            }
            .padding()
            .navigationTitle("RecipeClipper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: cancelAction)
                }
            }
        }
    }
}

@MainActor
private final class SharedURLModel: ObservableObject {
    @Published var url: URL?
    @Published var isLoading = true
    @Published var errorMessage: String?

    func load(from context: NSExtensionContext?) async {
        defer { isLoading = false }
        guard let inputItems = context?.inputItems as? [NSExtensionItem] else {
            errorMessage = "共有データを読み取れませんでした。"
            return
        }

        for item in inputItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let loadedURL = await loadURL(from: provider) {
                    url = loadedURL
                    return
                }
            }
        }

        for item in inputItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(from: provider),
                   let loadedURL = ShareURLTools.firstURL(in: text) {
                    url = loadedURL
                    return
                }
            }
        }

        errorMessage = "共有された内容にURLが含まれていません。"
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let text = item as? String {
                    continuation.resume(returning: ShareURLTools.firstURL(in: text))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private enum ShareURLTools {
    static func firstURL(in text: String) -> URL? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = detector.matches(in: text, range: range).first,
               let url = match.url {
                return url
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return nil
    }

    static func encodedImportURL(for sharedURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "recipeclipper"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "url", value: sharedURL.absoluteString)]
        return components.url
    }
}

private enum ShareExtensionError: LocalizedError {
    case cancelled
}
