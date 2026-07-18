import UIKit
import UniformTypeIdentifiers

/// Accepts a web URL, PDF, or image from the share sheet and stores it in the
/// App Group inbox for review inside Recipe Vault. Parsing remains in the app:
/// the extension has a tight memory budget and no access to the app's Keychain.
@MainActor
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Saving to Recipe Vault..."
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        processFirstUsableAttachment()
    }

    private func processFirstUsableAttachment() {
        guard let inbox = ShareInbox.inboxDirectory() else {
            finish(message: "Recipe Vault's shared container is unavailable.", succeeded: false)
            return
        }

        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        // A concrete document is more useful than the page URL that some
        // hosts include beside it.
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            loadData(from: provider, type: .pdf) { [weak self] data in
                self?.store(kind: .pdf, payload: data, in: inbox)
            }
        } else if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            loadData(from: provider, type: .image) { [weak self] data in
                self?.store(kind: .image, payload: data, in: inbox)
            }
        } else if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            loadURL(from: provider, in: inbox)
        } else if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            loadLinkText(from: provider, in: inbox)
        } else {
            finish(message: "Nothing shareable to Recipe Vault was found.", succeeded: false)
        }
    }

    private func loadData(
        from provider: NSItemProvider,
        type: UTType,
        completion: @escaping @MainActor (Data?) -> Void
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            Task { @MainActor in completion(data) }
        }
    }

    private func loadURL(from provider: NSItemProvider, in inbox: URL) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
            let urlString = (item as? URL)?.absoluteString
            Task { @MainActor in
                guard let self else { return }
                guard let urlString, let url = URL(string: urlString), Self.isWebURL(url) else {
                    self.finish(message: "Only web links can be shared to Recipe Vault.", succeeded: false)
                    return
                }
                self.store(kind: .url, payload: Data(url.absoluteString.utf8), in: inbox)
            }
        }
    }

    private func loadLinkText(from provider: NSItemProvider, in inbox: URL) {
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
            let sharedText = item as? String
            Task { @MainActor in
                guard let self else { return }
                let text = sharedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let text, let url = URL(string: text), Self.isWebURL(url) else {
                    self.finish(
                        message: "Recipe Vault can take web links, PDFs, and photos - not plain text yet.",
                        succeeded: false
                    )
                    return
                }
                self.store(kind: .url, payload: Data(url.absoluteString.utf8), in: inbox)
            }
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }

    private func store(kind: ShareInbox.Kind, payload: Data?, in inbox: URL) {
        guard let payload, !payload.isEmpty else {
            finish(message: "That item couldn't be read.", succeeded: false)
            return
        }

        do {
            try ShareInbox.writeItem(kind: kind, payload: payload, in: inbox)
            finish(message: "Saved. Open Recipe Vault and go to Import to review it.", succeeded: true)
        } catch {
            finish(message: error.localizedDescription, succeeded: false)
        }
    }

    private func finish(message: String, succeeded: Bool) {
        statusLabel.text = message
        let delay = succeeded ? 0.9 : 1.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let context = self?.extensionContext else { return }
            if succeeded {
                context.completeRequest(returningItems: nil)
            } else {
                context.cancelRequest(withError: NSError(
                    domain: "Patrick-App.Recipes.RecipeVaultShare",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                ))
            }
        }
    }
}
