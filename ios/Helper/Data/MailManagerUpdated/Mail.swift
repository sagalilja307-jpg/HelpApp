import SwiftUI

struct Mail: Identifiable, Decodable {
    let id: UUID
    let subject: String
    let sender: String
    let date: Date
    let isRead: Bool

    private struct SenderPayload: Codable {
        let address: String
        let name: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case subject
        case sender
        case date
        case receivedAt = "received_at"
        case isRead = "is_read"
        case isReplied = "is_replied"
    }

    init(id: UUID, subject: String, sender: String, date: Date, isRead: Bool) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.date = date
        self.isRead = isRead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let idString = try? container.decode(String.self, forKey: .id),
           let parsedID = UUID(uuidString: idString) {
            id = parsedID
        } else if let parsedID = try? container.decode(UUID.self, forKey: .id) {
            id = parsedID
        } else {
            id = UUID()
        }

        subject = (try? container.decode(String.self, forKey: .subject)) ?? "(Utan ämne)"

        if let senderString = try? container.decode(String.self, forKey: .sender) {
            sender = senderString
        } else if let senderPayload = try? container.decode(SenderPayload.self, forKey: .sender) {
            sender = senderPayload.name?.isEmpty == false ? senderPayload.name! : senderPayload.address
        } else {
            sender = "Okänd avsändare"
        }

        if let decodedDate = try? container.decode(Date.self, forKey: .date) {
            date = decodedDate
        } else if let receivedAt = try? container.decode(Date.self, forKey: .receivedAt) {
            date = receivedAt
        } else {
            date = Date()
        }

        if let readValue = try? container.decode(Bool.self, forKey: .isRead) {
            isRead = readValue
        } else if let repliedValue = try? container.decode(Bool.self, forKey: .isReplied) {
            isRead = repliedValue
        } else {
            isRead = false
        }
    }
}
