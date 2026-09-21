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
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            issueSwipeActions()
        }
        .contextMenu {
            issueContextMenu()
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

        // Полноэкранная галерея
        .fullScreenCover(isPresented: $showFullScreen) { fullScreenGallery() }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow() -> some View {
        HStack(spacing: 14) {
            doneButton()

            // Многострочный заголовок без обрезки
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
        Button {
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
        } label: {
            Image(systemName: statusIconName)
                .foregroundColor(statusIconColor)
                .font(.system(size: 22))
                .frame(width: 32, height: 32)
                .scaleEffect(checkBounce ? 1.15 : 1.0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked ? 0.35 : 1)
        .accessibilityLabel(statusAccessibilityLabel)
        .accessibilityHint(isIssue ? "Закройте замечание из меню или свайпом." : "Двойное нажатие отмечает пункт выполненным или снимает отметку.")
        .accessibilityIdentifier("checklist.item.status")
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
                    setStatus(.issue)
                } label: {
                    Label("Отметить как проблему", systemImage: "exclamationmark.circle")
                }
                .tint(.orange)
                .accessibilityLabel("Отметить как проблему")
                .accessibilityIdentifier("checklist.item.markIssue")
            }
        }
    }

    @ViewBuilder
    private func issueContextMenu() -> some View {
        if !isLocked {
            if isIssue {
                Button {
                    setStatus(.ok)
                } label: {
                    Label("Проблема устранена", systemImage: "checkmark.circle")
                }
                .accessibilityLabel("Проблема устранена")
                .accessibilityIdentifier("checklist.item.resolveIssue")

                Button {
                    setStatus(.na)
                } label: {
                    Label("Снять отметку проблемы", systemImage: "circle")
                }
                .accessibilityLabel("Снять отметку проблемы")
                .accessibilityIdentifier("checklist.item.clearIssue")
            } else {
                Button {
                    setStatus(.issue)
                } label: {
                    Label("Отметить как проблему", systemImage: "exclamationmark.circle")
                }
                .accessibilityLabel("Отметить как проблему")
                .accessibilityIdentifier("checklist.item.markIssue")
            }
        }
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
            let base = Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 74)
                .clipped()
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onTapGesture {
                    currentIndex = idx
                    showFullScreen = true
                }

            if isLocked {
                base
            } else {
                base.contextMenu {
                    Button {
                        currentIndex = idx
                        showFullScreen = true
                    } label: {
                        Label("Открыть фото", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Button(role: .destructive) {
                        deletePhoto(at: idx)
                    } label: {
                        Label("Удалить это фото", systemImage: "trash")
                    }
                }
            }
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

    private func noteFileURL(for item: StageItem) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let notesDir = dir.appendingPathComponent("BCNotes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: notesDir.path) {
            try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        }
        return notesDir.appendingPathComponent("\(item.id.uuidString).txt")
    }

    private func noteExists(for item: StageItem) -> Bool {
        FileManager.default.fileExists(atPath: noteFileURL(for: item).path)
    }

    private func loadNote(for item: StageItem) -> String? {
        let url = noteFileURL(for: item)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func saveNote(_ text: String, for item: StageItem) {
        guard !isLocked else { return }
        let url = noteFileURL(for: item)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
