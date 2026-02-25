import Foundation

struct OnboardingSlide: Identifiable, Hashable {
    enum Kind: Hashable {
        case text
        case pipeline(steps: [String], examples: [String])
    }

    let id: String
    let title: String
    let body: String
    let primaryCTA: String
    let kind: Kind
}

enum OnboardingContent {
    static let slides: [OnboardingSlide] = [
        .init(
            id: "welcome",
            title: "Struktur mellan dina appar",
            body:
"""
Helper kopplar ihop din kalender, påminnelser, mail, filer och hälsa.
Inte för att ersätta dem – utan för att skapa sammanhang.
Den ser mönster över tid.
Den hjälper dig förstå – inte bara hitta.
""",
            primaryCTA: "Kom igång",
            kind: .text
        ),
        .init(
            id: "control",
            title: "Din data. Dina regler.",
            body:
"""
Helper läser bara det du själv väljer att aktivera.
All analys sker för att ge dig överblick – inte för att påverka dig.

Du kan när som helst:
• Stänga av en källa
• Radera sparad historik
• Återställa analys

Det är ett verktyg. Inte en övervakare.
""",
            primaryCTA: "Fortsätt",
            kind: .text
        ),
        .init(
            id: "what",
            title: "Fråga. Förstå. Reflektera.",
            body: "När du ställer en fråga sker detta:",
            primaryCTA: "Nästa",
            kind: .pipeline(
                steps: ["Signal", "Tolkning", "Sammanlänkning", "Insikt"],
                examples: [
                    "“Vad händer nästa vecka?”",
                    "“Varför är jag trött på onsdagar?”",
                    "“När hörde jag senast av mig till Agnes?”"
                ]
            )
        ),
        .init(
            id: "not-calendar",
            title: "Det här är inte en ny kalender",
            body:
"""
Systemet finns redan. Helper binder ihop det.

Kalender → Händelser
Påminnelser → Uppgifter
Mail → Kommunikation
Hälsa → Mående

Helper ersätter inget.
Den skapar struktur mellan dem.
""",
            primaryCTA: "Nästa",
            kind: .text
        ),
        .init(
            id: "feeling",
            title: "Lugn i informationskaos",
            body:
"""
Helper är byggd för att:
• Minska överväldigande
• Visa helheten först
• Bryta ner i steg
• Spara vad du lär dig

Den ska kännas som en del av systemet.
Inte ännu en app.
""",
            primaryCTA: "Börja använda Helper",
            kind: .text
        )
    ]
}
