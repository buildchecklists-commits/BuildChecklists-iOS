import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    // MARK: - Input

    @State private var email: String = ""
    @State private var password: String = ""

    // MARK: - Validation

    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var globalError: String?

    @State private var isLoading: Bool = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !isLoading
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Premium background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        header
                        formCard
                        demoBlock
                        footerInfo
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Вход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Рады видеть вас снова")
                .font(.title2.weight(.semibold))

            Text("Войдите в аккаунт, чтобы продолжить работу с проектами и бюджетом.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(spacing: 20) {
            // Email
            VStack(alignment: .leading, spacing: 6) {
                PremiumTextField(
                    title: "Email",
                    placeholder: "example@mail.ru",
                    text: $email,
                    textContentType: .emailAddress,
                    keyboardType: .emailAddress
                )
                if let emailError { ValidationText(emailError) }
            }

            // Пароль
            VStack(alignment: .leading, spacing: 6) {
                PremiumSecureField(
                    title: "Пароль",
                    placeholder: "Ваш пароль",
                    text: $password
                )
                if let passwordError { ValidationText(passwordError) }
            }

            if let globalError {
                Text(globalError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            // Кнопка входа
            VStack(spacing: 8) {
                Button(action: login) {
                    HStack {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Войти")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentYellow)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1.0 : 0.6)

                Text("Используйте email и пароль, которые указывали при регистрации.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Demo block

    private var demoBlock: some View {
        VStack(spacing: 8) {
            Button {
                enterDemo()
            } label: {
                Text("Продолжить в демо-режиме")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.accentYellow)

            Text("В демо-режиме вы сможете протестировать приложение на примере готового проекта. Данные не сохраняются и могут быть очищены при перезапуске.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footerInfo: some View {
        VStack(spacing: 4) {
            Text("Если у вас ещё нет аккаунта, вы можете начать с демо-режима, а позже создать профиль.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func login() {
        emailError = nil
        passwordError = nil
        globalError = nil

        guard validateForm() else { return }

        isLoading = true
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try store.login(email: trimmedEmail, password: password)
            isLoading = false
            dismiss()
        } catch {
            isLoading = false
            globalError = error.localizedDescription
        }
    }

    private func enterDemo() {
        store.enterDemoMode()
        dismiss()
    }

    private func validateForm() -> Bool {
        var isValid = true

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            emailError = "Укажите email"
            isValid = false
        } else if !isValidEmail(trimmedEmail) {
            emailError = "Некорректный email"
            isValid = false
        }

        if password.isEmpty {
            passwordError = "Введите пароль"
            isValid = false
        }

        return isValid
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && !email.contains(" ")
    }
}

// MARK: - Helper Views

private struct PremiumTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType?
    var keyboardType: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }
}

private struct PremiumSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            SecureField(placeholder, text: $text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }
}

private struct ValidationText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
