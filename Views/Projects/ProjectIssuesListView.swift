import SwiftUI

enum ProjectIssuesFormatting {
    static func remarksPhrase(_ count: Int) -> String {
        ProjectUXCopy.remarksPhrase(count)
    }

    static func dashboardAccessibilityLabel(count: Int) -> String {
        if count == 0 {
            return "Замечания, замечаний нет"
        }
        return "Замечания, требуют внимания, \(remarksPhrase(count))"
    }

    static func rowAccessibilityLabel(_ issue: ChecklistIssueRef) -> String {
        var parts = [issue.itemTitle]
        if let note = issue.noteText {
            parts.append(accessibilityNoteExcerpt(note))
        } else {
            parts.append("без описания")
        }
        parts.append(issue.packTitle)
        parts.append(issue.stageTitle)
        if let subtitle = issue.blockSubtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if issue.hasPhotos {
            parts.append("фото \(issue.photoCount)")
        }
        return parts.joined(separator: ", ")
    }

    static func accessibilityNoteExcerpt(_ text: String) -> String {
        let maxLength = 160
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end])
    }
}

struct ProjectIssuesListView: View {
    let projectID: UUID

    @State private var issues: [ChecklistIssueRef] = []
    @State private var loadGeneration = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if issues.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(issues) { issue in
                            NavigationLink {
                                IssueStageDetailHost(
                                    projectID: issue.projectID,
                                    pack: issue.pack,
                                    stageID: issue.stageID,
                                    itemID: issue.itemID
                                )
                            } label: {
                                issueRow(issue)
                            }
                            .accessibilityHint("Открывает пункт чек-листа")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier("project.issues.list")
            }
        }
        .navigationTitle("Замечания")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reloadIssues)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reloadIssues()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bcProgressDidChange)) { _ in
            reloadIssues()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("Замечаний нет")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Пункты, отмеченные как проблема, появятся здесь.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project.issues.empty")
        .accessibilityLabel("Замечаний нет. Пункты, отмеченные как проблема, появятся здесь.")
    }

    private func issueRow(_ issue: ChecklistIssueRef) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(issue.itemTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = issue.noteText {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .truncationMode(.tail)
                } else {
                    Text("Без описания")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(issue.stageTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(issue.packTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = issue.blockSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let path = issue.firstPhotoPath {
                    HStack(alignment: .center, spacing: 8) {
                        IssuePhotoThumbnail(path: path, side: 56)
                        Label("Фото: \(issue.photoCount)", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ProjectIssuesFormatting.rowAccessibilityLabel(issue))
        .accessibilityIdentifier("project.issues.row")
    }

    private func reloadIssues() {
        loadGeneration += 1
        let generation = loadGeneration
        let pid = projectID
        Task.detached(priority: .userInitiated) {
            let result = ProjectIssuesCollector.issues(for: pid)
            await MainActor.run {
                guard generation == loadGeneration else { return }
                issues = result
            }
        }
    }
}
