import Foundation
import UIKit

struct MediaService {
    private let maxImageDimension: CGFloat = 2000

    private var imagesDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("BC_Media/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var pdfDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("BC_Media/PDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Public API

    func save(image: UIImage) throws -> String {
        let processedImage = resizedImageIfNeeded(image)

        let name = UUID().uuidString + ".jpg"
        let url = imagesDir.appendingPathComponent(name)

        guard let data = processedImage.jpegData(compressionQuality: 0.9) else {
            throw NSError(
                domain: "Media",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"]
            )
        }

        try data.write(to: url, options: .atomic)
        return url.path
    }

    func save(pdfData: Data, name: String?) throws -> String {
        let file = (name?.isEmpty == false ? name! : UUID().uuidString) + ".pdf"
        let url = pdfDir.appendingPathComponent(file)
        try pdfData.write(to: url, options: .atomic)
        return url.path
    }

    func deleteFile(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers

    private func resizedImageIfNeeded(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let maxCurrentDimension = max(size.width, size.height)
        guard maxCurrentDimension > maxImageDimension else {
            return image
        }

        let scale = maxImageDimension / maxCurrentDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Универсальный поиск сохранённых файлов
func existingFileURL(_ path: String) -> URL? {
    let fm = FileManager.default

    // 1 — абсолютный путь
    if fm.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
    }

    let directURL = URL(fileURLWithPath: path)
    if fm.fileExists(atPath: directURL.path) {
        return directURL
    }

    // 2 — Documents
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
        let relativeURL = docs.appendingPathComponent(path)
        if fm.fileExists(atPath: relativeURL.path) {
            return relativeURL
        }

        let fileName = (path as NSString).lastPathComponent

        // NEW: PDF каталог (исправление!)
        let pdfNew = docs
            .appendingPathComponent("BC_Media/PDF", isDirectory: true)
            .appendingPathComponent(fileName)
        if fm.fileExists(atPath: pdfNew.path) {
            return pdfNew
        }

        // NEW: Images каталог
        let imagesNew = docs
            .appendingPathComponent("BC_Media/Images", isDirectory: true)
            .appendingPathComponent(fileName)
        if fm.fileExists(atPath: imagesNew.path) {
            return imagesNew
        }

        // Старые каталоги
        let photosOld = docs.appendingPathComponent("BCPhotos").appendingPathComponent(fileName)
        if fm.fileExists(atPath: photosOld.path) {
            return photosOld
        }

        let docsOld = docs.appendingPathComponent("BCDocs").appendingPathComponent(fileName)
        if fm.fileExists(atPath: docsOld.path) {
            return docsOld
        }
    }

    // 3 — tmp
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent((path as NSString).lastPathComponent)
    if fm.fileExists(atPath: tmpURL.path) {
        return tmpURL
    }

    // 4 — caches
    if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let cacheURL = caches
            .appendingPathComponent((path as NSString).lastPathComponent)
        if fm.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }
    }

    return nil
}
