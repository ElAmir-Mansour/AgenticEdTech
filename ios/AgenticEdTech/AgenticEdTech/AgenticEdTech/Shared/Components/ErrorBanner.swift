import SwiftUI

/// Reusable, dismissible status banner for errors, warnings, and info messages.
/// Replaces inline Text() error displays with a proper, animated component.
struct StatusBanner: View {
    let message: String
    let variant: Variant
    var onDismiss: (() -> Void)? = nil
    
    enum Variant {
        case error
        case warning
        case info
        case success
        
        var icon: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
        
        var tintColor: Color {
            switch self {
            case .error: return Color.error
            case .warning: return Color.warning
            case .info: return Color.info
            case .success: return Color.success
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .error: return Color.error.opacity(0.12)
            case .warning: return Color.warning.opacity(0.12)
            case .info: return Color.info.opacity(0.12)
            case .success: return Color.success.opacity(0.12)
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: variant.icon)
                .font(.body)
                .foregroundStyle(variant.tintColor)
            
            Text(message)
                .font(.bodySmall)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(variant.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(variant.tintColor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

/// Auto-dismissing error banner modifier
struct AutoDismissErrorBanner: ViewModifier {
    @Binding var errorMessage: String?
    var duration: TimeInterval = 8.0
    
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = errorMessage {
                StatusBanner(message: message, variant: .error) {
                    withAnimation { errorMessage = nil }
                }
                .padding(.horizontal)
                .padding(.top, Spacing.sm)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation { errorMessage = nil }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4), value: errorMessage)
    }
}

extension View {
    func errorBanner(_ errorMessage: Binding<String?>, autoDismiss: TimeInterval = 8.0) -> some View {
        self.modifier(AutoDismissErrorBanner(errorMessage: errorMessage, duration: autoDismiss))
    }
}
