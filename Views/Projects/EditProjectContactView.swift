import SwiftUI

struct EditProjectContactView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let contact: ProjectContact?      // nil → создание, не nil → редактирование

    @State private var name: String
    @State private var role: String
    @State private var phone: String
    @State private var note: String
    @State private var isFavorite: Bool

    init(projectID: UUID, contact: ProjectContact?) {
        self.projectID = projectID
        self.contact = contact

        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _note = State(initialValue: contact?.note ?? "")
        _isFavorite = State(initialValue: contact?.isFavorite ?? true)
    }

    var body: some View {
        Form {
            Section("Основная информация") {
                TextField("Имя / организация", text: $name)
                    .textContentType(.name)

                TextField("Роль (заказчик, бригадир...)", text: $role)

                TextField("Телефон", text: $phone)
                    .keyboardType(.phonePad)
            }

            Section("Дополнительно") {
                TextField("Комментарий", text: $note, axis: .vertical)
                    .lineLimit(1...4)

                Toggle("Важный контакт", isOn: $isFavorite)
            }
        }
        .navigationTitle(contact == nil ? "Новый контакт" : "Редактирование")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Отмена") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Сохранить") {
                    save()
                }
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && !p.isEmpty
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmedNote.isEmpty ? nil : trimmedNote

        let model = ProjectContact(
            id: contact?.id ?? UUID(),
            name: trimmedName,
            role: trimmedRole,
            phone: trimmedPhone,
            note: noteValue,
            isFavorite: isFavorite
        )

        do {
            if contact == nil {
                try store.addContact(model, to: projectID)
            } else {
                try store.updateContact(model, in: projectID)
            }
            dismiss()
        } catch {
            debugPrint("❌ save contact error:", error.localizedDescription)
        }
    }
}
