import SwiftUI

struct AgentMessage: Identifiable {
    let id = UUID()
    let agentRole: AgentRole
    let messageType: String
    let content: String
    let timestamp: Date
    
    enum AgentRole: String {
        case planning = "Planning Agent"
        case content = "Content Agent"
        case assessment = "Assessment Agent"
        case critique = "Critique Agent"
        case heatmap = "Heatmap Agent"
        
        var color: Color {
            switch self {
            case .planning: return Color.agentPlanning
            case .content: return Color.agentContent
            case .assessment: return Color.agentAssessment
            case .critique: return Color.agentCritique
            case .heatmap: return Color.warning
            }
        }
        
        var icon: String {
            switch self {
            case .planning: return "list.bullet.clipboard"
            case .content: return "pencil.and.outline"
            case .assessment: return "checkmark.seal"
            case .critique: return "exclamationmark.bubble"
            case .heatmap: return "waveform.path.ecg"
            }
        }
    }
}

struct AgentMessageBubble: View {
    let message: AgentMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Agent Icon Avatar
            Circle()
                .fill(message.agentRole.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: message.agentRole.icon)
                        .font(.caption)
                        .foregroundStyle(.white)
                )
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Agent Header Name + Time
                HStack {
                    Text(message.agentRole.rawValue)
                        .font(.agentLabel)
                        .foregroundStyle(message.agentRole.color)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Text Message with markdown support
                Text(LocalizedStringKey(message.content))
                    .font(.bodyMedium)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TypingIndicatorView: View {
    let color: Color
    @State private var bounce1 = false
    @State private var bounce2 = false
    @State private var bounce3 = false
    
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6).offset(y: bounce1 ? -5 : 0)
            Circle().fill(color).frame(width: 6, height: 6).offset(y: bounce2 ? -5 : 0)
            Circle().fill(color).frame(width: 6, height: 6).offset(y: bounce3 ? -5 : 0)
        }
        .onAppear {
            let baseDuration: TimeInterval = 0.5
            let delay: TimeInterval = 0.15
            
            withAnimation(Animation.easeInOut(duration: baseDuration).repeatForever()) { bounce1 = true }
            withAnimation(Animation.easeInOut(duration: baseDuration).repeatForever().delay(delay)) { bounce2 = true }
            withAnimation(Animation.easeInOut(duration: baseDuration).repeatForever().delay(delay * 2)) { bounce3 = true }
        }
    }
}
