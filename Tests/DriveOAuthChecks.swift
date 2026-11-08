import Foundation
import Network

/// Fake listener events cover OAuth lifetime without opening a socket or contacting Google.
@MainActor
enum DriveOAuthChecks {
    static func run() async throws {
        try callbackValidation()
        try await readyAndCallback()
        try await failureAndCancellation()
        try await startupTimeout()
        print("OAuth callback checks passed: path/state validation, no forged completion, success/error response ordering, cached callback, startup failure/timeout, cancellation.")
    }

    static func callbackValidation() throws {
        let redirect = URL(string: "http://127.0.0.1:43123/oauth2callback")!
        let good = "GET /oauth2callback?code=fixture-code&state=fixture-state HTTP/1.1"
        try check(DriveOAuthCallbackValidator.callbackURL(requestLine: good, redirect: redirect, expectedState: "fixture-state")?.host == "127.0.0.1", "Valid callback must resolve only to the loopback host")
        for bad in [
            "GET /favicon.ico HTTP/1.1",
            "GET /oauth2callback?code=fixture-code HTTP/1.1",
            "GET /oauth2callback?code=fixture-code&state=wrong-state HTTP/1.1",
            "GET /oauth2callback?code=fixture-code&state=fixture-state&state=wrong-state HTTP/1.1",
            "GET /oauth2callback?code=one&code=two&state=fixture-state HTTP/1.1",
            "GET /oauth2callback?code=one&error=access_denied&state=fixture-state HTTP/1.1",
            "GET /oauth2callback?state=fixture-state HTTP/1.1",
            "GET http://evil.example/oauth2callback?code=one&state=fixture-state HTTP/1.1",
            "GET //evil.example/oauth2callback?code=one&state=fixture-state HTTP/1.1",
            "POST /oauth2callback?code=one&state=fixture-state HTTP/1.1"
        ] {
            try check(DriveOAuthCallbackValidator.callbackURL(requestLine: bad, redirect: redirect, expectedState: "fixture-state") == nil, "Unrelated, forged, or ambiguous callback must be rejected")
        }
        let denied = "GET /oauth2callback?error=access_denied&state=fixture-state HTTP/1.1"
        try check(DriveOAuthCallbackValidator.callbackURL(requestLine: denied, redirect: redirect, expectedState: "fixture-state") != nil, "Google consent denial is a valid verified callback")
    }

    static func readyAndCallback() async throws {
        for outcome in ["code=fixture-code", "error=access_denied"] {
            let listener = DriveOAuthTestListener(eventOnStart: .ready(43123))
            let flow = DriveOAuthLoopback(expectedState: "fixture-state", listenerFactory: { listener })
            let redirect = try await flow.start()
            try check(redirect.absoluteString == "http://127.0.0.1:43123/oauth2callback", "Listener must return its assigned loopback port")
            try check(!flow.handleCallbackRequestLine("GET /oauth2callback?code=forged&state=wrong HTTP/1.1"), "Forged state must not consume the listener")
            try check(!listener.cancelled, "An unrelated request must leave genuine sign-in available")
            var responseWasPrepared = false
            let accepted = flow.handleCallbackRequestLine("GET /oauth2callback?\(outcome)&state=fixture-state HTTP/1.1") { _ in
                responseWasPrepared = true
                // finish() must occur after the response is queued, otherwise the browser loses the reply.
                precondition(!listener.cancelled)
            }
            let callback = try await flow.waitForCallback()
            try check(accepted && responseWasPrepared && listener.cancelled, "A verified callback must queue response then complete and close listener")
            try check(callback.absoluteString.contains(outcome), "Callback must retain Google's code/error")
            let cached = try await flow.waitForCallback()
            try check(cached == callback, "Callback arriving before wait must remain available")
            try check(listener.stateUpdateHandler == nil && listener.newConnectionHandler == nil, "Completion must release callback handlers")
            try check(!flow.handleCallbackRequestLine("GET /oauth2callback?code=two&state=fixture-state HTTP/1.1"), "A second response must never complete the continuation twice")
        }
    }

    static func failureAndCancellation() async throws {
        let failing = DriveOAuthTestListener(eventOnStart: .failed(CheckFailure("fixture-listener-failure")))
        let failedFlow = DriveOAuthLoopback(expectedState: "fixture-state", listenerFactory: { failing })
        try await expectFailure("Listener failure must resume startup") { _ = try await failedFlow.start() }
        try check(failing.cancelled, "Listener failure must clean up its transport")

        let waiting = DriveOAuthTestListener(eventOnStart: nil)
        let waitingFlow = DriveOAuthLoopback(expectedState: "fixture-state", listenerFactory: { waiting })
        let startup = Task { try await waitingFlow.start() }
        for _ in 0..<20 where !waiting.started { await Task.yield() }
        startup.cancel()
        try await expectFailure("Task cancellation must resume an unready startup") { _ = try await startup.value }
        try check(waiting.cancelled, "Startup cancellation must stop the listener")

        let ready = DriveOAuthTestListener(eventOnStart: .ready(43124))
        let browserFlow = DriveOAuthLoopback(expectedState: "fixture-state", listenerFactory: { ready })
        _ = try await browserFlow.start()
        let callback = Task { try await browserFlow.waitForCallback() }
        await Task.yield()
        browserFlow.cancel()
        try await expectFailure("Manual cancellation must resume a waiting browser callback") { _ = try await callback.value }
        try check(ready.cancelled, "Browser cancellation must close the listener")

        let notStarted = DriveOAuthLoopback(expectedState: "fixture-state", listenerFactory: { ready })
        try await expectFailure("Waiting before startup must fail instead of hanging") { _ = try await notStarted.waitForCallback() }
    }

    static func startupTimeout() async throws {
        let listener = DriveOAuthTestListener(eventOnStart: nil)
        let flow = DriveOAuthLoopback(expectedState: "fixture-state", timeoutNanoseconds: 5_000_000, listenerFactory: { listener })
        try await expectFailure("Timeout must cover listener startup, not only browser consent") { _ = try await flow.start() }
        try check(listener.cancelled, "Timeout must close the stalled listener")
    }

    static func expectFailure(_ message: String, operation: () async throws -> Void) async throws {
        do { try await operation() } catch { return }
        throw CheckFailure(message)
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }
    struct CheckFailure: LocalizedError { var message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
}

final class DriveOAuthTestListener: DriveLoopbackListening {
    var stateUpdateHandler: ((DriveLoopbackListenerState) -> Void)?
    var newConnectionHandler: ((NWConnection) -> Void)?
    var started = false
    var cancelled = false
    var eventOnStart: DriveLoopbackListenerState?
    init(eventOnStart: DriveLoopbackListenerState?) { self.eventOnStart = eventOnStart }
    func start(queue: DispatchQueue) { started = true; if let eventOnStart { stateUpdateHandler?(eventOnStart) } }
    func cancel() { cancelled = true }
}
