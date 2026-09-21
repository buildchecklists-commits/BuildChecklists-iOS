import Foundation
import Combine
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {

    // MARK: - Tier

    enum Tier: String, Equatable {
        case none
        case user
        case pro
    }

    // MARK: - Published state

    @Published private(set) var products: [Product] = []

    /// Текущий тариф, определённый из активных entitlement’ов.
    @Published private(set) var tier: Tier = .none

    /// True если есть активная подписка USER или PRO.
    @Published private(set) var isSubscriptionActive: Bool = false

    /// True если подписки нет/истекла → режим “только просмотр” (для НЕ демо).
    @Published private(set) var isReadOnlyExpired: Bool = true

    @Published var lastErrorMessage: String?

    // MARK: - Product IDs (App Store Connect)

    private let userProductIDs: [String] = [
        "buildchecklists.user.monthly",
        "buildchecklists.user.yearly"
    ]

    private let proProductIDs: [String] = [
        "buildchecklists.pro.monthly.v2", // ✅ актуальный ID из App Store Connect
        "buildchecklists.pro.yearly"
    ]

    private var allProductIDs: [String] { userProductIDs + proProductIDs }

    // MARK: - Init

    private var updatesTask: Task<Void, Never>?

    /// Инициализация без вызова refreshAccessFromStoreKit(), чтобы не блокировать первый UI.
    /// Первая проверка подписок выполняется в AppStore.bootstrap() после появления экрана (WelcomeView/MainTabView).
    init() {
        BCTiming.log("SubscriptionService init")
        updatesTask = Task { [weak self] in
            guard let self else { return }
            await self.listenForTransactionUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Compatibility API (чтобы AppStore.swift не ломался)

    func refreshEntitlements() async {
        await refreshAccessFromStoreKit()
    }

    // MARK: - Public API

    func loadProducts() async {
        lastErrorMessage = nil
        do {
            let fetched = try await Product.products(for: allProductIDs)
            products = fetched.sorted(by: { $0.displayName < $1.displayName })
        } catch {
            products = []
            lastErrorMessage = "Не удалось загрузить подписки: \(error.localizedDescription)"
        }

        await refreshAccessFromStoreKit()
    }

    func purchase(_ product: Product) async -> Bool {
        lastErrorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
                await transaction.finish()
                await refreshAccessFromStoreKit()
                return true

            case .userCancelled:
                return false

            case .pending:
                lastErrorMessage = "Покупка ожидает подтверждения."
                return false

            @unknown default:
                lastErrorMessage = "Неизвестный результат покупки."
                return false
            }
        } catch {
            lastErrorMessage = "Ошибка покупки: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async -> Bool {
        lastErrorMessage = nil
        do {
            // ✅ важно: явно StoreKit.AppStore, чтобы не конфликтовало с твоим AppStore.swift
            try await StoreKit.AppStore.sync()
            await refreshAccessFromStoreKit()
            return true
        } catch {
            lastErrorMessage = "Не удалось восстановить покупки: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Access refresh

    private func refreshAccessFromStoreKit() async {
        BCTiming.log("refreshAccessFromStoreKit start")
        var hasUser = false
        var hasPro = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.isUpgraded { continue }
            guard transaction.revocationDate == nil else { continue }

            let pid = transaction.productID
            if userProductIDs.contains(pid) { hasUser = true }
            if proProductIDs.contains(pid) { hasPro = true }
        }

        if hasPro {
            tier = .pro
        } else if hasUser {
            tier = .user
        } else {
            tier = .none
        }

        isSubscriptionActive = (tier != .none)
        isReadOnlyExpired = !isSubscriptionActive
        BCTiming.log("refreshAccessFromStoreKit end")
    }

    // MARK: - Updates listener

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshAccessFromStoreKit()
        }
    }

    // MARK: - Verification helper

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Local reset (Account deletion)

    /// Сбрасывает локальные значения сервиса подписки.
    /// НЕ отменяет подписку у Apple ID — только очищает локальное состояние до следующей проверки StoreKit.
    func resetLocalState() {
        products = []
        tier = .none
        isSubscriptionActive = false
        isReadOnlyExpired = true
        lastErrorMessage = nil
    }
}
