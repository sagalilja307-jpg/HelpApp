//
//  LLMAvailability.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation
import FoundationModels
import OSLog

public enum LLMAvailability: Equatable {
    case available
    case unavailable(reason: String)

    public static func check() -> LLMAvailability {
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
            return .available
        } else {
            return .unavailable(
                reason: "Apple Intelligence / Foundation Models require newer OS versions on this device."
            )
        }
    }
}

