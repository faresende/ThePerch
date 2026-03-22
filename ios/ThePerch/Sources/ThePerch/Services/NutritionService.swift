import Foundation
import UIKit

final class NutritionService {
    static let shared = NutritionService()

    let edgeFunctionURL = AppConfig.shared.supabaseURL.appendingPathComponent("functions/v1/nutrition-copilot")

    private init() {}

    func analyzeMeal(text: String?, imageData: Data?) async throws -> [String: Any] {
        var body: [String: Any] = ["mode": "analyze"]
        if let text, text.isEmpty == false {
            body["text"] = text
        }
        if let imageData = try preparedImageData(from: imageData) {
            body["image_base64"] = imageData.base64EncodedString()
        }
        return try await performRequest(body: body)
    }

    func correctMeal(recordId: String, correctionText: String) async throws -> [String: Any] {
        try await performRequest(body: [
            "mode": "correct",
            "record_id": recordId,
            "correction_text": correctionText
        ])
    }

    func suggestMeals(userId: String, context: String?) async throws -> [String: Any] {
        var body: [String: Any] = [
            "mode": "suggest",
            "user_id": userId
        ]
        if let context, context.isEmpty == false {
            body["context"] = context
        }
        return try await performRequest(body: body)
    }

    private func performRequest(body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: edgeFunctionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfig.shared.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw SupabaseServiceError.networkError(message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseServiceError.decodingError("Invalid nutrition response payload")
        }

        return json
    }

    private func preparedImageData(from imageData: Data?) throws -> Data? {
        guard let imageData else { return nil }
        guard let image = UIImage(data: imageData) else {
            throw SupabaseServiceError.decodingError("Unable to decode selected meal image")
        }
        return try compressJPEG(image: image, maxBytes: 1_000_000)
    }

    private func compressJPEG(image: UIImage, maxBytes: Int) throws -> Data {
        var compressionQuality: CGFloat = 0.9
        guard var data = image.jpegData(compressionQuality: compressionQuality) else {
            throw SupabaseServiceError.decodingError("Unable to encode selected meal image")
        }

        while data.count > maxBytes, compressionQuality > 0.1 {
            compressionQuality -= 0.1
            guard let compressed = image.jpegData(compressionQuality: compressionQuality) else {
                break
            }
            data = compressed
        }

        if data.count <= maxBytes {
            return data
        }

        var currentImage = image
        while data.count > maxBytes {
            let nextSize = CGSize(
                width: max(currentImage.size.width * 0.85, 320),
                height: max(currentImage.size.height * 0.85, 320)
            )

            UIGraphicsBeginImageContextWithOptions(nextSize, true, 1.0)
            currentImage.draw(in: CGRect(origin: .zero, size: nextSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            guard let resizedImage,
                  let compressed = resizedImage.jpegData(compressionQuality: compressionQuality) else {
                break
            }

            currentImage = resizedImage
            data = compressed

            if Int(nextSize.width) == 320, Int(nextSize.height) == 320 {
                break
            }
        }

        return data
    }
}
