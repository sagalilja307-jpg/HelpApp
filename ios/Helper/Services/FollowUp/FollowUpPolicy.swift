//
//  FollowUpPolicy.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

struct FollowUpPolicy {

    /// Hur länge vi väntar innan vi föreslår uppföljning (i dagar)
    let daysUntilFollowUp: Int = 3

    func shouldSuggestFollowUp(
        waitingSince: Date,
        lastActivity: Date
    ) -> Bool {

        let daysWaiting = DateService.shared.dateComponents(
            [.day],
            from: waitingSince,
            to: DateService.shared.now()
        ).day ?? 0

        return daysWaiting >= daysUntilFollowUp
            && lastActivity < waitingSince
    }
}
