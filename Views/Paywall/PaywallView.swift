import SwiftUI
import StoreKit

// MARK: - Paywall

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    private enum BillingPeriod: String, CaseIterable, Identifiable {
        case month = "Месяц"
        case year = "Год"
        var id: String { rawValue }
    }

    private enum PlanKind {
        case user
        case pro
    }

    @State private var period: BillingPeriod = .month
    @State private var isLoading: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var isRestoring: Bool = false
    @State private var isRefreshing: Bool = false

    private var isReadOnly: Bool {
        store.isReadOnlyMode && !store.isDemoMode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {

                    header
                    periodPicker

                    VStack(spacing: 12) {
                        planCard(.user)
                        planCard(.pro)
                    }

                    footerHint

                    if let err = store.subscription.lastErrorMessage, !err.isEmpty {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }

                    // 🔥 LEGAL БЛОК ПЕРЕНЕСЁН ВЫШЕ
                    legalLinks
                        .padding(.top, 12)

                    actionsRow
                        .padding(.top, 10)

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Подписка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .task {
            await initialLoad()
        }
    }

    // MARK: - Legal Links (Apple Safe Version)

    private var legalLinks: some View {
        VStack(spacing: 10) {
            Divider().padding(.vertical, 6)

            Text("Legal Information")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Link("Privacy Policy",
                     destination: URL(string: "https://buildchecklists-commits.github.io/buildchecklists-privacy/")!)

                Link("Terms of Use",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text(isReadOnly ? "Доступ ограничен" : "Выберите тариф")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(
                isReadOnly
                ? "Срок подписки истёк. Данные сохранены, но сейчас доступен только просмотр."
                : "Оплата и управление подпиской выполняются через App Store."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack(spacing: 10) {
            ForEach(BillingPeriod.allCases) { p in
                Button {
                    period = p
                } label: {
                    Text(p.rawValue)
                        .font(.subheadline.weight(period == p ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(period == p
                                      ? Color("AccentYellow").opacity(0.22)
                                      : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(period == p
                                        ? Color("AccentYellow")
                                        : Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLoading || isPurchasing || isRestoring || isRefreshing)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Plan card

    private func planCard(_ kind: PlanKind) -> some View {
        let title = (kind == .user) ? "USER" : "PRO"
        let subtitle = (kind == .user)
            ? "До 2 проектов"
            : "Без ограничений"
        let badge: String? = (kind == .pro) ? "Рекомендуем" : nil

        let product = productFor(kind: kind, period: period)
        let priceText = product?.displayPrice ?? (isLoading ? "Загрузка…" : "Недоступно")
        let isCurrent = isCurrentPlan(kind)
        let canBuy = product != nil
            && !isPurchasing
            && !isRestoring
            && !isRefreshing
            && !isLoading

        return VStack(alignment: .leading, spacing: 12) {

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.bold))

                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color("AccentYellow").opacity(0.18))
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(priceText)
                        .font(.headline.weight(.semibold))

                    if period == .year {
                        Text("Выгоднее, чем помесячно")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(" ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 8) {
                bullet(text: kind == .user
                       ? "До 2 активных проектов"
                       : "Неограниченное количество проектов")
                bullet(text: "Редактирование и сохранение данных")
                bullet(text: "Отмена и управление через App Store")
            }

            Button {
                Task { await buy(kind: kind) }
            } label: {
                HStack(spacing: 10) {
                    if isPurchasing {
                        ProgressView().scaleEffect(0.95)
                    } else {
                        Image(systemName: isCurrent
                              ? "checkmark.seal.fill"
                              : "creditcard.fill")
                    }

                    Text(isCurrent ? "Текущий тариф" : "Оформить \(title)")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isCurrent
                              ? Color(.systemGray6)
                              : Color("AccentYellow").opacity(0.20))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canBuy || isCurrent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footerHint: some View {
        Text(
            isReadOnly
            ? "После оплаты доступ восстановится автоматически."
            : "Если покупка была оформлена ранее, используйте «Восстановить покупки»."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        VStack(spacing: 10) {

            Button {
                Task { await restore() }
            } label: {
                actionRowLabel(
                    icon: "arrow.counterclockwise",
                    loading: isRestoring,
                    text: "Восстановить покупки"
                )
            }
            .disabled(isLoading || isPurchasing || isRestoring || isRefreshing)

            Button {
                Task { await refreshAccess() }
            } label: {
                actionRowLabel(
                    icon: "arrow.clockwise",
                    loading: isRefreshing,
                    text: "Обновить доступ"
                )
            }
            .disabled(isLoading || isPurchasing || isRestoring || isRefreshing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func actionRowLabel(icon: String, loading: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            if loading {
                ProgressView().scaleEffect(0.95)
            } else {
                Image(systemName: icon)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    private func bullet(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color("AccentYellow"))
                .padding(.top, 2)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - StoreKit binding

    private func productID(for kind: PlanKind, period: BillingPeriod) -> String {
        switch (kind, period) {
        case (.user, .month): return "buildchecklists.user.monthly"
        case (.user, .year):  return "buildchecklists.user.yearly"
        case (.pro,  .month): return "buildchecklists.pro.monthly.v2"
        case (.pro,  .year):  return "buildchecklists.pro.yearly"
        }
    }

    private func productFor(kind: PlanKind, period: BillingPeriod) -> Product? {
        let pid = productID(for: kind, period: period)
        return store.subscription.products.first(where: { $0.id == pid })
    }

    private func isCurrentPlan(_ kind: PlanKind) -> Bool {
        switch kind {
        case .user:
            return store.subscription.tier == .user
        case .pro:
            return store.subscription.tier == .pro
        }
    }

    // MARK: - Actions

    private func initialLoad() async {
        if !store.subscription.products.isEmpty {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        await store.subscription.loadProducts()
    }

    private func buy(kind: PlanKind) async {
        guard let product = productFor(kind: kind, period: period) else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        let ok = await store.subscription.purchase(product)
        if ok {
            _ = await store.refreshRoleForCurrentUser()
            dismiss()
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }

        let ok = await store.subscription.restorePurchases()
        if ok {
            _ = await store.refreshRoleForCurrentUser()
        }
    }

    private func refreshAccess() async {
        isRefreshing = true
        defer { isRefreshing = false }

        _ = await store.refreshRoleForCurrentUser()
    }
}
