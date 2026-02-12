import Foundation

public struct PreferenceDecisionResolver {

    public static func apply(
        to basePolicy: DecisionPolicy,
        mode: TemporaryContextMode
    ) -> DecisionPolicy {

        var policy = basePolicy

        // ===========================================
        // MARK: - Prefer short messages
        // ===========================================

        if PreferenceService.get(key: .preferShortMessages, for: mode)?.value.boolValue == true {
            policy = policy.with(maxVisibleItems: 1)
        }

        // ===========================================
        // MARK: - Dislike checklists
        // ===========================================

        if PreferenceService.get(key: .dislikeChecklists, for: mode)?.value.boolValue == true {
            policy = policy.with(allowTaskBreakdown: false)
        }

        // ===========================================
        // MARK: - Tone preference (mode-aware)
        // ===========================================

        let toneKey: PreferenceKey = {
            switch mode {
            case .focused: return .toneWhenFocused
            case .supportive: return .toneWhenSupportive
            default: return .toneInGeneral
            }
        }()

        if let raw = PreferenceService.get(key: toneKey, for: mode)?.value.stringValue,
           let tone = InteractionTone(rawValue: raw) {
            policy = policy.with(tone: tone)
        }

        // ===========================================
        // ✅ Lägg till fler preferenser här vid behov
        // ===========================================

        return policy
    }
}
