import Foundation

struct ReconnectPolicy {
    let baseDelaySeconds: Int
    let maxDelaySeconds: Int
    let jitterRange: ClosedRange<Int>
    let maxAttempts: Int

    init(
        baseDelaySeconds: Int = 2,
        maxDelaySeconds: Int = 60,
        jitterRange: ClosedRange<Int> = 0...2,
        maxAttempts: Int = 8
    ) {
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.jitterRange = jitterRange
        self.maxAttempts = maxAttempts
    }

    func delaySeconds(forAttempt attempt: Int) -> Int {
        let safeAttempt = max(1, attempt)
        let factor = Int(pow(2.0, Double(max(0, safeAttempt - 1))))
        let exponentialDelay = baseDelaySeconds * factor
        let jitter = Int.random(in: jitterRange)
        return min(maxDelaySeconds, exponentialDelay + jitter)
    }

    func shouldRetry(parsedFailure: SshParsedFailure?) -> Bool {
        guard let parsedFailure else { return true }
        switch parsedFailure {
        case .permissionDenied, .authenticationFailed, .hostKeyVerificationFailed:
            return false
        case .connectionRefused, .networkUnreachable, .nameResolutionFailed, .portBindFailed, .generic:
            return true
        }
    }
}
