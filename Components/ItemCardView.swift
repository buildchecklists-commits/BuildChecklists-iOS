import SwiftUI
import PhotosUI

private enum ActiveSheet: Identifiable {
    case note
    case info(slug: String)
    case image(UIImage)

    var id: String {
        switch self {
        case .note:                return "note"
        case .info(let slug):      return "info:\(slug)"
        case .image(let ui):       return "img:\(Unmanaged.passUnretained(ui).toOpaque())"
        }
    }
}

struct ItemCardView: View {
    @EnvironmentObject var store: AppStore

    let projectID: UUID
    let stageID: UUID
    let item: StageItem

    // Локальные состояния
    @State private var noteDraft: String = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var activeSheet: ActiveSheet? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusRow
            actionsRow
            photosPreview
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color("BrandSeparator"), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .note:
                noteSheet
            case .info(let slug):
                InfoSheetView(slug: slug)
                    .environmentObject(store)
            case .image(let ui):
                FullScreenImageView(image: ui)
            }
        }
        .onChange(of: pickedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    try? store.addPhoto(projectID: projectID,
                                        stageID: stageID,
                                        itemID: item.id,
                                        image: image)
                }
                pickedPhoto = nil
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        Text(item.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusChip(title: "ОК", active: item.status == .ok) {
                try? store.setStatus(projectID: projectID, stageID: stageID, itemID: item.id, status: .ok)
            }
            .disabled(store.isReadOnlyMode)

            StatusChip(title: "Проблема", active: item.status == .issue) {
                try? store.setStatus(projectID: projectID, stageID: stageID, itemID: item.id, status: .issue)
            }
            .disabled(store.isReadOnlyMode)

            StatusChip(title: "Н/Д", active: item.status == .na) {
                try? store.setStatus(projectID: projectID, stageID: stageID, itemID: item.id, status: .na)
            }
            .disabled(store.isReadOnlyMode)

            Spacer()
            SeverityFlag(severity: item.severity ?? .low)
                .opacity(store.isReadOnlyMode ? 0.7 : 1.0)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {

            // Заметка — скрываем в read-only
            if !store.isReadOnlyMode {
                Button {
                    noteDraft = item.note ?? ""
                    activeSheet = .note
                } label: { actionLabel("Заметка", system: "square.and.pencil") }
                .buttonStyle(.plain)
            }

            // Фото (добавить) — скрываем в read-only
            if !store.isReadOnlyMode {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    actionLabel("Фото", system: "camera")
                }
                .buttonStyle(.plain)
            }

            // Инфо — скрываем в read-only
            if !store.isReadOnlyMode,
               let raw = item.infoSlug?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                Button {
                    activeSheet = .info(slug: raw)
                } label: { actionLabel("Инфо", system: "info.circle") }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Информация")
            }
        }
        .onChange(of: store.isReadOnlyMode) { _, isRO in
            // если внезапно переключились в read-only — закрываем любые открытые редакторы
            if isRO, case .note = activeSheet {
                activeSheet = nil
            }
        }
    }

    @ViewBuilder private var photosPreview: some View {
        if !item.photoPaths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(item.photoPaths, id: \.self) { path in
                        if let ui = UIImage(contentsOfFile: path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipped()
                                .cornerRadius(10)
                                .onTapGesture {
                                    activeSheet = .image(ui)
                                }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Sheets

    private var noteSheet: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $noteDraft)
                    .padding()
                    .frame(maxHeight: .infinity)
                    .background(Color("CardBG"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()

                Button("Сохранить") {
                    try? store.setNote(projectID: projectID,
                                       stageID: stageID,
                                       itemID: item.id,
                                       note: noteDraft)
                    activeSheet = nil
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
            }
            .navigationTitle("Заметка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { activeSheet = nil }
                }
            }
        }
    }

    // MARK: - Helpers

    private func actionLabel(_ title: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color("CardBG"))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Subviews

private struct StatusChip: View {
    var title: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Color("AccentYellow") : Color("CardBG"))
                .foregroundStyle(active ? Color("BrandBlack") : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SeverityFlag: View {
    var severity: Severity
    var body: some View {
        let (text, bg): (String, Color) = {
            switch severity {
            case .low:    return ("Низкий",  .blue.opacity(0.25))
            case .medium: return ("Средний", .orange.opacity(0.35))
            case .high:   return ("Высокий", .red.opacity(0.35))
            }
        }()
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(Capsule())
    }
}
