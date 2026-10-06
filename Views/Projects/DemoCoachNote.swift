import SwiftUI

/// One short DEMO hint. It sits beside an existing control and does not cover it.
struct DemoCoachNote: View {
    let text: String
    var identifier: String

    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(ProjectUXColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(text)
                    .accessibilityIdentifier(identifier)

                Button(action: store.declineDemoCoach) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ProjectUXColors.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .fixedSize()
                .layoutPriority(1)
                .accessibilityLabel("Закрыть подсказку")
                .accessibilityIdentifier("demo.coach.close")
            }

            Button(action: store.declineDemoCoach) {
                Text("Понятно")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("demo.coach.done")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
