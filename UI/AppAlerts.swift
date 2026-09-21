enum AppAlerts {

    static let readOnly = AppAlert(
        title: "Доступ ограничен",
        message: "Сейчас доступен только просмотр. Чтобы добавлять, редактировать или удалять данные, оформите или продлите подписку."
    )

    static func genericError(_ details: String? = nil) -> AppAlert {
        AppAlert(
            title: "Ошибка",
            message: details ?? "Произошла ошибка. Попробуйте ещё раз."
        )
    }
}
