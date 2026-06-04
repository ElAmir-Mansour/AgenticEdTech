import SwiftUI

struct GlassView<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var bodyColor: Color = Color.white.opacity(0.05)
    var borderColor: Color = Color.white.opacity(0.15)
    let content: () -> Content
    
    var body: some View {
        content()
            .background(.ultraThinMaterial)
            .background(bodyColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}
