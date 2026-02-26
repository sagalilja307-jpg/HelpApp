import SwiftUI

struct SourceCardView<Footer: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let isToggleEnabled: Bool
    let statusBadgeText: String?
    let onToggle: (Bool) -> Void
    @ViewBuilder let footer: () -> Footer

    init(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isToggleEnabled: Bool = true,
        statusBadgeText: String? = nil,
        onToggle: @escaping (Bool) -> Void,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.isToggleEnabled = isToggleEnabled
        self.statusBadgeText = statusBadgeText
        self.onToggle = onToggle
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if let statusBadgeText {
                            Text(statusBadgeText)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Toggle("Aktivera", isOn: Binding(
                get: { isOn },
                set: { value in
                    isOn = value
                    onToggle(value)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!isToggleEnabled)
            .opacity(isToggleEnabled ? 1 : 0.55)

            footer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

struct SourceSecondaryToggleView: View {
    let title: String
    @Binding var isOn: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { isOn },
            set: { value in
                isOn = value
                onToggle(value)
            }
        ))
        .font(.subheadline)
    }
}
