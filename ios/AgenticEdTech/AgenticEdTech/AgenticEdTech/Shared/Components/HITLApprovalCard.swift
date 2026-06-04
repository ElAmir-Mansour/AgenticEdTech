import SwiftUI

struct HITLCheckpoint {
    let id: String
    let description: String
}

struct HITLApprovalCard: View {
    let checkpoint: HITLCheckpoint
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with warning icon
            Label("Approval Required", systemImage: "hand.raised.fill")
                .font(.titleMedium)
                .foregroundStyle(Color.warning)
            
            // Content preview
            Text(checkpoint.description)
                .font(.bodyMedium)
                .foregroundStyle(.primary)
            
            // Action buttons
            HStack(spacing: Spacing.md) {
                Button("Reject", role: .destructive) { onReject() }
                    .buttonStyle(.bordered)
                
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.success)
            }
        }
        .padding(Spacing.lg)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}
