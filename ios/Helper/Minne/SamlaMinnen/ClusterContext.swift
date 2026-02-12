//
//  ClusterContext.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//

import Foundation

public struct ClusterContext {
    public var clusterId: String
    public var title: String?
    public var state: ClusterStatus
    public var lastUpdated: Date
    public var recentTexts: [String]
    public var itemCount: Int

    // 🆕 Follow-up metadata (viktigt!)
    public var followUpSuggested: Bool

    /// Ett kluster är aktivt om det inte är arkiverat
    public var isActive: Bool {
        state != .archived
    }

    /// Klustret väntar på svar från någon annan
    public var isWaitingForResponse: Bool {
        state == .waitingForResponse
    }
}
