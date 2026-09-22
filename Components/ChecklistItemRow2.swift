import SwiftUI
import PhotosUI
import UIKit

/// Строка чек-пункта: галочка ✅ + фото 📷 + заметка 📝 + инфо ℹ️.
/// Фото сохраняются через MediaService → Documents/BC_Media/Images,
/// заметка → Documents/BCNotes.
struct ChecklistItemRow2: View {
    @EnvironmentObject private var store: AppStore

    @Binding var item: StageItem

    // Визуальные опции (на будущее, пока не используются)
    var showStatusControls: Bool = true

    /// Колбэк для открытия InfoSheet (реализация в родителе)
    var onInfo: (String) -> Void = { _ in }

    // Note
    @State private var showNote = false
    @State private var draftNote: String = ""

    // Photos
    @State private var showPhotoPicker = false
    @State private var pickedItems: [PhotosPickerItem] = []

    // Fullscreen gallery
    @State private var showFullScreen = false
    @State private var currentIndex = 0

    // Issue editor
    @State private var showIssueEditor = false
    @State private var issueEditorIsCreate = true
    @State private var showIssueActions = false

    // Check bounce
    @State private var checkBounce = false

    // Media service для работы с файлами изображений
    private let media = MediaService()

    private var isLocked: Bool {
        store.isReadOnlyMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow()

            if !item.photoPaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(item.photoPaths.enumerated()), id: \.offset) { (idx, path) in
                            photoThumb(idx: idx, path: path)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text("Удерживайте фото, чтобы открыть или удалить.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .opacity(isLocked ? 0 : 1)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            issueSwipeActions()
        }
        .confirmationDialog(
            "Действия с пунктом",
            isPresented: $showIssueActions,
            titleVisibility: .visible
        ) {
            issueActionButtons
        }

        // Пикер фото
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickedItems,
            maxSelectionCount: 12,
            matching: .images
        )
        .onChange(of: pickedItems) { _, newValue in
            Task { await importPickedPhotos(newValue) }
        }

        // Редактор заметки
        .sheet(isPresented: $showNote) { noteEditor() }

        .sheet(isPresented: $showIssueEditor) {
            IssueEditorView(item: $item, isCreate: issueEditorIsCreate)
        }

        // Полноэкранная галерея
        .fullScreenCover(isPresented: $showFullScreen) { fullScreenGallery() }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow() -> some View {
        HStack(spacing: 14) {
            doneButton()

            Text(item.title)
                .font(.body)
                .foregroundStyle(item.status == .ok ? .secondary : .primary)
                .strikethrough(item.status == .ok, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Инфо-кнопка (если есть slug) — в read-only скрываем полностью
            if !isLocked,
               let slug = item.infoSlug?.trimmingCharacters(in: .whitespacesAndNewlines),
               !slug.isEmpty {
                Button {
                    onInfo(slug)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Справка по пункту")
            }

            // Фото/заметки — в read-only скрываем полностью
            if !isLocked {
                photosButton()
                noteButton()
            }
        }
    }

    private var resolvedStatus: ItemStatus {
        item.status ?? .na
    }

    private var isIssue: Bool {
        resolvedStatus == .issue
    }

    private func doneButton() -> some View {
        Image(systemName: statusIconName)
            .foregroundColor(statusIconColor)
            .font(.system(size: 22))
            .frame(width: 32, height: 32)
            .scaleEffect(checkBounce ? 1.15 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleDoneStatus)
            .onLongPressGesture(minimumDuration: 0.45) {
                guard !isLocked else { return }
                showIssueActions = true
            }
            .opacity(isLocked ? 0.35 : 1)
            .accessibilityLabel(statusAccessibilityLabel)
            .accessibilityHint(isIssue ? "Удерживайте значок статуса, чтобы открыть действия замечания." : "Двойное нажатие отмечает пункт выполненным или снимает отметку. Удерживайте значок статуса, чтобы открыть действия замечания.")
            .accessibilityIdentifier("checklist.item.status")
            .accessibilityAddTraits(.isButton)
    }

    private func toggleDoneStatus() {
        guard !isLocked else { return }
        if isIssue {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            item.status = (resolvedStatus == .ok) ? .na : .ok
            checkBounce.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                checkBounce = false
            }
        }
    }

    @ViewBuilder
    private var issueActionButtons: some View {
        if !isLocked {
            if isIssue {
                Button("Проблема устранена") { setStatus(.ok) }
                Button("Снять отметку проблемы") { setStatus(.na) }
                Button("Изменить замечание") { openIssueEditor(isCreate: false) }
            } else {
                Button("Отметить как проблему") { openIssueEditor(isCreate: true) }
            }
        }
        Button("Отмена", role: .cancel) {}
    }

    private var statusIconName: String {
        switch resolvedStatus {
        case .ok: return "checkmark.circle.fill"
        case .issue: return "exclamationmark.circle.fill"
        case .na: return "circle"
        }
    }

    private var statusIconColor: Color {
        switch resolvedStatus {
        case .ok: return .green
        case .issue: return .orange
        case .na: return .gray
        }
    }

    private var statusAccessibilityLabel: String {
        let prefix: String
        switch resolvedStatus {
        case .ok: prefix = "Выполнено"
        case .issue: prefix = "Проблема"
        case .na: prefix = "Не выполнено"
        }
        return "\(prefix), \(item.title)"
    }

    @ViewBuilder
    private func issueSwipeActions() -> some View {
        if !isLocked {
            if isIssue {
                Button {
                    setStatus(.ok)
                } label: {
                    Label("Проблема устранена", systemImage: "checkmark.circle")
                }
                .tint(.green)
                .accessibilityLabel("Проблема устранена")
                .accessibilityIdentifier("checklist.item.resolveIssue")
            } else {
                Button {
                    openIssueEditor(isCreate: true)
                } label: {
                    Label("Отметить как проблему", systemImage: "exclamationmark.circle")
                }
                .tint(.orange)
                .accessibilityLabel("Отметить как проблему")
                .accessibilityIdentifier("checklist.item.markIssue")
            }
        }
    }

    private func openIssueEditor(isCreate: Bool) {
        guard !isLocked else { return }
        issueEditorIsCreate = isCreate
        showIssueEditor = true
    }

    private func setStatus(_ status: ItemStatus) {
        guard !isLocked else { return }
        guard item.status != status else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            item.status = status
        }
    }

    private func photosButton() -> some View {
        Button {
            pickedItems.removeAll()
            showPhotoPicker = true
        } label: {
            let hasPhotos = !item.photoPaths.isEmpty
            ZStack(alignment: .topTrailing) {
                Image(systemName: hasPhotos ? "photo.fill.on.rectangle.fill" : "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(hasPhotos ? .blue : .primary)
                    .frame(width: 32, height: 32)

                if item.photoPaths.count > 0 {
                    Text("\(min(item.photoPaths.count, 99))")
                        .font(.caption2).bold()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
                        )
                        .offset(x: 2, y: -2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Добавить фотографии")
        .accessibilityHint("Открывает выбор фотографий для этого пункта.")
    }

    private func noteButton() -> some View {
        Button {
            draftNote = (loadNote(for: item) ?? "")
            showNote = true
        } label: {
            let hasNote = noteExists(for: item)
            ZStack(alignment: .topTrailing) {
                Image(systemName: "note.text")
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                if hasNote {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Заметка")
        .accessibilityHint("Открывает текстовую заметку пункта.")
    }

    // MARK: - Note Editor

    @ViewBuilder
    private func noteEditor() -> some View {
        NavigationStack {
            TextEditor(text: $draftNote)
                .padding()
                .navigationTitle("Заметка")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { showNote = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            saveNote(draftNote, for: item)
                            showNote = false
                        }
                    }
                }
        }
    }

    // MARK: - Fullscreen Gallery

    @ViewBuilder
    private func fullScreenGallery() -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !item.photoPaths.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(item.photoPaths.enumerated()), id: \.offset) { (idx, path) in
                        if let url = existingFileURL(path),
                           let ui = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .tag(idx)
                                .background(Color.black)
                                .ignoresSafeArea()
                        } else {
                            Color.black.tag(idx)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullScreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Photo thumb

    @ViewBuilder
    private func photoThumb(idx: Int, path: String) -> some View {
        if let url = existingFileURL(path),
           let ui = UIImage(contentsOfFile: url.path) {
            ChecklistPhotoThumb(
                image: ui,
                isLocked: isLocked,
                accessibilityLabel: "Фотография \(idx + 1)",
                onOpen: {
                    currentIndex = idx
                    showFullScreen = true
                },
                onDelete: {
                    deletePhoto(at: idx)
                }
            )
            .frame(width: 110, height: 74)
        } else {
            // Плейсхолдер если файл потерян
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                    Text("Файл не найден")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: 110, height: 74)
        }
    }

    // MARK: - Photos & Notes helpers

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        guard !isLocked else { return }

        for it in items {
            do {
                if let data = try await it.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    let path = try media.save(image: ui)
                    item.photoPaths.append(path)
                }
            } catch {
                print("❌ Load or save photo error:", error.localizedDescription)
            }
        }
    }

    private func deleteAllPhotos() {
        guard !isLocked else { return }
        for p in item.photoPaths {
            do {
                try media.deleteFile(at: p)
            } catch {
                print("❌ Delete photo error:", error.localizedDescription)
            }
        }
        item.photoPaths.removeAll()
    }

    private func deletePhoto(at index: Int) {
        guard !isLocked else { return }
        guard item.photoPaths.indices.contains(index) else { return }
        let path = item.photoPaths.remove(at: index)
        do {
            try media.deleteFile(at: path)
        } catch {
            print("❌ Delete single photo error:", error.localizedDescription)
        }
        if currentIndex >= item.photoPaths.count {
            currentIndex = max(0, item.photoPaths.count - 1)
        }
    }

    // MARK: - Notes FS helpers

    private func noteExists(for item: StageItem) -> Bool {
        guard let url = ChecklistWorkingNote.fileURL(itemID: item.id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func loadNote(for item: StageItem) -> String? {
        ChecklistWorkingNote.readRawText(itemID: item.id)
    }

    private func saveNote(_ text: String, for item: StageItem) {
        guard !isLocked else { return }
        try? ChecklistWorkingNote.write(text, itemID: item.id)
    }
}

/// Photo thumbnail with a UIKit context menu bound to this view only.
/// SwiftUI `.contextMenu` inside `List` is installed on the whole cell.
private struct ChecklistPhotoThumb: UIViewRepresentable {
    let image: UIImage
    let isLocked: Bool
    let accessibilityLabel: String
    let onOpen: () -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> ChecklistPhotoThumbView {
        let view = ChecklistPhotoThumbView()
        view.isUserInteractionEnabled = true
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 10
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.secondaryLabel.withAlphaComponent(0.2).cgColor
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(ChecklistPhotoThumbView.openTapped)))
        view.addInteraction(UIContextMenuInteraction(delegate: view))
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ChecklistPhotoThumbView,
        context: Context
    ) -> CGSize? {
        CGSize(width: 110, height: 74)
    }

    func updateUIView(_ view: ChecklistPhotoThumbView, context: Context) {
        view.image = image
        view.isLocked = isLocked
        view.onOpen = onOpen
        view.onDelete = onDelete
        view.isAccessibilityElement = true
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityHint = "Двойное нажатие открывает просмотр. Удерживайте, чтобы удалить или открыть."
        view.accessibilityIdentifier = "checklist.item.photo"
    }
}

private final class ChecklistPhotoThumbView: UIImageView, UIContextMenuInteractionDelegate {
    var isLocked = false
    var onOpen: () -> Void = {}
    var onDelete: () -> Void = {}

    @objc func openTapped() {
        onOpen()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isLocked else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let open = UIAction(
                title: "Открыть фото",
                image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")
            ) { _ in
                self?.onOpen()
            }
            let delete = UIAction(
                title: "Удалить это фото",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.onDelete()
            }
            return UIMenu(children: [open, delete])
        }
    }
}
