import os
import PDFKit
import SwiftUI
import UIKit

struct ChecklistReportExportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var scope: ChecklistReportScope = .full
    @State private var includePhotos = true
    @State private var isGenerating = false
    @State private var phaseText = "Подготавливаем данные…"
    @State private var errorText: String?
    @State private var partialWarning = false
    @State private var showPreview = false
    @State private var showShare = false
    @State private var shareOpen = false
    @State private var ownedURL: URL?
    @State private var task: Task<Void, Never>?
    @State private var cancelFlag = CancelFlag()
    @State private var screen = ScreenGate()

    private var project: Project? {
        store.projects.first { $0.id == projectID }
    }

    var body: some View {
        Group {
            if showPreview, let ownedURL {
                preview(url: ownedURL)
            } else {
                settings
            }
        }
        .onDisappear(perform: closeScreen)
        .sheet(isPresented: $showShare, onDismiss: shareDidDismiss) {
            if let ownedURL {
                ChecklistReportShareSheet(url: ownedURL) {
                    showShare = false
                }
            }
        }
    }

    private var settings: some View {
        Form {
            if let project {
                Section {
                    Text(project.name)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                Section("Тип отчёта") {
                    Picker("Тип отчёта", selection: $scope) {
                        Text("Полный отчёт").tag(ChecklistReportScope.full)
                        Text("Только замечания").tag(ChecklistReportScope.issuesOnly)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("project.checklistReport.scope")
                    .accessibilityLabel("Тип отчёта")
                }

                Section {
                    Toggle("Включить фотографии", isOn: $includePhotos)
                        .accessibilityIdentifier("project.checklistReport.includePhotos")
                    Text("Фотографии увеличивают размер файла и время создания.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Проект не найден")
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("project.checklistReport.error")
                        .accessibilityLabel(errorText)
                }
            }
        }
        .navigationTitle("Отчёт по чек-листам")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
                    .accessibilityLabel("Закрыть")
            }
        }
        .safeAreaInset(edge: .bottom) {
            generationBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var generationBar: some View {
        if isGenerating {
            VStack(spacing: 12) {
                ProgressView()
                Text(phaseText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Отмена", action: cancelGeneration)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Отмена")
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project.checklistReport.progress")
            .accessibilityLabel(phaseText)
        } else {
            Button(action: startExport) {
                Text("Сформировать PDF")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(project == nil || task != nil)
            .accessibilityIdentifier("project.checklistReport.generate")
            .accessibilityLabel("Сформировать PDF")
        }
    }

    private func preview(url: URL) -> some View {
        VStack(spacing: 0) {
            if partialWarning {
                Text(ChecklistReportExportMessage.partialReport)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15))
                    .accessibilityLabel(ChecklistReportExportMessage.partialReport)
            }
            ChecklistReportPDFPreview(url: url)
                .accessibilityIdentifier("project.checklistReport.preview")
                .accessibilityLabel("Просмотр PDF")
        }
        .navigationTitle("Отчёт по чек-листам")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { showPreview = false }
                    .accessibilityLabel("Закрыть просмотр")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    shareOpen = true
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Отправить или сохранить")
                .accessibilityIdentifier("project.checklistReport.share")
            }
        }
    }

    private func startExport() {
        guard task == nil, !isGenerating, let project else { return }
        errorText = nil
        partialWarning = false
        showPreview = false
        let flag = CancelFlag()
        cancelFlag = flag
        let source = ChecklistReportSource(
            projectID: project.id,
            name: project.name,
            address: project.address,
            manager: project.manager,
            generatedAt: Date(),
            dateStart: project.dateStart,
            dateEnd: project.dateEnd,
            budget: project.budget,
            projectDescription: project.description,
            foundationTitle: project.foundationType?.title,
            wallTitle: project.wallType?.title,
            slabTitle: project.slabType?.title,
            roofShapeTitle: project.roofShapeType?.title,
            roofCoverTitle: project.roofCoverType?.title
        )
        let options = ChecklistReportRenderOptions(scope: scope, includePhotos: includePhotos)
        let destination = ChecklistReportExportFile.makeURL(projectName: source.name)
        if !shareOpen {
            ChecklistReportExportFile.remove(ownedURL)
        }
        ownedURL = nil
        isGenerating = true
        phaseText = "Подготавливаем данные…"
        let screen = screen
        task = Task {
            await withTaskCancellationHandler {
                await run(
                    source: source,
                    options: options,
                    destination: destination,
                    flag: flag,
                    screen: screen
                )
            } onCancel: {
                flag.cancel()
            }
        }
    }

    private func run(
        source: ChecklistReportSource,
        options: ChecklistReportRenderOptions,
        destination: URL,
        flag: CancelFlag,
        screen: ScreenGate
    ) async {
        defer {
            isGenerating = false
            task = nil
        }
        do {
            let snapshot = try await Task.detached {
                try ChecklistReportSnapshotBuilder.make(from: source, isCancelled: { flag.isCancelled })
            }.value
            if flag.isCancelled || !screen.isOpen {
                throw ChecklistReportPDFError.cancelled
            }
            phaseText = "Создаём PDF…"
            try await Task.detached {
                try ChecklistReportPDFRenderer.render(
                    snapshot,
                    options: options,
                    to: destination,
                    isCancelled: { flag.isCancelled }
                )
            }.value
            if flag.isCancelled || !screen.isOpen {
                ChecklistReportExportFile.remove(destination)
                return
            }
            ownedURL = destination
            partialWarning = snapshot.packs.contains { $0.readState == .unreadable }
            showPreview = true
        } catch {
            ChecklistReportExportFile.remove(destination)
            if screen.isOpen, let message = ChecklistReportExportMessage.text(for: error) {
                errorText = message
            }
        }
    }

    private func cancelGeneration() {
        cancelFlag.cancel()
        task?.cancel()
    }

    private func closeScreen() {
        screen.close()
        cancelFlag.cancel()
        task?.cancel()
        guard !shareOpen else { return }
        ChecklistReportExportFile.remove(ownedURL)
        ownedURL = nil
    }

    private func shareDidDismiss() {
        shareOpen = false
        guard !screen.isOpen else { return }
        ChecklistReportExportFile.remove(ownedURL)
        ownedURL = nil
    }
}

private struct ChecklistReportPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displayBox = .mediaBox
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard uiView.document?.documentURL != url else { return }
        uiView.document = PDFDocument(url: url)
        uiView.autoScales = true
    }
}

private struct ChecklistReportShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> ChecklistReportShareHost {
        let host = ChecklistReportShareHost()
        host.fileURL = url
        host.onFinish = context.coordinator.onFinish
        return host
    }

    func updateUIViewController(_ host: ChecklistReportShareHost, context: Context) {
        host.fileURL = url
        host.onFinish = context.coordinator.onFinish
    }

    final class Coordinator {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    }
}

final class ChecklistReportShareHost: UIViewController {
    var fileURL: URL?
    var onFinish: (() -> Void)?
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started, let fileURL else { return }
        started = true
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        checklistReportConfigurePopover(activity, sourceView: view)
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            DispatchQueue.main.async {
                self?.onFinish?()
            }
        }
        present(activity, animated: true)
    }
}

final class CancelFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func cancel() {
        state.withLock { $0 = true }
    }

    var isCancelled: Bool {
        state.withLock { $0 }
    }
}

final class ScreenGate: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: true)

    func close() {
        state.withLock { $0 = false }
    }

    var isOpen: Bool {
        state.withLock { $0 }
    }
}
