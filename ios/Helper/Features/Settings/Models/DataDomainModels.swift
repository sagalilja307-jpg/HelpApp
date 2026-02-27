import Foundation

enum DataPermissionState: String, Codable, Hashable {
    case unknown
    case granted
    case denied

    var label: String {
        switch self {
        case .unknown:
            return "Ej frågad"
        case .granted:
            return "Tillåten"
        case .denied:
            return "Nekad"
        }
    }
}

enum DataDomainID: String, CaseIterable, Identifiable {
    case planning
    case info
    case activity
    case wellbeing

    var id: String { rawValue }
}

enum DataSourceID: String, CaseIterable, Identifiable {
    // Planering
    case calendar
    case reminders
    case notifications

    // Information
    case contacts
    case mail
    case files
    case photos
    case camera

    // Aktivitet
    case location
    case healthActivity

    // Mående
    case sleep
    case mentalHealth
    case vitals

    var id: String { rawValue }
}

struct DataSource: Identifiable, Hashable {
    let id: DataSourceID
    let title: String
    let subtitle: String
    let systemPermissionHint: String?
}

struct DataDomain: Identifiable, Hashable {
    let id: DataDomainID
    let title: String
    let description: String

    let domainToggleTitle: String
    let domainToggleSubtitle: String?
    let footerText: String

    let sources: [DataSource]
    let sensitiveAccent: Bool
}

enum DomainCatalog {
    static let planning = DataDomain(
        id: .planning,
        title: "Planering",
        description: "Koppla din vardag om du vill.",
        domainToggleTitle: "Använd Planering",
        domainToggleSubtitle: "Synkroniserar kalender och påminnelser.",
        footerText: "Du kan när som helst stänga av Planering.",
        sources: [
            .init(id: .calendar, title: "Kalender", subtitle: "Händelser och tidsblock.", systemPermissionHint: "Kalenderåtkomst"),
            .init(id: .reminders, title: "Påminnelser", subtitle: "Uppgifter och listor.", systemPermissionHint: "Påminnelseåtkomst"),
            .init(id: .notifications, title: "Notiser", subtitle: "Kommer i en senare version.", systemPermissionHint: "Notisbehörighet")
        ],
        sensitiveAccent: false
    )

    static let info = DataDomain(
        id: .info,
        title: "Information",
        description: "Få tillgång till information när du behöver den.",
        domainToggleTitle: "Använd Information",
        domainToggleSubtitle: "Källor läses endast när du ställer en fråga.",
        footerText: "Ingen bakgrundsläsning sker.",
        sources: [
            .init(id: .contacts, title: "Kontakter", subtitle: "Används endast vid aktiv förfrågan.", systemPermissionHint: "Kontaktåtkomst"),
            .init(id: .mail, title: "Mejl", subtitle: "Används endast vid aktiv förfrågan.", systemPermissionHint: nil),
            .init(id: .files, title: "Filer", subtitle: "Används endast vid aktiv förfrågan.", systemPermissionHint: nil),
            .init(id: .photos, title: "Bilder", subtitle: "Används endast vid aktiv förfrågan.", systemPermissionHint: "Bildåtkomst"),
            .init(id: .camera, title: "Kamera", subtitle: "Importera bilder direkt med kameran.", systemPermissionHint: "Kameraåtkomst")
        ],
        sensitiveAccent: false
    )

    static let activity = DataDomain(
        id: .activity,
        title: "Aktivitet",
        description: "Se rörelse och plats om du vill.",
        domainToggleTitle: "Använd Aktivitet",
        domainToggleSubtitle: nil,
        footerText: "Data används bara när du frågar.",
        sources: [
            .init(id: .location, title: "Plats", subtitle: "Används för kontext vid behov.", systemPermissionHint: "Platsåtkomst"),
            .init(id: .healthActivity, title: "Hälsa – Aktivitet", subtitle: "Kommer i en senare version.", systemPermissionHint: "HealthKit-åtkomst")
        ],
        sensitiveAccent: false
    )

    static let wellbeing = DataDomain(
        id: .wellbeing,
        title: "Mående",
        description: "Utforska hur du mår över tid.",
        domainToggleTitle: "Använd Mående",
        domainToggleSubtitle: "Innehåller känslig information.",
        footerText: "Du styr alltid åtkomsten.",
        sources: [
            .init(id: .sleep, title: "Sömn", subtitle: "Kommer i en senare version.", systemPermissionHint: "HealthKit-åtkomst"),
            .init(id: .mentalHealth, title: "Mental hälsa", subtitle: "Kommer i en senare version.", systemPermissionHint: "HealthKit-åtkomst"),
            .init(id: .vitals, title: "Vitalparametrar", subtitle: "Kommer i en senare version.", systemPermissionHint: "HealthKit-åtkomst")
        ],
        sensitiveAccent: true
    )

    static let all: [DataDomain] = [planning, info, activity, wellbeing]
}
