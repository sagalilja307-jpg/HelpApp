//
//  ClusterMatchingRules.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

struct ClusterMatchingRules {

    /// similarity >= strongMatch → utöka kluster
    let strongMatchThreshold: Double = 0.82

    /// similarity >= weakMatch → osäker zon
    let weakMatchThreshold: Double = 0.70

    /// max antal dagar mellan events för tids-boost
    let timeWindowDays: Int = 7

    /// hur mycket tid får boosta similarity
    let timeBoost: Double = 0.05

    func boostedSimilarity(
        baseSimilarity: Double,
        timeDifferenceInDays: Int
    ) -> Double {
        guard timeDifferenceInDays <= timeWindowDays else {
            return baseSimilarity
        }
        return min(baseSimilarity + timeBoost, 1.0)
    }
}
