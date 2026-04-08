import Foundation
import Contacts

/// Searches and reads the user's contacts.
/// Uses the Contacts framework — this one works great on iOS.
class ContactProvider {
    private let store = CNContactStore()

    /// Request contact access. Must be called before other methods.
    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    /// Search contacts by name, phone, or email.
    func search(query: String) async throws -> String {
        let granted = await requestAccess()
        guard granted else {
            return "I don't have permission to access your contacts. Please grant access in Settings → G → Contacts."
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts: [CNContact]
        do {
            contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        } catch {
            return "Error searching contacts: \(error.localizedDescription)"
        }

        if contacts.isEmpty {
            // Try phone number search
            return try await searchByPhone(query: query, keys: keysToFetch)
        }

        return contacts.prefix(10).enumerated().map { i, contact in
            var parts: [String] = []
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            parts.append("[\(i+1)] \(name)")

            if !contact.organizationName.isEmpty {
                parts.append("  Company: \(contact.organizationName)")
            }

            for phone in contact.phoneNumbers {
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "")
                parts.append("  \(label): \(phone.value.stringValue)")
            }

            for email in contact.emailAddresses {
                parts.append("  Email: \(email.value as String)")
            }

            if let birthday = contact.birthday,
               let date = Calendar.current.date(from: birthday) {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM d"
                parts.append("  Birthday: \(formatter.string(from: date))")
            }

            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func searchByPhone(query: String, keys: [CNKeyDescriptor]) async throws -> String {
        // Strip non-numeric characters for phone search
        let digits = query.filter { $0.isNumber }
        guard digits.count >= 4 else {
            return "No contacts found matching '\(query)'"
        }

        let phoneNumber = CNPhoneNumber(stringValue: digits)
        let predicate = CNContact.predicateForContacts(matching: phoneNumber)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            if contacts.isEmpty {
                return "No contacts found matching '\(query)'"
            }
            let name = "\(contacts[0].givenName) \(contacts[0].familyName)".trimmingCharacters(in: .whitespaces)
            return "Found: \(name) — \(contacts[0].phoneNumbers.first?.value.stringValue ?? "")"
        } catch {
            return "No contacts found matching '\(query)'"
        }
    }
}
