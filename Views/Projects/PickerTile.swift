import SwiftUI

struct PickerTile: View {
    let title: String
    let imageName: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 90)
                Text(title)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
