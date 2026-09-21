import Foundation

// MARK: - Упрощённая материализация без загрузки любых паков
// ВАЖНО: Этот файл deliberately игнорирует любые foundation_/walls_/roof_/slab_ пакеты,
// чтобы не было попыток открыть удалённые ресурсы. Он просто превращает seed-этапы
// в обычные Stage с их пунктами как есть.
//
// Когда подключим новые провайдеры для стен/крыши/перекрытий — вернём точечную логику.

extension SeedStage {
    func materialize(using project: Project, loader: SeedPackLoader) -> Stage {
        // Просто копируем items, без попыток что-то подгружать из паков
        let built: [StageItem] = items.map { seed in
            StageItem(
                id: UUID(),
                code: seed.code,
                title: seed.title,
                status: .na,
                severity: .medium,
                photoPaths: [],
                pdfPaths: []
            )
        }

        return Stage(
            id: self.id,
            title: self.title,
            items: built
        )
    }
}
