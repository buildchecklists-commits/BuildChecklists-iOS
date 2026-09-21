import SwiftUI

struct InfoTextView: View {
    let slug: String
    private let loader = MarkdownLoader()
    @State private var content: AttributedString?

    var body: some View {
        ScrollView {
            if let content {
                Text(content)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Загружаем информацию…").foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }
        }
        .background(Color("CardBG"))
        .navigationTitle("Информация")
        .task {
            do {
                let md = try loader.load(slug: slug)
                content = try? AttributedString(markdown: md)
            } catch {
                content = AttributedString("""
                Текст для ‘\(slug)’ пока не добавлен.

                Добавьте файл **\(slug).md** в каталог **Resources/InfoTexts** (вложенные папки поддерживаются).
                """)
            }
        }
    }
}
