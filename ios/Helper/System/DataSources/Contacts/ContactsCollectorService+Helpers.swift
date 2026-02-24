import Foundation
#if canImport(Contacts)
@preconcurrency import Contacts
#endif

// MARK: - Helpers

extension ContactsCollectorService {

    #if canImport(Contacts)
    func fetchSnapshots() throws -> [ContactSnapshot] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var snapshots: [ContactSnapshot] = []

        try contactStore.enumerateContacts(with: request) { contact, _ in
            let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            guard !fullName.isEmpty else { return }

            let organization = contact.organizationName
            let emails = contact.emailAddresses.map { $0.value as String }
            let phones = contact.phoneNumbers.map { $0.value.stringValue }

            let hash = Self.computeHash(
                name: fullName,
                org: organization,
                emails: emails,
                phones: phones
            )

            snapshots.append(ContactSnapshot(
                identifier: contact.identifier,
                fullName: fullName,
                organization: organization,
                emails: emails,
                phones: phones,
                hash: hash
            ))
        }

        return snapshots
    }

    static func computeHash(
        name: String,
        org: String,
        emails: [String],
        phones: [String]
    ) -> String {
        let combined = "\(name)|\(org)|\(emails.joined(separator: ","))|\(phones.joined(separator: ","))"
        return String(combined.hashValue)
    }
    #endif

    static func contactBody(
        organization: String,
        emails: [String],
        phones: [String]
    ) -> String {
        var parts: [String] = []

        if !organization.isEmpty {
            parts.append("Org: \(organization)")
        }

        if !emails.isEmpty {
            parts.append("E-post: \(emails.joined(separator: ", "))")
        }

        if !phones.isEmpty {
            parts.append("Tel: \(phones.joined(separator: ", "))")
        }

        return parts.isEmpty ? "Kontakt" : parts.joined(separator: " | ")
    }
}
