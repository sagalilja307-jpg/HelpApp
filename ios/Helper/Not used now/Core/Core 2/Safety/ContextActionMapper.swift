import Foundation

public struct ContextActionMapper {

    public static func mode(for action: ContextAction) -> TemporaryContextMode? {
        switch action {

        case .setNormal:
            return .normal
        case .setLowEnergy:
            return .lowEnergy
        case .setOverwhelmed:
            return .overwhelmed
        case .setFocused:
            return .focused
        case .setSupportive:
            return .supportive

        case .acknowledgeSafetyAndContinue:
            return .normal
        }
    }
}
