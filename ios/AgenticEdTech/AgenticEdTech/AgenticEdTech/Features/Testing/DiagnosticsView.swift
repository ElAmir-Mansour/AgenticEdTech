import SwiftUI

struct DiagnosticsView: View {
    @StateObject private var testRunner = AppTestRunner()
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header Panel
                GlassView {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Diagnostics & Verification")
                                .font(.titleLarge)
                                .foregroundStyle(Color.brandLight)
                            Text("Verify client integrity, mock serialization, and real-time backend links.")
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        
                        Button(action: {
                            Task {
                                await testRunner.runAllTests(appState: appState)
                            }
                        }) {
                            HStack {
                                if testRunner.isTesting {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, Spacing.xs)
                                }
                                Text(testRunner.isTesting ? "Running Tests..." : "Run Test Suite")
                                    .font(.bodyMedium)
                                    .bold()
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(testRunner.isTesting ? Color.secondary : Color.brand)
                            .clipShape(Capsule())
                        }
                        .disabled(testRunner.isTesting)
                    }
                    .padding()
                }
                
                // Summary Stats
                let total = testRunner.testResults.count
                let passed = testRunner.testResults.filter { $0.status == .passed }.count
                let failed = testRunner.testResults.filter { $0.status == .failed }.count
                
                HStack(spacing: Spacing.md) {
                    StatBox(title: "Total Tests", value: "\(total)", color: .brandLight)
                    StatBox(title: "Passed", value: "\(passed)", color: .success)
                    StatBox(title: "Failed", value: "\(failed)", color: .error)
                }
                
                // Test Results List
                Text("Verification Assertions")
                    .font(.titleMedium)
                
                VStack(spacing: Spacing.sm) {
                    ForEach(testRunner.testResults) { result in
                        GlassView {
                            HStack(spacing: Spacing.md) {
                                // Status Icon
                                Group {
                                    switch result.status {
                                    case .pending:
                                        Circle()
                                            .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                    case .running:
                                        ProgressView()
                                            .tint(Color.brandLight)
                                            .frame(width: 24, height: 24)
                                    case .passed:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.success)
                                            .font(.titleMedium)
                                    case .failed:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.error)
                                            .font(.titleMedium)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    HStack {
                                        Text(result.name)
                                            .font(.bodyMedium)
                                            .bold()
                                        
                                        Spacer()
                                        
                                        Text(result.category.uppercased())
                                            .font(.agentLabel)
                                            .padding(.horizontal, Spacing.xs)
                                            .padding(.vertical, 2)
                                            .background(Color.brand.opacity(0.1))
                                            .foregroundStyle(Color.brandLight)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    
                                    if !result.message.isEmpty {
                                        Text(result.message)
                                            .font(.bodySmall)
                                            .foregroundStyle(result.status == .failed ? Color.error : .secondary)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                
                // Verification Logs
                Text("Test Log Output")
                    .font(.titleMedium)
                
                GlassView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if testRunner.logs.isEmpty {
                                Text("Ready to test app components...")
                                    .font(.bodySmall)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(testRunner.logs, id: \.self) { log in
                                    Text(log)
                                        .font(.codeSmall)
                                        .foregroundStyle(log.contains("❌") ? Color.error : (log.contains("✅") ? Color.success : .primary))
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
            }
            .padding()
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        GlassView {
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.displayLarge)
                    .foregroundStyle(color)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}
