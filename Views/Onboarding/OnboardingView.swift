import SwiftUI

private let onboardingKey = "bc_has_seen_onboarding"

struct OnboardingPage: Identifiable {
    let id: Int
    let imageName: String
}

struct OnboardingView: View {
    @AppStorage(onboardingKey) private var hasSeenOnboarding: Bool = false
    @State private var currentPage = 0

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            imageName: "onboarding_1"
        ),
        OnboardingPage(
            id: 1,
            imageName: "onboarding_2"
        ),
        OnboardingPage(
            id: 2,
            imageName: "onboarding_3"
        ),
        OnboardingPage(
            id: 3,
            imageName: "onboarding_4"
        ),
        OnboardingPage(
            id: 4,
            imageName: "onboarding_5"
        ),
        OnboardingPage(
            id: 5,
            imageName: "onboarding_6"
        ),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                TabView(selection: $currentPage) {
                    ForEach(Self.pages) { page in
                        ZStack {
                            Color(.black)
                                .ignoresSafeArea()

                            Image(page.imageName)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: geo.size.width,
                                    height: geo.size.height
                                )
                                .clipped()
                                .ignoresSafeArea()
                        }
                        .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Нижняя панель: градиент + индикатор страниц + кнопка
                VStack {
                    Spacer()

                    ZStack(alignment: .bottom) {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.0),
                                Color.black.opacity(0.35),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)

                        VStack(spacing: 16) {
                            HStack(spacing: 8) {
                                ForEach(0..<Self.pages.count, id: \.self) { index in
                                    Capsule(style: .continuous)
                                        .fill(index == currentPage ? Color("AccentYellow") : Color.white.opacity(0.4))
                                        .frame(width: index == currentPage ? 18 : 8, height: 8)
                                }
                            }

                            Button {
                                if currentPage == Self.pages.count - 1 {
                                    UserDefaults.standard.set(true, forKey: onboardingKey)
                                } else {
                                    withAnimation(.easeInOut) {
                                        currentPage += 1
                                    }
                                }
                            } label: {
                                Text(currentPage == Self.pages.count - 1 ? "Начать" : "Далее")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.horizontal, 24)
                            .padding(.bottom, max(20, geo.safeAreaInsets.bottom + 12))
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
