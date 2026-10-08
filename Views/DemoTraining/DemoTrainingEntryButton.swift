import SwiftUI

/// Compact entry that opens the DEMO training menu. Never auto-starts a tour.
struct DemoTrainingEntryButton: View {
    @ObservedObject private var training = DemoTrainingController.shared

    var body: some View {
        Button {
            training.openMenu()
        } label: {
            Label("Обучение", systemImage: "graduationcap.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("demo.training.entry")
        .accessibilityHint("Открывает меню туров обучения")
    }
}

/// The entry button inside the same capsule chrome on every tab.
/// Renders nothing outside DEMO, so a normal profile never sees training.
struct DemoTrainingEntryCapsule: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if DemoTrainingPrototypeGate.isEnabled && store.isDemoMode {
            DemoTrainingEntryButton()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(ProjectUXColors.accentAction.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

/// Own row (trailing capsule) for screens where the entry must not compete with list tools
/// (Projects, Profile). Header screens use `DemoTrainingEntryCapsule` next to their title instead.
struct DemoTrainingEntryRow: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if DemoTrainingPrototypeGate.isEnabled && store.isDemoMode {
            HStack {
                Spacer(minLength: 0)
                DemoTrainingEntryCapsule()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
