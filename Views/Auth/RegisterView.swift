import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    // MARK: - Input

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    // MARK: - Validation

    @State private var nameError: String?
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var confirmPasswordError: String?
    @State private var globalError: String?

    @State private var isLoading: Bool = false

    // Переход на Paywall (после регистрации)
    @State private var showPaywall: Bool = false

    // Роль больше НЕ выбираем и НЕ присваиваем платную локально
    // (оставляем доступ только после подтверждения через Supabase get-role)

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        !isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: - Premium Background
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
                        footerInfo
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Создать аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Добро пожаловать в Build Checklists")
                .font(.title2.weight(.semibold))

            Text("Создайте профиль, чтобы фиксировать прогресс и затем активировать уровень «Пользователь» или «Прораб» для сохранения проектов.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(spacing: 20) {
            // Имя
            VStack(alignment: .leading, spacing: 6) {
                PremiumTextField(
                    title: "Имя",
                    placeholder: "Как к вам обращаться",
                    text: $name,
                    textContentType: .name,
                    keyboardType: .default,
                    autocapitalization: .words
                )
                if let nameError { ValidationText(nameError) }
            }

            // Email
            VStack(alignment: .leading, spacing: 6) {
                PremiumTextField(
                    title: "Email",
                    placeholder: "example@mail.ru",
                    text: $email,
                    textContentType: .emailAddress,
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
                if let emailError { ValidationText(emailError) }
            }

            // Пароль
            VStack(alignment: .leading, spacing: 6) {
                PremiumSecureField(
                    title: "Пароль",
                    placeholder: "Минимум 6 символов",
                    text: $password
                )
                if let passwordError { ValidationText(passwordError) }
            }

            // Повтор пароля
            VStack(alignment: .leading, spacing: 6) {
                PremiumSecureField(
                    title: "Повторите пароль",
                    placeholder: "Ещё раз пароль",
                    text: $confirmPassword
                )
                if let confirmPasswordError { ValidationText(confirmPasswordError) }
            }

            if let globalError {
                Text(globalError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            // MARK: - Кнопка регистрации

            VStack(spacing: 8) {
                Button(action: register) {
                    HStack {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Создать аккаунт")
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

                Text("После регистрации вы сможете выбрать уровень «Пользователь» или «Прораб». В демо-режиме данные не сохраняются.")
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

    // MARK: - Footer

    private var footerInfo: some View {
        VStack(spacing: 4) {
            Text("Создавая аккаунт, вы принимаете правила использования приложения.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func register() {
        nameError = nil
        emailError = nil
        passwordError = nil
        confirmPasswordError = nil
        globalError = nil

        guard validateForm() else { return }

        isLoading = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            // Регистрация = создание профиля. Платную роль НЕ выдаём локально.
            try store.register(
                name: trimmedName,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                secret: password,
                role: .demo
            )

            isLoading = false

            // После регистрации сразу показываем экран выбора уровня (Paywall).
            showPaywall = true

        } catch {
            isLoading = false
            globalError = error.localizedDescription
        }
    }

    private func validateForm() -> Bool {
        var isValid = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameError = "Введите имя"
            isValid = false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            emailError = "Укажите email"
            isValid = false
        } else if !isValidEmail(trimmedEmail) {
            emailError = "Некорректный email"
            isValid = false
        }

        if password.count < 6 {
            passwordError = "Минимум 6 символов"
            isValid = false
        }

        if confirmPassword != password {
            confirmPasswordError = "Пароли не совпадают"
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
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
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
