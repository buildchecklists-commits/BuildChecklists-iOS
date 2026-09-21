import SwiftUI

/// Универсальный экран деталки этапа + прогресс.
/// При любом изменении вызывает onStageChanged()
struct StageDetailView2: View {
    @EnvironmentObject private var store: AppStore

    @Binding var stage: Stage
    let project: Project
    var onStageChanged: () -> Void = {}

    // InfoSheet
    @State private var infoSlugToShow: String? = nil
    @State private var showInfo: Bool = false

    // Подтверждения
    @State private var showDeletePhotosConfirm = false
    @State private var showMarkAllDoneConfirm = false
    @State private var showResetProgressConfirm = false
    @State private var showResetWithIssuesConfirm = false
    @State private var showMarkAllResult = false
    @State private var markAllResultMessage = ""

    // Paywall
    @State private var showPaywall: Bool = false

    // MediaService
    private let media = MediaService()

    private var isLocked: Bool {
        store.isReadOnlyMode
    }

    private var progress: Double {
        let total = max(stage.items.count, 1)
        let done = stage.items.filter { $0.status == .ok }.count
        return Double(done) / Double(total)
    }

    var body: some View {
        VStack(spacing: 0) {

            if isLocked {
                readOnlyBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            List {
                // Прогресс
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress)
                            .tint(Color("AccentYellow"))
                        Text("\(Int(progress * 100))% выполнено")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Пункты
                Section {
                    ForEach(stage.items.indices, id: \.self) { j in
                        ChecklistItemRow2(item: $stage.items[j]) { slug in
                            infoSlugToShow = slug
                            showInfo = true
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(stage.title)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isLocked)
        }
        .background(Color("CardBG"))

        // Сохранение
        .onChange(of: stage) { _, _ in
            onStageChanged()
            NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
        }
        .onDisappear {
            onStageChanged()
            NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
        }

        // Toolbar
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showMarkAllDoneConfirm = true
                    } label: {
                        Label("Отметить все пункты как выполненные", systemImage: "checkmark.circle")
                    }
                    .disabled(isLocked)

                    Button {
                        if ChecklistStageBulkActions.issueCount(in: stage.items) > 0 {
                            showResetWithIssuesConfirm = true
                        } else {
                            showResetProgressConfirm = true
                        }
                    } label: {
                        Label("Сбросить прогресс этапа", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(isLocked)

                    Divider()

                    Button(role: .destructive) {
                        showDeletePhotosConfirm = true
                    } label: {
                        Label("Удалить все фото этапа", systemImage: "trash")
                    }
                    .disabled(isLocked)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .opacity(isLocked ? 0.35 : 1)
                }
                .disabled(isLocked)
            }
        }

        // Info
        .sheet(isPresented: $showInfo) {
            if let slug = infoSlugToShow, !slug.isEmpty {
                InfoSheetView(slug: slug)
            } else {
                Text("Информация недоступна").padding()
            }
        }

        // Paywall
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }

        // Алерты
        .alert("Отметить все как выполненные?", isPresented: $showMarkAllDoneConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Отметить") {
                applyMarkAllDone()
            }
        } message: {
            if ChecklistStageBulkActions.issueCount(in: stage.items) > 0 {
                Text("Пункты без замечаний будут отмечены как выполненные. Замечания не изменятся.")
            }
        }

        .alert("Готово", isPresented: $showMarkAllResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(markAllResultMessage)
        }

        .alert("Сбросить прогресс этапа?", isPresented: $showResetProgressConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Сбросить", role: .destructive) {
                resetStageProgress()
            }
        }

        .alert("Сбросить прогресс этапа?", isPresented: $showResetWithIssuesConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Сбросить всё", role: .destructive) {
                resetStageProgress()
            }
        } message: {
            Text(resetWithIssuesMessage)
        }

        .alert("Удалить все фото?", isPresented: $showDeletePhotosConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                deleteAllStagePhotos()
            }
        }
    }

    // MARK: - Read-only banner

    private var readOnlyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Режим только просмотр")
                    .font(.subheadline.weight(.semibold))
                Text("Редактирование доступно при активной подписке.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showPaywall = true
            } label: {
                Text("Разблокировать")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color("BrandSeparator"), lineWidth: 1)
        }
    }

    // MARK: - Actions

    private var resetWithIssuesMessage: String {
        let count = ChecklistStageBulkActions.issueCount(in: stage.items)
        let phrase = ChecklistStageBulkActions.russianRemarksPhrase(count)
        return "Будут сняты все отметки этого блока, включая \(phrase). Отметки «Проблема» будут сняты. Это нельзя отменить."
    }

    private func applyMarkAllDone() {
        guard !isLocked else { return }
        let result = ChecklistStageBulkActions.markAllDone(items: &stage.items)
        markAllResultMessage = result.userMessage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showMarkAllResult = true
        }
    }

    private func resetStageProgress() {
        guard !isLocked else { return }
        ChecklistStageBulkActions.resetAllToNA(items: &stage.items)
    }

    private func deleteAllStagePhotos() {
        guard !isLocked else { return }
        for idx in stage.items.indices {
            let paths = stage.items[idx].photoPaths
            for path in paths {
                try? media.deleteFile(at: path)
            }
            stage.items[idx].photoPaths.removeAll()
        }
    }
}

// MARK: - Bulk actions (ProgressStore items only)

enum ChecklistStageBulkActions {
    struct MarkAllResult: Equatable {
        let newlyMarked: Int
        let preservedIssues: Int
        let total: Int

        var userMessage: String {
            if total == 0 {
                return "Нет пунктов в этом блоке."
            }
            if newlyMarked > 0 {
                return "Отмечено выполненными: \(newlyMarked). Замечания сохранены: \(preservedIssues)."
            }
            if preservedIssues == total {
                return "Нет пунктов для отметки. Замечания сохранены: \(preservedIssues)."
            }
            if preservedIssues > 0 {
                return "Все пункты без замечаний уже выполнены. Замечания сохранены: \(preservedIssues)."
            }
            return "Все пункты уже отмечены выполненными."
        }
    }

    static func issueCount(in items: [StageItem]) -> Int {
        items.filter { $0.status == .issue }.count
    }

    @discardableResult
    static func markAllDone(items: inout [StageItem]) -> MarkAllResult {
        var newlyMarked = 0
        var preservedIssues = 0
        for idx in items.indices {
            if items[idx].status == .issue {
                preservedIssues += 1
                continue
            }
            if items[idx].status != .ok {
                newlyMarked += 1
            }
            items[idx].status = .ok
        }
        return MarkAllResult(
            newlyMarked: newlyMarked,
            preservedIssues: preservedIssues,
            total: items.count
        )
    }

    static func resetAllToNA(items: inout [StageItem]) {
        for idx in items.indices {
            items[idx].status = .na
        }
    }

    static func russianRemarksPhrase(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        let word: String
        if (11...14).contains(mod100) {
            word = "замечаний"
        } else if mod10 == 1 {
            word = "замечание"
        } else if (2...4).contains(mod10) {
            word = "замечания"
        } else {
            word = "замечаний"
        }
        return "\(count) \(word)"
    }
}
