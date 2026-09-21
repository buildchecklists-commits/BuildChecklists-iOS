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
                        showResetProgressConfirm = true
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
            Button("Отметить", role: .destructive) {
                markAllItemsDone()
            }
        }

        .alert("Сбросить прогресс этапа?", isPresented: $showResetProgressConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Сбросить", role: .destructive) {
                resetStageProgress()
            }
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

    private func markAllItemsDone() {
        guard !isLocked else { return }
        for idx in stage.items.indices {
            stage.items[idx].status = .ok
        }
    }

    private func resetStageProgress() {
        guard !isLocked else { return }
        for idx in stage.items.indices {
            stage.items[idx].status = .na
        }
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
