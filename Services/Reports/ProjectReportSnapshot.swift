import Foundation

/// Who will read the report. The customer audience cannot carry internal fields.
nonisolated enum ProjectReportAudience: Equatable {
    case owner
    case customer
}

/// Sections the next screens can turn on. Tasks and contacts start off.
nonisolated struct ProjectReportSections: Equatable {
    var checklists: Bool
    var expenses: Bool
    var issues: Bool
    var tasks: Bool
    var contacts: Bool
    var paymentComments: Bool

    static let ownerDefault = ProjectReportSections(
        checklists: true,
        expenses: true,
        issues: true,
        tasks: false,
        contacts: false,
        paymentComments: true
    )

    static let customerDefault = ProjectReportSections(
        checklists: true,
        expenses: true,
        issues: false,
        tasks: false,
        contacts: false,
        paymentComments: false
    )
}

/// Filters for a future report. `nil` means the filter is not applied.
nonisolated struct ProjectReportRequest: Equatable {
    var audience: ProjectReportAudience
    var dateFrom: Date?
    var dateTo: Date?
    var stages: Set<GlobalStageCategory>?
    var expenseTypes: Set<ExpenseSubCategory>?
    var sections: ProjectReportSections
    var generatedAt: Date

    init(
        audience: ProjectReportAudience,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        stages: Set<GlobalStageCategory>? = nil,
        expenseTypes: Set<ExpenseSubCategory>? = nil,
        sections: ProjectReportSections? = nil,
        generatedAt: Date = Date()
    ) {
        self.audience = audience
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.stages = stages
        self.expenseTypes = expenseTypes
        self.sections = sections ?? (audience == .customer ? .customerDefault : .ownerDefault)
        self.generatedAt = generatedAt
    }
}

nonisolated struct ProjectReportMetadata: Equatable {
    var projectID: UUID
    var name: String
    var address: String
    var manager: String?
    var dateStart: Date?
    var dateEnd: Date?
    /// Project-wide budget. This is not the sum of `plannedBudgetByStage`.
    var budget: Decimal?
    var generatedAt: Date
}

nonisolated struct ProjectReportPack: Equatable {
    var pack: ChecklistPack
    var category: GlobalStageCategory
    var title: String
    var readState: ChecklistReportPackReadState
    var readError: String?
    var progress: Double
    var itemCount: Int
    var doneCount: Int
    var issueCount: Int
    var notDoneCount: Int
    /// Empty for the customer audience: internal items are not copied.
    var stages: [ProjectReportChecklistStage]
}

nonisolated struct ProjectReportChecklistStage: Equatable {
    var stageID: UUID
    var title: String
    var items: [ProjectReportChecklistItem]
}

nonisolated struct ProjectReportChecklistItem: Equatable {
    var itemID: UUID
    var title: String
    var statusTitle: String
    var noteText: String?
    var photoPaths: [String]
}

nonisolated struct ProjectReportExpense: Equatable {
    var id: UUID
    var amount: Decimal
    var date: Date
    var category: ExpenseCategory
    var subCategory: ExpenseSubCategory
    /// Stage used for the total. Untagged expenses use the `totalsByStageCategory` fallback.
    var stage: GlobalStageCategory
    var note: String?
}

nonisolated struct ProjectReportMoneyRow: Equatable {
    var stage: GlobalStageCategory
    var plan: Decimal
    var fact: Decimal
    var difference: Decimal
}

/// Timeline row from `project.stages`. It is not matched to a money row.
nonisolated struct ProjectReportScheduleRow: Equatable {
    var stageID: UUID
    var title: String
    var plannedStart: Date?
    var plannedEnd: Date?
    var actualStart: Date?
    var actualEnd: Date?
    var isOverdue: Bool
    var delayReason: DelayReason?
    var delayComment: String?

    var hasAnyDate: Bool {
        plannedStart != nil || plannedEnd != nil || actualStart != nil || actualEnd != nil
    }
}

nonisolated struct ProjectReportContact: Equatable {
    var id: UUID
    var name: String
    var role: String
    var phone: String
    var note: String?
}

nonisolated struct ProjectReportComposition: Equatable {
    var packsWithData: Int
    var issueCount: Int
    var operationCount: Int
    var hasPlan: Bool
    var hasDates: Bool
}

/// Immutable report contents. Building it does not write projects, packs, or notes.
nonisolated struct ProjectReportSnapshot: Equatable {
    var metadata: ProjectReportMetadata
    /// Ten-pack card formula. Doors stay out of this number.
    var overallProgress: Double
    var packs: [ProjectReportPack]
    var issues: [ChecklistIssueRef]
    var expenses: [ProjectReportExpense]
    var moneyRows: [ProjectReportMoneyRow]
    var schedule: [ProjectReportScheduleRow]
    var tasks: [TaskItem]
    var contacts: [ProjectReportContact]
    var composition: ProjectReportComposition
}

nonisolated enum ProjectReportSnapshotError: LocalizedError, Equatable {
    case unreadablePack(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePack(let message):
            return message
        }
    }
}

nonisolated enum ProjectReportSnapshotBuilder {
    /// Reads working packs through `ChecklistReportSnapshotBuilder`, then assembles.
    /// Does not call `*ProgressStore.load`, `save`, or `merge`.
    static func read(
        project: Project,
        expenses: [ExpenseItem],
        tasks: [TaskItem],
        request: ProjectReportRequest
    ) throws -> ProjectReportSnapshot {
        let source = ChecklistReportSource(
            projectID: project.id,
            name: project.name,
            address: project.address,
            manager: project.manager,
            generatedAt: request.generatedAt,
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
        let checklist = try ChecklistReportSnapshotBuilder.make(from: source)
        if let failed = checklist.packs.first(where: { $0.readState == .unreadable }) {
            throw ProjectReportSnapshotError.unreadablePack(
                failed.readError ?? ChecklistReportProgress.unreadablePackMessage
            )
        }
        return assemble(
            project: project,
            checklist: checklist,
            expenses: expenses,
            tasks: tasks,
            request: request
        )
    }

    /// Pure mapping. The checklist snapshot must already have been read.
    static func assemble(
        project: Project,
        checklist: ChecklistReportSnapshot,
        expenses: [ExpenseItem],
        tasks: [TaskItem],
        request: ProjectReportRequest
    ) -> ProjectReportSnapshot {
        let customer = request.audience == .customer
        var sections = request.sections
        if customer {
            sections.issues = false
            sections.tasks = false
            sections.paymentComments = false
        }

        let filteredExpenses = filterExpenses(expenses, projectID: project.id, request: request)
        let stagePacks = checklist.packs.filter { pack in
            guard let selected = request.stages else { return true }
            return selected.contains(category(for: pack.pack))
        }
        let visiblePacks = sections.checklists ? stagePacks : []
        let issues = sections.issues
            ? makeIssues(projectID: project.id, packs: stagePacks)
            : []
        let schedule = project.stages.map { scheduleRow($0, includeDelay: !customer) }
        let moneyRows = moneyRows(project: project, expenses: filteredExpenses, stages: request.stages)
        let lineItems = sections.expenses
            ? filteredExpenses.map { expenseRow($0, includeNote: sections.paymentComments) }
            : []
        let visibleTasks = sections.tasks
            ? tasks.filter { $0.projectID == project.id }
            : []
        let visibleContacts = sections.contacts
            ? project.contacts.map { contactRow($0, includePhone: !customer) }
            : []
        let packs = visiblePacks.map { displayPack($0, includeItems: !customer) }

        let composition = ProjectReportComposition(
            packsWithData: packs.filter { $0.readState == .ready && $0.itemCount > 0 }.count,
            issueCount: issues.count,
            operationCount: lineItems.count,
            hasPlan: moneyRows.contains { $0.plan > 0 },
            hasDates: schedule.contains(where: \.hasAnyDate)
        )

        return ProjectReportSnapshot(
            metadata: ProjectReportMetadata(
                projectID: project.id,
                name: project.name,
                address: project.address,
                manager: project.manager,
                dateStart: project.dateStart,
                dateEnd: project.dateEnd,
                budget: project.budget,
                generatedAt: request.generatedAt
            ),
            overallProgress: checklist.overallProgress,
            packs: packs,
            issues: issues,
            expenses: lineItems,
            moneyRows: moneyRows,
            schedule: schedule,
            tasks: visibleTasks,
            contacts: visibleContacts,
            composition: composition
        )
    }

    /// Same fallback as `AppStore.totalsByStageCategory`: a missing `stageCategory` follows `ExpenseCategory`.
    /// Roof-cover fact exists only when `stageCategory` is `.roofCover`.
    static func resolvedStage(for expense: ExpenseItem) -> GlobalStageCategory {
        if let stage = expense.stageCategory {
            return stage
        }
        switch expense.category {
        case .geologyAndPrep: return .geologyAndPrep
        case .foundation: return .foundation
        case .walls: return .walls
        case .slabs: return .slabs
        case .roof: return .roof
        case .engineering: return .engineering
        case .windows: return .windows
        case .doors: return .doors
        case .finishing: return .finishing
        case .landscaping: return .landscaping
        }
    }

    static func category(for pack: ChecklistPack) -> GlobalStageCategory {
        switch pack {
        case .geology: return .geologyAndPrep
        case .foundation: return .foundation
        case .walls: return .walls
        case .slab: return .slabs
        case .roof: return .roof
        case .roofCover: return .roofCover
        case .engineering: return .engineering
        case .windows: return .windows
        case .doors: return .doors
        case .finishing: return .finishing
        case .landscaping: return .landscaping
        }
    }

    private static func filterExpenses(
        _ expenses: [ExpenseItem],
        projectID: UUID,
        request: ProjectReportRequest
    ) -> [ExpenseItem] {
        let period = normalizedPeriod(from: request.dateFrom, to: request.dateTo)
        return expenses.filter { expense in
            guard expense.projectID == projectID else { return false }
            if let stages = request.stages, !stages.contains(resolvedStage(for: expense)) {
                return false
            }
            if let types = request.expenseTypes, !types.contains(expense.subCategory) {
                return false
            }
            if let from = period.from, expense.date < from { return false }
            if let to = period.to, expense.date >= to { return false }
            return true
        }
    }

    /// Swaps reversed bounds. The end date then covers the whole calendar day.
    private static func normalizedPeriod(from: Date?, to: Date?) -> (from: Date?, to: Date?) {
        var lower = from
        var upper = to
        if let start = lower, let end = upper, start > end {
            lower = end
            upper = start
        }
        let inclusiveEnd = upper.flatMap { endOfSelectedDay(for: $0) }
        return (lower, inclusiveEnd)
    }

    /// First instant that is no longer inside the selected calendar day.
    private static func endOfSelectedDay(for date: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    private static func moneyRows(
        project: Project,
        expenses: [ExpenseItem],
        stages: Set<GlobalStageCategory>?
    ) -> [ProjectReportMoneyRow] {
        GlobalStageCategory.allCases.compactMap { stage in
            if let stages, !stages.contains(stage) { return nil }
            let fact = expenses.reduce(Decimal(0)) { partial, expense in
                resolvedStage(for: expense) == stage ? partial + expense.amount : partial
            }
            let plan = project.plannedBudget(for: stage)
            return ProjectReportMoneyRow(stage: stage, plan: plan, fact: fact, difference: fact - plan)
        }
    }

    private static func expenseRow(_ expense: ExpenseItem, includeNote: Bool) -> ProjectReportExpense {
        ProjectReportExpense(
            id: expense.id,
            amount: expense.amount,
            date: expense.date,
            category: expense.category,
            subCategory: expense.subCategory,
            stage: resolvedStage(for: expense),
            note: includeNote ? expense.note : nil
        )
    }

    private static func displayPack(_ pack: ChecklistReportPack, includeItems: Bool) -> ProjectReportPack {
        let stages = includeItems
            ? pack.stages.map { stage in
                ProjectReportChecklistStage(
                    stageID: stage.stageID,
                    title: stage.title,
                    items: stage.items.map { item in
                        ProjectReportChecklistItem(
                            itemID: item.itemID,
                            title: item.title,
                            statusTitle: item.statusTitle,
                            noteText: item.noteText,
                            photoPaths: item.photoPaths
                        )
                    }
                )
            }
            : []
        return ProjectReportPack(
            pack: pack.pack,
            category: category(for: pack.pack),
            title: pack.title,
            readState: pack.readState,
            readError: pack.readError,
            progress: pack.progress,
            itemCount: pack.itemCount,
            doneCount: pack.doneCount,
            issueCount: pack.issueCount,
            notDoneCount: pack.notDoneCount,
            stages: stages
        )
    }

    private static func makeIssues(projectID: UUID, packs: [ChecklistReportPack]) -> [ChecklistIssueRef] {
        var seen = Set<String>()
        var result: [ChecklistIssueRef] = []
        for pack in packs where pack.readState == .ready {
            for stage in pack.stages {
                for item in stage.items where item.status == .issue {
                    let ref = ChecklistIssueRef(
                        projectID: projectID,
                        pack: pack.pack,
                        stageID: stage.stageID,
                        itemID: item.itemID,
                        packTitle: pack.title,
                        stageTitle: stage.title,
                        itemTitle: item.title,
                        blockSubtitle: stage.subtitle,
                        noteText: item.noteText,
                        photoCount: item.photoCount,
                        firstPhotoPath: item.photoPaths.first
                    )
                    if seen.insert(ref.id).inserted {
                        result.append(ref)
                    }
                }
            }
        }
        return result
    }

    private static func scheduleRow(_ stage: Stage, includeDelay: Bool) -> ProjectReportScheduleRow {
        ProjectReportScheduleRow(
            stageID: stage.id,
            title: stage.title,
            plannedStart: stage.plannedStart,
            plannedEnd: stage.plannedEnd,
            actualStart: stage.actualStart,
            actualEnd: stage.actualEnd,
            isOverdue: stage.isOverdue,
            delayReason: includeDelay ? stage.delayReason : nil,
            delayComment: includeDelay ? stage.delayComment : nil
        )
    }

    private static func contactRow(_ contact: ProjectContact, includePhone: Bool) -> ProjectReportContact {
        ProjectReportContact(
            id: contact.id,
            name: contact.name,
            role: contact.role,
            phone: includePhone ? contact.phone : "",
            note: contact.note
        )
    }
}
