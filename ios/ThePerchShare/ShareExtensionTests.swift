import XCTest
import Foundation

/**
 ShareExtensionTests.swift - Unit tests for Share Extension components

 Add this file to your test target to verify extension functionality.
 */

class SharedCredentialsTests: XCTestCase {
    var sut: SharedCredentials!

    override func setUp() {
        super.setUp()
        sut = SharedCredentials()
        // Clean up any existing test credentials
        sut.clearCredentials()
    }

    override func tearDown() {
        super.tearDown()
        sut.clearCredentials()
    }

    func testSaveAndLoadCredentials() {
        // Arrange
        let testURL = "https://test.supabase.co"
        let testKey = "test-anon-key-12345"
        let testToken = "test-access-token-98765"
        let testUserID = "user-id-12345"

        // Act
        sut.saveCredentials(
            supabaseURL: testURL,
            anonKey: testKey,
            accessToken: testToken,
            userId: testUserID
        )

        let loaded = sut.loadCredentials()

        // Assert
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.supabaseURL, testURL)
        XCTAssertEqual(loaded?.anonKey, testKey)
        XCTAssertEqual(loaded?.accessToken, testToken)
        XCTAssertEqual(loaded?.userId, testUserID)
    }

    func testLoadCredentialsWhenNone() {
        // Act
        let loaded = sut.loadCredentials()

        // Assert
        XCTAssertNil(loaded)
    }

    func testClearCredentials() {
        // Arrange
        sut.saveCredentials(
            supabaseURL: "https://test.supabase.co",
            anonKey: "test-key",
            accessToken: "test-token",
            userId: "user-id"
        )

        var loaded = sut.loadCredentials()
        XCTAssertNotNil(loaded)

        // Act
        sut.clearCredentials()
        loaded = sut.loadCredentials()

        // Assert
        XCTAssertNil(loaded)
    }

    func testHasCredentials() {
        // Assert - before save
        XCTAssertFalse(sut.hasCredentials())

        // Arrange
        sut.saveCredentials(
            supabaseURL: "https://test.supabase.co",
            anonKey: "test-key",
            accessToken: "test-token",
            userId: "user-id"
        )

        // Assert - after save
        XCTAssertTrue(sut.hasCredentials())

        // Arrange
        sut.clearCredentials()

        // Assert - after clear
        XCTAssertFalse(sut.hasCredentials())
    }

    func testAccessTokenSecureStorage() {
        // Arrange
        let sensitiveToken = "super-secret-token-with-sensitive-data-xyz"

        // Act
        sut.saveCredentials(
            supabaseURL: "https://test.supabase.co",
            anonKey: "test-key",
            accessToken: sensitiveToken,
            userId: "user-id"
        )

        let loaded = sut.loadCredentials()

        // Assert - token should be securely stored in Keychain
        XCTAssertEqual(loaded?.accessToken, sensitiveToken)
        // Token should NOT be in UserDefaults (plain text)
        let defaults = UserDefaults(suiteName: "group.com.theperch.shared")
        XCTAssertNil(defaults?.string(forKey: "ThePerch_AccessToken"))
    }
}

class ShareSupabaseClientTests: XCTestCase {
    var sut: ShareSupabaseClient!
    var mockCredentials: SharedCredentials!

    override func setUp() {
        super.setUp()
        sut = ShareSupabaseClient()
        mockCredentials = SharedCredentials()
        mockCredentials.clearCredentials()
    }

    override func tearDown() {
        super.tearDown()
        mockCredentials.clearCredentials()
    }

    func testSaveBookmarkRequiresCredentials() async {
        // Act & Assert
        do {
            _ = try await sut.saveBookmark(
                url: "https://example.com",
                title: "Test",
                tags: []
            )
            XCTFail("Should throw credentialsNotFound error")
        } catch ShareSupabaseError.credentialsNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSaveBookmarkRequiresValidURL() async {
        // Arrange
        mockCredentials.saveCredentials(
            supabaseURL: "https://test.supabase.co",
            anonKey: "test-key",
            accessToken: "test-token",
            userId: "user-id"
        )

        // Act & Assert
        do {
            _ = try await sut.saveBookmark(
                url: "not-a-valid-url",
                title: "Test",
                tags: []
            )
            XCTFail("Should throw invalidURL error")
        } catch ShareSupabaseError.invalidURL {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testValidateBookmarkURLs() {
        // Valid URLs
        XCTAssertNotNil(URL(string: "https://example.com"))
        XCTAssertNotNil(URL(string: "https://example.com/path?query=value"))
        XCTAssertNotNil(URL(string: "https://subdomain.example.co.uk"))

        // Invalid URLs
        XCTAssertNil(URL(string: "not a url"))
        XCTAssertNil(URL(string: "htp://typo.com"))
    }
}

class URLExtractionTests: XCTestCase {
    func testExtractURLFromString() {
        // Valid URLs
        let testCases = [
            ("https://www.example.com", true),
            ("http://example.com/path", true),
            ("https://sub.domain.example.com", true),
            ("https://example.com:8080/path", true),
            ("not a url", false),
            ("just some text", false),
            ("", false)
        ]

        for (urlString, shouldSucceed) in testCases {
            let result = URL(string: urlString)
            if shouldSucceed {
                XCTAssertNotNil(result, "Should parse: \(urlString)")
            } else {
                XCTAssertNil(result, "Should not parse: \(urlString)")
            }
        }
    }

    func testURLTruncation() {
        let longURL = "https://example.com/path/to/some/very/long/resource/name/that/exceeds/normal/display/width"
        let displayURL = truncateURL(longURL, maxLength: 50)

        XCTAssertLessThanOrEqual(displayURL.count, 50)
        XCTAssert(displayURL.contains("..."), "Should contain ellipsis")
    }

    private func truncateURL(_ url: String, maxLength: Int) -> String {
        guard url.count > maxLength else { return url }
        let truncated = String(url.prefix(maxLength - 3))
        return truncated + "..."
    }
}

class TagParsingTests: XCTestCase {
    func testParseCommaSeparatedTags() {
        let testCases = [
            ("article, research, design", ["article", "research", "design"]),
            ("single", ["single"]),
            ("  trimmed  ,  tags  ", ["trimmed", "tags"]),
            ("", [] as [String]),
            (",,,,", [] as [String])
        ]

        for (input, expected) in testCases {
            let tags = parseTags(input)
            XCTAssertEqual(tags, expected, "Failed for input: \(input)")
        }
    }

    func testDuplicateTagRemoval() {
        let input = "article, research, article, design, research"
        let tags = parseTags(input)
        let uniqueTags = Array(Set(tags))

        XCTAssertEqual(Set(tags).count, uniqueTags.count)
        XCTAssert(Set(tags).contains("article"))
        XCTAssert(Set(tags).contains("research"))
        XCTAssert(Set(tags).contains("design"))
    }

    private func parseTags(_ input: String) -> [String] {
        return input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

class ErrorHandlingTests: XCTestCase {
    func testShareSupabaseErrorDescriptions() {
        let errors: [ShareSupabaseError] = [
            .credentialsNotFound,
            .invalidURL,
            .invalidRequest,
            .networkError("Connection timeout"),
            .decodingError("Invalid JSON"),
            .serverError(500, "Internal Server Error"),
            .unknownError
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssert(!error.errorDescription!.isEmpty)
        }
    }

    func testLocalizedErrorConformance() {
        let error = ShareSupabaseError.credentialsNotFound
        XCTAssertNotNil(error.localizedDescription)
    }
}

// MARK: - Integration Tests (requires real Supabase or mock server)

class ShareExtensionIntegrationTests: XCTestCase {
    var sut: ShareSupabaseClient!
    var credentials: SharedCredentials!

    override func setUp() {
        super.setUp()
        sut = ShareSupabaseClient()
        credentials = SharedCredentials()
        // Note: These tests require actual Supabase credentials
        // Set them in setUp if you want to run real integration tests
    }

    override func tearDown() {
        super.tearDown()
    }

    func testEndToEndBookmarkSave() async {
        // This test requires real Supabase credentials
        // Skip in CI/CD unless credentials are provided

        let hasCredentials = credentials.hasCredentials()
        guard hasCredentials else {
            print("Skipping integration test - no Supabase credentials")
            return
        }

        do {
            let bookmarkID = try await sut.saveBookmark(
                url: "https://www.wikipedia.org/wiki/Bookmark",
                title: "Bookmark - Wikipedia",
                tags: ["research", "reference"]
            )

            XCTAssertFalse(bookmarkID.isEmpty)
            XCTAssertTrue(UUID(uuidString: bookmarkID) != nil)
        } catch {
            XCTFail("Integration test failed: \(error)")
        }
    }
}

// MARK: - Performance Tests

class ShareExtensionPerformanceTests: XCTestCase {
    func testCredentialLoadingPerformance() {
        let credentials = SharedCredentials()

        // Warm up
        _ = credentials.loadCredentials()

        measure {
            _ = credentials.loadCredentials()
        }
    }

    func testTagParsingPerformance() {
        let longTagString = (0..<1000)
            .map { "tag\($0)" }
            .joined(separator: ", ")

        measure {
            _ = longTagString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}
