import SwiftUI

struct SourceCardView<Footer: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let onToggle: (Bool) -> Void
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
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
