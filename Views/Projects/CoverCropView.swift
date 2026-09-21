import SwiftUI
import UIKit

/// Экран кадрирования обложки проекта под формат 16:9
struct CoverCropView: View {
    let sourceImage: UIImage
    let onCancel: () -> Void
    let onDone: (UIImage) -> Void

    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    @State private var cropSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Верхние кнопки — всегда кликабельны
                    HStack {
                        Button(action: { onCancel() }) {
                            Text("Отмена")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Button(action: {
                            if let img = renderCroppedImage() {
                                onDone(img)
                            } else {
                                onCancel()
                            }
                        }) {
                            Text("Использовать")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    GeometryReader { geo in
                        // Фиксированная рамка 16:9, адаптивная по ширине экрана
                        let horizontalPadding: CGFloat = 24
                        let availableWidth = geo.size.width - horizontalPadding * 2
                        let width = availableWidth
                        let height = width * 9.0 / 16.0      // строгое 16:9

                        let size = CGSize(width: width, height: height)

                        VStack {
                            Spacer(minLength: 0)

                            cropArea(size: size)
                                .frame(width: size.width, height: size.height)
                                .onAppear {
                                    cropSize = size
                                }
                                .onChange(of: geo.size) { _, _ in
                                    cropSize = size
                                }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Text("Пальцами масштабируйте и перетаскивайте фото, чтобы подобрать идеальную обложку.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 16)
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Crop Area (живой предпросмотр)

    private func cropArea(size: CGSize) -> some View {
        let totalScale = baseScale * gestureScale
        let totalOffset = CGSize(
            width: baseOffset.width + gestureOffset.width,
            height: baseOffset.height + gestureOffset.height
        )

        return CroppingImageView(
            image: sourceImage,
            scale: totalScale,
            offset: totalOffset
        )
        .clipped() // обрезаем по рамке
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .contentShape(Rectangle()) // жест только по рамке
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        // Обновляем базовый масштаб и не даём уменьшать меньше заполнения рамки
                        var newScale = baseScale * value
                        newScale = max(newScale, 1)

                        // После изменения масштаба поджимаем смещение,
                        // чтобы картинка всё равно полностью закрывала рамку
                        let clamped = clampedOffset(baseOffset,
                                                    frameSize: size,
                                                    scale: newScale)
                        baseScale = newScale
                        baseOffset = clamped
                    },
                DragGesture()
                    .updating($gestureOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let proposed = CGSize(
                            width: baseOffset.width + value.translation.width,
                            height: baseOffset.height + value.translation.height
                        )

                        // Поджимаем смещение, чтобы не было чёрных полос по краям
                        let clamped = clampedOffset(proposed,
                                                    frameSize: size,
                                                    scale: baseScale)
                        baseOffset = clamped
                    }
            )
        )
    }

    /// Поджимает offset так, чтобы изображение всегда полностью закрывало рамку 16:9,
    /// без провалов фона по краям.
    private func clampedOffset(_ offset: CGSize,
                               frameSize: CGSize,
                               scale: CGFloat) -> CGSize {
        let imageSize = sourceImage.size

        // Масштаб, чтобы картинка заполнила рамку хотя бы по одной стороне
        let scaleToFill = max(frameSize.width / imageSize.width,
                              frameSize.height / imageSize.height)

        let totalScale = scaleToFill * scale
        let displayWidth = imageSize.width * totalScale
        let displayHeight = imageSize.height * totalScale

        let limitX = max(0, (displayWidth - frameSize.width) / 2)
        let limitY = max(0, (displayHeight - frameSize.height) / 2)

        var result = offset

        if limitX > 0 {
            result.width = min(max(result.width, -limitX), limitX)
        } else {
            result.width = 0
        }

        if limitY > 0 {
            result.height = min(max(result.height, -limitY), limitY)
        } else {
            result.height = 0
        }

        return result
    }

    // MARK: - Рендер результата (реальный кроп из UIImage)

    private func renderCroppedImage() -> UIImage? {
        guard cropSize.width > 0, cropSize.height > 0 else { return nil }

        let frameSize = cropSize                // размер окна кропа в поинтах
        let image = sourceImage
        let imgSizePoints = image.size          // поинты

        // базовый scale, чтобы заполнить 16:9
        let scaleToFill = max(frameSize.width / imgSizePoints.width,
                              frameSize.height / imgSizePoints.height)

        let extraScale = baseScale
        let totalScale = scaleToFill * extraScale

        let displayWidth = imgSizePoints.width * totalScale
        let displayHeight = imgSizePoints.height * totalScale

        let originX = (frameSize.width - displayWidth) / 2.0 + baseOffset.width
        let originY = (frameSize.height - displayHeight) / 2.0 + baseOffset.height

        let scaleXToImage = imgSizePoints.width / displayWidth
        let scaleYToImage = imgSizePoints.height / displayHeight

        var cropRectPoints = CGRect(
            x: (-originX) * scaleXToImage,
            y: (-originY) * scaleYToImage,
            width: frameSize.width * scaleXToImage,
            height: frameSize.height * scaleYToImage
        )

        cropRectPoints.origin.x = max(0, cropRectPoints.origin.x)
        cropRectPoints.origin.y = max(0, cropRectPoints.origin.y)

        let maxX = imgSizePoints.width
        let maxY = imgSizePoints.height

        if cropRectPoints.maxX > maxX {
            cropRectPoints.size.width = maxX - cropRectPoints.origin.x
        }
        if cropRectPoints.maxY > maxY {
            cropRectPoints.size.height = maxY - cropRectPoints.origin.y
        }

        let scale = image.scale
        var cropRectPixels = CGRect(
            x: cropRectPoints.origin.x * scale,
            y: cropRectPoints.origin.y * scale,
            width: cropRectPoints.size.width * scale,
            height: cropRectPoints.size.height * scale
        ).integral

        guard let cgImage = image.cgImage else { return nil }

        let maxPixelWidth = CGFloat(cgImage.width)
        let maxPixelHeight = CGFloat(cgImage.height)

        cropRectPixels.origin.x = max(0, min(cropRectPixels.origin.x, maxPixelWidth))
        cropRectPixels.origin.y = max(0, min(cropRectPixels.origin.y, maxPixelHeight))

        if cropRectPixels.maxX > maxPixelWidth {
            cropRectPixels.size.width = maxPixelWidth - cropRectPixels.origin.x
        }
        if cropRectPixels.maxY > maxPixelHeight {
            cropRectPixels.size.height = maxPixelHeight - cropRectPixels.origin.y
        }

        guard let croppedCG = cgImage.cropping(to: cropRectPixels) else { return nil }

        let croppedImage = UIImage(
            cgImage: croppedCG,
            scale: image.scale,
            orientation: image.imageOrientation
        )

        // окончательно приводим к ровному размеру рамки (16:9)
        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let finalImage = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: frameSize))
        }

        return finalImage
    }
}

/// Вспомогательный вью для предпросмотра
private struct CroppingImageView: View {
    let image: UIImage
    let scale: CGFloat
    let offset: CGSize

    var body: some View {
        ZStack {
            Color.black

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scale)
                .offset(offset)
        }
    }
}
