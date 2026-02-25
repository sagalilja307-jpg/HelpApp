import SwiftUI

struct OnboardingView: View {
    @Binding var onboardingComplete: Bool
    @AppStorage("helper.onboarding.done") private var onboardingDone: Bool = false
    @State private var index: Int = 0

    private let slides = OnboardingContent.slides

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { i, slide in
                        SlideCard(slide: slide)
                            .padding(.horizontal, 18)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .padding(.top, 12)

                footer
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .padding(.top, 10)
                    .background(
                        Color.black
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundStyle(Color.white.opacity(0.08)),
                                alignment: .top
                            )
                    )
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Dots(total: slides.count, index: index) { i in
                withAnimation(.easeInOut(duration: 0.2)) { index = i }
            }

            HStack(spacing: 12) {
                Button {
                    finish()
                } label: {
                    Text("Hoppa över")
                        .foregroundStyle(Color.white.opacity(0.65))
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Button {
                    next()
                } label: {
                    Text(slides[index].primaryCTA)
                        .foregroundStyle(Color.black)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("Du kan ändra detta senare i Inställningar.")
                .foregroundStyle(Color.white.opacity(0.38))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func next() {
        let last = slides.count - 1
        if index < last {
            withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        onboardingComplete = true
        onboardingDone = true
    }
}

private struct SlideCard: View {
    let slide: OnboardingSlide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Helper")
                .foregroundStyle(Color.white.opacity(0.58))
                .font(.system(size: 13, weight: .regular))
                .tracking(0.6)

            Text(slide.title)
                .foregroundStyle(Color.white.opacity(0.92))
                .font(.system(size: 26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            content
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch slide.kind {
        case .text:
            Text(slide.body)
                .foregroundStyle(Color.white.opacity(0.78))
                .font(.system(size: 16))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .pipeline(let steps, let examples):
            VStack(alignment: .leading, spacing: 14) {
                Text(slide.body)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .center, spacing: 10) {
                            Circle()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 8, height: 8)

                            Text(s)
                                .foregroundStyle(Color.white.opacity(0.90))
                                .font(.system(size: 15, weight: .medium))

                            Spacer(minLength: 0)
                        }

                        if i < steps.count - 1 {
                            Text("↓")
                                .foregroundStyle(Color.white.opacity(0.55))
                                .font(.system(size: 16, weight: .regular))
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Exempel:")
                        .foregroundStyle(Color.white.opacity(0.90))
                        .font(.system(size: 14, weight: .semibold))

                    ForEach(examples, id: \.self) { e in
                        Text(e)
                            .foregroundStyle(Color.white.opacity(0.78))
                            .font(.system(size: 15))
                    }
                }

                Text("Helper sparar betydelse över tid – inte bara svar.")
                    .foregroundStyle(Color.white.opacity(0.58))
                    .font(.system(size: 13))
                    .padding(.top, 2)
            }
        }
    }
}

private struct Dots: View {
    let total: Int
    let index: Int
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Button {
                    onTap(i)
                } label: {
                    Circle()
                        .fill(i == index ? Color.white.opacity(0.55) : Color.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gå till steg \(i + 1)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}
