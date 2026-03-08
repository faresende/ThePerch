import Foundation
import os.log

/// Manages reconnection logic for Supabase realtime subscriptions
/// with exponential backoff and max retry limits.
@Observable
@MainActor
final class RealtimeReconnectManager {
    static let shared = RealtimeReconnectManager()

    // MARK: - Properties

    /// Whether the realtime connection is currently active.
    private(set) var isConnected: Bool = true

    /// Whether we've exhausted all retry attempts.
    private(set) var hasGivenUp: Bool = false

    /// Current retry attempt count.
    private(set) var retryCount: Int = 0

    // MARK: - Configuration

    private let maxRetries = 5
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0

    private var reconnectTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.theperch", category: "Realtime")

    private init() {}

    // MARK: - Connection State

    /// Call when the realtime connection is established or re-established.
    func didConnect() {
        isConnected = true
        hasGivenUp = false
        retryCount = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        logger.info("Realtime connected")
    }

    /// Call when the realtime connection drops. Starts exponential backoff reconnection.
    /// - Parameter reconnect: The async closure to attempt reconnection.
    func didDisconnect(reconnect: @escaping @MainActor () async -> Bool) {
        isConnected = false

        guard !hasGivenUp else { return }
        guard reconnectTask == nil else { return }

        reconnectTask = Task { @MainActor in
            while retryCount < maxRetries && !Task.isCancelled {
                retryCount += 1
                let delay = min(baseDelay * pow(2.0, Double(retryCount - 1)), maxDelay)
                logger.warning("Realtime disconnected. Retry \(self.retryCount)/\(self.maxRetries) in \(delay)s")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let success = await reconnect()
                if success {
                    didConnect()
                    return
                }
            }

            // Exhausted all retries
            if !Task.isCancelled {
                hasGivenUp = true
                logger.error("Realtime reconnection failed after \(self.maxRetries) attempts")
            }
        }
    }

    /// Manual reconnect triggered by user after giving up.
    func manualReconnect(reconnect: @escaping @MainActor () async -> Bool) {
        hasGivenUp = false
        retryCount = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        didDisconnect(reconnect: reconnect)
    }
}
