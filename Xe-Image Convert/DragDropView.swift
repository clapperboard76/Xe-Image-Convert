import SwiftUI
import UniformTypeIdentifiers

struct DragDropView: View {
    @Binding var droppedImageURLs: [URL]
    @State private var isDragging = false
    @State private var showFilePicker = false

    var body: some View {
        Button { showFilePicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDragging ? Color.accentColor.opacity(0.08) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)

                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDragging)

                HStack(spacing: 14) {
                    Image(systemName: isDragging ? "arrow.down.circle.fill" : "photo.stack")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
                        .animation(.easeInOut(duration: 0.15), value: isDragging)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isDragging ? "Drop to add" : "Drag images or folders here")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("or click to browse")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { droppedImageURLs.append(url) }
                    }
                }
            }
            return true
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image, .folder] + (["afdesign", "afphoto", "afpub", "af"].compactMap { UTType(filenameExtension: $0) }),
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    _ = url.startAccessingSecurityScopedResource()
                    DispatchQueue.main.async { droppedImageURLs.append(url) }
                }
            }
        }
    }
}
