import SwiftUI
import UIKit

/// Экран «Сроки проекта» — только таймлайн этапов.
struct ProjectPlanView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var editingStage: Stage?
    @State private var completingStage: Stage?
    @State private var delayStage: Stage?          // выбор / правка причины просрочки

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    private var project: Project? {
        store.projects.first(where: { $0.id == projectID })
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let project {
                content(for: project)
            } else {
                VStack(spacing: 12) {
                    Text("Проект не найден")
                        .font(.headline)
                    Text("Возможно, он был удалён или ещё не успел загрузиться.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationTitle("Сроки")
        .navigationBarTitleDisplayMode(.inline)

        // Paywall
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }

        // Read-only alert
        .alert("Режим только просмотр", isPresented: $showReadOnlyAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Разблокировать") {
                Task {
                    _ = await store.refreshRoleForCurrentUser()
                    if store.isReadOnlyMode {
                        showPaywall = true
                    }
                }
            }
        } message: {
            Text("Сейчас активен режим просмотра. Для изменения сроков, факта выполнения и причин просрочек нужна подписка USER или PRO.")
        }
    }

    @ViewBuilder
    private func content(for project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ✅ Баннер read-only (эталонный UX для экрана “Сроки”)
                if store.isReadOnlyMode {
                    readOnlyBanner
                }

                // Шапка проекта
                projectHeader(project)

                // Таймлайн этапов
                VStack(alignment: .leading, spacing: 12) {
                    timelineSection(for: project)
                }
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding()
        }
        // Редактирование плановых дат
        .sheet(item: $editingStage) { stage in
            StageScheduleEditView(projectID: project.id, stage: stage)
                .environmentObject(store)
        }
        // Факт завершения
        .sheet(item: $completingStage) { stage in
            StageCompleteView(
                projectID: project.id,
                stage: stage,
                onCompleted: { actualStart, actualEnd in
                    handleStageCompleted(stage: stage, actualStart: actualStart, actualEnd: actualEnd)
                }
            )
            .environmentObject(store)
        }
        // Причина просрочки (можно открыть как после завершения, так и вручную)
        .sheet(item: $delayStage) { stage in
            StageDelayReasonView(projectID: project.id, stage: stage)
                .environmentObject(store)
        }
    }

    private var readOnlyBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Режим только просмотр")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Сейчас активен режим просмотра. Чтобы менять сроки, фиксировать факт и указывать причины задержек, нужна подписка USER или PRO.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    _ = await store.refreshRoleForCurrentUser()
                    if store.isReadOnlyMode {
                        showPaywall = true
                    }
                }
            } label: {
                Text("Разблокировать")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Header

    @ViewBuilder
    private func projectHeader(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.title3.weight(.semibold))

            if !project.address.isEmpty {
                Text(project.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let start = project.dateStart, let end = project.dateEnd {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(dateRangeString(start: start, end: end))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let end = project.dateEnd {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.caption)
                    Text("Дедлайн: \(dateFormatter.string(from: end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timelineSection(for project: Project) -> some View {
        if project.stages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Этапы пока не настроены")
                    .font(.headline)
                Text("Этапы загружены из базового шаблона. Позже здесь появится таймлайн с датами и причинами просрочек.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Этапы и сроки")
                    .font(.headline)

                Text("Тап по карточке — плановые сроки. «Завершить» — факт выполнения. Для просроченных этапов можно указать причину задержки.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(project.stages) { stage in
                    StageTimelineRow(
                        stage: stage,
                        onTap: { requestPlannedDatesEdit(stage) },
                        onComplete: { requestComplete(stage) },
                        onDelay: { requestDelayReason(stage) }
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    private func requestPlannedDatesEdit(_ stage: Stage) {
        guard !store.isReadOnlyMode else {
            showReadOnlyAlert = true
            return
        }
        editingStage = stage
    }

    private func requestComplete(_ stage: Stage) {
        guard !store.isReadOnlyMode else {
            showReadOnlyAlert = true
            return
        }
        completingStage = stage
    }

    private func requestDelayReason(_ stage: Stage) {
        guard !store.isReadOnlyMode else {
            showReadOnlyAlert = true
            return
        }
        delayStage = stage
    }

    // MARK: - Completion handler

    /// Вызывается после сохранения фактических дат.
    /// Если завершили позже дедлайна — открываем экран причины.
    private func handleStageCompleted(stage: Stage, actualStart: Date, actualEnd: Date) {
        guard let plannedEnd = stage.plannedEnd else { return }

        // Завершён позже плановой даты окончания → просрочка
        if actualEnd > plannedEnd {
            delayStage = stage
        }
    }

    // MARK: - Date helpers

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    private func dateRangeString(start: Date, end: Date) -> String {
        let s = dateFormatter.string(from: start)
        let e = dateFormatter.string(from: end)
        return "\(s) — \(e)"
    }
}

// MARK: - StageTimelineRow

private struct StageTimelineRow: View {
    let stage: Stage
    let onTap: (() -> Void)?
    let onComplete: (() -> Void)?
    let onDelay: (() -> Void)?

    init(
        stage: Stage,
        onTap: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil,
        onDelay: (() -> Void)? = nil
    ) {
        self.stage = stage
        self.onTap = onTap
        self.onComplete = onComplete
        self.onDelay = onDelay
    }

    // MARK: - Computed props

    private var statusText: String {
        switch stage.status {
        case .notStarted:        return "Не начат"
        case .inProgress:        return "В работе"
        case .completed:         return "Завершён"
        case .completedDelayed:  return "С просрочкой"
        case .delayed:           return "Просрочен"
        }
    }

    private var statusColor: Color {
        switch stage.status {
        case .completed:
            return Color(.systemGreen)

        case .completedDelayed:
            if stage.delayReason != nil {
                return Color(.systemOrange)
            } else {
                return Color(.systemRed)
            }

        case .delayed:
            return Color(.systemRed)

        case .inProgress:
            return Color(.systemBlue)

        case .notStarted:
            return Color(.systemGray3)
        }
    }

    private var completionInfo: (text: String, color: Color)? {
        guard let actualEnd = stage.actualEnd else { return nil }

        let dateString = Self.df.string(from: actualEnd)

        if let plannedEnd = stage.plannedEnd {
            if actualEnd < plannedEnd {
                return ("Завершён раньше срока: \(dateString)", Color(.systemGreen))
            } else if actualEnd > plannedEnd {
                return ("Завершён позже срока: \(dateString)", Color(.systemRed))
            } else {
                return ("Завершён в срок: \(dateString)", Color.secondary)
            }
        } else {
            return ("Завершён: \(dateString)", Color.secondary)
        }
    }

    private var datesText: String {
        if let s = stage.plannedStart, let e = stage.plannedEnd {
            "\(Self.df.string(from: s)) — \(Self.df.string(from: e))"
        } else if let e = stage.plannedEnd {
            "Дедлайн: \(Self.df.string(from: e))"
        } else {
            "Плановые даты не заданы"
        }
    }

    private var delayReasonText: String? {
        guard let r = stage.delayReason else { return nil }
        if let c = stage.delayComment, !c.isEmpty {
            return "\(r.title): \(c)"
        } else {
            return r.title
        }
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            VStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Rectangle()
                    .fill(Color(.systemGray4).opacity(0.6))
                    .frame(width: 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stage.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Spacer()

                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(statusColor.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(statusColor.opacity(0.5), lineWidth: 0.8)
                        )
                }

                if let subtitle = stage.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(datesText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let info = completionInfo {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.caption)
                            .foregroundColor(info.color)
                        Text(info.text)
                            .font(.caption2)
                            .foregroundColor(info.color)
                    }
                }

                if !stage.items.isEmpty {
                    ProgressView(value: stage.progress)
                        .progressViewStyle(.linear)
                        .tint(statusColor)
                }

                if let delay = delayReasonText {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(delay)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Button(action: { onTap?() }) {
                        Label("Плановые даты", systemImage: "calendar.badge.clock")
                            .font(.caption2)
                    }

                    Spacer()

                    Button(action: { onComplete?() }) {
                        if stage.status == .completed || stage.status == .completedDelayed {
                            Label("Изменить факт", systemImage: "pencil.circle.fill")
                                .font(.caption2.weight(.semibold))
                        } else {
                            Label("Завершить", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stage.status == .completed || stage.status == .completedDelayed ? .blue : .green)
                }
                .padding(.top, 4)

                if stage.isOverdue || stage.delayReason != nil {
                    Button(action: { onDelay?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.caption2)
                            Text(stage.delayReason == nil ? "Указать причину просрочки" : "Изменить причину просрочки")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(backgroundColor)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private var backgroundColor: Color {
        switch stage.status {
        case .completedDelayed:
            if stage.delayReason != nil {
                return Color(.systemOrange).opacity(0.06)
            } else {
                return Color(.systemRed).opacity(0.06)
            }
        case .delayed:
            return Color(.systemRed).opacity(0.06)
        default:
            return Color(.secondarySystemBackground)
        }
    }
}
