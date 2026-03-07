import UIKit
import SwiftUI

/**
 ShareViewController - Entry point for the iOS Share Extension

 INFO.PLIST CONFIGURATION:
 Add this to the share extension's Info.plist:

 <key>NSExtension</key>
 <dict>
     <key>NSExtensionPointIdentifier</key>
     <string>com.apple.share-services</string>
     <key>NSExtensionActivationRule</key>
     <dict>
         <key>NSExtensionActivationSupportsText</key>
         <true/>
         <key>NSExtensionActivationSupportsURL</key>
         <true/>
     </dict>
     <key>NSExtensionAttributes</key>
     <dict>
         <key>NSExtensionActivationRule</key>
         <dict>
             <key>NSExtensionActivationSupportsText</key>
             <true/>
             <key>NSExtensionActivationSupportsURL</key>
             <true/>
         </dict>
     </dict>
 </dict>
 */

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Extract shared content
        extractSharedContent()
    }

    private func extractSharedContent() {
        guard let extensionContext = extensionContext else {
            dismissWithError("Unable to access extension context")
            return
        }

        guard let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            dismissWithError("No input items found")
            return
        }

        var sharedURL: URL?
        var sharedTitle: String?

        // Process input items to extract URL and title
        for item in inputItems {
            // Try to get URL from attachments
            if let attachments = item.attachments {
                for attachment in attachments {
                    // Check for URL type
                    if attachment.hasItemConformingToTypeIdentifier("public.url") {
                        attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] url, error in
                            if let url = url as? URL {
                                sharedURL = url
                            }
                        }
                    }

                    // Check for text type (in case URL is shared as text)
                    if attachment.hasItemConformingToTypeIdentifier("public.plain-text") {
                        attachment.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] text, error in
                            if let text = text as? String, let url = URL(string: text) {
                                sharedURL = url
                            }
                        }
                    }
                }
            }

            // Try to get page title from attributed content
            if let attributedTitle = item.attributedContentText {
                sharedTitle = attributedTitle.string
            }
        }

        // Wait a moment for async item loading, then present UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.presentShareSheet(url: sharedURL, title: sharedTitle)
        }
    }

    private func presentShareSheet(url: URL?, title: String?) {
        let shareView = ShareView(
            sharedURL: url,
            sharedTitle: title,
            extensionContext: extensionContext
        )

        let hostingController = UIHostingController(rootView: shareView)
        hostingController.view.backgroundColor = UIColor(named: "SystemBackground") ?? .systemBackground

        // Configure the hosting controller for sheet presentation
        if #available(iOS 16.0, *) {
            if let sheet = hostingController.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
        }

        present(hostingController, animated: true)
    }

    private func dismissWithError(_ message: String) {
        let alert = UIAlertController(
            title: "Unable to Share",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        present(alert, animated: true)
    }
}
