import UIKit
import UniformTypeIdentifiers

/// Recipe Vault share extension (STAGED — not yet in any target; see
/// README.md in this folder). Accepts a web URL, PDF, or image from the
/// share sheet, stores it in the App Group inbox, and tells the user to
/// finish in the app.
///
/// It deliberately does NOT parse anything: extensions get ~120 MB of
/// memory (a 25 MB PDF through PDFKit/Vision would be killed), and the AI
/// key lives in the app's Keychain and is never shared with this process.
/// The only shared code is `ShareInboxEnvelope.swift` (Foundation-only).
final class ShareViewController: UIViewController {

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Saving to Recipe Vault…"
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

        // Priority: a concrete document beats the page URL that often rides
        // along with it.
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) {
            loadData(from: provider, type: UTType.pdf) { [weak self] data in
                self?.store(kind: .pdf, payload: data, in: inbox)
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            loadData(from: provider, type: UTType.image) { [weak self] data in
                self?.store(kind: .image, payload: data, in: inbox)
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                let url = item as? URL
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                        self.finish(message: "Only web links can be shared to Recipe Vault.", succeeded: false)
                        return
                    }
                    self.store(kind: .url, payload: Data(url.absoluteString.utf8), in: inbox)
                }
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                let text = (item as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    guard let self else { return }
                    // Accept text only when it is a link; free-text parsing
                    // belongs to a later phase.
                    if let text, let url = URL(string: text),
                       ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        self.store(kind: .url, payload: Data(url.absoluteString.utf8), in: inbox)
                    } else {
                        self.finish(message: "Recipe Vault can take web links, PDFs, and photos — not plain text yet.", succeeded: false)
                    }
                }
            }
        } else {
            finish(message: "Nothing shareable to Recipe Vault was found.", succeeded: false)
        }
    }

    private func loadData(from provider: NSItemProvider, type: UTType, completion: @escaping (Data?) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            DispatchQueue.main.async { completion(data) }
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (succeeded ? 0.9 : 1.8)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
