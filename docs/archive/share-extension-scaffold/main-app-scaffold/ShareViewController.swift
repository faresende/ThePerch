import UIKit
import SwiftUI

/*
 SHARE EXTENSION INFO.PLIST CONFIGURATION:

 <key>NSExtension</key>
 <dict>
     <key>NSExtensionPointIdentifier</key>
     <string>com.apple.share-services</string>
     <key>NSExtensionActivationRule</key>
     <dict>
         <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
         <integer>1</integer>
         <key>NSExtensionActivationSupportsWebPageWithMaxCount</key>
         <integer>1</integer>
     </dict>
     <key>NSExtensionAttributes</key>
     <dict>
         <key>UIExtensionPointIdentifier</key>
         <string>com.apple.share-services</string>
     </dict>
 </dict>

 APP GROUPS ENTITLEMENT:
 Add to ShareExtension.entitlements:
 <key>com.apple.security.application-groups</key>
 <array>
     <string>group.com.theperch.shared</string>
 </array>

 KEYCHAIN SHARING ENTITLEMENT:
 <key>keychain-access-groups</key>
 <array>
     <string>$(AppIdentifierPrefix)group.com.theperch.shared</string>
 </array>
*/

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            await handleShareExtension()
        }
    }

    private func handleShareExtension() async {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            dismissWithError("Could not access shared content")
            return
        }

        // Extract URL and title from the share extension
        var extractedURL: URL?
        var extractedTitle: String?

        for attachment in extensionItem.attachments ?? [] {
            // Try to get URL
            if attachment.hasItemConformingToTypeIdentifier("public.url") {
                if let url = await loadItemOfType("public.url", from: attachment) as? URL {
                    extractedURL = url
                }
            }

            // Try to get title
            if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
                if let text = await loadItemOfType("public.plain-text", from: attachment) as? String {
                    extractedTitle = text
                }
            }
        }

        // If we didn't get a title from the attachment, try to extract it from URL or use the hostname
        if extractedTitle == nil, let url = extractedURL {
            extractedTitle = url.host ?? url.absoluteString
        }

        // If we still don't have a URL, that's a problem
        guard let url = extractedURL else {
            dismissWithError("Could not extract URL from shared content")
            return
        }

        // Present the share sheet UI
        let rootView = ShareExtensionView(
            url: url,
            title: extractedTitle ?? "",
            extensionContext: extensionContext
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .systemBackground

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
    }

    private func loadItemOfType(_ type: String, from attachment: NSItemProvider) async -> Any? {
        do {
            return try await attachment.loadItem(forTypeIdentifier: type, options: nil)
        } catch {
            print("Error loading item of type \(type): \(error)")
            return nil
        }
    }

    private func dismissWithError(_ message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            })
            self.present(alert, animated: true)
        }
    }
}
