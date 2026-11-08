import SwiftUI

struct FeedbackToast: View {
    let message: String?
    var body: some View {
        if let message {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(message).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
