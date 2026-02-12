import Foundation

public final class PreferenceService {
    
    // MARK: - Public API
    
    /// Sätt eller uppdatera en preferens (endast för användare).
    public static func set(
        actor: Actor,
        key: PreferenceKey,
        value: PreferenceValue,
        scope: PreferenceScope,
        source: PreferenceSource
    ) throws {
        guard actor == .user else {
            throw MemoryError.permissionDenied(
                actor: actor,
                store: "preferences(user_only)"
            )
        }
        
        let id = makeId(key: key, scope: scope)
        let entry = PreferenceEntry(
            key: key,
            value: value,
            scope: scope,
            source: source
        )
        
        PreferenceStore.set(entry: entry, forKey: id)
    }
    
    /// Hämta en preferens för ett visst sammanhang.
    public static func get(
        key: PreferenceKey,
        for mode: TemporaryContextMode
    ) -> PreferenceEntry? {
        let scopedScope = scope(for: mode)
        
        // 1️⃣ Försök hämta scoped
        let scopedId = makeId(key: key, scope: scopedScope)
        if let scoped = PreferenceStore.get(forKey: scopedId) {
            return scoped
        }
        
        // 2️⃣ Fallback till global
        let globalId = makeId(key: key, scope: .global)
        return PreferenceStore.get(forKey: globalId)
    }
    
    // MARK: - Interna helpers
    
    private static func scope(for mode: TemporaryContextMode) -> PreferenceScope {
        switch mode {
        case .focused: return .focused
        case .supportive: return .supportive
        default: return .global
        }
    }
    
    private static func makeId(
        key: PreferenceKey,
        scope: PreferenceScope
    ) -> String {
        "\(key.rawValue)_\(scope.rawValue)"
    }
    
    /// Ta bort en specifik preferens.
    public static func remove(
        key: PreferenceKey,
        scope: PreferenceScope
    ) {
        let id = makeId(key: key, scope: scope)
        PreferenceStore.remove(forKey: id)
    }
}
