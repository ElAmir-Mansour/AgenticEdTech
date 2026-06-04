import SwiftUI

struct BrandButton: View {
    let title: String
    var icon: String? = nil
    var role: ButtonRole? = nil
    var style: Style = .primary
    var isLoading: Bool = false
    let action: () -> Void
    
    enum Style {
        case primary
        case secondary
        case destructive
        case glass
    }
    
    var body: some View {
        Button(role: role, action: {
            // Haptic feedback on tap
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(style == .glass ? Color.brand : .white)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.body.weight(.semibold))
                    }
                    Text(title)
                        .font(.bodyMedium)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, Spacing.lg)
            .foregroundStyle(foregroundColor)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: style == .glass ? 1 : 0)
            )
            .shadow(color: shadowColor, radius: style == .primary ? 8 : 4, y: style == .primary ? 4 : 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoading)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            LinearGradient(
                colors: [Color.brand, Color.brandDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            Color.brand.opacity(0.15)
        case .destructive:
            LinearGradient(
                colors: [Color.error, Color.error.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .glass:
            Color.white.opacity(0.05)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary: return Color.brand
        case .glass: return Color.brandLight
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .glass: return Color.white.opacity(0.15)
        default: return .clear
        }
    }
    
    private var shadowColor: Color {
        switch style {
        case .primary: return Color.brand.opacity(0.4)
        case .destructive: return Color.error.opacity(0.3)
        case .secondary: return Color.brand.opacity(0.1)
        case .glass: return .clear
        }
    }
}

/// Makes buttons scale down on press for a satisfying tactile feel
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
