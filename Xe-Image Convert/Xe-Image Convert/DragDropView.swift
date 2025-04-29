import SwiftUI

struct DragDropView: View {
    @Binding var droppedImageURLs: [URL]
    @State private var isDragging = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDragging ? Color.accentColor : Color.gray, lineWidth: 3)
                .background(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
                .animation(.easeInOut, value: isDragging)
            VStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                Text("Drag images here to convert")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
        }
        .frame(height: 180)
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