import CryptoKit
import ImageIO
import SwiftUI
import UIKit

nonisolated enum IssueHistoryRead: Sendable {
    case loaded(IssueHistoryDocument)
    case failed(String)
}

nonisolated enum IssueHistoryListRead: Sendable {
    case loaded(IssueHistoryDocument, [UUID: IssueHistoryPhotoSummary])
    case failed(String)
}

/// Read-only photo availability for a closed case card. Does not invent unique missing counts.
nonisolated struct IssueHistoryPhotoSummary: Sendable, Equatable {
    /// Distinct readable photograph digests.
    var availableUniqueCount: Int
    /// True when any event lists at least one photo file name.
    var hasReferences: Bool
    /// True when at least one referenced file could not be read.
    var hasUnavailable: Bool

    var phrase: String {
        if !hasReferences { return "Без фото" }
        if availableUniqueCount == 0 { return "Фото недоступны" }
        if hasUnavailable {
            return "Фото: \(availableUniqueCount). Есть недоступные"
        }
        return "Фото: \(availableUniqueCount)"
    }
}

enum IssueRemarksSection: String, CaseIterable, Identifiable {
    case active
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Активные"
        case .history: return "История"
        }
    }
}

/// Read-only presentation of a history file. Does not call prepare, commit, transfer, or recover.
nonisolated enum IssueHistoryPresentation {
    static func closedCases(in document: IssueHistoryDocument) -> [IssueHistoryCase] {
        document.cases
            .filter { $0.closeKind != nil && $0.closedAt != nil }
            .sorted { lhs, rhs in
                let left = lhs.closedAt ?? .distantPast
                let right = rhs.closedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    static func itemTitle(of item: IssueHistoryCase) -> String {
        let title = item.events.last?.itemTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Без названия" : title
    }

    static func stageTitle(of item: IssueHistoryCase) -> String {
        let title = item.events.last?.stageTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Без названия этапа" : title
    }

    static func photoPhrase(_ summary: IssueHistoryPhotoSummary) -> String {
        summary.phrase
    }

    /// Distinct readable photographs for a case. Same bytes across events count once.
    /// Missing or unreadable files are marked unavailable without inventing a missing count.
    /// Read-only: does not change history files. Safe to call off the main actor.
    static func uniquePhotoSummaries(
        projectID: UUID,
        document: IssueHistoryDocument
    ) -> [UUID: IssueHistoryPhotoSummary] {
        let store = IssueHistoryRuntime.store()
        var result: [UUID: IssueHistoryPhotoSummary] = [:]
        for item in closedCases(in: document) {
            var digests = Set<String>()
            var hasReferences = false
            var hasUnavailable = false
            for event in item.events {
                for name in event.photoFileNames {
                    hasReferences = true
                    do {
                        let data = try store.photoData(
                            projectID: projectID,
                            eventID: event.id,
                            fileName: name
                        )
                        digests.insert(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
                    } catch {
                        hasUnavailable = true
                    }
                }
            }
            result[item.id] = IssueHistoryPhotoSummary(
                availableUniqueCount: digests.count,
                hasReferences: hasReferences,
                hasUnavailable: hasUnavailable
            )
        }
        return result
    }

    /// A pending close is not a closed case. The note appears only when that case is absent from the list.
    static func unfinishedSaveMessage(in document: IssueHistoryDocument) -> String? {
        let closed = Set(closedCases(in: document).map(\.id))
        let hidden = document.pending.contains { operation in
            operation.actionKind == .closed && !closed.contains(operation.caseID)
        }
        guard hidden else { return nil }
        return "Сохранение ещё не завершено. Закрытый случай появится в истории после успешной записи."
    }

    static func discoveryLine(openedAt: Date?) -> String {
        guard let openedAt else { return "Дата обнаружения неизвестна" }
        return "Обнаружено \(dateTime(openedAt))"
    }

    static func closeLine(closedAt: Date) -> String {
        "Закрыто \(dateTime(closedAt))"
    }

    static func transferLine(transferredAt: Date) -> String {
        "Принято в историю \(dateTime(transferredAt))"
    }

    static func eventTitle(_ kind: IssueHistoryEventKind, closeKind: IssueHistoryCloseKind?) -> String {
        switch kind {
        case .opened:
            return "Открыто"
        case .updated:
            return "Изменение"
        case .closed:
            if let closeKind {
                return "Закрыто, \(closeKind.title)"
            }
            return "Закрыто"
        case .transferred:
            return "Принято в историю"
        }
    }

    static func rowAccessibilityLabel(for item: IssueHistoryCase, photos: IssueHistoryPhotoSummary) -> String {
        var parts = [
            itemTitle(of: item),
            stageTitle(of: item),
            item.closeKind?.title ?? "Без состояния"
        ]
        if let closedAt = item.closedAt {
            parts.append(closeLine(closedAt: closedAt))
        }
        if item.previousCaseID != nil {
            parts.append("Повторное замечание")
        }
        parts.append(photoPhrase(photos))
        return parts.joined(separator: ", ")
    }

    static func noteText(_ note: String?) -> String {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Без описания" : (note ?? "")
    }

    static func load(projectID: UUID) -> IssueHistoryRead {
        do {
            return .loaded(try IssueHistoryRuntime.store().load(projectID: projectID))
        } catch let error as IssueHistoryError {
            return .failed(error.message)
        } catch {
            return .failed("Не удалось прочитать историю замечаний.")
        }
    }

    static func loadList(projectID: UUID) -> IssueHistoryListRead {
        switch load(projectID: projectID) {
        case .failed(let message):
            return .failed(message)
        case .loaded(let document):
            return .loaded(document, uniquePhotoSummaries(projectID: projectID, document: document))
        }
    }

    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let identifier = Locale.preferredLanguages.first ?? "ru_RU"
        formatter.locale = Locale(identifier: identifier)
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct IssueRemarksSectionPicker: View {
    @Binding var section: IssueRemarksSection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    choice(.active)
                    choice(.history)
                }
            } else {
                Picker("Раздел замечаний", selection: $section) {
                    ForEach(IssueRemarksSection.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("project.issues.sectionPicker")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func choice(_ item: IssueRemarksSection) -> some View {
        let selected = section == item
        return Button {
            section = item
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .background(selected ? ProjectUXColors.accentAction.opacity(0.18) : ProjectUXColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "\(item.title), выбрано" : item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("project.issues.section.\(item.rawValue)")
    }
}

struct IssueHistoryListContent: View {
    let projectID: UUID
    @Binding var section: IssueRemarksSection

    @State private var state: LoadState = .loading
    @State private var loadGeneration = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch state {
            case .loading:
                VStack(spacing: 0) {
                    IssueRemarksSectionPicker(section: $section)
                    ProgressView("Читаем историю")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("project.issues.history.loading")
                }
            case .failed(let message):
                errorState(message)
            case .loaded(let document, let photoSummaries):
                loaded(document, photoSummaries: photoSummaries)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bcProgressDidChange)) { _ in
            reload()
        }
    }

    @ViewBuilder
    private func loaded(
        _ document: IssueHistoryDocument,
        photoSummaries: [UUID: IssueHistoryPhotoSummary]
    ) -> some View {
        let cases = IssueHistoryPresentation.closedCases(in: document)
        let pending = IssueHistoryPresentation.unfinishedSaveMessage(in: document)
        if cases.isEmpty && pending == nil {
            emptyState
        } else {
            List {
                Section {
                    IssueRemarksSectionPicker(section: $section)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let pending {
                    Section {
                        Text(pending)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("project.issues.history.pending")
                    }
                }
                if cases.isEmpty {
                    Section {
                        Text("Закрытых случаев пока нет.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section {
                        ForEach(cases) { item in
                            NavigationLink {
                                IssueHistoryDetailView(projectID: projectID, caseID: item.id)
                            } label: {
                                historyRow(
                                    item,
                                    photos: photoSummaries[item.id] ?? IssueHistoryPhotoSummary(
                                        availableUniqueCount: 0,
                                        hasReferences: false,
                                        hasUnavailable: false
                                    )
                                )
                            }
                            .accessibilityHint("Открывает сохранённую историю случая")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("project.issues.history.list")
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                IssueRemarksSectionPicker(section: $section)
                Text("Истории пока нет")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                Text("Закрытые замечания появятся здесь после исправления или снятия отметки.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.issues.history.empty")
    }

    private func errorState(_ message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                IssueRemarksSectionPicker(section: $section)
                Text("Не удалось прочитать историю")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                historyRetryButton(action: reload)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("project.issues.history.error")
    }

    private func historyRow(_ item: IssueHistoryCase, photos: IssueHistoryPhotoSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusMark(item)
            historyText(item, photos: photos)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IssueHistoryPresentation.rowAccessibilityLabel(for: item, photos: photos))
        .accessibilityIdentifier("project.issues.history.row")
    }

    private func statusMark(_ item: IssueHistoryCase) -> some View {
        Image(systemName: item.closeKind == .withdrawn ? "minus.circle" : "checkmark.circle")
            .font(.title3)
            .foregroundStyle(item.closeKind == .resolved ? ProjectUXColors.progressComplete : ProjectUXColors.secondaryText)
            .accessibilityHidden(true)
    }

    private func historyText(_ item: IssueHistoryCase, photos: IssueHistoryPhotoSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(IssueHistoryPresentation.itemTitle(of: item))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(IssueHistoryPresentation.stageTitle(of: item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.closeKind?.title ?? "Без состояния")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let closedAt = item.closedAt {
                Text(IssueHistoryPresentation.closeLine(closedAt: closedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.previousCaseID != nil {
                Text("Повторное замечание")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(IssueHistoryPresentation.photoPhrase(photos))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        let pid = projectID
        state = state.isLoaded ? state : .loading
        Task.detached(priority: .userInitiated) {
            let loaded = IssueHistoryPresentation.loadList(projectID: pid)
            await MainActor.run {
                guard generation == loadGeneration else { return }
                switch loaded {
                case .loaded(let document, let counts):
                    state = .loaded(document, counts)
                case .failed(let message):
                    state = .failed(message)
                }
            }
        }
    }

    private enum LoadState {
        case loading
        case loaded(IssueHistoryDocument, [UUID: IssueHistoryPhotoSummary])
        case failed(String)

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }
}

private func historyRetryButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text("Повторить чтение")
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(ProjectUXColors.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ProjectUXColors.accentAction)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("project.issues.history.retry")
}

struct IssueHistoryDetailView: View {
    let projectID: UUID
    let caseID: UUID

    @State private var state: LoadState = .loading
    @State private var loadGeneration = 0
    @State private var preview: HistoryPhotoPreview?

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Читаем историю")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                failure(message)
            case .missing:
                missing
            case .loaded(let document, let item):
                detail(document: document, item: item)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProjectUXColors.screenBackground)
        .navigationTitle("История")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .fullScreenCover(item: $preview) { item in
            IssueHistoryPhotoViewer(image: item.image)
        }
    }

    private func detail(document: IssueHistoryDocument, item: IssueHistoryCase) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary(item)
                previousLink(document: document, item: item)
                Text("Хронология")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(item.events) { event in
                    eventCard(event, closeKind: item.closeKind)
                }
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("project.issues.history.detail")
    }

    private func summary(_ item: IssueHistoryCase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(IssueHistoryPresentation.itemTitle(of: item))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(IssueHistoryPresentation.stageTitle(of: item))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.closeKind?.title ?? "Без состояния")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(IssueHistoryPresentation.discoveryLine(openedAt: item.openedAt))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let transferredAt = item.transferredAt {
                Text(IssueHistoryPresentation.transferLine(transferredAt: transferredAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let closedAt = item.closedAt {
                Text(IssueHistoryPresentation.closeLine(closedAt: closedAt))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            if item.previousCaseID != nil {
                Text("Повторное замечание")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func previousLink(document: IssueHistoryDocument, item: IssueHistoryCase) -> some View {
        if let previousID = item.previousCaseID {
            if document.cases.contains(where: { $0.id == previousID }) {
                NavigationLink {
                    IssueHistoryDetailView(projectID: projectID, caseID: previousID)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Предыдущий случай")
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(ProjectUXColors.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Открывает более ранний случай этого пункта")
                .accessibilityIdentifier("project.issues.history.previous")
            } else {
                Text("Предыдущий случай недоступен")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project.issues.history.previousMissing")
            }
        }
    }

    private func eventCard(_ event: IssueHistoryEvent, closeKind: IssueHistoryCloseKind?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(IssueHistoryPresentation.eventTitle(event.kind, closeKind: closeKind))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(IssueHistoryPresentation.dateTime(event.at))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(IssueHistoryPresentation.noteText(event.note))
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if event.photoFileNames.isEmpty {
                Text("Без фото")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                IssueHistoryEventPhotos(
                    projectID: projectID,
                    eventID: event.id,
                    fileNames: event.photoFileNames
                ) { name, image in
                    preview = HistoryPhotoPreview(id: "\(event.id.uuidString)/\(name)", image: image)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("Случай не найден")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("В сохранённой истории этого случая нет. Остальные записи не изменены.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            Text("Не удалось прочитать историю")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            historyRetryButton(action: reload)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        let pid = projectID
        let wanted = caseID
        Task.detached(priority: .userInitiated) {
            let loaded = IssueHistoryPresentation.load(projectID: pid)
            await MainActor.run {
                guard generation == loadGeneration else { return }
                switch loaded {
                case .failed(let message):
                    state = .failed(message)
                case .loaded(let document):
                    if let item = document.cases.first(where: { $0.id == wanted }) {
                        state = .loaded(document, item)
                    } else {
                        state = .missing
                    }
                }
            }
        }
    }

    private enum LoadState {
        case loading
        case loaded(IssueHistoryDocument, IssueHistoryCase)
        case missing
        case failed(String)
    }
}

private struct HistoryPhotoPreview: Identifiable {
    let id: String
    let image: UIImage
}

/// Loads event photos; keeps available thumbs in the adaptive grid and places
/// missing captions on the card width (not the 88 pt thumbnail column).
private struct IssueHistoryEventPhotos: View {
    let projectID: UUID
    let eventID: UUID
    let fileNames: [String]
    var onOpen: (String, UIImage) -> Void

    private enum Slot {
        case loading
        case ready(UIImage)
        case missing

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }
    }

    @State private var slots: [String: Slot] = [:]

    var body: some View {
        let ready = fileNames.compactMap { name -> (String, UIImage)? in
            if case .ready(let image) = slots[name] { return (name, image) }
            return nil
        }
        let loading = fileNames.filter { slots[$0] == nil || slots[$0]?.isLoading == true }
        let missing = fileNames.filter { slots[$0]?.isMissing == true }

        VStack(alignment: .leading, spacing: 8) {
            if !ready.isEmpty || !loading.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(ready, id: \.0) { name, image in
                        availableThumb(name: name, image: image)
                    }
                    ForEach(loading, id: \.self) { _ in
                        ProgressView()
                            .frame(width: 88, height: 88)
                    }
                }
            }
            ForEach(missing, id: \.self) { _ in
                missingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(eventID.uuidString)/\(fileNames.joined(separator: ","))") {
            let pid = projectID
            let eid = eventID
            for name in fileNames {
                if slots[name] == nil {
                    slots[name] = .loading
                }
            }
            for name in fileNames {
                let loaded = await Task.detached(priority: .utility) {
                    IssueHistoryPhotoDecoding.thumbnail(projectID: pid, eventID: eid, fileName: name)
                }.value
                slots[name] = loaded.map { .ready($0) } ?? .missing
            }
        }
    }

    private func availableThumb(name: String, image: UIImage) -> some View {
        Button {
            let pid = projectID
            let eid = eventID
            let fallback = image
            Task.detached(priority: .userInitiated) {
                let larger = IssueHistoryPhotoDecoding.viewerImage(
                    projectID: pid,
                    eventID: eid,
                    fileName: name
                )
                await MainActor.run {
                    onOpen(name, larger ?? fallback)
                }
            }
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Открыть фото")
        .accessibilityHint("Просмотр без изменения")
        .accessibilityIdentifier("project.issues.history.photo")
    }

    private var missingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 88, height: 88)
                .background(ProjectUXColors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text("Фото не найдено")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Фото не найдено")
        .accessibilityIdentifier("project.issues.history.photoMissing")
    }
}

private struct IssueHistoryPhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Фото замечания")
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .padding()
                    }
                    .accessibilityLabel("Закрыть просмотр фото")
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("project.issues.history.photoViewer")
    }
}

private nonisolated enum IssueHistoryPhotoDecoding {
    static func viewerImage(projectID: UUID, eventID: UUID, fileName: String) -> UIImage? {
        guard let data = try? IssueHistoryRuntime.store().photoData(projectID: projectID, eventID: eventID, fileName: fileName) else {
            return nil
        }
        return image(data: data, maxPixelSize: 1600)
    }

    static func thumbnail(projectID: UUID, eventID: UUID, fileName: String) -> UIImage? {
        guard let data = try? IssueHistoryRuntime.store().photoData(projectID: projectID, eventID: eventID, fileName: fileName) else {
            return nil
        }
        return image(data: data, maxPixelSize: 264)
    }

    private static func image(data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
