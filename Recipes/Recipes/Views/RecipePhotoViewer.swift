import SwiftUI
import UIKit

struct RecipePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    
    let photoData: [Data]
    @Binding var selectedIndex: Int
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(Array(photoData.enumerated()), id: \.offset) { index, data in
                    ZoomableRecipeImageView(data: data)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photoData.count > 1 ? .automatic : .never))
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                // Guard against a stale binding value pointing past the end of
                // the array (e.g. photos removed before reopening the viewer).
                if selectedIndex >= photoData.count {
                    selectedIndex = max(0, photoData.count - 1)
                }
            }

            VStack {
                HStack(spacing: 12) {
                    if photoData.count > 1 {
                        Text("\(selectedIndex + 1) of \(photoData.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .accessibilityLabel("Close photo viewer")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Spacer()
                
                Text("Pinch to zoom • Drag to pan • Double-tap to reset")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .statusBarHidden(true)
    }
}

private struct ZoomableRecipeImageView: View {
    let data: Data
    
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        // Pan only while zoomed in — at 1x the drag gesture
                        // competed with the TabView's page swipe.
                        .gesture(scale > 1.01 ? dragGesture : nil)
                        .simultaneousGesture(magnificationGesture)
                        .onTapGesture(count: 2) {
                            resetZoom()
                        }
                        .animation(.easeOut(duration: 0.16), value: scale)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = lastScale * value
                scale = max(1, min(next, 5))
                
                if scale <= 1.01 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .onEnded { value in
                let next = lastScale * value
                scale = max(1, min(next, 5))
                lastScale = scale
                
                if scale <= 1.01 {
                    resetZoom()
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1 else {
                    offset = .zero
                    lastOffset = .zero
                    return
                }
                lastOffset = offset
            }
    }
    
    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
