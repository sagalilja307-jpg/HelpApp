//
//  PreferenceStore.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

enum PreferenceStore {
    private static let defaults = UserDefaults.standard

    static func set(entry: PreferenceEntry, forKey key: String) {
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: key)
        }
    }

    static func get(forKey key: String) -> PreferenceEntry? {
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(PreferenceEntry.self, from: data)
        else {
            return nil
        }

        return entry
    }
    
    static func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
