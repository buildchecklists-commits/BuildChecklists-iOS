// BuildChecklists/Services/AuthService.swift

import Foundation

struct AuthService {

    // MARK: - Constants

    private let flagKey = "bc_is_registered"

    private let profileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("build_checklists_profile.json")
    }()

    // MARK: - Models

    struct Profile: Codable {
        var name: String
        var email: String?
        var secret: String?
        var createdAt: Date
    }

    // MARK: - Registration

    func loadRegistrationFlag() -> Bool {
        UserDefaults.standard.bool(forKey: flagKey)
    }

    func register(name: String, email: String?, secret: String?) throws {
        let profile = Profile(
            name: name,
            email: email,
            secret: secret,
            createdAt: Date()
        )

        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileURL, options: .atomic)

        UserDefaults.standard.set(true, forKey: flagKey)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: profileURL.path) {
            try FileManager.default.removeItem(at: profileURL)
        }
        UserDefaults.standard.set(false, forKey: flagKey)
    }

    // MARK: - Profile access

    /// Текущий профиль пользователя (если есть)
    func loadProfile() -> Profile? {
        guard FileManager.default.fileExists(atPath: profileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: profileURL)
            return try JSONDecoder().decode(Profile.self, from: data)
        } catch {
            debugPrint("❌ Failed to load profile:", error.localizedDescription)
            return nil
        }
    }

    /// Email текущего пользователя
    func currentEmail() -> String? {
        loadProfile()?.email
    }

    /// ✅ Добавить/обновить email в профиле (используется в AppStore.login()).
    /// Никаких сетевых вызовов — только локальная запись профиля.
    func upsertEmail(_ email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var profile = loadProfile()

        // Если профиля ещё нет — создаём минимальный (на случай странных состояний).
        if profile == nil {
            profile = Profile(
                name: "Пользователь",
                email: normalized,
                secret: nil,
                createdAt: Date()
            )
        } else {
            profile?.email = normalized
        }

        guard let profile else { return }

        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: profileURL, options: .atomic)
            UserDefaults.standard.set(true, forKey: flagKey)
        } catch {
            debugPrint("❌ Failed to upsert email:", error.localizedDescription)
        }
    }
}
