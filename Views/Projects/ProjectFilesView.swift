import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

struct ProjectFilesView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    // Работа с файлами (тот же сервис, что и для фото/доков чек-листов)
    private let mediaService = MediaService()

    // Состояние для выбора фото / документов
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showDocsPicker = false
    @State private var showProjectPDFPicker = false

    @State private var errorText: String?

    // Просмотр файлов
    @State private var activePreview: FilePreview?

    // Удобные геттеры
    private var project: Project? {
        store.project(by: projectID)
    }

    private var photoPaths: [String] {
        project?.photoPaths ?? []
    }

    private var documentPaths: [String] {
        project?.documentPaths ?? []
    }

    private var projectPDFPath: String? {
        project?.projectPDFPath
    }

    var body: some View {
        List {
            // Фото
            Section("Фото проекта") {
                if photoPaths.isEmpty {
                    Text("Фотографии пока не добавлены.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(photoPaths, id: \.self) { path in
                        photoRow(path: path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openPhoto(path)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removePhoto(path)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                    }
                }

                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    Label("Добавить фото", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }

            // Документы (PDF)
            Section("Документы") {
                if documentPaths.isEmpty {
                    Text("Документы пока не добавлены.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(documentPaths, id: \.self) { path in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.blue)
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName(from: path))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("PDF-документ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openPDF(path)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeDocument(path)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showDocsPicker = true
                } label: {
                    Label("Добавить документ (PDF)", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }

            // PDF-проект
            Section("Проект (PDF)") {
                if let pdfPath = projectPDFPath {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.green)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileName(from: pdfPath))
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("Текущий файл проекта")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openPDF(pdfPath)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            removeProjectPDF(pdfPath)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }

                    Text("Можно загрузить новый файл, чтобы заменить текущий проект.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("PDF-проект пока не загружен.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showProjectPDFPicker = true
                } label: {
                    Label(
                        projectPDFPath == nil ? "Загрузить проект (PDF)" : "Заменить проект (PDF)",
                        systemImage: "arrow.up.doc"
                    )
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Файлы проекта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Назад") {
                    dismiss()
                }
            }
        }
        // Фото → как только выбрали, импортируем
        .onChange(of: photoItems) { newItems in
            guard !newItems.isEmpty else { return }
            Task { await importPhotos(from: newItems) }
        }
        // Документы / проект PDF → системный picker
        .sheet(isPresented: $showDocsPicker) {
            DocumentPicker(
                contentTypes: [.pdf],
                allowsMultiple: true
            ) { urls in
                Task {
                    await importPDFs(from: urls, asProjectPDF: false)
                    await MainActor.run { showDocsPicker = false }
                }
            }
        }
        .sheet(isPresented: $showProjectPDFPicker) {
            DocumentPicker(
                contentTypes: [.pdf],
                allowsMultiple: false
            ) { urls in
                Task {
                    await importPDFs(from: urls, asProjectPDF: true)
                    await MainActor.run { showProjectPDFPicker = false }
                }
            }
        }
        .alert("Ошибка", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        // Полноэкранный просмотр (фото + PDF)
        .fullScreenCover(item: $activePreview) { preview in
            switch preview {
            case .image(let uiImage):
                FullScreenImageView(image: uiImage)

            case .pdf(let url):
                NavigationStack {
                    PDFPreviewFullScreen(url: url)
                }
            }
        }
    }

    // MARK: - Фото-ряд с миниатюрой

    private func photoRow(path: String) -> some View {
        HStack(spacing: 12) {
            photoThumbnail(path: path)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(from: path))
                    .font(.subheadline)
                    .lineLimit(1)

                Text("Фото проекта")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func photoThumbnail(path: String) -> some View {
        if let url = existingFileURL(path),
           let uiImage = UIImage(contentsOfFile: url.path) {
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            )
        } else {
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            )
        }
    }

    // MARK: - Импорт фото

    private func importPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { continue }

                let path = try mediaService.save(image: image)

                try await MainActor.run {
                    try store.updateProjectMeta(projectID) { project in
                        project.photoPaths.append(path)
                    }
                }
            } catch {
                await MainActor.run {
                    errorText = "Не удалось импортировать фото: \(error.localizedDescription)"
                }
            }
        }

        await MainActor.run {
            photoItems = []
        }
    }

    // MARK: - Импорт PDF (документы + проект)

    private func importPDFs(from urls: [URL], asProjectPDF: Bool) async {
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent

                let savedPath = try mediaService.save(pdfData: data, name: name)

                try await MainActor.run {
                    try store.updateProjectMeta(projectID) { project in
                        if asProjectPDF {
                            // Заменяем путь к проекту
                            project.projectPDFPath = savedPath
                        } else {
                            // Добавляем в список документов
                            project.documentPaths.append(savedPath)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorText = "Не удалось импортировать PDF: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Удаление файлов

    private func removePhoto(_ path: String) {
        Task {
            do {
                try mediaService.deleteFile(at: path)
            } catch {
                await MainActor.run {
                    errorText = "Не удалось удалить файл: \(error.localizedDescription)"
                }
            }

            do {
                try await MainActor.run {
                    try store.updateProjectMeta(projectID) { project in
                        project.photoPaths.removeAll { $0 == path }
                    }
                }
            } catch {
                await MainActor.run {
                    errorText = "Не удалось обновить проект после удаления файла: \(error.localizedDescription)"
                }
            }
        }
    }

    private func removeDocument(_ path: String) {
        Task {
            do {
                try mediaService.deleteFile(at: path)
            } catch {
                await MainActor.run {
                    errorText = "Не удалось удалить файл: \(error.localizedDescription)"
                }
            }

            do {
                try await MainActor.run {
                    try store.updateProjectMeta(projectID) { project in
                        project.documentPaths.removeAll { $0 == path }
                    }
                }
            } catch {
                await MainActor.run {
                    errorText = "Не удалось обновить проект после удаления документа: \(error.localizedDescription)"
                }
            }
        }
    }

    private func removeProjectPDF(_ path: String) {
        Task {
            do {
                try mediaService.deleteFile(at: path)
            } catch {
                await MainActor.run {
                    errorText = "Не удалось удалить файл проекта: \(error.localizedDescription)"
                }
            }

            do {
                try await MainActor.run {
                    try store.updateProjectMeta(projectID) { project in
                        if project.projectPDFPath == path {
                            project.projectPDFPath = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorText = "Не удалось обновить проект после удаления PDF: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Открытие файлов

    private func openPhoto(_ path: String) {
        // Используем existingFileURL, чтобы превратить относительный путь в абсолютный
        guard let url = existingFileURL(path) else {
            errorText = "Файл не найден на диске."
            return
        }

        if let image = UIImage(contentsOfFile: url.path) {
            activePreview = .image(image)
        } else {
            errorText = "Не удалось открыть изображение."
        }
    }

    private func openPDF(_ path: String) {
        guard let url = existingFileURL(path) else {
            errorText = "Файл не найден на диске."
            return
        }

        activePreview = .pdf(url)
    }

    // MARK: - Вспомогательное

    private func fileName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        return last.isEmpty ? path : last
    }
}

// MARK: - UIKit-пикер документов

private struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        controller.allowsMultipleSelection = allowsMultiple
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - Модель для превью

private enum FilePreview: Identifiable {
    case image(UIImage)
    case pdf(URL)

    var id: String {
        switch self {
        case .image(let ui):
            return "img:\(Unmanaged.passUnretained(ui).toOpaque())"
        case .pdf(let url):
            return "pdf:\(url.path)"
        }
    }
}

// MARK: - Полноэкранный PDF-просмотр

private struct PDFPreviewFullScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PDFKitView(url: url)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
            }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}
