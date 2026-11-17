import SwiftUI

/// Design tokens. Kept in one file so the whole app stays visually consistent.
enum Theme {
    static let accent = Color(red: 0.36, green: 0.31, blue: 0.93)
    static let accentSoft = Color(red: 0.62, green: 0.55, blue: 1.0)
    static let tutorBubble = Color(uiColor: .secondarySystemBackground)
    static let cardCorner: CGFloat = 22

    static let heroGradient = LinearGradient(
        colors: [accent, Color(red: 0.99, green: 0.42, blue: 0.52)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let softGradient = LinearGradient(
        colors: [accent.opacity(0.16), accentSoft.opacity(0.08)],
        startPoint: .top,
        endPoint: .bottom
    )

    static func languageColor(_ language: SupportedLanguage) -> Color {
        switch language {
        case .english:
            return Color(red: 0.20, green: 0.51, blue: 0.96)
        case .japanese:
            return Color(red: 0.90, green: 0.28, blue: 0.39)
        }
    }
}

/// Rounded card surface used across the app.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(enabled ? Theme.accent : Color.gray.opacity(0.4))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
    }
}

/// Small pill used for badges such as "演示模式".
struct BadgePill: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}