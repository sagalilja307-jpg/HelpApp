import SwiftUI

enum IOS26Style {
    static let cornerRadius: CGFloat = 20

    static var pageBackground: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    func ios26Card(sensitive: Bool = false) -> some View {
        self
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: IOS26Style.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: IOS26Style.cornerRadius, style: .continuous)
                            .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                    )
                    .overlay {
                        if sensitive {
                            RoundedRectangle(cornerRadius: IOS26Style.cornerRadius, style: .continuous)
                                .fill(Color.purple.opacity(0.06))
                        }
                    }
            )
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
    }
}
