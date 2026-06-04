import SwiftUI
import Charts

// MARK: - Dashboard Data Models

struct ProjectMetrics: Codable {
    let projectId: String
    let projectTitle: String
    let documents: DocumentMetrics
    let concepts: ConceptMetrics
    let modules: ModuleMetrics
    let simulations: SimulationMetrics
}

struct DocumentMetrics: Codable {
    let total: Int
    let completed: Int
    let totalChunks: Int
}

struct ConceptMetrics: Codable {
    let total: Int
    let bloomDistribution: [String: Int]
}

struct ModuleMetrics: Codable {
    let total: Int
}

struct SimulationMetrics: Codable {
    let total: Int
    let totalAnswers: Int
    let totalPassed: Int
    let overallPassRate: Double
    let personaScores: [PersonaScore]
}

struct PersonaScore: Codable, Identifiable {
    var id: String { name }
    let name: String
    let total: Int
    let passed: Int
    let passRate: Double
}

// Chart data helper
struct BloomEntry: Identifiable {
    let id = UUID()
    let level: String
    let count: Int
    let color: Color
}

struct PersonaChartEntry: Identifiable {
    let id = UUID()
    let name: String
    let passRate: Double
}

// MARK: - ViewModel

@Observable
class DashboardViewModel {
    var metrics: ProjectMetrics? = nil
    var isLoading = false
    var errorMessage: String? = nil
    var appState: AppState? = nil
    
    // Computed chart data
    var bloomEntries: [BloomEntry] {
        guard let dist = metrics?.concepts.bloomDistribution else { return [] }
        let colorMap: [String: Color] = [
            "remember": .blue,
            "understand": .cyan,
            "apply": .green,
            "analyze": .yellow,
            "evaluate": .orange,
            "create": .red,
        ]
        return dist.map { key, value in
            BloomEntry(
                level: key.capitalized,
                count: value,
                color: colorMap[key.lowercased()] ?? .gray
            )
        }.sorted { $0.count > $1.count }
    }
    
    var personaEntries: [PersonaChartEntry] {
        guard let scores = metrics?.simulations.personaScores else { return [] }
        return scores.map { PersonaChartEntry(name: $0.name, passRate: $0.passRate) }
    }
    
    func setAppState(_ state: AppState) {
        self.appState = state
        fetchMetrics()
    }
    
    func fetchMetrics() {
        guard let appState = appState, let projectId = appState.selectedProjectID, projectId != "offline-mock" else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let result: ProjectMetrics = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/metrics"
                )
                await MainActor.run {
                    self.metrics = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not load metrics: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var viewModel = DashboardViewModel()
    @State private var pingResponse = "No ping sent yet"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                headerSection
                
                if viewModel.isLoading {
                    ProgressView("Loading metrics...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let metrics = viewModel.metrics {
                    // KPI Summary Cards
                    kpiCardsSection(metrics: metrics)
                    
                    // Charts Row
                    chartsSection(metrics: metrics)
                    
                    // Persona Performance
                    if !viewModel.personaEntries.isEmpty {
                        personaSection(metrics: metrics)
                    }
                    
                    // System Health
                    systemHealthSection
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.05))
        .onAppear {
            viewModel.setAppState(appState)
        }
        .refreshable {
            viewModel.fetchMetrics()
        }
        .onReceive(WebSocketManager.shared.messagePublisher) { serverMsg in
            if serverMsg.type == "pong" {
                pingResponse = "✅ Received PONG from server!"
            } else {
                pingResponse = "📨 Event: \(serverMsg.type)"
            }
        }
        .errorBanner($viewModel.errorMessage, autoDismiss: 10.0)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        GlassView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Agentic EdTech Control Center")
                    .font(.titleLarge)
                    .foregroundStyle(Color.brandLight)
                Text("Welcome back, \(appState.currentUserName ?? "Developer"). Here's your project overview.")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
    
    // MARK: - KPI Cards
    
    private func kpiCardsSection(metrics: ProjectMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Key Metrics")
                .font(.titleMedium)
                .foregroundStyle(.primary)
            
            let isCompact = sizeClass == .compact
            let layout = isCompact
                ? AnyLayout(LazyVGridLayout(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md))
                : AnyLayout(HStackLayout(spacing: Spacing.md))
            
            layout {
                MetricCard(
                    title: "Documents",
                    value: "\(metrics.documents.total)",
                    subtitle: "\(metrics.documents.completed) processed",
                    icon: "doc.text.fill",
                    accentColor: .cyan
                )
                MetricCard(
                    title: "Concepts",
                    value: "\(metrics.concepts.total)",
                    subtitle: "Knowledge graph nodes",
                    icon: "point.3.connected.trianglepath.dotted",
                    accentColor: .purple
                )
                MetricCard(
                    title: "Modules",
                    value: "\(metrics.modules.total)",
                    subtitle: "Curriculum blocks",
                    icon: "square.stack.3d.up.fill",
                    accentColor: .orange
                )
                MetricCard(
                    title: "Pass Rate",
                    value: "\(Int(metrics.simulations.overallPassRate))%",
                    subtitle: "\(metrics.simulations.totalPassed)/\(metrics.simulations.totalAnswers) correct",
                    icon: "checkmark.seal.fill",
                    accentColor: metrics.simulations.overallPassRate >= 70 ? .green : .yellow
                )
            }
        }
    }
    
    // MARK: - Charts
    
    private func chartsSection(metrics: ProjectMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Analytics")
                .font(.titleMedium)
            
            let isCompact = sizeClass == .compact
            let layout = isCompact
                ? AnyLayout(VStackLayout(spacing: Spacing.md))
                : AnyLayout(HStackLayout(spacing: Spacing.md))
            
            layout {
                // Bloom's Taxonomy Distribution
                GlassView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Bloom's Taxonomy Distribution")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                        
                        if viewModel.bloomEntries.isEmpty {
                            Text("No concept data available yet")
                                .font(.codeSmall)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                        } else {
                            Chart(viewModel.bloomEntries) { entry in
                                BarMark(
                                    x: .value("Level", entry.level),
                                    y: .value("Count", entry.count)
                                )
                                .foregroundStyle(entry.color.gradient)
                                .cornerRadius(6)
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisValueLabel()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .chartXAxis {
                                AxisMarks { _ in
                                    AxisValueLabel()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 180)
                        }
                    }
                    .padding()
                }
                
                // Document Processing Status
                GlassView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Document Processing")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                        
                        let processed = metrics.documents.completed
                        let pending = metrics.documents.total - metrics.documents.completed
                        
                        if metrics.documents.total == 0 {
                            Text("No documents uploaded yet")
                                .font(.codeSmall)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                        } else {
                            Chart {
                                SectorMark(
                                    angle: .value("Processed", processed),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color.success.gradient)
                                .annotation(position: .overlay) {
                                    Text("\(processed)")
                                        .font(.codeSmall)
                                        .foregroundStyle(.white)
                                }
                                
                                SectorMark(
                                    angle: .value("Pending", max(pending, 0)),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color.warning.gradient)
                                .annotation(position: .overlay) {
                                    if pending > 0 {
                                        Text("\(pending)")
                                            .font(.codeSmall)
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .frame(minHeight: 180)
                            
                            HStack(spacing: Spacing.md) {
                                Label("Processed", systemImage: "checkmark.circle.fill")
                                    .font(.codeSmall)
                                    .foregroundStyle(Color.success)
                                Label("Pending", systemImage: "clock.fill")
                                    .font(.codeSmall)
                                    .foregroundStyle(Color.warning)
                            }
                        }
                        
                        Text("\(metrics.documents.totalChunks) total chunks indexed")
                            .font(.codeSmall)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Persona Performance
    
    private func personaSection(metrics: ProjectMetrics) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Persona Simulation Scores")
                .font(.titleMedium)
            
            GlassView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Chart(viewModel.personaEntries) { entry in
                        BarMark(
                            x: .value("Pass Rate", entry.passRate),
                            y: .value("Persona", entry.name)
                        )
                        .foregroundStyle(
                            entry.passRate >= 70
                                ? Color.success.gradient
                                : entry.passRate >= 50
                                    ? Color.warning.gradient
                                    : Color.error.gradient
                        )
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(Int(entry.passRate))%")
                                .font(.codeSmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(position: .bottom, values: [0, 25, 50, 75, 100]) { _ in
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.3))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: CGFloat(max(viewModel.personaEntries.count * 50, 100)))
                }
                .padding()
            }
        }
    }
    
    // MARK: - System Health
    
    private var systemHealthSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("System Health")
                .font(.titleMedium)
            
            let isCompact = sizeClass == .compact
            let layout = isCompact
                ? AnyLayout(VStackLayout(spacing: Spacing.md))
                : AnyLayout(HStackLayout(spacing: Spacing.md))
            
            layout {
                GlassView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.xs) {
                            PulsingStatusDot(color: WebSocketManager.shared.isConnected ? Color.success : Color.warning)
                            Label("Server Connection", systemImage: "bolt.horizontal.fill")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.brandLight)
                        }
                        
                        if !pingResponse.isEmpty {
                            Text(pingResponse)
                                .font(.codeSmall)
                                .foregroundStyle(.secondary)
                        }
                        
                        BrandButton(title: "Test Connection", icon: "antenna.radiowaves.left.and.right", style: .glass) {
                            if let token = appState.authToken {
                                WebSocketManager.shared.connect(token: token)
                            }
                            WebSocketManager.shared.send(message: ClientMessage(
                                type: "ping",
                                workspace: "dashboard",
                                payload: [:]
                            ))
                            pingResponse = "⏳ Sending ping..."
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GlassView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Console")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                        
                        Text(pingResponse)
                            .font(.codeSmall)
                            .foregroundStyle(Color.brandLight)
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - KPI Metric Card Component

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    
    var body: some View {
        GlassView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                    Spacer()
                }
                
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(title)
                    .font(.bodySmall)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.codeSmall)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding()
        }
    }
}

// MARK: - Grid Layout Helper

struct LazyVGridLayout: Layout {
    let columns: [GridItem]
    let spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let colCount = columns.count
        let colWidth = (width - spacing * CGFloat(colCount - 1)) / CGFloat(colCount)
        let rowCount = (subviews.count + colCount - 1) / colCount
        var totalHeight: CGFloat = 0
        
        for row in 0..<rowCount {
            var maxH: CGFloat = 0
            for col in 0..<colCount {
                let idx = row * colCount + col
                if idx < subviews.count {
                    let size = subviews[idx].sizeThatFits(.init(width: colWidth, height: nil))
                    maxH = max(maxH, size.height)
                }
            }
            totalHeight += maxH
        }
        totalHeight += spacing * CGFloat(max(rowCount - 1, 0))
        return CGSize(width: width, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let colCount = columns.count
        let colWidth = (bounds.width - spacing * CGFloat(colCount - 1)) / CGFloat(colCount)
        var y = bounds.minY
        let rowCount = (subviews.count + colCount - 1) / colCount
        
        for row in 0..<rowCount {
            var maxH: CGFloat = 0
            for col in 0..<colCount {
                let idx = row * colCount + col
                if idx < subviews.count {
                    let size = subviews[idx].sizeThatFits(.init(width: colWidth, height: nil))
                    maxH = max(maxH, size.height)
                }
            }
            for col in 0..<colCount {
                let idx = row * colCount + col
                if idx < subviews.count {
                    let x = bounds.minX + CGFloat(col) * (colWidth + spacing)
                    subviews[idx].place(
                        at: CGPoint(x: x, y: y),
                        anchor: .topLeading,
                        proposal: .init(width: colWidth, height: maxH)
                    )
                }
            }
            y += maxH + spacing
        }
    }
}

// MARK: - Pulsing Status Dot Helper View
struct PulsingStatusDot: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.8
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        scale = 1.5
                        opacity = 0.0
                    }
                }
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
    }
}
