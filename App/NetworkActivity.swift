import Foundation
import SwiftUI
import SEQTAKit

@MainActor
final class NetworkActivity: ObservableObject {
    static let shared = NetworkActivity()
    @Published private(set) var visible = false
    private var count = 0
    private var delay: Task<Void, Never>?
    func begin() {
        count += 1
        guard count == 1 else { return }
        delay = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, count > 0 else { return }
            visible = true
        }
    }
    func finish() {
        count = max(0, count - 1)
        if count == 0 { delay?.cancel(); delay = nil; visible = false }
    }
}

struct ActivityTransport: SEQTATransport {
    private let base = URLSessionTransport()
    /// Told when SEQTA answers "signed out", so the app can offer to sign in again in one place.
    var expiry: SessionExpiryRelay? = nil
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await NetworkActivity.shared.begin()
        do {
            let response = try await base.send(request)
            if let expiry, SessionExpiry.isExpired(statusCode: response.1.statusCode, body: response.0) { await expiry.fire() }
            await NetworkActivity.shared.finish(); return response
        } catch {
            await NetworkActivity.shared.finish(); throw error
        }
    }
}

struct DelayedNetworkIndicator: ViewModifier {
    @ObservedObject private var network = NetworkActivity.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if network.visible {
                HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Loading…").font(.caption) }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8).allowsHitTesting(false)
                    .accessibilityIdentifier("network-activity")
            }
        }
    }
}

/// Connects a saved account's transport back to the app model. The account ID is filled in once known (a client made
/// during sign-in exists before its account is saved).
@MainActor final class SessionExpiryRelay {
    weak var model: AppModel?
    var accountID: UUID?
    init(model: AppModel?, accountID: UUID? = nil) { self.model = model; self.accountID = accountID }
    func fire() { if let accountID { model?.sessionExpired(for: accountID) } }
}
