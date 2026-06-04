import SwiftUI

// Structs representing simulation results
struct Persona: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var background: String
    var attentionSpan: String // Low, Medium, High
    var experience: String // Beginner, Intermediate, Expert
    var passRate: Int // Percentage
    var errorRate: Double // Probability of error, 0.0 - 1.0
    var isSimulated: Bool = false
    var statusText: String = "Ready"

    enum CodingKeys: String, CodingKey {
        case name
        case background
        case attentionSpan
        case experience
        case passRate
        case errorRate
    }
    
    static func == (lhs: Persona, rhs: Persona) -> Bool {
        lhs.id == rhs.id
    }
}

struct SimulationResponse: Codable {
    let runId: String
    let logs: [String]
    let passRates: [String: Int]
    let bloomHeatmap: [String: Double]
    let cohortSize: Int?
    let standardDeviation: Double?
    let averageResponseTime: Double?
    let predictedRoiSavings: Double?
    let questionFailureRates: [String: Double]?
}

struct RunSimulationRequest: Codable {
    let moduleId: String
    let personas: [Persona]
    let cohortSize: Int?
    let hourlyWage: Double?
}

// Detailed results schemas to match backend responses
struct SimulationRunItem: Identifiable, Codable {
    let id: String
    let projectId: String
    let sessionId: String?
    let status: String
    let personaCount: Int
    let totalQuestions: Int
    let startedAt: String
    let completedAt: String?
    let meta: SimulationRunMeta?
}

struct SimulationRunMeta: Codable {
    let passRates: [String: Int]
    let bloomHeatmap: [String: Double]
    let recommendations: [PedagogicalRecommendation]?
    let logs: [String]?
    let cohortSize: Int?
    let standardDeviation: Double?
    let averageResponseTime: Double?
    let predictedRoiSavings: Double?
    let questionFailureRates: [String: Double]?
}

struct PedagogicalRecommendation: Identifiable, Codable {
    var id: String { target + description }
    let target: String
    let description: String
    let suggestion: String
}

struct PersonaProfileData: Codable {
    let name: String
    let background: String
    let attentionSpan: String
    let experience: String
    let errorRate: Double
}

struct PersonaResultItem: Identifiable, Codable {
    let id: String
    let runId: String
    let personaProfile: PersonaProfileData
    let moduleId: String
    let questionId: String?
    let passed: Bool
    let responseText: String?
    let confusionSignal: String?
    let timeEstimateSeconds: Double?
    let createdAt: String
}

struct SimulationRunDetail: Identifiable, Codable {
    let id: String
    let projectId: String
    let sessionId: String?
    let status: String
    let personaCount: Int
    let totalQuestions: Int
    let startedAt: String
    let completedAt: String?
    let meta: SimulationRunMeta?
    let personaResults: [PersonaResultItem]
}

@Observable
class SimulationViewModel {
    var personas: [Persona] = [
        Persona(name: "Alex", background: "Career Changer (Sales)", attentionSpan: "Low", experience: "Beginner", passRate: 0, errorRate: 0.45),
        Persona(name: "Sofia", background: "Product Associate", attentionSpan: "High", experience: "Intermediate", passRate: 0, errorRate: 0.18),
        Persona(name: "Jordan", background: "Software Dev (Junior)", attentionSpan: "Medium", experience: "Expert", passRate: 0, errorRate: 0.08)
    ]
    
    var modules: [CurriculumModuleResponse] = []
    var selectedModuleId: String = "default"
    
    var isSimulating = false
    var currentQuestion = 0
    var totalQuestions = 5
    var simulationLogs: [String] = []
    var showResults = false
    var appState: AppState? = nil
    
    // New variables for detailed analysis reports & history
    var historyRuns: [SimulationRunItem] = []
    var selectedRunId: String? = nil
    var selectedRunDetail: SimulationRunDetail? = nil
    var recommendations: [PedagogicalRecommendation] = []
    var isLoadingDetail = false
    var cohortSize: Int = 3
    var hourlyWage: Double = 45.0
    
    // Bloom's levels success rates (for heatmap rendering)
    var bloomHeatmap: [String: Double] = [
        "Remember": 0.0,
        "Understand": 0.0,
        "Apply": 0.0,
        "Analyze": 0.0,
        "Evaluate": 0.0,
        "Create": 0.0
    ]
    
    func setAppState(_ state: AppState) {
        self.appState = state
        fetchModules()
        fetchHistory()
    }
    
    func fetchModules() {
        guard let appState = appState, let projectId = appState.selectedProjectID, appState.selectedProjectID != "offline-mock" else { return }
        Task {
            do {
                let fetched: [CurriculumModuleResponse] = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/modules"
                )
                await MainActor.run {
                    self.modules = fetched
                    if let first = fetched.first {
                        self.selectedModuleId = first.id
                    }
                }
            } catch {
                print("Failed to fetch modules for simulation: \(error.localizedDescription)")
            }
        }
    }
    
    func fetchHistory() {
        guard let appState = appState, let projectId = appState.selectedProjectID, appState.selectedProjectID != "offline-mock" else { return }
        Task {
            do {
                let fetched: [SimulationRunItem] = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/simulations"
                )
                await MainActor.run {
                    self.historyRuns = fetched
                }
            } catch {
                print("Failed to fetch simulation history: \(error.localizedDescription)")
            }
        }
    }
    
    func fetchRunDetail(runId: String) {
        guard let appState = appState, let projectId = appState.selectedProjectID, appState.selectedProjectID != "offline-mock" else { return }
        isLoadingDetail = true
        selectedRunId = runId
        Task {
            do {
                let detail: SimulationRunDetail = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/simulations/\(runId)"
                )
                await MainActor.run {
                    self.selectedRunDetail = detail
                    self.isLoadingDetail = false
                    self.showResults = true
                    
                    // Map details to local display state
                    self.simulationLogs = detail.meta?.logs ?? []
                    self.recommendations = detail.meta?.recommendations ?? []
                    
                    // Map bloom heatmap
                    if let heatmap = detail.meta?.bloomHeatmap {
                        self.bloomHeatmap = [:]
                        for (key, val) in heatmap {
                            self.bloomHeatmap[key.capitalized] = val
                        }
                    }
                    
                    // Update personas scores to match the details
                    for i in 0..<self.personas.count {
                        let pName = self.personas[i].name
                        if let passRate = detail.meta?.passRates[pName] {
                            self.personas[i].passRate = passRate
                        }
                        self.personas[i].statusText = "Completed"
                    }
                }
            } catch {
                print("Failed to fetch simulation run detail: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoadingDetail = false
                }
            }
        }
    }
    
    func runSimulation() {
        guard !isSimulating else { return }
        isSimulating = true
        showResults = false
        currentQuestion = 0
        simulationLogs = ["Initializing simulation environment..."]
        selectedRunDetail = nil
        recommendations = []
        
        for i in 0..<personas.count {
            personas[i].statusText = "Testing..."
            personas[i].passRate = 0
        }
        
        bloomHeatmap = [
            "Remember": 0.0,
            "Understand": 0.0,
            "Apply": 0.0,
            "Analyze": 0.0,
            "Evaluate": 0.0,
            "Create": 0.0
        ]
        
        if let appState = appState, let projectId = appState.selectedProjectID, appState.selectedProjectID != "offline-mock" {
            Task {
                do {
                    let reqPayload = RunSimulationRequest(
                        moduleId: selectedModuleId,
                        personas: personas,
                        cohortSize: cohortSize,
                        hourlyWage: hourlyWage
                    )
                    let reqData = try JSONEncoder().encode(reqPayload)
                    
                    let result: SimulationResponse = try await APIClient.shared.request(
                        path: "/api/projects/\(projectId)/simulations/run",
                        method: "POST",
                        body: reqData
                    )
                    
                    await MainActor.run {
                        self.isSimulating = false
                        self.fetchHistory() // Refresh history list
                        self.fetchRunDetail(runId: result.runId)
                    }
                } catch {
                    await MainActor.run {
                        self.runLocalSimulation()
                    }
                }
            }
        } else {
            runLocalSimulation()
        }
    }
    
    private func runLocalSimulation() {
        simulateNextQuestion()
    }
    
    private func simulateNextQuestion() {
        guard currentQuestion < totalQuestions else {
            finishSimulation()
            return
        }
        
        currentQuestion += 1
        
        let moduleName = modules.first(where: { $0.id == selectedModuleId })?.title ?? "Sprint Retrospectives"
        simulationLogs.append("📝 Testing Question \(currentQuestion) on Module: \(moduleName)...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            for i in 0..<self.personas.count {
                let p = self.personas[i]
                // Probabilistic model based on custom errorRate
                let correct = Double.random(in: 0...1) > p.errorRate
                
                let time = correct ? Double.random(in: 1.0...5.0) : Double.random(in: 3.0...10.0)
                let timeStr = String(format: "%.1fs", time)
                
                self.simulationLogs.append("👤 \(p.name) (\(p.experience)): \(correct ? "✅ Correct" : "❌ Incorrect") (\(timeStr))")
                
                // Live pass rate increment
                let increment = correct ? Int(100.0 / Double(self.totalQuestions)) : 0
                self.personas[i].passRate += increment
            }
            
            self.simulateNextQuestion()
        }
    }
    
    private func finishSimulation() {
        isSimulating = false
        showResults = true
        simulationLogs.append("🎉 Classroom simulation finished. Calculating scores...")
        
        for i in 0..<personas.count {
            personas[i].statusText = "Completed"
        }
        
        bloomHeatmap = [
            "Remember": 0.90,
            "Understand": 0.82,
            "Apply": 0.70,
            "Analyze": 0.55,
            "Evaluate": 0.40,
            "Create": 0.30
        ]
        
        // Populate offline recommendations
        self.recommendations = [
            PedagogicalRecommendation(
                target: "Syllabus Clarity",
                description: "Alex (Beginner) failed Question 2 due to confusion over agile terms.",
                suggestion: "Add a glossary or simple introductory definitions of Sprint Goals and Scrum Values."
            ),
            PedagogicalRecommendation(
                target: "Bloom's Level Alignment",
                description: "Sofia (Intermediate) failed Question 4 on evaluating sprint safety.",
                suggestion: "Provide scenario-based examples in the module contents showing safety practices in action."
            )
        ]
        
        // Generate mock question-level results for each question and persona
        var mockResults: [PersonaResultItem] = []
        for qIdx in 1...totalQuestions {
            for persona in personas {
                let passed = Double.random(in: 0...1) > persona.errorRate
                let signals = ["complex_jargon", "missing_prerequisite", "careless_mistake", "ambiguous_options"]
                let confusion = passed ? "none" : signals.randomElement() ?? "complex_jargon"
                let chosen = passed ? "Identify process improvements" : "Assign blame for failures"
                
                let profile = PersonaProfileData(
                    name: persona.name,
                    background: persona.background,
                    attentionSpan: persona.attentionSpan,
                    experience: persona.experience,
                    errorRate: persona.errorRate
                )
                
                mockResults.append(
                    PersonaResultItem(
                        id: UUID().uuidString,
                        runId: "local_run",
                        personaProfile: profile,
                        moduleId: selectedModuleId,
                        questionId: "mock_q_\(qIdx)",
                        passed: passed,
                        responseText: "Chose '\(chosen)': I felt it was the most reasonable step to take based on sales experiences.",
                        confusionSignal: confusion,
                        timeEstimateSeconds: Double.random(in: 5...30),
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
            }
        }
        
        var mockQFailures: [String: Double] = [:]
        for qIdx in 1...totalQuestions {
            mockQFailures["mock_q_\(qIdx)"] = Double.random(in: 10...60).rounded()
        }
        
        self.selectedRunDetail = SimulationRunDetail(
            id: "local_run",
            projectId: "offline-mock",
            sessionId: nil,
            status: "completed",
            personaCount: cohortSize,
            totalQuestions: totalQuestions,
            startedAt: ISO8601DateFormatter().string(from: Date()),
            completedAt: ISO8601DateFormatter().string(from: Date()),
            meta: SimulationRunMeta(
                passRates: personas.reduce(into: [:]) { $0[$1.name] = $1.passRate },
                bloomHeatmap: bloomHeatmap,
                recommendations: recommendations,
                logs: simulationLogs,
                cohortSize: cohortSize,
                standardDeviation: Double.random(in: 5...25).rounded(),
                averageResponseTime: Double.random(in: 3...7).rounded(),
                predictedRoiSavings: Double(cohortSize) * 15.0 * hourlyWage * 0.8,
                questionFailureRates: mockQFailures
            ),
            personaResults: mockResults
        )
    }
}

struct SimulationSandboxView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SimulationViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    // Add/Edit sheet states
    @State private var editingPersona: Persona? = nil
    @State private var showEditSheet = false
    @State private var showAddSheet = false
    
    // Form fields for adding
    @State private var newName = ""
    @State private var newBackground = ""
    @State private var newExperience = "Beginner"
    @State private var newAttentionSpan = "Medium"
    @State private var newErrorRate = 0.3
    
    // Form fields for editing
    @State private var editName = ""
    @State private var editBackground = ""
    @State private var editExperience = "Beginner"
    @State private var editAttentionSpan = "Medium"
    @State private var editErrorRate = 0.3
    
    // Diagnostic segmented tabs
    @State private var selectedTab = 0 // 0 = Overview, 1 = Question Analysis, 2 = AI Recommendations, 3 = Logs
    @State private var showHelpSheet = false
    @State private var expandedQuestionId: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header description
                GlassView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: 8) {
                                    Text("Simulation Sandbox")
                                        .font(.titleLarge)
                                        .foregroundStyle(Color.brandLight)
                                    
                                    Button(action: { showHelpSheet = true }) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.bodyLarge)
                                            .foregroundStyle(Color.brandLight)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Text("Simulate student learning paths. Test how different learners parse your modules before publishing.")
                                    .font(.bodySmall)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            Button(action: { viewModel.runSimulation() }) {
                                Text(viewModel.isSimulating ? "Running..." : "Run Test")
                                    .font(.bodyMedium)
                                    .bold()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, Spacing.lg)
                                    .padding(.vertical, Spacing.sm)
                                    .background(viewModel.isSimulating ? Color.brandDark.opacity(0.5) : Color.brand)
                                    .clipShape(Capsule())
                            }
                            .disabled(viewModel.isSimulating)
                        }
                        
                        if !viewModel.modules.isEmpty {
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            HStack {
                                Text("Target Module:")
                                    .font(.bodySmall)
                                    .bold()
                                    .foregroundStyle(.secondary)
                                Picker("Module Selection", selection: $viewModel.selectedModuleId) {
                                    Text("Default Module (Sprint Retrospectives)").tag("default")
                                    ForEach(viewModel.modules) { module in
                                        Text(module.title).tag(module.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Color.brandLight)
                            }
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        HStack(spacing: Spacing.xl) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("COHORT SIZE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Picker("Cohort Size", selection: $viewModel.cohortSize) {
                                    Text("3 Students (Standard)").tag(3)
                                    Text("15 Students (Classroom)").tag(15)
                                    Text("50 Students (Enterprise)").tag(50)
                                }
                                .pickerStyle(.menu)
                                .tint(Color.brandLight)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HOURLY L&D WAGE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 2) {
                                    Text("$")
                                        .font(.bodySmall)
                                        .foregroundStyle(Color.brandLight)
                                    TextField("Wage", value: $viewModel.hourlyWage, format: .number)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.plain)
                                        .font(.bodySmall)
                                        .frame(width: 44)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // History List
                if !viewModel.historyRuns.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Simulation History")
                            .font(.titleMedium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xs)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                ForEach(viewModel.historyRuns) { run in
                                    Button(action: { viewModel.fetchRunDetail(runId: run.id) }) {
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            HStack {
                                                Text("Run \(run.id.prefix(5))")
                                                    .font(.codeSmall)
                                                    .bold()
                                                    .foregroundStyle(.white)
                                                Spacer()
                                                Text(run.status.capitalized)
                                                    .font(.system(size: 8, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(run.status == "completed" ? Color.success.opacity(0.2) : Color.warning.opacity(0.2))
                                                    .foregroundStyle(run.status == "completed" ? Color.success : Color.warning)
                                                    .clipShape(Capsule())
                                            }
                                            
                                            Text(formatRunTime(run.startedAt))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(viewModel.selectedRunId == run.id ? Color.brand.opacity(0.2) : Color.white.opacity(0.05))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(viewModel.selectedRunId == run.id ? Color.brandLight : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                
                // Live Progress
                if viewModel.isSimulating {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Testing module comprehension...")
                                .font(.bodySmall)
                            Spacer()
                            Text("Question \(viewModel.currentQuestion)/\(viewModel.totalQuestions)")
                                .font(.codeSmall)
                        }
                        ProgressView(value: Double(viewModel.currentQuestion), total: Double(viewModel.totalQuestions))
                            .tint(Color.brand)
                    }
                    .padding()
                    .background(Color.brand.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Segmented picker for analysis tabs
                Picker("Report Section", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Question Analysis").tag(1)
                    Text("AI Recommendations").tag(2)
                    Text("Logs").tag(3)
                }
                .pickerStyle(.segmented)
                
                // Render different report sections
                if selectedTab == 0 {
                    overviewReportSection
                } else if selectedTab == 1 {
                    questionReportSection
                } else if selectedTab == 2 {
                    recommendationsReportSection
                } else {
                    logsReportSection
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.setAppState(appState)
        }
        .sheet(isPresented: $showAddSheet) {
            addPersonaSheet
        }
        .sheet(isPresented: $showEditSheet) {
            editPersonaSheet
        }
        .sheet(isPresented: $showHelpSheet) {
            helpSheet
        }
    }
    
    // MARK: - Segmented Sections
    
    private var overviewReportSection: some View {
        let useVerticalLayout = sizeClass == .compact
        let gridLayout = useVerticalLayout ? AnyLayout(VStackLayout(spacing: Spacing.lg)) : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.lg))
        
        return VStack(alignment: .leading, spacing: Spacing.xl) {
            if let detail = viewModel.selectedRunDetail, let meta = detail.meta, let cohortSize = meta.cohortSize, cohortSize > 3 {
                let sd = meta.standardDeviation ?? 0.0
                let roi = meta.predictedRoiSavings ?? 0.0
                let avgSpeed = meta.averageResponseTime ?? 0.0
                
                let useVerticalCards = sizeClass == .compact
                let cardLayout = useVerticalCards ? AnyLayout(VStackLayout(spacing: Spacing.md)) : AnyLayout(HStackLayout(spacing: Spacing.md))
                
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Enterprise Cohort Analytics")
                        .font(.titleMedium)
                        .foregroundStyle(Color.brandLight)
                    
                    cardLayout {
                        GlassView {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Projected L&D ROI", systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.success)
                                
                                Text("$\(Int(roi))")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Text("Predicted training cost savings")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        GlassView {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Score Consistency", systemImage: "checklist.checked")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.brandLight)
                                
                                Text("SD: \(String(format: "%.1f", sd))")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Text(sd < 10.0 ? "Highly Consistent Training" : (sd <= 20.0 ? "Moderate Score Variance" : "High Skill Gaps Detected"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(sd < 10.0 ? Color.success : (sd <= 20.0 ? Color.warning : Color.error))
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        GlassView {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Avg Response Speed", systemImage: "clock.badge.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.cyan)
                                
                                Text("\(String(format: "%.1f", avgSpeed))s")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Text("Indicates low cognitive friction")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    cohortScatterPlot(results: detail.personaResults)
                }
            }
            
            gridLayout {
                // Left Grid: Personas & Pass Rates
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Simulated Learner Personas")
                            .font(.titleMedium)
                        Spacer()
                        
                        Button(action: { showAddSheet = true }) {
                            Label("Add Persona", systemImage: "plus.circle.fill")
                                .font(.bodySmall)
                                .bold()
                                .foregroundStyle(Color.brandLight)
                        }
                    }
                    
                    ForEach(viewModel.personas) { persona in
                        GlassView {
                            Button(action: { startEditing(persona) }) {
                                HStack(spacing: Spacing.md) {
                                    PersonaAvatarView(name: persona.name, attentionSpan: persona.attentionSpan, experience: persona.experience)
                                    
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(persona.name)
                                                .font(.bodyLarge)
                                                .bold()
                                                .foregroundStyle(.white)
                                        }
                                        Text("\(persona.experience) • \(persona.background)")
                                            .font(.bodySmall)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    
                                    Spacer()
                                    
                                    ScoreProgressRing(score: persona.passRate, statusText: persona.statusText, isSimulating: viewModel.isSimulating)
                                }
                                .padding()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right Grid: Bloom's Heatmap (Comprehension analytics)
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Cognitive Load Heatmap")
                        .font(.titleMedium)
                    
                    GlassView {
                        VStack(spacing: Spacing.sm) {
                            ForEach(Array(viewModel.bloomHeatmap.keys.sorted(by: { viewModel.bloomHeatmap[$0]! > viewModel.bloomHeatmap[$1]! })), id: \.self) { level in
                                let rate = viewModel.bloomHeatmap[level] ?? 0.0
                                HStack {
                                    Text(level)
                                        .font(.bodySmall)
                                        .frame(width: 90, alignment: .leading)
                                    
                                    Spacer()
                                    
                                    // Bar progress indicating level success
                                    GeometryReader { geo in
                                        ZProxyView(rate: rate, width: geo.size.width)
                                    }
                                    .frame(height: 12)
                                    
                                    Text("\(Int(rate * 100))%")
                                        .font(.codeSmall)
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .padding(.vertical, Spacing.xs)
                            }
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var questionReportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Quiz Item Comprehension Breakdown")
                .font(.titleMedium)
            
            if viewModel.isLoadingDetail {
                HStack {
                    Spacer()
                    ProgressView("Loading detailed question logs...")
                        .font(.bodySmall)
                        .padding()
                    Spacer()
                }
            } else if let detail = viewModel.selectedRunDetail {
                questionList(detail: detail)
            } else {
                noDetailPlaceholder
            }
        }
    }
    
    @ViewBuilder
    private func questionList(detail: SimulationRunDetail) -> some View {
        let activeModule = viewModel.modules.first(where: { $0.id == viewModel.selectedModuleId })
        let questions = activeModule?.quizQuestions ?? []
        
        if questions.isEmpty && detail.id != "local_run" {
            noQuestionsPlaceholder
        } else {
            let displayQuestions = getDisplayQuestions(questions: questions)
            
            ForEach(displayQuestions) { q in
                let questionResults = detail.personaResults.filter { $0.questionId == q.id }
                questionRow(q: q, questionResults: questionResults)
            }
        }
    }
    
    private var noQuestionsPlaceholder: some View {
        GlassView {
            HStack {
                Spacer()
                Text("No curriculum quiz questions found. Run a simulation against a module containing quiz questions.")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
        }
    }
    
    private var noDetailPlaceholder: some View {
        GlassView {
            HStack {
                Spacer()
                Text("No detailed results loaded. Please select a historic run or execute a new simulation.")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
        }
    }
    
    private func getDisplayQuestions(questions: [QuizQuestionResponse]) -> [QuizQuestionResponse] {
        if questions.isEmpty {
            return [
                QuizQuestionResponse(id: "mock_q_1", moduleId: "default", questionText: "What is the primary goal of a Sprint Retrospective?", questionType: "multiple_choice", options: ["Identify process improvements", "Assign blame for failures", "Write status reports", "Plan the next Sprint outline"], correctAnswer: "Identify process improvements", bloomsLevel: "remember", difficulty: 0.3, explanation: "Retrospectives are inspect-and-adapt cycles for team process improvements.", sequenceOrder: 1),
                QuizQuestionResponse(id: "mock_q_2", moduleId: "default", questionText: "How should psychological safety be fostered in a team retrospective?", questionType: "multiple_choice", options: ["Establish a blameless culture focused on processes", "Publicly rank team members", "Strictly enforce performance targets", "Restrict discussions to status metrics"], correctAnswer: "Establish a blameless culture focused on processes", bloomsLevel: "apply", difficulty: 0.6, explanation: "Blameless environments allow open reflection without fear of reprisal.", sequenceOrder: 2),
                QuizQuestionResponse(id: "mock_q_3", moduleId: "default", questionText: "Which action best demonstrates the 'inspect and adapt' Scrum values?", questionType: "multiple_choice", options: ["Updating the sprint backlog daily", "Failing to change process after recurring defects", "Ignoring feedback from stakeholders", "Cancelling planning sessions"], correctAnswer: "Updating the sprint backlog daily", bloomsLevel: "analyze", difficulty: 0.5, explanation: "Inspect and adapt focuses on continuous alignment.", sequenceOrder: 3),
                QuizQuestionResponse(id: "mock_q_4", moduleId: "default", questionText: "Evaluate the role of an external facilitator during a tense team retrospective.", questionType: "multiple_choice", options: ["Neutral mediator to guide communication", "Enforcer of scrum rules and deadlines", "Judge to assign responsibility for blocks", "Silent observer with no input"], correctAnswer: "Neutral mediator to guide communication", bloomsLevel: "evaluate", difficulty: 0.7, explanation: "Facilitators help ease blockages.", sequenceOrder: 4),
                QuizQuestionResponse(id: "mock_q_5", moduleId: "default", questionText: "Design a sprint retrospective exercise that helps introverts participate fully.", questionType: "multiple_choice", options: ["Silent sticky note gathering", "Round-robin public verbal speaking", "Unstructured open-floor debate", "Strictly timed rapid-fire interviews"], correctAnswer: "Silent sticky note gathering", bloomsLevel: "create", difficulty: 0.8, explanation: "Sticky notes reduce anxiety.", sequenceOrder: 5)
            ]
        }
        return questions
    }
    
    @ViewBuilder
    private func questionRow(q: QuizQuestionResponse, questionResults: [PersonaResultItem]) -> some View {
        let isExpanded = expandedQuestionId == q.id
        
        GlassView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    withAnimation {
                        expandedQuestionId = isExpanded ? nil : q.id
                    }
                }) {
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                           HStack(spacing: Spacing.xs) {
                               Text(q.bloomsLevel?.capitalized ?? "Understand")
                                   .font(.system(size: 9, weight: .bold))
                                   .padding(.horizontal, 6)
                                   .padding(.vertical, 2)
                                   .background(Color.brand.opacity(0.2))
                                   .foregroundStyle(Color.brandLight)
                                   .clipShape(Capsule())
                               
                               Text("Diff: \(String(format: "%.1f", q.difficulty ?? 0.5))")
                                   .font(.codeSmall)
                                   .foregroundStyle(.secondary)
                               
                               if let detail = viewModel.selectedRunDetail,
                                  let meta = detail.meta,
                                  let failRates = meta.questionFailureRates,
                                  let failRate = failRates[q.id] {
                                   Text("Cohort Failed: \(Int(failRate))%")
                                       .font(.system(size: 8, weight: .bold))
                                       .padding(.horizontal, 6)
                                       .padding(.vertical, 2)
                                       .background(failRate > 40.0 ? Color.error.opacity(0.2) : Color.success.opacity(0.2))
                                       .foregroundStyle(failRate > 40.0 ? Color.error : Color.success)
                                       .clipShape(Capsule())
                               }
                           }
                           
                           Text(q.questionText)
                               .font(.bodySmall)
                               .bold()
                               .foregroundStyle(.white)
                               .multilineTextAlignment(.leading)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: -6) {
                            ForEach(questionResults) { res in
                                Circle()
                                    .stroke(res.passed ? Color.success : Color.error, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Text(res.personaProfile.name.prefix(1))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                    .background(Circle().fill(Color.white.opacity(0.1)))
                            }
                        }
                        .padding(.trailing, 4)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        questionOptionsView(q: q)
                        studentAttemptsView(questionResults: questionResults)
                    }
                    .background(Color.black.opacity(0.1))
                }
            }
        }
    }
    
    private func cohortScatterPlot(results: [PersonaResultItem]) -> some View {
        let studentGroups = Dictionary(grouping: results, by: { $0.personaProfile.name })
        
        let cohortData: [(name: String, score: Double, latency: Double, passed: Bool, exp: String)] = studentGroups.map { name, items in
            let total = Double(items.count)
            let passedCount = Double(items.filter { $0.passed }.count)
            let score = total > 0 ? (passedCount / total) * 100.0 : 0.0
            let avgLatency = items.reduce(0.0) { $0 + ($1.timeEstimateSeconds ?? 0.0) } / total
            let passed = score >= 70.0
            let exp = items.first?.personaProfile.experience ?? "Beginner"
            return (name, score, avgLatency, passed, exp)
        }
        
        return GlassView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Cohort Skill Scatter Distribution")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.brandLight)
                
                HStack(spacing: Spacing.md) {
                    VStack {
                        Text("100%").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Text("70%").font(.system(size: 7, design: .monospaced)).foregroundStyle(Color.success.opacity(0.8))
                        Spacer()
                        Text("0%").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .frame(height: 120)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .bottomLeading) {
                            Rectangle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            
                            Path { path in
                                let yPos = geo.size.height * 0.3
                                path.move(to: CGPoint(x: 0, y: yPos))
                                path.addLine(to: CGPoint(x: geo.size.width, y: yPos))
                            }
                            .stroke(Color.success.opacity(0.25), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3]))
                            
                            Path { path in
                                let xPos = geo.size.width * 0.5
                                path.move(to: CGPoint(x: xPos, y: 0))
                                path.addLine(to: CGPoint(x: xPos, y: geo.size.height))
                            }
                            .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3]))
                            
                            ForEach(cohortData, id: \.name) { student in
                                let clampedLatency = min(10.0, max(1.0, student.latency))
                                let xPct = (clampedLatency - 1.0) / 9.0
                                let yPct = student.score / 100.0
                                
                                let xPos = geo.size.width * CGFloat(xPct)
                                let yPos = geo.size.height * CGFloat(1.0 - yPct)
                                
                                let dotColor: Color = student.exp == "Expert" ? Color.success : (student.exp == "Intermediate" ? Color.brandLight : Color.warning)
                                
                                Circle()
                                    .fill(dotColor.gradient)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                                    .position(x: xPos, y: yPos)
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding(.trailing, 8)
                
                HStack {
                    Spacer().frame(width: 32)
                    Text("1s speed").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text("10s delay").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                }
                
                HStack(spacing: Spacing.md) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.warning).frame(width: 6, height: 6)
                        Text("Beginner").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.brandLight).frame(width: 6, height: 6)
                        Text("Intermediate").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.success).frame(width: 6, height: 6)
                        Text("Expert").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func questionOptionsView(q: QuizQuestionResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Distractor & Correct Options:")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            
            ForEach(q.options ?? [], id: \.self) { option in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: option == q.correctAnswer ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(option == q.correctAnswer ? Color.success : .secondary)
                        .padding(.top, 2)
                    
                    Text(option)
                        .font(.system(size: 12))
                        .foregroundStyle(option == q.correctAnswer ? .white : .secondary)
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
    }
    
    @ViewBuilder
    private func studentAttemptsView(questionResults: [PersonaResultItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Persona Reasoning:")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            
            ForEach(questionResults) { res in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Circle()
                        .fill(res.passed ? Color.success.opacity(0.15) : Color.error.opacity(0.15))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(res.passed ? "✅" : "❌")
                                .font(.system(size: 12))
                        )
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text(res.personaProfile.name)
                                .font(.bodySmall)
                                .bold()
                                .foregroundStyle(.white)
                            Text("(\(res.personaProfile.experience))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            if let signal = res.confusionSignal, signal != "none" {
                                Text(formatConfusionSignal(signal))
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.error.opacity(0.2))
                                    .foregroundStyle(Color.error)
                                    .clipShape(Capsule())
                            }
                            
                            Text("\(String(format: "%.1f", res.timeEstimateSeconds ?? 0.0))s")
                                .font(.codeSmall)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(res.responseText ?? "No thoughts logged.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(Spacing.xs)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(6)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, Spacing.md)
    }
    
    private var recommendationsReportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("AI Pedagogical Insights")
                .font(.titleMedium)
            
            if viewModel.isLoadingDetail {
                HStack {
                    Spacer()
                    ProgressView("Analyzing results...")
                        .font(.bodySmall)
                        .padding()
                    Spacer()
                }
            } else if viewModel.recommendations.isEmpty {
                GlassView {
                    HStack {
                        Spacer()
                        Text("No recommendations found. Run a simulation to generate pedagogical recommendations.")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer()
                    }
                }
            } else {
                ForEach(viewModel.recommendations) { rec in
                    GlassView {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text(rec.target)
                                    .font(.bodySmall)
                                    .bold()
                                    .foregroundStyle(Color.brandLight)
                                
                                Spacer()
                                
                                Label("Gemini Tutor", systemImage: "sparkles")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.brand)
                            }
                            
                            Text(rec.description)
                                .font(.bodySmall)
                                .foregroundStyle(.white)
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.warning)
                                    .padding(.top, 1)
                                
                                Text(rec.suggestion)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(2.0)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    private var logsReportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Simulation Execution Stream")
                .font(.titleMedium)
            
            GlassView {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        if viewModel.simulationLogs.isEmpty {
                            Text("No logs captured.")
                                .font(.bodySmall)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.simulationLogs, id: \.self) { log in
                                Text(log)
                                    .font(.codeSmall)
                                    .foregroundStyle(log.contains("❌") ? Color.error : (log.contains("✅") ? Color.success : .primary))
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 250)
            }
        }
    }
    
    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Welcome to the Simulation Sandbox!")
                        .font(.titleMedium)
                        .bold()
                        .foregroundStyle(Color.brandLight)
                    
                    Text("This sandbox allows you to run virtual student cohorts against curriculum modules before publishing. It models learner behaviors using Generative AI to catch phrasing ambiguities, concept gaps, and cognitive overloads.")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    Text("The Learner Variables")
                        .font(.bodyMedium)
                        .bold()
                        .padding(.top, Spacing.xs)
                    
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text("🧠")
                            VStack(alignment: .leading) {
                                Text("Experience Level").bold().font(.bodySmall)
                                Text("Beginners fail if they encounter undefined jargon. Experts get everything correct but complain about ease or ambiguity.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text("😴")
                            VStack(alignment: .leading) {
                                Text("Attention Span").bold().font(.bodySmall)
                                Text("Low attention span students rush and make careless mistakes on long or complex questions.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text("⚠️")
                            VStack(alignment: .leading) {
                                Text("Base Error Rate").bold().font(.bodySmall)
                                Text("Models base test anxiety or fatigue, creating a random chance of picking incorrect options.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    Text("Understanding Results")
                        .font(.bodyMedium)
                        .bold()
                        .padding(.top, Spacing.xs)
                    
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("• **Question Breakdown**: Review each question's pass rate. If experts fail, look at their thought process—it usually reveals ambiguous phrasings.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("• **Cognitive Heatmap**: Visualizes success across Bloom's Taxonomy. Ensure beginners are tested on Remember/Understand, and only experts are pushed to Evaluate/Create.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("• **AI Recommendations**: Actionable pedagogical feedback generated by Gemini to improve course structures or quiz questions.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Sandbox Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showHelpSheet = false }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatConfusionSignal(_ sig: String) -> String {
        switch sig.lowercased() {
        case "missing_prerequisite": return "Missing Prerequisite"
        case "complex_jargon": return "Terminology Overload"
        case "careless_mistake": return "Attention Slip"
        case "ambiguous_options": return "Ambiguous Options"
        default: return sig.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func formatRunTime(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let dispFormatter = DateFormatter()
            dispFormatter.dateStyle = .short
            dispFormatter.timeStyle = .short
            return dispFormatter.string(from: date)
        }
        
        let formatter2 = ISO8601DateFormatter()
        if let date = formatter2.date(from: dateStr) {
            let dispFormatter = DateFormatter()
            dispFormatter.dateStyle = .short
            dispFormatter.timeStyle = .short
            return dispFormatter.string(from: date)
        }
        
        return String(dateStr.prefix(16).replacingOccurrences(of: "T", with: " "))
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return Color.success }
        if score >= 50 { return Color.warning }
        return Color.error
    }
    
    private func startEditing(_ persona: Persona) {
        editingPersona = persona
        editName = persona.name
        editBackground = persona.background
        editExperience = persona.experience
        editAttentionSpan = persona.attentionSpan
        editErrorRate = persona.errorRate
        showEditSheet = true
    }
    
    // MARK: - Sheets
    
    private var addPersonaSheet: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $newName)
                    TextField("Background", text: $newBackground)
                }
                Section("Behavioral Characteristics") {
                    Picker("Experience Level", selection: $newExperience) {
                        Text("Beginner").tag("Beginner")
                        Text("Intermediate").tag("Intermediate")
                        Text("Expert").tag("Expert")
                    }
                    Picker("Attention Span", selection: $newAttentionSpan) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Base Error Rate")
                            Spacer()
                            Text("\(Int(newErrorRate * 100))%")
                                .font(.codeSmall)
                                .bold()
                        }
                        Slider(value: $newErrorRate, in: 0...1, step: 0.05)
                    }
                }
            }
            .navigationTitle("Add Custom Student")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let newP = Persona(
                            name: newName,
                            background: newBackground,
                            attentionSpan: newAttentionSpan,
                            experience: newExperience,
                            passRate: 0,
                            errorRate: newErrorRate
                        )
                        viewModel.personas.append(newP)
                        showAddSheet = false
                        // Reset
                        newName = ""
                        newBackground = ""
                        newExperience = "Beginner"
                        newAttentionSpan = "Medium"
                        newErrorRate = 0.3
                    }
                    .disabled(newName.isEmpty || newBackground.isEmpty)
                }
            }
        }
    }
    
    private var editPersonaSheet: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $editName)
                    TextField("Background", text: $editBackground)
                }
                Section("Behavioral Characteristics") {
                    Picker("Experience Level", selection: $editExperience) {
                        Text("Beginner").tag("Beginner")
                        Text("Intermediate").tag("Intermediate")
                        Text("Expert").tag("Expert")
                    }
                    Picker("Attention Span", selection: $editAttentionSpan) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Base Error Rate")
                            Spacer()
                            Text("\(Int(editErrorRate * 100))%")
                                .font(.codeSmall)
                                .bold()
                        }
                        Slider(value: $editErrorRate, in: 0...1, step: 0.05)
                    }
                }
                Section {
                    Button("Remove Student Persona", role: .destructive) {
                        if let editingPersona = editingPersona,
                           let index = viewModel.personas.firstIndex(where: { $0.id == editingPersona.id }) {
                            viewModel.personas.remove(at: index)
                        }
                        showEditSheet = false
                    }
                }
            }
            .navigationTitle("Edit Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let editingPersona = editingPersona,
                           let index = viewModel.personas.firstIndex(where: { $0.id == editingPersona.id }) {
                            viewModel.personas[index].name = editName
                            viewModel.personas[index].background = editBackground
                            viewModel.personas[index].experience = editExperience
                            viewModel.personas[index].attentionSpan = editAttentionSpan
                            viewModel.personas[index].errorRate = editErrorRate
                        }
                        showEditSheet = false
                    }
                    .disabled(editName.isEmpty || editBackground.isEmpty)
                }
            }
        }
    }
}

struct ZProxyView: View {
    let rate: Double
    let width: CGFloat
    
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.05))
            Capsule()
                .fill(heatmapColor(rate))
                .frame(width: max(0, width * CGFloat(rate)))
        }
    }
    
    private func heatmapColor(_ val: Double) -> Color {
        if val >= 0.8 { return Color.heatmapGreen }
        if val >= 0.6 { return Color.heatmapYellow }
        if val >= 0.4 { return Color.heatmapOrange }
        return Color.heatmapRed
    }
}

// MARK: - Persona Avatar View Helper View
struct PersonaAvatarView: View {
    let name: String
    let attentionSpan: String
    let experience: String
    
    var emoji: String {
        if attentionSpan.lowercased() == "low" { return "😴" }
        if experience.lowercased() == "expert" { return "🧠" }
        if experience.lowercased() == "intermediate" { return "🧐" }
        if name.lowercased().contains("alex") { return "🥱" }
        if name.lowercased().contains("sofia") { return "📚" }
        if name.lowercased().contains("jordan") { return "🚀" }
        return "🎒"
    }
    
    var gradient: LinearGradient {
        if attentionSpan.lowercased() == "low" {
            return LinearGradient(colors: [Color(hex: "#F87171"), Color(hex: "#F59E0B")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if experience.lowercased() == "expert" {
            return LinearGradient(colors: [Color(hex: "#A78BFA"), Color(hex: "#6366F1")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if experience.lowercased() == "intermediate" {
            return LinearGradient(colors: [Color(hex: "#34D399"), Color(hex: "#059669")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color(hex: "#60A5FA"), Color(hex: "#3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: 44, height: 44)
            .overlay(
                Text(emoji)
                    .font(.system(size: 22))
            )
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Score Progress Ring Helper View
struct ScoreProgressRing: View {
    let score: Int
    let statusText: String
    let isSimulating: Bool
    
    var body: some View {
        ZStack {
            if isSimulating && score == 0 {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3.5)
                    .frame(width: 38, height: 38)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(Double(score) / 100.0, 1.0)))
                    .stroke(
                        scoreColor(score),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 38, height: 38)
                    .rotationEffect(Angle(degrees: -90))
                    .animation(.easeOut(duration: 0.8), value: score)
                
                Text("\(score)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
    
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return Color.success }
        if score >= 50 { return Color.warning }
        return Color.error
    }
}
