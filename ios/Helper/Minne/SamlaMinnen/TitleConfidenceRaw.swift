//
//  TitleConfidenceRaw.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation
import SwiftData

public enum TitleConfidence: String, Codable {
    case low
    case medium
    case high
}

@Model
public final class TitleConfidenceRaw {
    @Attribute(.unique)
    public var value: String

    public init(value: String) {
        self.value = value
    }

    public convenience init(value: TitleConfidence) {
        self.init(value: value.rawValue)
    }

    public var wrapped: TitleConfidence {
        TitleConfidence(rawValue: value) ?? .low
    }
}
