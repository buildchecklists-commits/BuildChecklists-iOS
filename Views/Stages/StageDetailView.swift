import SwiftUI

struct StageDetailView: View {
    @EnvironmentObject var store: AppStore
    let projectID: UUID
    let stageID: UUID

    @State private var showPaywall: Bool = false

    private var stage: Stage? {
        store.stage(projectID: projectID, stageID: stageID)
    }

    var body: some View {
        Group {
            if let stage {
                VStack(spacing: 0) {

                    if store.isReadOnlyMode {
                        readOnlyBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                    }

                    List {
                        ForEach(stage.items) { item in
                            ItemCardView(projectID: projectID, stageID: stageID, item: item)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .disabled(store.isReadOnlyMode)
                }
                .navigationTitle(stage.title)
                .environmentObject(store)
                .background(Color("CardBG"))
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                        .environmentObject(store)
                }
            } else {
                Text("Этап не найден")
                    .foregroundStyle(.secondary)
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
}
