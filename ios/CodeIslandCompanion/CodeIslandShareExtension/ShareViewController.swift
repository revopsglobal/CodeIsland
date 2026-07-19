import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        titleLabel.text = "New Code Island task"
        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        titleLabel.textColor = .label

        detailLabel.text = "Review the instructions, workspace, and provider in Buddy before anything runs."
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Continue in Buddy"
        configuration.image = UIImage(systemName: "arrow.up.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .black
        sendButton.configuration = configuration
        sendButton.addTarget(self, action: #selector(saveDraft), for: .touchUpInside)
        sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, sendButton, cancelButton, spinner])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    @objc private func saveDraft() {
        sendButton.isEnabled = false
        spinner.startAnimating()
        Task {
            do {
                let payload = try await collectPayload()
                let inbox = try SharedDraftInbox()
                _ = try inbox.store(text: payload.text, files: payload.files)
                await MainActor.run { openBuddy() }
            } catch {
                await MainActor.run {
                    spinner.stopAnimating()
                    sendButton.isEnabled = true
                    detailLabel.text = error.localizedDescription
                    detailLabel.textColor = .systemOrange
                }
            }
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: CancellationError())
    }

    private func openBuddy() {
        spinner.stopAnimating()
        guard let url = URL(string: "codeisland://new-task") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func collectPayload() async throws -> (text: String?, files: [SharedDraftFileInput]) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        var textParts: [String] = []
        var files: [SharedDraftFileInput] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let value = try await loadItem(provider, type: .plainText) as? String {
                textParts.append(value)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try await loadItem(provider, type: .url) as? URL {
                textParts.append(url.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = try await loadData(provider, type: .image) {
                files.append(.init(
                    data: data,
                    displayName: Self.safeName(provider.suggestedName, fallback: "Shared image.png"),
                    mediaType: "image/png"
                ))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                      let url = try await loadItem(provider, type: .fileURL) as? URL {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.preferredMIMEType
                    ?? "application/octet-stream"
                files.append(.init(
                    data: try Data(contentsOf: url, options: [.mappedIfSafe]),
                    displayName: Self.safeName(provider.suggestedName ?? url.lastPathComponent, fallback: "Shared file"),
                    mediaType: type
                ))
            } else if let identifier = provider.registeredTypeIdentifiers.first,
                      let type = UTType(identifier),
                      let data = try await loadData(provider, type: type) {
                files.append(.init(
                    data: data,
                    displayName: Self.safeName(provider.suggestedName, fallback: "Shared file"),
                    mediaType: type.preferredMIMEType ?? "application/octet-stream"
                ))
            }
        }
        guard !textParts.isEmpty || !files.isEmpty else { throw SharedDraftInbox.InboxError.emptyDraft }
        return (textParts.isEmpty ? nil : textParts.joined(separator: "\n\n"), files)
    }

    private func loadItem(_ provider: NSItemProvider, type: UTType) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item) }
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }

    private static func safeName(_ value: String?, fallback: String) -> String {
        let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !candidate.isEmpty,
              !candidate.contains("/"),
              !candidate.contains("\\"),
              candidate != ".",
              candidate != ".."
        else { return fallback }
        return String(candidate.prefix(180))
    }
}
