import SwiftUI

struct ProjectContactsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let projectID: UUID

    @State private var showAddContact = false
    @State private var editingContact: ProjectContact?

    private var contacts: [ProjectContact] {
        let all = store.contacts(for: projectID)
        return all.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if contacts.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Пока нет контактов.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Добавьте хотя бы заказчика и бригадира для этого проекта.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    ForEach(contacts) { contact in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(contact.name)
                                    .font(.headline)
                                if contact.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }

                            if !contact.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(contact.role)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text(contact.phone)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    callPhone(contact.phone)
                                } label: {
                                    Image(systemName: "phone.fill")
                                }
                                .buttonStyle(.borderless)
                            }

                            if let note = contact.note,
                               !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(contact)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }

                            Button {
                                editingContact = contact
                            } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Контакты проекта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            NavigationStack {
                EditProjectContactView(projectID: projectID, contact: nil)
                    .environmentObject(store)
            }
        }
        .sheet(item: $editingContact) { contact in
            NavigationStack {
                EditProjectContactView(projectID: projectID, contact: contact)
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Helpers

    private func callPhone(_ phone: String) {
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }

    private func delete(_ contact: ProjectContact) {
        do {
            try store.deleteContact(contact, from: projectID)
        } catch {
            debugPrint("❌ deleteContact error:", error.localizedDescription)
        }
    }
}
