//
//  FollowUpEvaluator.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

/// Ansvarar för att avgöra om en uppföljning bör föreslås för ett kluster.
final class FollowUpEvaluator {

    // ======================================
    // MARK: - Konfiguration
    // ======================================

    /// Hur länge vi ska vänta (i sekunder) innan vi föreslår en uppföljning.
    /// Här: 2 dygn = 2 * 24 * 60 * 60 sekunder
    private let maxWaitTime: TimeInterval = 2 * 24 * 60 * 60

    // ======================================
    // MARK: - Utvärdering
    // ======================================

    /// Returnerar `true` om systemet bör föreslå en uppföljning för det givna klustret.
    ///
    /// Klustret uppdateras internt genom att `followUpSuggested` sätts till `true` om förslaget ges.
    ///
    /// - Parameter cluster: Klustret att utvärdera (muteras vid behov)
    /// - Returns: `true` om en uppföljning bör föreslås, annars `false`.
    func evaluate(cluster: inout Cluster) -> Bool {

        // ⛔️ Om klustret inte är i vänteläge → gör inget
        guard cluster.status == .waitingForResponse else {
            return false
        }

        // ⛔️ Om vi inte vet hur länge det har väntat → gör inget
        guard let waitingSince = cluster.waitingSince else {
            return false
        }

        // ⛔️ Om uppföljning redan föreslagits tidigare → gör inget
        guard cluster.followUpSuggested == false else {
            return false
        }

        // ✅ Om tillräckligt lång tid har passerat → föreslå uppföljning
        let now = DateService.shared.now()
        let elapsedTime = now.timeIntervalSince(waitingSince)

        if elapsedTime >= maxWaitTime {
            cluster.followUpSuggested = true
            return true
        }

        // ⏳ Annars: vänta längre
        return false
    }
}
