import SwiftUI

struct DragDropView: View {
    @Binding var droppedImageURLs: [URL]
    @State private var isDragging = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDragging ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isDragging ? 2 : 1)
                .background(Color(NSColor.controlBackgroundColor))
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)
                Text("Drag images here to convert")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: $isDragging) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.droppedImageURLs.append(url)
                        }
                    }
                }
            }
            return true
        }
    }
} 