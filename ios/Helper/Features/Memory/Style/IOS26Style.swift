import SwiftUI

/// Design tokens + view helpers for the app's "iOS 26" look.
/// Keep this file dependency-free so any module can use it.
enum IOS26Style {

    // MARK: - Metrics

    enum Metrics {
        static let cornerRadius: CGFloat = 22
        static let innerCornerRadius: CGFloat = 16
        static let strokeWidth: CGFloat = 0.5
        static let shadowRadius: CGFloat = 16
        static let shadowY: CGFloat = 10
    }

    enum Spacing {
        static let xxs: CGFloat = 6
        static let xs: CGFloat = 10
        static let sm: CGFloat = 14
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: - Background

    static var pageBackground: some View {
        // Subtle depth, but still respects light/dark + reduces banding.
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Small UI building blocks

    static func badge(_ text: String, systemImage: String? = nil, prominence: BadgeProminence = .secondary) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(prominence.foreground)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(prominence.background)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.separator.opacity(0.55), lineWidth: Metrics.strokeWidth)
        )
        .accessibilityElement(children: .combine)
    }

    enum BadgeProminence {
        case primary
        case secondary
        case sensitive

        var background: some ShapeStyle {
            switch self {
            case .primary: return AnyShapeStyle(.thinMaterial)
            case .secondary: return AnyShapeStyle(.ultraThinMaterial)
            case .sensitive: return AnyShapeStyle(Color.purple.opacity(0.10))
            }
        }

        var foreground: some ShapeStyle {
            switch self {
            case .primary: return AnyShapeStyle(.primary)
            case .secondary: return AnyShapeStyle(.secondary)
            case .sensitive: return AnyShapeStyle(Color.purple)
            }
        }
    }
}

// MARK: - View modifiers

extension View {

    /// Default page chrome (background + better scroll defaults).
    func ios26Page() -> some View {
        self
            .scrollIndicators(.hidden)
            .background(IOS26Style.pageBackground)
    }

    /// Material card with subtle stroke + shadow.
    func ios26Card(sensitive: Bool = false) -> some View {
        self
            .padding(IOS26Style.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: IOS26Style.Metrics.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: IOS26Style.Metrics.cornerRadius, style: .continuous)
                            .strokeBorder(.separator.opacity(0.60), lineWidth: IOS26Style.Metrics.strokeWidth)
                    )
                    .overlay {
                        if sensitive {
                            RoundedRectangle(cornerRadius: IOS26Style.Metrics.cornerRadius, style: .continuous)
                                .fill(Color.purple.opacity(0.06))
                        }
                    }
            )
            .shadow(color: .black.opacity(0.08), radius: IOS26Style.Metrics.shadowRadius, x: 0, y: IOS26Style.Metrics.shadowY)
            .contentShape(RoundedRectangle(cornerRadius: IOS26Style.Metrics.cornerRadius, style: .continuous))
    }

    /// A smaller, tappable surface used inside cards/lists.
    func ios26Pill() -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: IOS26Style.Metrics.innerCornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IOS26Style.Metrics.innerCornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.55), lineWidth: IOS26Style.Metrics.strokeWidth)
            )
    }

    /// Slight lift on press for card-like buttons.
    func ios26Pressable() -> some View {
        self.buttonStyle(IOS26PressableButtonStyle())
    }
}

private struct IOS26PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
