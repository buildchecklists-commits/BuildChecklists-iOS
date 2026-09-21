import SwiftUI
import PhotosUI
import UIKit

struct EditProjectView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let project: Project

    // Локальные стейты для редактирования
    @State private var name: String
    @State private var address: String
    @State private var descriptionText: String
    @State private var selectedColor: String

    // Обложка (загруженная или новая)
    @State private var coverImage: UIImage?

    // Пикер
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?

    // Фото для кадрирования
    @State private var cropImage: UIImage?

    // Read-only
    @State private var showReadOnlyAlert = false

    // Цвета карточек
    private let availableColors: [(id: String, title: String)] = [
        ("softYellow", "Жёлтый"),
        ("softBlue", "Голубой"),
        ("softGreen", "Зелёный"),
        ("softPink", "Розовый"),
        ("softGray", "Серый")
    ]

    private var isReadOnlyBlocked: Bool {
        store.isReadOnlyMode && !store.isDemoMode
    }

    // MARK: - Init
    init(project: Project) {
        self.project = project
        _name = State(initialValue: project.name)
        _address = State(initialValue: project.address)
        _descriptionText = State(initialValue: project.description ?? "")
        _selectedColor = State(initialValue: project.cardColor ?? "softGray")
        _coverImage = State(initialValue: CoverImageStore.shared.loadCover(for: project.id))
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                // Основная информация
                Section("Основная информация") {
                    TextField("Название проекта", text: $name)
                        .textInputAutocapitalization(.sentences)

                    TextField("Адрес объекта", text: $address)
                        .textInputAutocapitalization(.sentences)

                    TextField("Описание (необязательно)", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Цвет карточки
                Section("Цвет карточки") {
                    colorPickerRow
                }

                // Обложка
                Section("Обложка проекта") {
                    coverSection
                }
            }
            // В read-only блокируем любые изменения прямо на уровне формы
            .disabled(isReadOnlyBlocked)

            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { saveChanges() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespaces).isEmpty ||
                            address.trimmingCharacters(in: .whitespaces).isEmpty ||
                            isReadOnlyBlocked
                        )
                }
            }

            // Пикер изображений
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $photoPickerItem,
                          matching: .images)

            // Экран кадрирования
            .sheet(
                isPresented: Binding(
                    get: { cropImage != nil },
                    set: { if !$0 { cropImage = nil } }
                )
            ) {
                if let cropImage {
                    CoverCropView(
                        sourceImage: cropImage,
                        onCancel: { self.cropImage = nil },
                        onDone: { cropped in
                            self.coverImage = cropped
                            self.cropImage = nil
                        }
                    )
                    .preferredColorScheme(.dark)
                }
            }

            // Подгрузка фото из PhotosPicker
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { self.cropImage = img }
                    }
                }
            }

            // Если экран открылся в read-only — показываем ошибку и закрываем
            .onAppear {
                if isReadOnlyBlocked {
                    showReadOnlyAlert = true
                }
            }
            .alert("Ошибка", isPresented: $showReadOnlyAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Доступен только просмотр. Чтобы редактировать проект, оформите или продлите подписку.")
            }
        }
    }

    // MARK: - Цвета выбора
    private var colorPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableColors, id: \.id) { color in
                    let isSelected = (color.id == selectedColor)

                    Button {
                        selectedColor = color.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(color.id))
                                .frame(width: 20, height: 20)

                            Text(color.title)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected
                                      ? Color(color.id).opacity(0.25)
                                      : Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected
                                        ? Color(color.id)
                                        : Color.secondary.opacity(0.2),
                                        lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Обложка проекта
    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // --- Кликабельная обложка как отдельная кнопка ---
            Button {
                showPhotoPicker = true
            } label: {
                ZStack {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16/9, contentMode: .fit)
                            .clipped()
                            .cornerRadius(14)
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.title2)
                                    Text("Добавить обложку")
                                        .font(.footnote.weight(.medium))
                                    Text("Рекомендуем горизонтальное фото фасада.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            )
                    }
                }
            }
            .buttonStyle(.plain)

            // --- Кнопки при наличии обложки ---
            if coverImage != nil {
                HStack {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Заменить фото", systemImage: "arrow.clockwise")
                    }
                    .font(.footnote)

                    Spacer()

                    Button(role: .destructive) {
                        // Вариант A: просто очищаем обложку, без автозапуска галереи
                        coverImage = nil
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    .font(.footnote)
                }
            }
        }
    }

    // MARK: - Save
    private func saveChanges() {
        // Read-only: блокируем любые изменения, если подписки нет/истекла (и это не DEMO)
        if isReadOnlyBlocked {
            showReadOnlyAlert = true
            return
        }

        var updated = project
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : descriptionText
        updated.cardColor = selectedColor
        updated.lastUpdated = Date()

        // Обновление проекта
        try? store.updateProject(updated)

        // Сохранение обложки
        if let coverImage {
            CoverImageStore.shared.saveCover(coverImage, for: project.id)
        } else {
            CoverImageStore.shared.deleteCover(for: project.id)
        }

        dismiss()
    }
}
