import SwiftUI

struct Mail: Identifiable, Codable {
    let id: UUID
    let subject: String
    let sender: String
    let date: Date
    let isRead: Bool
}
