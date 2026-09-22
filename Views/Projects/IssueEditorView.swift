import PhotosUI
import SwiftUI
import UIKit

/// Create/edit an issue using existing `BCNotes` and `photoPaths`.
/// New photos stay in memory until save. Cancel writes nothing.
struct IssueEditorView: View {
    @Binding var item: StageItem
    let isCreate: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var draftNote: String = ""
    @State private var draftPhotos: [IssueDraftPhoto] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var didLoadDraft = false

    private var trimmedNote: String {
        draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedNote.isEmpty || !draftPhotos.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Пункт") {
                    Text(item.title)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Описание проблемы") {
                    TextEditor(text: $draftNote)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Описание проблемы")
                        .accessibilityIdentifier("issue.editor.description")
                }

                Section("Фотографии") {
                    if !draftPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(draftPhotos) { photo in
                                    draftThumb(photo)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button {
                        pickedItems.removeAll()
                        showPhotoPicker = true
                    } label: {
                        Label("Добавить фотографии", systemImage: "photo.badge.plus")
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("issue.editor.addPhotos")
                }

                if !canSave {
                    Section {
                        Text("Добавьте описание или фотографию.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(isCreate ? "Новое замечание" : "Изменить замечание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("issue.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить замечание") { save() }
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("issue.editor.save")
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $pickedItems,
                maxSelectionCount: 12,
                matching: .images
            )
            .onChange(of: pickedItems) { _, newValue in
                Task { await importPickedPhotos(newValue) }
            }
            .alert("Не удалось сохранить", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Замечание не изменено.")
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: loadDraft)
        }
    }

    @ViewBuilder
    private func draftThumb(_ photo: IssueDraftPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            switch photo {
            case .existing(_, let path):
                IssuePhotoThumbnail(path: path, side: 74)
            case .incoming(_, let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 74, height: 74)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button {
                draftPhotos.removeAll { $0.id == photo.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .disabled(isSaving)
            .accessibilityLabel("Удалить фотографию")
        }
    }

    private func loadDraft() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        draftNote = ChecklistWorkingNote.readRawText(itemID: item.id) ?? ""
        draftPhotos = item.photoPaths.map { IssueDraftPhoto.existing(id: UUID(), path: $0) }
    }

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var incoming: [IssueDraftPhoto] = []
        for pickerItem in items {
            if let data = try? await pickerItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                incoming.append(.incoming(id: UUID(), image: image))
            }
        }
        guard !incoming.isEmpty else { return }
        await MainActor.run {
            draftPhotos.append(contentsOf: incoming)
            pickedItems.removeAll()
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        let originalPaths = item.photoPaths
        let keptExisting = draftPhotos.compactMap(\.existingPath)
        let newImages = draftPhotos.compactMap(\.incomingImage)
        let removedExisting = originalPaths.filter { path in
            !keptExisting.contains(path)
        }
        do {
            let paths = try IssueContentSaver.persist(
                itemID: item.id,
                note: draftNote,
                keptExistingPaths: keptExisting,
                newImages: newImages
            )
            item.photoPaths = paths
            item.status = .issue
            let media = MediaService()
            for path in removedExisting {
                try? media.deleteFile(at: path)
            }
            NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
            isSaving = false
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось сохранить замечание. Существующие данные не изменены."
            showError = true
            isSaving = false
        }
    }
}

private enum IssueDraftPhoto: Identifiable {
    case existing(id: UUID, path: String)
    case incoming(id: UUID, image: UIImage)

    var id: UUID {
        switch self {
        case .existing(let id, _), .incoming(let id, _):
            return id
        }
    }

    var existingPath: String? {
        if case .existing(_, let path) = self { return path }
        return nil
    }

    var incomingImage: UIImage? {
        if case .incoming(_, let image) = self { return image }
        return nil
    }
}

enum IssueSaveError: LocalizedError {
    case photo
    case note

    var errorDescription: String? {
        switch self {
        case .photo:
            return "Не удалось сохранить фотографию. Замечание не изменено."
        case .note:
            return "Не удалось сохранить описание. Замечание не изменено."
        }
    }
}

/// Persist note and new photos before the caller sets `issue`.
///
/// Order:
/// 1. Write new JPEGs to `BC_Media/Images`.
/// 2. Write or delete `BCNotes/<itemUUID>.txt`.
/// 3. On any error, delete files created in step 1 and leave the existing note/photos untouched.
/// 4. Caller then updates `photoPaths`, sets `status = .issue`, and lets ProgressStore save.
/// 5. Caller deletes existing files that were removed in the draft (best-effort, after JSON is updated).
enum IssueContentSaver {
    static func persist(
        itemID: UUID,
        note: String,
        keptExistingPaths: [String],
        newImages: [UIImage]
    ) throws -> [String] {
        let media = MediaService()
        var created: [String] = []
        do {
            for image in newImages {
                let path = try media.save(image: image)
                created.append(path)
            }
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try ChecklistWorkingNote.deleteIfExists(itemID: itemID)
            } else {
                try ChecklistWorkingNote.write(trimmed, itemID: itemID)
            }
        } catch let error as IssueSaveError {
            rollback(created, media: media)
            throw error
        } catch {
            rollback(created, media: media)
            if created.count < newImages.count {
                throw IssueSaveError.photo
            }
            throw IssueSaveError.note
        }
        return keptExistingPaths + created
    }

    private static func rollback(_ created: [String], media: MediaService) {
        for path in created {
            try? media.deleteFile(at: path)
        }
    }
}
