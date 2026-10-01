import os
import PDFKit
import SwiftUI
import UIKit

/// New report setup. Checklist export stays on `ChecklistReportExportView`.
struct ReportExportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let projectID: UUID

    @State private var variant: ReportVariant = .ownerSummary
    @State private var audienceChoice: ReportAudienceChoice = .owner
    @State private var periodMode: ReportPeriodMode = .off
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var allStages = true
    @State private var selectedStages = Set(GlobalStageCategory.allCases)
    @State private var includeChecklists = true
    @State private var includeExpenses = true
    @State private var includeIssues = true
    @State private var includeTasks = false
    @State private var includeContacts = false
    @State private var includeComments = true
    @State private var includeCharts = true

    @State private var prepared: PreparedReport?
    @State private var prepareID = 0
    @State private var prepareTask: Task<Void, Never>?
    @State private var isPreparing = false
    @State private var isGenerating = false
    @State private var errorText: String?
    @State private var showPreview = false
    @State private var task: Task<Void, Never>?
    @State private var cancelFlag = CancelFlag()
    @State private var session = ReportFileSession()

    private var project: Project? {
        store.projects.first { $0.id == projectID }
    }

    private var planFactAvailable: Bool {
        prepared.map { Self.containsPlanFact($0.snapshot) } ?? false
    }

    var body: some View {
        Group {
            if showPreview, let ownedURL = session.ownedURL {
                preview(url: ownedURL)
            } else {
                settings
            }
        }
        .onAppear {
            session.reopen()
            refreshEstimate()
        }
        .onChange(of: selectionKey) { _, _ in
            errorText = nil
            refreshEstimate()
        }
        .onDisappear(perform: closeScreen)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            Form {
                if project != nil {
                    variantSection
                    if variant == .checklists {
                        checklistSection
                    } else {
                        optionsSection
                        compositionSection
                    }
                } else {
                    Text("Проект не найден")
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
            .contentMargins(.bottom, 28, for: .scrollContent)
            .clipped()
            if variant != .checklists, project != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let errorText {
                        Text(errorText)
                            .font(.body)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("project.reports.error")
                            .accessibilityLabel(errorText)
                    }
                    generationBar
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Отчёты")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("project.reports.title")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Назад") { dismiss() }
                    .accessibilityLabel("Назад")
                    .accessibilityIdentifier("project.reports.back")
            }
        }
    }

    private var variantSection: some View {
        Section {
            ForEach(visibleVariants) { item in
                HStack(alignment: .center, spacing: 8) {
                    UnbrokenText(
                        text: item.title,
                        textStyle: .body,
                        weight: variant == item ? .semibold : .regular,
                        maxLines: 3
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    if variant == item {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                    .contentShape(Rectangle())
                    .onTapGesture { variant = item }
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("project.reports.variant")
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(variant == item ? .isSelected : [])
                    .accessibilityRemoveTraits(variant == item ? [] : .isSelected)
            }

            if prepared != nil, !planFactAvailable {
                UnbrokenText(
                    text: "Для отчёта «План/факт» нужны план, расходы или даты этапов.",
                    textStyle: .footnote,
                    color: .secondary,
                    maxLines: 4
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Для отчёта «План/факт» нужны план, расходы или даты этапов.")
                .accessibilityIdentifier("project.reports.planFactUnavailable")
            }
        } header: {
            ReportSectionHeader(title: "Отчёт")
        }
        .onChange(of: planFactAvailable) { _, available in
            if !available, variant == .planFact {
                variant = .ownerSummary
            }
        }
    }

    private var checklistSection: some View {
        Section {
            NavigationLink {
                ChecklistReportExportView(projectID: projectID)
            } label: {
                Text("Открыть отчёт по чек-листам")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("project.reports.checklist")
            Text("Это текущий отчёт по рабочим чек-листам.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        if variant != .customer {
            Section {
                ReportAdaptiveChoice(
                    title: "Аудитория",
                    selection: $audienceChoice,
                    options: ReportAudienceChoice.allCases.map { ($0, $0.title) },
                    identifier: "project.reports.audience"
                )
            } header: {
                ReportSectionHeader(title: "Аудитория")
            }
        } else {
            Section {
                ReportAdaptiveValue(title: "Аудитория", identifier: "project.reports.audience", valueLabel: "Аудитория: заказчик") {
                    Text("Заказчик")
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                }
            } header: {
                ReportSectionHeader(title: "Аудитория")
            }
        }

        Section {
            ReportAdaptiveChoice(
                title: "Период расходов",
                selection: $periodMode,
                options: ReportPeriodMode.allCases.map { ($0, $0.title) },
                identifier: "project.reports.period"
            )
            if periodMode == .from || periodMode == .both {
                ReportAdaptiveDate(title: "От", date: $dateFrom, identifier: "project.reports.dateFrom")
            }
            if periodMode == .to || periodMode == .both {
                ReportAdaptiveDate(title: "До", date: $dateTo, identifier: "project.reports.dateTo")
            }
            if periodMode == .to || periodMode == .both {
                UnbrokenText(
                    text: "Выбранный день «до» входит в отчёт целиком.",
                    textStyle: .footnote,
                    color: .secondary,
                    maxLines: 3
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Выбранный день «до» входит в отчёт целиком.")
            }
        } header: {
            ReportSectionHeader(title: "Период расходов")
        }

        Section {
            ReportAdaptiveToggle(title: "Все этапы", isOn: $allStages, identifier: "project.reports.allStages")
            if !allStages {
                ForEach(GlobalStageCategory.allCases) { stage in
                    ReportAdaptiveToggle(
                        title: stage.title,
                        isOn: stageBinding(stage),
                        identifier: "project.reports.stage.\(stage.rawValue)"
                    )
                }
                if selectedStages.isEmpty {
                    Text("Не выбран ни один этап.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if variant == .ownerSummary || variant == .customer || variant == .planFact {
                UnbrokenText(
                    text: "Сроки проекта этим списком не фильтруются.",
                    textStyle: .footnote,
                    color: .secondary,
                    maxLines: 4
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Сроки проекта этим списком не фильтруются.")
            }
        } header: {
            ReportSectionHeader(title: "Этапы")
        }

        Section {
            if showsChecklistToggle {
                ReportAdaptiveToggle(title: "Чек-листы", isOn: $includeChecklists, identifier: "project.reports.checklists")
            }
            if showsExpenseToggle {
                ReportAdaptiveToggle(title: "Расходы", isOn: $includeExpenses, identifier: "project.reports.expenses")
            }
            if showsIssueToggle {
                ReportAdaptiveToggle(title: "Замечания", isOn: $includeIssues, identifier: "project.reports.issues")
            }
            if showsTaskToggle {
                ReportAdaptiveToggle(title: "Задачи", isOn: $includeTasks, identifier: "project.reports.tasks")
            }
            if showsContactToggle {
                ReportAdaptiveToggle(title: "Контакты", isOn: $includeContacts, identifier: "project.reports.contacts")
            }
            if showsCommentToggle {
                ReportAdaptiveToggle(title: "Комментарии", isOn: $includeComments, identifier: "project.reports.comments")
            }
            ReportAdaptiveToggle(title: "Графики", isOn: $includeCharts, identifier: "project.reports.charts")
        } header: {
            ReportSectionHeader(title: "Разделы")
        }
    }

    private var compositionSection: some View {
        Section {
            if let composition = prepared?.snapshot.composition {
                UnbrokenText(
                    text: Self.compositionSpeech(composition).replacingOccurrences(of: ", ", with: "\n"),
                    textStyle: .body,
                    maxLines: 8
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.compositionSpeech(composition))
                    .accessibilityIdentifier("project.reports.composition")
            } else if isPreparing {
                Text("Считаем состав…")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("project.reports.composition")
            }
        } header: {
            ReportSectionHeader(title: "Состав")
        }
    }

    private static func compositionSpeech(_ composition: ProjectReportComposition) -> String {
        [
            "Пакетов с данными: \(composition.packsWithData)",
            "Замечаний: \(composition.issueCount)",
            "Операций: \(composition.operationCount)",
            "План: \(composition.hasPlan ? "есть" : "нет")",
            "Даты этапов: \(composition.hasDates ? "есть" : "нет")"
        ].joined(separator: ", ")
    }

    @ViewBuilder
    private var generationBar: some View {
        if isGenerating {
            VStack(spacing: 12) {
                ProgressView()
                Text("Создаём PDF…")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Отмена", action: cancelGeneration)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Отмена")
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("project.reports.progress")
        } else {
            Button(action: startExport) {
                ViewThatFits(in: .horizontal) {
                    Text("Сформировать")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "doc.badge.plus")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(project == nil || task != nil)
            .accessibilityIdentifier("project.reports.generate")
            .accessibilityLabel("Сформировать отчёт")
        }
    }

    private func preview(url: URL) -> some View {
        ReportPDFPreview(url: url)
            .accessibilityIdentifier("project.reports.preview")
            .accessibilityLabel("Просмотр PDF")
            .navigationTitle(variant.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showPreview = false }
                        .accessibilityLabel("Закрыть просмотр")
                }
                ToolbarItem(placement: .primaryAction) {
                    ReportSendButton(url: url, session: session)
                }
            }
    }

    private var visibleVariants: [ReportVariant] {
        ReportVariant.allCases.filter { item in
            item != .planFact || planFactAvailable
        }
    }

    private var selectionKey: ReportSelectionKey {
        ReportSelectionKey(request: currentRequest(generatedAt: Date(timeIntervalSince1970: 0)))
    }

    private var showsChecklistToggle: Bool {
        variant == .ownerSummary || variant == .customer
    }

    private var showsExpenseToggle: Bool {
        variant == .ownerSummary || variant == .customer || variant == .expenses
    }

    private var showsIssueToggle: Bool {
        variant == .ownerSummary && audienceChoice == .owner
    }

    private var showsTaskToggle: Bool {
        variant == .ownerSummary && audienceChoice == .owner
    }

    private var showsContactToggle: Bool {
        variant == .ownerSummary || variant == .customer
    }

    private var showsCommentToggle: Bool {
        switch variant {
        case .ownerSummary:
            return audienceChoice == .owner
        case .expenses:
            return audienceChoice == .owner
        default:
            return false
        }
    }

    private func stageBinding(_ stage: GlobalStageCategory) -> Binding<Bool> {
        Binding(
            get: { selectedStages.contains(stage) },
            set: { isOn in
                if isOn {
                    selectedStages.insert(stage)
                } else {
                    selectedStages.remove(stage)
                }
            }
        )
    }

    private func currentRequest(generatedAt: Date) -> ProjectReportRequest {
        if variant == .checklists {
            return ProjectReportRequest(
                audience: .owner,
                sections: .ownerDefault,
                generatedAt: generatedAt
            )
        }
        let audience = variant == .customer ? ProjectReportAudience.customer : audienceChoice.audience
        var sections = ProjectReportSections(
            checklists: includeChecklists,
            expenses: includeExpenses,
            issues: includeIssues,
            tasks: includeTasks,
            contacts: includeContacts,
            paymentComments: includeComments
        )
        if audience == .customer {
            sections.issues = false
            sections.tasks = false
            sections.paymentComments = false
        }
        switch variant {
        case .expenses:
            sections.checklists = false
            sections.issues = false
            sections.tasks = false
            sections.contacts = false
        case .planFact:
            sections.checklists = false
            sections.issues = false
            sections.tasks = false
            sections.contacts = false
            sections.expenses = true
            sections.paymentComments = false
        default:
            break
        }
        return ProjectReportRequest(
            audience: audience,
            dateFrom: activeDateFrom,
            dateTo: activeDateTo,
            stages: allStages ? nil : selectedStages,
            sections: sections,
            generatedAt: generatedAt
        )
    }

    private var activeDateFrom: Date? {
        switch periodMode {
        case .off, .to:
            return nil
        case .from, .both:
            return dateFrom
        }
    }

    private var activeDateTo: Date? {
        switch periodMode {
        case .off, .from:
            return nil
        case .to, .both:
            return dateTo
        }
    }

    private func refreshEstimate() {
        guard !isGenerating, let project else { return }
        prepareID += 1
        let token = prepareID
        let request = currentRequest(generatedAt: Date())
        let expenses = store.expenses(for: project.id)
        let tasks = store.tasks(for: project.id)
        isPreparing = true
        prepareTask?.cancel()
        prepareTask = Task {
            let outcome = await Self.loadSnapshot(
                project: project,
                expenses: expenses,
                tasks: tasks,
                request: request
            )
            guard !Task.isCancelled, token == prepareID, !isGenerating else { return }
            isPreparing = false
            switch outcome {
            case .success(let snapshot):
                prepared = PreparedReport(request: request, snapshot: snapshot)
                if variant == .planFact, !Self.containsPlanFact(snapshot) {
                    variant = .ownerSummary
                }
            case .failure(let error):
                prepared = nil
                if let message = Self.message(for: error) {
                    errorText = message
                }
            }
        }
    }

    private func startExport() {
        guard task == nil, !isGenerating, !session.shareOpen, variant != .checklists, let project else { return }
        errorText = nil
        showPreview = false
        let flag = CancelFlag()
        cancelFlag = flag
        let request: ProjectReportRequest
        let knownSnapshot: ProjectReportSnapshot?
        if let prepared, Self.sameSelection(prepared.request, currentRequest(generatedAt: prepared.request.generatedAt)) {
            request = prepared.request
            knownSnapshot = prepared.snapshot
        } else {
            request = currentRequest(generatedAt: Date())
            knownSnapshot = nil
        }
        let expenses = store.expenses(for: project.id)
        let tasksForProject = store.tasks(for: project.id)
        let destination = ProjectReportExportFile.makeURL(projectName: project.name)
        session.claim(destination)
        isGenerating = true
        prepareTask?.cancel()
        let charts = includeCharts
        let selectedVariant = variant
        let session = session
        task = Task {
            await withTaskCancellationHandler {
                await run(
                    project: project,
                    expenses: expenses,
                    tasks: tasksForProject,
                    request: request,
                    knownSnapshot: knownSnapshot,
                    variant: selectedVariant,
                    includeCharts: charts,
                    destination: destination,
                    flag: flag,
                    session: session
                )
            } onCancel: {
                flag.cancel()
            }
        }
    }

    private func run(
        project: Project,
        expenses: [ExpenseItem],
        tasks: [TaskItem],
        request: ProjectReportRequest,
        knownSnapshot: ProjectReportSnapshot?,
        variant: ReportVariant,
        includeCharts: Bool,
        destination: URL,
        flag: CancelFlag,
        session: ReportFileSession
    ) async {
        defer {
            isGenerating = false
            task = nil
        }
        do {
            let snapshot: ProjectReportSnapshot
            if let knownSnapshot {
                snapshot = knownSnapshot
            } else {
                let loaded = await Self.loadSnapshot(
                    project: project,
                    expenses: expenses,
                    tasks: tasks,
                    request: request
                )
                snapshot = try loaded.get()
            }
            if flag.isCancelled || !session.isOpen {
                session.discard(destination)
                return
            }
            let outcome = ReportExportRendering.make(
                variant: variant,
                snapshot: snapshot,
                includeCharts: includeCharts
            )
            if flag.isCancelled || !session.isOpen {
                session.discard(destination)
                return
            }
            switch outcome {
            case .pdf(let data):
                guard !data.isEmpty else {
                    session.discard(destination)
                    if session.isOpen {
                        errorText = ChecklistReportExportMessage.createPDF
                    }
                    return
                }
                do {
                    try data.write(to: destination, options: .atomic)
                } catch {
                    session.discard(destination)
                    if session.isOpen {
                        errorText = ChecklistReportExportMessage.createPDF
                    }
                    return
                }
                if flag.isCancelled || !session.isOpen {
                    session.discard(destination)
                    return
                }
                prepared = PreparedReport(request: request, snapshot: snapshot)
                session.keep(destination)
                showPreview = true
            case .noContent(let reason):
                session.discard(destination)
                prepared = PreparedReport(request: request, snapshot: snapshot)
                if session.isOpen {
                    errorText = reason
                }
            }
        } catch {
            session.discard(destination)
            if session.isOpen, let message = Self.message(for: error) {
                errorText = message
            }
        }
    }

    private func cancelGeneration() {
        cancelFlag.cancel()
        task?.cancel()
    }

    private func closeScreen() {
        cancelFlag.cancel()
        task?.cancel()
        prepareTask?.cancel()
        session.closeScreen()
    }

    private static func containsPlanFact(_ snapshot: ProjectReportSnapshot) -> Bool {
        let money = snapshot.moneyRows.contains { $0.plan != 0 || $0.fact != 0 }
        let dates = snapshot.schedule.contains(where: \.hasAnyDate)
        return money || dates
    }

    private static func sameSelection(_ stored: ProjectReportRequest, _ current: ProjectReportRequest) -> Bool {
        stored.audience == current.audience
            && stored.dateFrom == current.dateFrom
            && stored.dateTo == current.dateTo
            && stored.stages == current.stages
            && stored.expenseTypes == current.expenseTypes
            && stored.sections == current.sections
    }

    private static func loadSnapshot(
        project: Project,
        expenses: [ExpenseItem],
        tasks: [TaskItem],
        request: ProjectReportRequest
    ) async -> Result<ProjectReportSnapshot, Error> {
        await Task.detached {
            do {
                let snapshot = try ProjectReportSnapshotBuilder.read(
                    project: project,
                    expenses: expenses,
                    tasks: tasks,
                    request: request
                )
                return .success(snapshot)
            } catch {
                return .failure(error)
            }
        }.value
    }

    private static func message(for error: Error) -> String? {
        if error is CancellationError { return nil }
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return ChecklistReportExportMessage.prepareData
    }
}

private struct ReportSectionHeader: View {
    let title: String

    var body: some View {
        UnbrokenText(
            text: title,
            textStyle: .footnote,
            color: .secondary,
            maxLines: 2
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Owns the temporary PDF for one report screen, including after the view is gone.
private final class ReportFileSession: @unchecked Sendable {
    private struct State {
        var isOpen = true
        var shareOpen = false
        var ownedURL: URL?
        var inflightURL: URL?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var isOpen: Bool {
        state.withLock { $0.isOpen }
    }

    var shareOpen: Bool {
        state.withLock { $0.shareOpen }
    }

    var ownedURL: URL? {
        state.withLock { $0.ownedURL }
    }

    func claim(_ destination: URL) {
        state.withLock { state in
            if !state.shareOpen {
                let previous = state.ownedURL
                state.ownedURL = nil
                if let previous {
                    ProjectReportExportFile.remove(previous)
                }
            }
            state.inflightURL = destination
        }
    }

    func keep(_ destination: URL) {
        state.withLock { state in
            if state.inflightURL == destination {
                state.inflightURL = nil
            }
            state.ownedURL = destination
        }
    }

    func discard(_ destination: URL) {
        state.withLock { state in
            if state.inflightURL == destination {
                state.inflightURL = nil
            }
            if state.ownedURL == destination {
                state.ownedURL = nil
            }
        }
        ProjectReportExportFile.remove(destination)
    }

    func closeScreen() {
        let urls: [URL?] = state.withLock { state in
            state.isOpen = false
            guard !state.shareOpen else { return [nil, nil] }
            let urls = [state.ownedURL, state.inflightURL]
            state.ownedURL = nil
            state.inflightURL = nil
            return urls
        }
        for url in urls {
            ProjectReportExportFile.remove(url)
        }
    }

    func beginShare() {
        state.withLock { $0.shareOpen = true }
    }

    func reopen() {
        state.withLock { $0.isOpen = true }
    }

    func shareDidFinish() {
        let url: URL? = state.withLock { state in
            state.shareOpen = false
            guard !state.isOpen else { return nil }
            let url = state.ownedURL
            state.ownedURL = nil
            return url
        }
        ProjectReportExportFile.remove(url)
    }
}

private struct PreparedReport {
    var request: ProjectReportRequest
    var snapshot: ProjectReportSnapshot
}

private struct ReportSelectionKey: Equatable {
    var request: ProjectReportRequest
}

private struct ReportAdaptiveChoice<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]
    var identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var valueTitle: String {
        options.first { $0.0 == selection }?.1 ?? ""
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    menu
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    menu
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menu: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.0
                } label: {
                    if option.0 == selection {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            Text(valueTitle)
                .font(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("\(title): \(valueTitle)")
        .accessibilityIdentifier(identifier)
    }
}

private struct ReportAdaptiveValue<Value: View>: View {
    let title: String
    var identifier: String
    var valueLabel: String
    @ViewBuilder var value: () -> Value
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    value()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    value()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(valueLabel)
        .accessibilityIdentifier(identifier)
    }
}

private struct ReportAdaptiveDate: View {
    let title: String
    @Binding var date: Date
    var identifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var spoken: String {
        date.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    dateControl
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    dateControl
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateControl: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(spoken)
                    .font(.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 4)
                    .background(Color(.secondarySystemGroupedBackground))
                    .allowsHitTesting(false)
                    .background {
                        DatePicker(selection: $date, displayedComponents: .date) {
                            Text(title)
                        }
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityLabel(title)
                        .accessibilityValue(spoken)
                        .accessibilityIdentifier(identifier)
                    }
                    .accessibilityHidden(true)
            } else {
                DatePicker(selection: $date, displayedComponents: .date) {
                    Text(title)
                }
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityValue(spoken)
                .accessibilityIdentifier(identifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        .clipped()
    }
}

private struct ReportAdaptiveToggle: View {
    let title: String
    @Binding var isOn: Bool
    var identifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.body)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    Toggle(isOn: $isOn) {
                        Text(title)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier)
                }
            } else {
                Toggle(title, isOn: $isOn)
                    .accessibilityIdentifier(identifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private nonisolated enum ReportAudienceChoice: String, CaseIterable, Identifiable, Hashable {
    case owner
    case customer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: return "Владелец"
        case .customer: return "Заказчик"
        }
    }

    var audience: ProjectReportAudience {
        switch self {
        case .owner: return .owner
        case .customer: return .customer
        }
    }
}

private nonisolated enum ReportVariant: String, CaseIterable, Identifiable, Hashable {
    case ownerSummary
    case customer
    case checklists
    case expenses
    case planFact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownerSummary: return "Сводка для владельца"
        case .customer: return "Для заказчика"
        case .checklists: return "Только чек-листы"
        case .expenses: return "Только расходы"
        case .planFact: return "План/факт"
        }
    }
}

private nonisolated enum ReportPeriodMode: String, CaseIterable, Identifiable, Hashable {
    case off
    case from
    case to
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Выключен"
        case .from: return "Только от"
        case .to: return "Только до"
        case .both: return "От и до"
        }
    }
}

private nonisolated enum ReportExportRendering {
    static func make(
        variant: ReportVariant,
        snapshot: ProjectReportSnapshot,
        includeCharts: Bool
    ) -> ReportExportOutcome {
        switch variant {
        case .ownerSummary:
            return .pdf(SummaryReportRenderer.pdfData(for: snapshot, includeCharts: includeCharts))
        case .customer:
            return .pdf(CustomerReportRenderer.pdfData(for: snapshot, includeCharts: includeCharts))
        case .expenses:
            switch ExpensesReportRenderer.render(snapshot, includeCharts: includeCharts) {
            case .pdf(let data):
                return .pdf(data)
            case .noContent:
                return .noContent("В выбранных условиях нет операций. PDF не создан.")
            }
        case .planFact:
            switch PlanFactReportRenderer.render(snapshot, includeCharts: includeCharts) {
            case .pdf(let data):
                return .pdf(data)
            case .noContent:
                return .noContent("Для отчёта нужны план, расходы или даты этапов.")
            }
        case .checklists:
            return .noContent("Отчёт по чек-листам открывается отдельно.")
        }
    }
}

private nonisolated enum ReportExportOutcome {
    case pdf(Data)
    case noContent(String)
}

/// Temporary unified report. The name does not match checklist, expense, or project PDF names.
private nonisolated enum ProjectReportExportFile {
    static func makeURL(projectName: String, now: Date = Date()) -> URL {
        let directory = FileManager.default.temporaryDirectory
        let safe = ChecklistReportExportFile.sanitizedProjectName(projectName)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let stamp = formatter.string(from: now)
        let suffix = String(UUID().uuidString.prefix(8))
        return directory.appendingPathComponent("BC_ProjectReport_\(safe)_\(stamp)_\(suffix).pdf")
    }

    static func remove(_ url: URL?) {
        ChecklistReportExportFile.remove(url)
    }
}

private struct ReportPDFPreview: UIViewRepresentable {
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

/// Share control whose own view is the popover anchor.
private struct ReportSendButton: UIViewRepresentable {
    let url: URL
    let session: ReportFileSession

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.accessibilityLabel = "Отправить отчёт"
        button.accessibilityIdentifier = "project.reports.share"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.send), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.url = url
        context.coordinator.session = session
        context.coordinator.button = button
        button.accessibilityLabel = "Отправить отчёт"
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    final class Coordinator: NSObject {
        var url: URL?
        var session: ReportFileSession?
        weak var button: UIButton?
        private var presented = false

        @objc func send() {
            guard !presented, let url, let session, let button else { return }
            button.window?.layoutIfNeeded()
            button.layoutIfNeeded()
            guard button.bounds.width >= 1, button.bounds.height >= 1 else { return }
            guard let presenter = Self.presenter(from: button), presenter.presentedViewController == nil else { return }
            presented = true
            session.beginShare()
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            checklistReportConfigurePopover(activity, sourceView: button)
            let retainedSession = session
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
                DispatchQueue.main.async {
                    self?.presented = false
                    retainedSession.shareDidFinish()
                }
            }
            presenter.present(activity, animated: true)
        }

        private static func presenter(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            var fallback: UIViewController?
            while let next = responder?.next {
                if let controller = next as? UIViewController {
                    fallback = controller
                    if let navigation = controller as? UINavigationController ?? controller.navigationController {
                        return navigation
                    }
                }
                responder = next
            }
            return fallback
        }
    }
}
