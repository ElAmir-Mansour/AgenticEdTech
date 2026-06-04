import SwiftUI
import Combine

enum PedagogicalFramework: String, CaseIterable, Identifiable {
    case traditional = "traditional"
    case scenarioBased = "scenario_based"
    case socratic = "socratic"
    case blooms = "blooms"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .traditional: return "Traditional/Compliance"
        case .scenarioBased: return "Scenario-Based Learning"
        case .socratic: return "Socratic Inquiry"
        case .blooms: return "Bloom's Progression"
        }
    }
    
    var icon: String {
        switch self {
        case .traditional: return "doc.text"
        case .scenarioBased: return "person.and.arrow.left.and.arrow.right"
        case .socratic: return "questionmark.bubble"
        case .blooms: return "arrow.up.and.line.horizontal.and.arrow.down"
        }
    }
    
    var description: String {
        switch self {
        case .traditional: return "Standard compliance structure with modules and summaries."
        case .scenarioBased: return "Immersive real-world situations, dilemmas, and consequences."
        case .socratic: return "Guided dialogue and key conceptual questions to discover truths."
        case .blooms: return "Strict progression from Remember -> Understand -> Apply -> Create."
        }
    }
}

struct OutlineItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var bloomsLevel: String
    var description: String
}

@Observable
class AgenticCanvasViewModel {
    var messages: [AgentMessage] = []
    var selectedFramework: PedagogicalFramework = .traditional
    var proposedOutlineItems: [OutlineItem] = []
    var showOutlineChecklist = false
    
    var activeModules: [CurriculumModuleResponse] = []
    var availableDocuments: [IngestedDocument] = []
    var selectedDocumentIDs: Set<String> = []
    var currentInput = ""
    var isThinking = false
    var thinkingAgent: AgentMessage.AgentRole? = nil
    var showApprovalCard = false
    var errorMessage: String? = nil
    var dynamicSuggestions: [String] = []
    var selectedExportModuleId = "all"
    
    // Selected module for detail view
    var selectedModule: CurriculumModuleResponse? = nil
    
    // Core Network and state references
    var appState: AppState? = nil
    var sessionId: String? = nil
    
    // SCORM Export States
    var isExporting = false
    var showExportSuccess = false
    var exportedFileURL: URL? = nil
    
    // Keep reference to Combine cancellables
    private var subscription: AnyCancellable? = nil
    private var isInitialized = false
    
    func setAppState(_ state: AppState) {
        self.appState = state
        
        // Only set up subscription once to prevent re-initialization on tab switch
        if !isInitialized {
            isInitialized = true
            setupWebSocketSubscription()
        }
        fetchModules()
        fetchDocuments()
    }
    
    func fetchDocuments() {
        guard let appState = appState,
              let projectId = appState.selectedProjectID else {
            return
        }
        
        Task {
            do {
                let fetched: [IngestedDocument] = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/documents"
                )
                await MainActor.run {
                    self.availableDocuments = fetched
                    // Select all by default if not set
                    if self.selectedDocumentIDs.isEmpty {
                        self.selectedDocumentIDs = Set(fetched.map { $0.id })
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not load documents: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func fetchModules() {
        guard let appState = appState,
              let projectId = appState.selectedProjectID else {
            return
        }
        
        Task {
            do {
                let fetched: [CurriculumModuleResponse] = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/modules"
                )
                await MainActor.run {
                    self.activeModules = fetched
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not load modules: \(error.localizedDescription)"
                }
            }
        }
    }
    
    struct StatusResponse: Codable {
        let status: String
    }
    
    func deleteModule(id: String) {
        guard let appState = appState,
              let projectId = appState.selectedProjectID else {
            return
        }
        
        Task {
            do {
                let _: StatusResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/modules/\(id)",
                    method: "DELETE"
                )
                await MainActor.run {
                    self.activeModules.removeAll { $0.id == id }
                    self.fetchModules()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not delete module: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func updateModule(id: String, title: String, content: String, bloomsLevel: String) {
        guard let appState = appState,
              let projectId = appState.selectedProjectID else {
            return
        }
        
        struct UpdateBody: Codable {
            let title: String
            let content: String
            let bloomsLevel: String
        }
        
        let bodyObj = UpdateBody(title: title, content: content, bloomsLevel: bloomsLevel)
        guard let bodyData = try? JSONEncoder().encode(bodyObj) else { return }
        
        Task {
            do {
                let updated: CurriculumModuleResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/modules/\(id)",
                    method: "PUT",
                    body: bodyData
                )
                await MainActor.run {
                    if let index = self.activeModules.firstIndex(where: { $0.id == id }) {
                        self.activeModules[index] = updated
                    }
                    self.fetchModules()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not update module: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func reorderModules(moduleIds: [String]) {
        guard let appState = appState,
              let projectId = appState.selectedProjectID else {
            return
        }
        
        struct ReorderBody: Codable {
            let moduleIds: [String]
            
            enum CodingKeys: String, CodingKey {
                case moduleIds = "module_ids"
            }
        }
        
        // Optimistically update sequence locally first
        var reorderedList: [CurriculumModuleResponse] = []
        for mId in moduleIds {
            if let found = self.activeModules.first(where: { $0.id == mId }) {
                reorderedList.append(found)
            }
        }
        self.activeModules = reorderedList
        
        // Sync to backend in background — local reorder is already applied
        let bodyObj = ReorderBody(moduleIds: moduleIds)
        guard let bodyData = try? JSONEncoder().encode(bodyObj) else { return }
        
        Task {
            do {
                let _: StatusResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/modules/reorder",
                    method: "POST",
                    body: bodyData
                )
            } catch {
                // Background sync failed — local order is still correct
                print("Reorder sync failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupWebSocketSubscription() {
        subscription?.cancel()
        subscription = WebSocketManager.shared.messagePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.handleServerMessage(message)
            }
    }
    
    private func handleServerMessage(_ msg: ServerMessage) {
        switch msg.type {
        case "agent_session_created":
            if let payloadSId = msg.payload["sessionId"]?.value as? String {
                self.sessionId = payloadSId
            }
            
        case "agent_stream":
            guard let agentName = msg.payload["agent"]?.value as? String,
                  let type = msg.payload["messageType"]?.value as? String,
                  let content = msg.payload["content"]?.value as? String else {
                return
            }
            
            // Check if dynamic suggestions are passed from the server
            if let suggestionsArray = msg.payload["suggestions"]?.value as? [String] {
                self.dynamicSuggestions = suggestionsArray
            }
            
            let role: AgentMessage.AgentRole
            switch agentName {
            case "Planning Agent": role = .planning
            case "Content Agent": role = .content
            case "Assessment Agent": role = .assessment
            case "Critique Agent": role = .critique
            case "Heatmap Agent": role = .heatmap
            default: role = .planning
            }
            
            if type == "thinking" {
                self.isThinking = true
                self.thinkingAgent = role
            } else if type == "approval_request" {
                self.isThinking = false
                self.thinkingAgent = nil
                self.messages.append(AgentMessage(
                    agentRole: role,
                    messageType: "draft",
                    content: "Course Outline proposed for approval:\n\n\(content)",
                    timestamp: Date()
                ))
                self.proposedOutlineItems = self.parseOutlineText(content)
                self.showOutlineChecklist = !self.proposedOutlineItems.isEmpty
                withAnimation(.spring()) {
                    self.showApprovalCard = true
                }
            } else {
                self.isThinking = false
                self.thinkingAgent = nil
                self.messages.append(AgentMessage(
                    agentRole: role,
                    messageType: type,
                    content: content,
                    timestamp: Date()
                ))
            }
            
        case "agent_complete":
            self.isThinking = false
            self.thinkingAgent = nil
            self.fetchModules()
            self.dynamicSuggestions = [] // Clear suggestions on completion
            self.messages.append(AgentMessage(
                agentRole: .planning,
                messageType: "system",
                content: "✅ Generation completed and saved to Curriculum Canvas!",
                timestamp: Date()
            ))
            
        case "error":
            self.isThinking = false
            self.thinkingAgent = nil
            self.dynamicSuggestions = []
            if let errMsg = msg.payload["message"]?.value as? String {
                self.messages.append(AgentMessage(
                    agentRole: .critique,
                    messageType: "system",
                    content: "⚠️ Error: \(errMsg)",
                    timestamp: Date()
                ))
            }
            
        default:
            break
        }
    }
    
    func sendMessage() {
        guard !currentInput.isEmpty else { return }
        
        let userPrompt = currentInput
        currentInput = ""
        showApprovalCard = false
        dynamicSuggestions = [] // Clear suggestions on user input
        
        // Add user message to chat
        messages.append(AgentMessage(
            agentRole: .planning,
            messageType: "user",
            content: "📝 \(userPrompt)",
            timestamp: Date()
        ))
        
        guard let appState = appState,
              let projectId = appState.selectedProjectID,
              WebSocketManager.shared.isConnected else {
            self.errorMessage = "Cannot reach the backend. Ensure the server is running and your device is on the same network."
            return
        }
        
        isThinking = true
        var payload: [String: AnyCodable] = [
            "topic": AnyCodable(userPrompt),
            "project_id": AnyCodable(projectId),
            "pedagogical_framework": AnyCodable(selectedFramework.rawValue)
        ]
        if !selectedDocumentIDs.isEmpty {
            payload["document_ids"] = AnyCodable(Array(selectedDocumentIDs))
        }
        if let activeSessionId = sessionId {
            payload["session_id"] = AnyCodable(activeSessionId)
        }
        
        let clientMsg = ClientMessage(
            type: "start_agent_debate",
            workspace: "canvas",
            payload: payload
        )
        WebSocketManager.shared.send(message: clientMsg)
    }
    
    func approveModule(editedOutline: String? = nil) {
        showApprovalCard = false
        dynamicSuggestions = []
        showOutlineChecklist = false
        
        guard let sessionId = sessionId, WebSocketManager.shared.isConnected else {
            self.errorMessage = "Cannot approve — no active WebSocket connection."
            return
        }
        
        var payload: [String: AnyCodable] = [
            "session_id": AnyCodable(sessionId),
            "approved": AnyCodable(true)
        ]
        if let edited = editedOutline {
            payload["edited_outline"] = AnyCodable(edited)
        }
        
        let msg = ClientMessage(
            type: "submit_hitl_approval",
            workspace: "canvas",
            payload: payload
        )
        WebSocketManager.shared.send(message: msg)
    }
    
    func refineModule(id: String, prompt: String) {
        guard let appState = appState,
              let projectId = appState.selectedProjectID else {
            return
        }
        
        struct RefineBody: Codable {
            let prompt: String
        }
        
        let bodyObj = RefineBody(prompt: prompt)
        guard let bodyData = try? JSONEncoder().encode(bodyObj) else { return }
        
        isThinking = true
        
        Task {
            do {
                let updated: CurriculumModuleResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/modules/\(id)/refine",
                    method: "POST",
                    body: bodyData
                )
                await MainActor.run {
                    self.isThinking = false
                    if let index = self.activeModules.firstIndex(where: { $0.id == id }) {
                        self.activeModules[index] = updated
                    }
                    if self.selectedModule?.id == id {
                        self.selectedModule = updated
                    }
                    self.fetchModules()
                }
            } catch {
                await MainActor.run {
                    self.isThinking = false
                    self.errorMessage = "Refinement failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func parseOutlineText(_ text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        
        var cleanText = text
        if cleanText.contains("Course Outline proposed for approval:") {
            cleanText = cleanText.replacingOccurrences(of: "Course Outline proposed for approval:", with: "")
        }
        if cleanText.contains("Proposed course outline:") {
            cleanText = cleanText.replacingOccurrences(of: "Proposed course outline:", with: "")
        }
        
        let lines = cleanText.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            var lineContent = trimmed
            // Strip bullets or numbering
            if let firstChar = lineContent.first {
                if firstChar == "-" || firstChar == "*" {
                    lineContent = String(lineContent.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if firstChar.isNumber {
                    if let dotIndex = lineContent.firstIndex(of: ".") {
                        lineContent = String(lineContent[lineContent.index(after: dotIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        lineContent = String(lineContent.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            
            if lineContent.isEmpty { continue }
            
            var detectedBloom = "understand"
            let bloomsList = ["remember", "understand", "apply", "analyze", "evaluate", "create"]
            for bloom in bloomsList {
                if lineContent.lowercased().contains("(\(bloom))") {
                    detectedBloom = bloom
                    lineContent = lineContent.replacingOccurrences(of: "(\(bloom))", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                } else if lineContent.lowercased().contains("(\(bloom)") {
                    detectedBloom = bloom
                    lineContent = lineContent.replacingOccurrences(of: "(\(bloom)", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            
            var title = lineContent
            var description = ""
            
            let splitSeps = [" - ", " – ", " : ", ": "]
            for sep in splitSeps {
                if title.contains(sep) {
                    let parts = title.components(separatedBy: sep)
                    if parts.count >= 2 {
                        title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        description = parts[1...].joined(separator: sep).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
            
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "()[]:-– \t"))
            if title.isEmpty { continue }
            
            items.append(OutlineItem(title: title, bloomsLevel: detectedBloom, description: description))
        }
        return items
    }
    
    func formatOutlineText() -> String {
        var text = "Proposed course outline:\n\n"
        for (index, item) in proposedOutlineItems.enumerated() {
            let bloomStr = item.bloomsLevel.capitalized
            let descPart = item.description.isEmpty ? "" : " - \(item.description)"
            text += "\(index + 1). \(item.title) (\(bloomStr))\(descPart)\n"
        }
        return text
    }
    
    func rejectModule() {
        showApprovalCard = false
        dynamicSuggestions = []
        
        guard let sessionId = sessionId, WebSocketManager.shared.isConnected else {
            self.errorMessage = "Cannot reject — no active WebSocket connection."
            return
        }
        
        let msg = ClientMessage(
            type: "submit_hitl_approval",
            workspace: "canvas",
            payload: [
                "session_id": AnyCodable(sessionId),
                "approved": AnyCodable(false),
                "feedback": AnyCodable("Please revise parameters.")
            ]
        )
        WebSocketManager.shared.send(message: msg)
        
        messages.append(AgentMessage(
            agentRole: .critique,
            messageType: "system",
            content: "❌ Module rejected. Agents will revise the outline.",
            timestamp: Date()
        ))
    }
    
    enum SCORMVersion: String, CaseIterable, Identifiable {
        case scorm12 = "SCORM 1.2"
        case scorm2004 = "SCORM 2004"
        case tincan = "xAPI (Tin Can ZIP)"
        case xapi = "xAPI (JSON log)"
        var id: String { self.rawValue }
    }
    
    func exportSCORM(version: SCORMVersion) {
        guard let appState = appState, let projectId = appState.selectedProjectID else {
            self.errorMessage = "No project selected. Cannot export."
            return
        }
        isExporting = true
        exportedFileURL = nil
        
        Task {
            do {
                let base = APIClient.shared.baseURL.absoluteString
                var baseClean = base
                if baseClean.hasSuffix("/") { baseClean = String(baseClean.dropLast()) }
                
                let endpoint: String
                let method: String
                let filename: String
                
                switch version {
                case .scorm12:
                    endpoint = "/api/projects/\(projectId)/export/scorm?module_id=\(selectedExportModuleId)"
                    method = "GET"
                    filename = "curriculum_scorm12.zip"
                case .scorm2004:
                    endpoint = "/api/projects/\(projectId)/export/scorm2004?module_id=\(selectedExportModuleId)"
                    method = "GET"
                    filename = "curriculum_scorm2004.zip"
                case .tincan:
                    endpoint = "/api/projects/\(projectId)/export/tincan?module_id=\(selectedExportModuleId)"
                    method = "GET"
                    filename = "curriculum_tincan.zip"
                case .xapi:
                    endpoint = "/api/projects/\(projectId)/export/xapi"
                    method = "POST"
                    filename = "xapi_statements.json"
                }
                
                let urlStr = "\(baseClean)\(endpoint)"
                guard let url = URL(string: urlStr) else {
                    await MainActor.run {
                        self.errorMessage = "Invalid export URL."
                        self.isExporting = false
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = method
                if let token = APIClient.shared.token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                if method == "POST" {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
                }
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        self.errorMessage = "Unexpected server response."
                        self.isExporting = false
                    }
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                    await MainActor.run {
                        if httpResponse.statusCode == 404 {
                            self.errorMessage = "No curriculum module found to export. Create one on the canvas first."
                        } else {
                            self.errorMessage = "Export failed (HTTP \(httpResponse.statusCode)): \(body)"
                        }
                        self.isExporting = false
                    }
                    return
                }
                
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(filename)
                try data.write(to: fileURL)
                
                await MainActor.run {
                    self.isExporting = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        self.showExportSuccess = true
                    }
                    
                    // Show success checkmark for 1.5 seconds, then reveal the share link
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            self.showExportSuccess = false
                            self.exportedFileURL = fileURL
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
}

struct AgenticCanvasView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AgenticCanvasViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var activeTab = 0 // 0: Chat, 1: Canvas
    @State private var showExportSheet = false
    @State private var viewMode: CurriculumViewMode = .graph
    @State private var showLMSSimulator = false
    @State private var editMode: EditMode = .inactive
    @Namespace private var frameworkNamespace
    
    enum CurriculumViewMode: String, CaseIterable, Identifiable {
        case graph = "Map View"
        case outline = "Outline View"
        var id: String { self.rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if sizeClass == .compact {
                Picker("View Mode", selection: $activeTab) {
                    Text("Agent Chat").tag(0)
                    Text("Curriculum").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(.ultraThinMaterial)
                
                if activeTab == 0 {
                    chatOrchestrationPane
                } else {
                    curriculumHierarchyPane
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    curriculumHierarchyPane
                        .frame(minWidth: 340, maxWidth: 450)
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                    
                    chatOrchestrationPane
                }
            }
        }
        .onAppear {
            viewModel.setAppState(appState)
        }
        .errorBanner($viewModel.errorMessage)
        .sheet(item: $viewModel.selectedModule) { module in
            ModuleDetailSheet(viewModel: viewModel, module: module)
        }
        .sheet(isPresented: $showExportSheet) {
            SCORMExportOptionsSheet(
                viewModel: viewModel,
                onSelect: { version in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        viewModel.exportSCORM(version: version)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showLMSSimulator) {
            LMSSimulatorView(modules: viewModel.activeModules)
        }
    }
    
    // MARK: - Curriculum Hierarchy Pane
    
    private var curriculumHierarchyPane: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Dynamic project header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Curriculum Canvas")
                        .font(.titleMedium)
                        .foregroundStyle(Color.brandLight)
                    
                    Spacer()
                    
                    if !viewModel.activeModules.isEmpty {
                        Button(action: {
                            showLMSSimulator = true
                        }) {
                            Label("LMS Preview", systemImage: "play.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.success.opacity(0.2))
                                .foregroundStyle(Color.success)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.success.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.trailing, 4)
                    }
                    
                    if viewMode == .outline && !viewModel.activeModules.isEmpty {
                        Button(action: {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }) {
                            Text(editMode == .active ? "Done" : "Edit")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.brand.opacity(0.2))
                                .foregroundStyle(Color.brandLight)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.brand.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.trailing, 4)
                    }
                    
                    Text("\(viewModel.activeModules.count) modules")
                        .font(.codeSmall)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                if let projectTitle = appState.selectedProjectTitle {
                    Text(projectTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !viewModel.activeModules.isEmpty {
                    let totalQuizzes = viewModel.activeModules.reduce(0) { $0 + $1.quizQuestions.count }
                    let bloomsLevels = Set(viewModel.activeModules.compactMap { $0.bloomsLevel?.lowercased() })
                    
                    HStack(spacing: Spacing.sm) {
                        Label("\(totalQuizzes) quiz Q's", systemImage: "checkmark.seal")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        if !bloomsLevels.isEmpty {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(bloomsLevels.map { $0.capitalized }.joined(separator: ", "))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.brandLight.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.top, Spacing.sm)
            
            if !viewModel.activeModules.isEmpty {
                Picker("Syllabus Display Mode", selection: Binding(
                    get: { viewMode },
                    set: { val in
                        viewMode = val
                        if val == .graph {
                            editMode = .inactive
                        }
                    }
                )) {
                    ForEach(CurriculumViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }
            
            if viewModel.activeModules.isEmpty {
                // Empty state
                VStack(spacing: Spacing.md) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No modules yet")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                    Text("Use the chat to ask agents to create curriculum modules.")
                        .font(.codeSmall)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                if viewMode == .graph {
                    CurriculumNodeGraph(
                        modules: viewModel.activeModules,
                        onSelect: { module in
                            viewModel.selectedModule = module
                        }
                    )
                } else {
                    interactiveOutlineList
                }
            }
            
            // SCORM Export Section
            if !viewModel.activeModules.isEmpty {
                VStack(spacing: Spacing.sm) {
                    if viewModel.isExporting {
                        HStack(spacing: Spacing.md) {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(Color.brandLight)
                            Text("Packaging SCORM...")
                                .font(.bodySmall)
                                .foregroundStyle(Color.brandLight)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brand.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brand.opacity(0.3), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale))
                    } else if viewModel.showExportSuccess {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                            Text("Ready to Share!")
                                .font(.bodySmall)
                                .bold()
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.success.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.scale.combined(with: .opacity))
                    } else if let fileURL = viewModel.exportedFileURL {
                        ShareLink(item: fileURL) {
                            Label("Share SCORM ZIP", systemImage: "square.and.arrow.up")
                                .bold()
                                .font(.bodySmall)
                                .foregroundStyle(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.brand.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: Color.brand.opacity(0.4), radius: 8, y: 4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    } else {
                        BrandButton(title: "Export Options", icon: "archivebox.fill", style: .primary) {
                            showExportSheet = true
                        }
                    }
                }
                .padding(.top, Spacing.sm)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isExporting)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.showExportSuccess)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.exportedFileURL)
            }
        }
        .padding()
        .background(Color.black.opacity(0.2))
    }
    
    // MARK: - Chat Orchestration Pane
    
    private var topControlBar: some View {
        HStack {
            Menu {
                Picker("Pedagogical Framework", selection: Binding(
                    get: { viewModel.selectedFramework },
                    set: { val in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            viewModel.selectedFramework = val
                        }
                    }
                )) {
                    ForEach(PedagogicalFramework.allCases) { fw in
                        Label(fw.displayName, systemImage: fw.icon).tag(fw)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.selectedFramework.icon)
                        .font(.system(size: 11))
                    Text(viewModel.selectedFramework.displayName)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.brand.opacity(0.15))
                .foregroundStyle(Color.brandLight)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.brand.opacity(0.3), lineWidth: 1))
            }
            
            Spacer()
            
            if viewModel.isThinking {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Agent active")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.1))
    }
    
    private var chatOrchestrationPane: some View {
        VStack(spacing: 0) {
            topControlBar
            
            // Grounded Source Selection
            if !viewModel.availableDocuments.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Grounding Files (\(viewModel.selectedDocumentIDs.count)/\(viewModel.availableDocuments.count))", systemImage: "doc.on.doc.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brandLight)
                        Spacer()
                        Button(action: {
                            if viewModel.selectedDocumentIDs.count == viewModel.availableDocuments.count {
                                viewModel.selectedDocumentIDs.removeAll()
                            } else {
                                viewModel.selectedDocumentIDs = Set(viewModel.availableDocuments.map { $0.id })
                            }
                        }) {
                            Text(viewModel.selectedDocumentIDs.count == viewModel.availableDocuments.count ? "Deselect All" : "Select All")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(viewModel.availableDocuments) { doc in
                                let isSelected = viewModel.selectedDocumentIDs.contains(doc.id)
                                Button(action: {
                                    if isSelected {
                                        viewModel.selectedDocumentIDs.remove(doc.id)
                                    } else {
                                        viewModel.selectedDocumentIDs.insert(doc.id)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.caption2)
                                            .foregroundStyle(isSelected ? Color.success : .secondary)
                                        Text(doc.filename)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.brand.opacity(0.15) : Color.white.opacity(0.05))
                                    .foregroundStyle(isSelected ? Color.brandLight : .secondary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.brand.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Spacing.sm)
                .background(Color.white.opacity(0.02))
                .overlay(
                    VStack {
                        Spacer()
                        Divider().background(Color.white.opacity(0.1))
                    }
                )
            }
            
            if viewModel.messages.isEmpty {
                // Welcome state
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.lg) {
                        Spacer(minLength: 30)
                        
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.brandLight.opacity(0.5))
                        
                        Text("Agentic Canvas")
                            .font(.titleLarge)
                            .foregroundStyle(Color.brandLight)
                        
                        Text("The multi-agent curriculum pipeline will plan, write content, critique, and assess your course modules automatically based on the selected pedagogical framework.")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                        
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Select Pedagogical Model")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.brandLight)
                                .padding(.horizontal, 4)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                                ForEach(PedagogicalFramework.allCases) { framework in
                                    Button(action: {
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            viewModel.selectedFramework = framework
                                        }
                                    }) {
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            HStack(spacing: 6) {
                                                Image(systemName: framework.icon)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(viewModel.selectedFramework == framework ? Color.brandLight : .secondary)
                                                
                                                Text(framework.displayName)
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(viewModel.selectedFramework == framework ? .white : .secondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            Text(framework.description)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(3)
                                                .frame(height: 36, alignment: .topLeading)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            ZStack {
                                                if viewModel.selectedFramework == framework {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Color.brand.opacity(0.15))
                                                        .matchedGeometryEffect(id: "frameworkBg", in: frameworkNamespace)
                                                } else {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Color.white.opacity(0.03))
                                                }
                                            }
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.selectedFramework == framework ? Color.brandLight.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1.5)
                                        )
                                        .scaleEffect(viewModel.selectedFramework == framework ? 1.02 : 1.0)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                        
                        Spacer(minLength: 30)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(viewModel.messages) { message in
                                AgentMessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.isThinking, let agent = viewModel.thinkingAgent {
                                thinkingIndicator(agent: agent)
                            }
                            
                            if viewModel.showApprovalCard {
                                if viewModel.showOutlineChecklist {
                                    interactiveOutlineApprovalCard
                                } else {
                                    HITLApprovalCard(
                                        checkpoint: HITLCheckpoint(
                                            id: "module-outline-check",
                                            description: viewModel.messages.last?.content ?? "Approve curriculum layout?"
                                        ),
                                        onApprove: { viewModel.approveModule() },
                                        onReject: { viewModel.rejectModule() }
                                    )
                                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let lastId = viewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Input Bar
            inputBar
        }
    }
    
    // MARK: - Interactive Outline Approval Card
    
    private var interactiveOutlineApprovalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Outline Verification Required", systemImage: "hand.raised.fill")
                .font(.titleMedium)
                .foregroundStyle(Color.warning)
            
            Text("Review and adjust the syllabus layout. You can rename, reorder, delete, or add custom chapters before approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                ForEach(Array(viewModel.proposedOutlineItems.enumerated()), id: \.element.id) { index, item in
                    outlineItemRow(index: index, item: item)
                }
            }
            
            // Add Custom Chapter Button
            Button(action: {
                withAnimation {
                    viewModel.proposedOutlineItems.append(OutlineItem(
                        title: "New Chapter Title",
                        bloomsLevel: "understand",
                        description: ""
                    ))
                }
            }) {
                Label("Add Custom Chapter", systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandLight)
            }
            .padding(.vertical, 4)
            
            // Approval Actions
            HStack(spacing: Spacing.md) {
                Button("Reject", role: .destructive) {
                    viewModel.rejectModule()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Approve & Write Content") {
                    let formatted = viewModel.formatOutlineText()
                    viewModel.approveModule(editedOutline: formatted)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.success)
            }
        }
        .padding(Spacing.lg)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(radius: 8)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }
    
    @ViewBuilder
    private func outlineItemRow(index: Int, item: OutlineItem) -> some View {
        HStack(spacing: Spacing.sm) {
            // Title Editor
            TextField("Chapter Title", text: Binding(
                get: { item.title },
                set: { viewModel.proposedOutlineItems[index].title = $0 }
            ))
            .font(.bodySmall.weight(.bold))
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // Bloom's Picker
            Menu {
                Picker("Bloom's Level", selection: Binding(
                    get: { item.bloomsLevel },
                    set: { viewModel.proposedOutlineItems[index].bloomsLevel = $0 }
                )) {
                    Text("Remember").tag("remember")
                    Text("Understand").tag("understand")
                    Text("Apply").tag("apply")
                    Text("Analyze").tag("analyze")
                    Text("Evaluate").tag("evaluate")
                    Text("Create").tag("create")
                }
            } label: {
                Text(item.bloomsLevel.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.brand.opacity(0.2))
                    .foregroundStyle(Color.brandLight)
                    .clipShape(Capsule())
            }
            
            // Reorder Arrows
            VStack(spacing: 2) {
                Button(action: {
                    if index > 0 {
                        viewModel.proposedOutlineItems.swapAt(index, index - 1)
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(index > 0 ? Color.brandLight : .secondary.opacity(0.3))
                }
                .disabled(index == 0)
                
                Button(action: {
                    if index < viewModel.proposedOutlineItems.count - 1 {
                        viewModel.proposedOutlineItems.swapAt(index, index + 1)
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(index < viewModel.proposedOutlineItems.count - 1 ? Color.brandLight : .secondary.opacity(0.3))
                }
                .disabled(index == viewModel.proposedOutlineItems.count - 1)
            }
            
            // Delete Button
            Button(action: {
                withAnimation {
                    _ = viewModel.proposedOutlineItems.remove(at: index)
                }
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(Color.error)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Thinking Indicator
    
    private func thinkingIndicator(agent: AgentMessage.AgentRole) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(agent.color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: agent.icon)
                        .font(.caption)
                        .foregroundStyle(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.rawValue)
                    .font(.agentLabel)
                    .foregroundStyle(agent.color)
                TypingIndicatorView(color: .secondary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(agent.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(agent.color.opacity(0.15), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - Input Bar
    
    // Contextual quick actions based on current state
    private var contextualChips: [(label: String, icon: String)] {
        if viewModel.showApprovalCard {
            return [
                ("Approve outline", "checkmark.circle"),
                ("Reject and revise", "arrow.counterclockwise"),
            ]
        } else if !viewModel.dynamicSuggestions.isEmpty {
            return viewModel.dynamicSuggestions.map { ($0, "sparkles") }
        } else if viewModel.messages.isEmpty {
            return [
                ("Create a curriculum outline", "doc.text"),
                ("Generate from uploaded docs", "arrow.up.doc"),
                ("Quick quiz on a topic", "checkmark.seal"),
            ]
        } else {
            return [
                ("Make it simpler", "minus.circle"),
                ("Increase difficulty", "flame"),
                ("Add practical examples", "wrench.and.screwdriver"),
                ("Add more quiz questions", "plus.circle"),
                ("Regenerate", "arrow.clockwise"),
            ]
        }
    }
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Context-Aware Quick Action Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(contextualChips, id: \.label) { chip in
                        Button(action: {
                            if chip.label == "Approve outline" {
                                viewModel.approveModule()
                            } else if chip.label == "Reject and revise" {
                                viewModel.rejectModule()
                            } else {
                                viewModel.currentInput = chip.label
                                viewModel.sendMessage()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 10))
                                Text(chip.label)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.brandLight.opacity(0.15))
                            .foregroundStyle(Color.brandLight)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.brandLight.opacity(0.3), lineWidth: 1))
                        }
                        .disabled(viewModel.isThinking)
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.dynamicSuggestions)
                .padding(.horizontal)
                .padding(.top, Spacing.sm)
            }
            
            HStack(spacing: Spacing.sm) {
                TextField("e.g. Create a module on Agile Scrum...", text: $viewModel.currentInput)
                    .textFieldStyle(.plain)
                    .font(.bodyMedium)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .disabled(viewModel.isThinking)
                    .onSubmit { viewModel.sendMessage() }
                
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    viewModel.sendMessage()
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(
                            LinearGradient(
                                colors: viewModel.currentInput.isEmpty || viewModel.isThinking
                                     ? [Color.brandDark.opacity(0.3), Color.brandDark.opacity(0.3)]
                                     : [Color.brand, Color.brandDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: viewModel.currentInput.isEmpty ? .clear : Color.brand.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(viewModel.currentInput.isEmpty || viewModel.isThinking)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }
    
    private var interactiveOutlineList: some View {
        List {
            ForEach(viewModel.activeModules) { module in
                Button(action: {
                    if editMode == .inactive {
                        viewModel.selectedModule = module
                    }
                }) {
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.title)
                                .font(.bodySmall.weight(.bold))
                                .foregroundStyle(.primary)
                            
                            if let bloom = module.bloomsLevel {
                                Text(bloom.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.brandLight)
                            }
                        }
                        
                        Spacer()
                        
                        if editMode == .inactive {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let module = viewModel.activeModules[index]
                    viewModel.deleteModule(id: module.id)
                }
            }
            .onMove { indices, newOffset in
                var updatedList = viewModel.activeModules
                updatedList.move(fromOffsets: indices, toOffset: newOffset)
                let orderedIds = updatedList.map { $0.id }
                viewModel.reorderModules(moduleIds: orderedIds)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
    }
}

// MARK: - Module Detail Sheet

struct ModuleDetailSheet: View {
    @Bindable var viewModel: AgenticCanvasViewModel
    let module: CurriculumModuleResponse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var editedContent = ""
    @State private var editedBloomsLevel = "remember"
    @State private var refinementPrompt = ""
    @State private var selectedCitation: GroundingCitation? = nil
    
    var quizHasAlignmentIssues: Bool {
        guard let blooms = module.bloomsLevel?.lowercased() else { return false }
        let highCognitiveLevels = ["apply", "analyze", "evaluate", "create"]
        if highCognitiveLevels.contains(blooms) {
            for q in module.quizQuestions {
                let qBloom = q.bloomsLevel?.lowercased() ?? "understand"
                if qBloom == "remember" || qBloom == "understand" {
                    return true
                }
                let stems = ["what is", "define", "list the", "name the", "state the", "which of the following is the definition"]
                for stem in stems {
                    if q.questionText.lowercased().contains(stem) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    editingForm
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            heroHeader
                            
                            VStack(alignment: .leading, spacing: Spacing.xl) {
                                lessonContentCard
                                
                                alignmentAuditorBanner()
                                
                                quizQuestionsSection
                                
                                aiRefinementCard
                            }
                            .padding(.bottom, 40)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                    .background(Color.black.opacity(0.03))
                }
            }
            .onAppear {
                editedTitle = module.title
                editedContent = module.content
                editedBloomsLevel = module.bloomsLevel ?? "remember"
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            editedTitle = module.title
                            editedContent = module.content
                            editedBloomsLevel = module.bloomsLevel ?? "remember"
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.brandLight)
                    } else {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.brandLight)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if isEditing {
                            Button("Save") {
                                viewModel.updateModule(
                                    id: module.id,
                                    title: editedTitle,
                                    content: editedContent,
                                    bloomsLevel: editedBloomsLevel
                                )
                                isEditing = false
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.brandLight)
                        } else {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }
            .toolbarBackground(isEditing ? .visible : .hidden, for: .navigationBar)
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "citation" {
                let filename = url.host?.removingPercentEncoding ?? (url.host ?? "")
                let pageStr = url.lastPathComponent
                if let page = Int(pageStr) {
                    selectedCitation = GroundingCitation(filename: filename, page: page)
                }
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $selectedCitation) { citation in
            if let projectId = viewModel.appState?.selectedProjectID {
                GroundingPreviewSheet(projectId: projectId, filename: citation.filename, page: citation.page)
            }
        }
    }
    
    private var editingForm: some View {
        Form {
            Section(header: Text("Module Details").font(.caption.weight(.semibold)).foregroundStyle(Color.brandLight)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("Module Title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bloom's Level")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Picker("Bloom's Level", selection: $editedBloomsLevel) {
                        Text("Remember").tag("remember")
                        Text("Understand").tag("understand")
                        Text("Apply").tag("apply")
                        Text("Analyze").tag("analyze")
                        Text("Evaluate").tag("evaluate")
                        Text("Create").tag("create")
                    }
                    .pickerStyle(.menu)
                }
            }
            .listRowBackground(Color.white.opacity(0.05))
            
            Section(header: Text("Lesson Content").font(.caption.weight(.semibold)).foregroundStyle(Color.brandLight)) {
                TextEditor(text: $editedContent)
                    .frame(minHeight: 250)
                    .font(.body)
                    .padding(4)
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
        .background(Color.black.opacity(0.05))
    }
    
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.brandDark, Color.brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 180)
            
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 150, height: 150)
                .offset(x: 250, y: -40)
                .blur(radius: 20)
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let bloom = module.bloomsLevel {
                    Text(bloom.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }
                
                Text(module.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                
                Text("Version \(module.version) • Order \(module.sequenceOrder)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(Spacing.lg)
        }
    }
    
    private var lessonContentCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Lesson Content", systemImage: "book.pages.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.brandLight)
            
            Text(LocalizedStringKey(module.content))
                .font(.body)
                .lineSpacing(6)
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
        }
        .padding(Spacing.lg)
        .background(colorScheme == .dark ? Color(white: 0.1) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal)
        .offset(y: -20)
    }
    
    @ViewBuilder
    private func alignmentAuditorBanner() -> some View {
        if quizHasAlignmentIssues {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Pedagogical Alignment Warning")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.yellow)
                }
                Text("The target cognitive level is '\(module.bloomsLevel?.capitalized ?? "")', but some quiz questions only test low-level recall (Remember/Understand).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Button(action: {
                    viewModel.refineModule(id: module.id, prompt: "Rewrite the quiz questions to align with the module's cognitive level of \(module.bloomsLevel?.capitalized ?? "") using scenario-based application questions.")
                }) {
                    if viewModel.isThinking {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Label("Auto-Align with AI", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.yellow.opacity(0.15))
                            .foregroundStyle(.yellow)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.yellow.opacity(0.4), lineWidth: 1))
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(viewModel.isThinking)
            }
            .padding(12)
            .background(Color.yellow.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var quizQuestionsSection: some View {
        if !module.quizQuestions.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Assessment", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.brandLight)
                    .padding(.horizontal)
                
                ForEach(Array(module.quizQuestions.enumerated()), id: \.element.id) { index, q in
                    quizCard(question: q, index: index + 1)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var aiRefinementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask AI to Refine Content", systemImage: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.brandLight)
            
            HStack(spacing: Spacing.sm) {
                TextField("e.g. Add a section on Sprint Planning best practices...", text: $refinementPrompt)
                    .textFieldStyle(.plain)
                    .font(.bodySmall)
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .disabled(viewModel.isThinking)
                
                Button(action: {
                    if !refinementPrompt.isEmpty {
                        let prompt = refinementPrompt
                        refinementPrompt = ""
                        viewModel.refineModule(id: module.id, prompt: prompt)
                    }
                }) {
                    if viewModel.isThinking {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.horizontal, 12)
                    } else {
                        Text("Refine")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.brand.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(refinementPrompt.isEmpty || viewModel.isThinking)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func quizCard(question: QuizQuestionResponse, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                Text("Q\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.brandLight)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.questionText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    if let sourceInfo = question.sourceInfo, let parsed = parseSourceInfo(sourceInfo) {
                        Button(action: {
                            selectedCitation = GroundingCitation(filename: parsed.filename, page: parsed.page)
                        }) {
                            Label("Verified Source (p. \(parsed.page))", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.success.opacity(0.15))
                                .foregroundStyle(Color.success)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.success.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.top, 4)
            }
            
            if let options = question.options {
                VStack(spacing: Spacing.xs) {
                    ForEach(options, id: \.self) { option in
                        let isCorrect = (option == question.correctAnswer)
                        
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: isCorrect ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isCorrect ? AnyShapeStyle(Color.success) : AnyShapeStyle(.tertiary))
                                .font(.system(size: 18))
                            
                            Text(option)
                                .font(.subheadline)
                                .foregroundStyle(isCorrect ? .primary : .secondary)
                                .fontWeight(isCorrect ? .medium : .regular)
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(isCorrect ? Color.success.opacity(0.1) : Color.black.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isCorrect ? Color.success.opacity(0.3) : Color.black.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
                .padding(.leading, 36) // Indent to align with text
            }
            
            if let explanation = question.explanation, !explanation.isEmpty {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "lightbulb.max.fill")
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                    
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.leading, 36)
                .padding(.top, 4)
            }
        }
        .padding(Spacing.lg)
        .background(colorScheme == .dark ? Color(white: 0.1) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, y: 3)
    }
}

struct SCORMExportOptionsSheet: View {
    @Bindable var viewModel: AgenticCanvasViewModel
    let onSelect: (AgenticCanvasViewModel.SCORMVersion) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Target Module")) {
                    Picker("Select Target", selection: $viewModel.selectedExportModuleId) {
                        Text("Full Course (All Modules)").tag("all")
                        ForEach(viewModel.activeModules, id: \.id) { mod in
                            Text(mod.title).tag(mod.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("Select Export Format")) {
                    ForEach(AgenticCanvasViewModel.SCORMVersion.allCases) { version in
                        Button(action: {
                            onSelect(version)
                            dismiss()
                        }) {
                            HStack {
                                Text(version.rawValue)
                                    .foregroundStyle(.primary)
                                    .font(.bodyMedium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Hardware-Accelerated Graph Canvas

struct CurriculumNodeGraph: View {
    let modules: [CurriculumModuleResponse]
    let onSelect: (CurriculumModuleResponse) -> Void
    
    @State private var offset = CGSize.zero
    @State private var currentDrag = CGSize.zero
    @State private var scale: CGFloat = 1.0
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background grid or dots
                Circle()
                    .fill(Color.brandLight.opacity(0.05))
                    .frame(width: 400, height: 400)
                    .blur(radius: 50)
                
                // Draw Edges using Metal Canvas
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: 80)
                    for (index, _) in modules.enumerated() {
                        if index < modules.count - 1 {
                            let startPoint = point(for: index, center: center)
                            let endPoint = point(for: index + 1, center: center)
                            
                            var path = Path()
                            path.move(to: startPoint)
                            
                            let midY = (startPoint.y + endPoint.y) / 2
                            path.addCurve(to: endPoint, control1: CGPoint(x: startPoint.x, y: midY), control2: CGPoint(x: endPoint.x, y: midY))
                            
                            context.stroke(
                                path,
                                with: .color(Color.brandLight.opacity(0.3)),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 8])
                            )
                        }
                    }
                }
                
                // Draw Nodes
                ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                    NodeView(module: module)
                        .position(point(for: index, center: CGPoint(x: geo.size.width / 2, y: 80)))
                        .onTapGesture {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            onSelect(module)
                        }
                }
            }
            .scaleEffect(scale * currentScale)
            .offset(x: offset.width + currentDrag.width, y: offset.height + currentDrag.height)
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            scale = 1.0
                            currentScale = 1.0
                            offset = .zero
                            currentDrag = .zero
                        }
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        currentDrag = value.translation
                    }
                    .onEnded { value in
                        let newWidth = offset.width + value.translation.width
                        let newHeight = offset.height + value.translation.height
                        offset.width = min(max(newWidth, -1200), 1200)
                        offset.height = min(max(newHeight, -1500), 1500)
                        currentDrag = .zero
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        currentScale = value
                    }
                    .onEnded { value in
                        let nextScale = scale * value
                        let clamped = min(max(nextScale, 0.4), 3.0)
                        
                        if clamped == 0.4 || clamped == 3.0 {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                        
                        scale = clamped
                        currentScale = 1.0
                    }
            )
        }
        .clipped()
    }
    
    private func point(for index: Int, center: CGPoint) -> CGPoint {
        let row = index / 2
        let col = index % 2
        let direction = (row % 2 == 0) ? 1.0 : -1.0
        let xOffset = direction * (col == 0 ? -70.0 : 70.0)
        return CGPoint(x: center.x + xOffset, y: center.y + CGFloat(index * 130))
    }
}

struct NodeView: View {
    let module: CurriculumModuleResponse
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let bloomColor: Color = {
            switch module.bloomsLevel?.lowercased() {
            case "remember", "understand": return .blue
            case "apply", "analyze": return .orange
            case "evaluate", "create": return .purple
            default: return .brand
            }
        }()
        
        VStack(spacing: 6) {
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(bloomColor)
            
            Text(module.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            if let bloom = module.bloomsLevel {
                Text(bloom.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(bloomColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bloomColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .frame(width: 150, height: 110)
        .background(colorScheme == .dark ? Color(white: 0.1) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bloomColor.opacity(0.6), lineWidth: 2)
        )
        .shadow(color: bloomColor.opacity(0.3), radius: 10, y: 4)
    }
}

// MARK: - LMS Simulator View & Parser Helper

func splitContentToSlides(content: String) -> [String] {
    var sections: [String] = []
    
    // Try splitting by markdown headings (e.g., ## or ###)
    let components = content.components(separatedBy: "\n##")
    if components.count > 1 {
        sections = components.map { section in
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            var clean = trimmed
            if clean.hasPrefix("#") {
                clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return clean
        }.filter { !$0.isEmpty }
    }
    
    // If we didn't find clear heading splits, try splitting by paragraph boundaries (double newlines)
    if sections.count <= 1 {
        let paras = content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if paras.count > 1 {
            let maxSlides = 5
            let groupSize = max(1, Int(ceil(Double(paras.count) / Double(maxSlides))))
            
            var currentChunk = ""
            for (idx, para) in paras.enumerated() {
                if idx > 0 && idx % groupSize == 0 {
                    sections.append(currentChunk)
                    currentChunk = para
                } else {
                    if currentChunk.isEmpty {
                        currentChunk = para
                    } else {
                        currentChunk += "\n\n" + para
                    }
                }
            }
            if !currentChunk.isEmpty {
                sections.append(currentChunk)
            }
        }
    }
    
    // Fallback: If still single page, chunk by sentence counts
    if sections.isEmpty {
        sections = [content]
    }
    
    return sections
}

struct LMSSimulatorView: View {
    let modules: [CurriculumModuleResponse]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @State private var currentModuleIndex = 0
    @State private var currentSlideIndex = 0 // 0 to slidesCount - 1 (learning content), slidesCount is the Quiz
    @State private var isSidebarCollapsed = false
    @State private var selectedCitation: GroundingCitation? = nil
    
    // Quiz state for the current module
    @State private var selectedAnswers: [String: String] = [:] // quizQuestionId -> selectedOption
    @State private var quizSubmitted = false
    @State private var scorePercent: Int = 0
    @State private var showExplanation: [String: Bool] = [:] // quizQuestionId -> showExplanation
    
    @State private var telemetryLogs: [String] = []
    @State private var showTelemetryConsole = false
    @State private var isPulsing = false
    
    func logTelemetry(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeStr = formatter.string(from: Date())
        telemetryLogs.append("[\(timeStr)] \(msg)")
    }
    
    var body: some View {
        let currentModule = modules.indices.contains(currentModuleIndex) ? modules[currentModuleIndex] : nil
        let slides = currentModule != nil ? splitContentToSlides(content: currentModule!.content) : []
        let hasQuiz = currentModule != nil && !currentModule!.quizQuestions.isEmpty
        let totalSteps = slides.count + (hasQuiz ? 1 : 0)
        
        NavigationStack {
            ZStack(alignment: .leading) {
                // Main player content
                VStack(spacing: 0) {
                    if let currentModule = currentModule {
                        playerHeader(module: currentModule, slidesCount: slides.count, totalSteps: totalSteps)
                        progressBar(totalSteps: totalSteps)
                        
                        ScrollView {
                            VStack(spacing: Spacing.xl) {
                                if currentSlideIndex < slides.count {
                                    slideContent(text: slides[currentSlideIndex])
                                } else {
                                    quizPlayerView(module: currentModule)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        playerFooter(totalSteps: totalSteps, slidesCount: slides.count, hasQuiz: hasQuiz)
                        
                        telemetryConsoleView
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, (sizeClass == .regular && !isSidebarCollapsed) ? 240 : 0)
                
                // Adaptive Sidebar Panel
                if !isSidebarCollapsed {
                    if sizeClass == .compact {
                        // Mobile Overlay Style Drawer
                        ZStack(alignment: .leading) {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isSidebarCollapsed = true
                                    }
                                }
                            
                            sidebar
                                .frame(width: 260)
                                .background(Color.brandDark)
                                .ignoresSafeArea(edges: .bottom)
                        }
                        .zIndex(10)
                        .transition(.opacity)
                    } else {
                        // Desktop Side-by-Side Style Panel
                        HStack(spacing: 0) {
                            sidebar
                                .frame(width: 240)
                                .background(Color.black.opacity(0.15))
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 1)
                        }
                        .frame(maxHeight: .infinity)
                        .zIndex(5)
                        .transition(.move(edge: .leading))
                    }
                }
            }
            .navigationTitle("LMS Simulator Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Exit") {
                        logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.exit', 'suspend') -> SUCCESS")
                        logTelemetry("[SCORM 1.2] LMSFinish() -> SUCCESS")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandLight)
                }
            }
            .onChange(of: currentSlideIndex) { _, _ in
                if let mod = currentModule {
                    if currentSlideIndex < slides.count {
                        logTelemetry("[xAPI] Statement Generated -> ACTOR: [Simulated Learner], VERB: experienced, OBJECT: Slide \(currentSlideIndex + 1) (\(mod.title))")
                    } else {
                        logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.lesson_location', 'quiz') -> SUCCESS")
                        logTelemetry("[xAPI] Statement Generated -> ACTOR: [Simulated Learner], VERB: experienced, OBJECT: Quiz Section (\(mod.title))")
                    }
                }
            }
            .onChange(of: currentModuleIndex) { _, _ in
                if let mod = currentModule {
                    logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.lesson_location', 'module_\(currentModuleIndex + 1)') -> SUCCESS")
                    logTelemetry("[xAPI] Statement Generated -> ACTOR: [Simulated Learner], VERB: experienced, OBJECT: Module \(currentModuleIndex + 1) (\(mod.title))")
                }
            }
            .onAppear {
                logTelemetry("[SCORM 1.2] LMSInitialize() -> SUCCESS")
                logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.lesson_status', 'incomplete') -> SUCCESS")
                logTelemetry("[SCORM 1.2] LMSCommit() -> SUCCESS")
                if let mod = currentModule {
                    logTelemetry("[xAPI] Statement Generated -> ACTOR: [Simulated Learner], VERB: experienced, OBJECT: Course Launch (\(mod.title))")
                }
                
                // Hide sidebar by default on mobile to keep player un-squished
                if sizeClass == .compact {
                    isSidebarCollapsed = true
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "citation" {
                let filename = url.host?.removingPercentEncoding ?? (url.host ?? "")
                let pageStr = url.lastPathComponent
                if let page = Int(pageStr) {
                    selectedCitation = GroundingCitation(filename: filename, page: page)
                }
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $selectedCitation) { citation in
            if let projectId = modules.first?.projectId {
                GroundingPreviewSheet(projectId: projectId, filename: citation.filename, page: citation.page)
            }
        }
    }
    
    // MARK: - Telemetry Console
    
    private var telemetryConsoleView: some View {
        VStack(spacing: 0) {
            // Console Header
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showTelemetryConsole.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isPulsing ? 1.3 : 0.85)
                        .opacity(isPulsing ? 1.0 : 0.6)
                        .shadow(color: Color.success.opacity(0.6), radius: 2)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                isPulsing = true
                            }
                        }
                    
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(Color.brandLight)
                        .font(.system(size: 11))
                    
                    Text("LMS Telemetry Console")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Text("\(telemetryLogs.count) logs")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.success.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.success.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.success.opacity(0.3), lineWidth: 0.5))
                    
                    Image(systemName: showTelemetryConsole ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(Divider().background(Color.white.opacity(0.08)), alignment: .top)
            }
            
            if showTelemetryConsole {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if telemetryLogs.isEmpty {
                                Text("No API handshakes recorded yet. Navigate slides or take the quiz.")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding()
                            } else {
                                ForEach(telemetryLogs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(logColor(log))
                                        .textSelection(.enabled)
                                        .id(log)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .frame(height: sizeClass == .regular ? 240 : 160)
                    .background(Color.black.opacity(0.7))
                    .onChange(of: telemetryLogs.count) { _, _ in
                        if let lastLog = telemetryLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func logColor(_ log: String) -> Color {
        if log.contains("SUCCESS") || log.contains("passed") {
            return Color.success
        } else if log.contains("failed") || log.contains("error") {
            return Color.error
        } else if log.contains("xAPI") {
            return Color.brandLight
        } else if log.contains("LMSSetValue") {
            return .cyan
        }
        return .secondary
    }
    
    private func resetQuiz() {
        selectedAnswers.removeAll()
        quizSubmitted = false
        scorePercent = 0
        showExplanation.removeAll()
    }
}

// MARK: - LMS Simulator Subviews

extension LMSSimulatorView {
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Course Outline")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brandLight)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(modules.enumerated()), id: \.element.id) { idx, mod in
                        let isSelected = idx == currentModuleIndex
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                currentModuleIndex = idx
                                currentSlideIndex = 0
                                resetQuiz()
                                if sizeClass == .compact {
                                    isSidebarCollapsed = true
                                }
                            }
                        }) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: isSelected ? "book.fill" : "book")
                                    .font(.system(size: 13))
                                    .foregroundStyle(isSelected ? Color.brandLight : .secondary)
                                
                                Text(mod.title)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func playerHeader(module: CurriculumModuleResponse, slidesCount: Int, totalSteps: Int) -> some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSidebarCollapsed.toggle()
                }
            }) {
                Image(systemName: isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.brandLight)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let bloom = module.bloomsLevel {
                    Text(bloom.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.brandLight)
                }
            }
            
            Spacer()
            
            Text(currentSlideIndex == slidesCount ? "Knowledge Check" : "Slide \(currentSlideIndex + 1) of \(slidesCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.black.opacity(0.1))
    }
    
    private func progressBar(totalSteps: Int) -> some View {
        GeometryReader { gp in
            let percent = totalSteps > 0 ? Double(currentSlideIndex + 1) / Double(totalSteps) : 0.0
            Rectangle()
                .fill(Color.brand.gradient)
                .frame(width: gp.size.width * CGFloat(percent))
        }
        .frame(height: 4)
        .background(Color.white.opacity(0.1))
    }
    
    private func slideContent(text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(LocalizedStringKey(text))
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(8)
                .foregroundStyle(.primary)
                .padding(Spacing.lg)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .padding(.top, Spacing.lg)
    }
    
    private func playerFooter(totalSteps: Int, slidesCount: Int, hasQuiz: Bool) -> some View {
        HStack {
            Button(action: {
                if currentSlideIndex > 0 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentSlideIndex -= 1
                    }
                }
            }) {
                Label("Previous", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(currentSlideIndex > 0 ? Color.brandLight : Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(currentSlideIndex == 0)
            
            Spacer()
            
            Button(action: {
                if currentSlideIndex < totalSteps - 1 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentSlideIndex += 1
                    }
                } else {
                    if currentModuleIndex < modules.count - 1 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentModuleIndex += 1
                            currentSlideIndex = 0
                            resetQuiz()
                        }
                    }
                }
            }) {
                let label = (currentSlideIndex == slidesCount - 1 && hasQuiz) ? "Take Quiz" :
                            (currentSlideIndex == totalSteps - 1 && currentModuleIndex < modules.count - 1) ? "Next Module" : "Next"
                let icon = currentSlideIndex == totalSteps - 1 ? "arrow.right" : "chevron.right"
                
                Label(label, systemImage: icon)
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.brand.gradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(currentSlideIndex == totalSteps - 1 && currentModuleIndex == modules.count - 1)
        }
        .padding()
        .background(Color.black.opacity(0.1))
    }
    
    private var emptyState: some View {
        VStack {
            Text("No content selected")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func quizPlayerView(module: CurriculumModuleResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Module Quiz Checkpoint")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.brandLight)
            
            ForEach(Array(module.quizQuestions.enumerated()), id: \.element.id) { qIdx, q in
                quizQuestionCard(question: q, index: qIdx + 1)
            }
            
            if !quizSubmitted {
                submitButton(module: module)
            } else {
                scorecardView(module: module)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
    
    private func quizQuestionCard(question: QuizQuestionResponse, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                Text("Q\(index)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.brandLight)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.questionText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    if let sourceInfo = question.sourceInfo, let parsed = parseSourceInfo(sourceInfo) {
                        Button(action: {
                            selectedCitation = GroundingCitation(filename: parsed.filename, page: parsed.page)
                        }) {
                            Label("Verified Source (p. \(parsed.page))", systemImage: "checkmark.shield.fill")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.success.opacity(0.15))
                                .foregroundStyle(Color.success)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.success.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
            
            if let options = question.options {
                quizOptionsList(question: question, options: options)
            }
            
            if quizSubmitted {
                explanationView(question: question)
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
    
    private func quizOptionsList(question: QuizQuestionResponse, options: [String]) -> some View {
        VStack(spacing: Spacing.xs) {
            ForEach(options, id: \.self) { opt in
                quizOptionRow(question: question, option: opt)
            }
        }
        .padding(.leading, 32)
    }
    
    private func quizOptionRow(question: QuizQuestionResponse, option: String) -> some View {
        let isSelected = selectedAnswers[question.id] == option
        let isCorrect = option == question.correctAnswer
        let iconColor = optionIconColor(isSelected: isSelected, isCorrect: isCorrect)
        let textColor = optionTextColor(isSelected: isSelected, isCorrect: isCorrect)
        let bgColor = optionBgColor(isSelected: isSelected, isCorrect: isCorrect)
        let borderColor = optionBorderColor(isSelected: isSelected, isCorrect: isCorrect)
        
        return Button(action: {
            if !quizSubmitted {
                selectedAnswers[question.id] = option
                logTelemetry("[xAPI] Statement Generated -> ACTOR: [Simulated Learner], VERB: interacted, OBJECT: Select Option \"\(option)\" for Q\(question.sequenceOrder)")
            }
        }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                
                Text(option)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if quizSubmitted && isCorrect {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.success)
                        .font(.system(size: 11, weight: .bold))
                } else if quizSubmitted && isSelected && !isCorrect {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.error)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .padding(12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
        }
        .disabled(quizSubmitted)
    }
    
    private func optionIconColor(isSelected: Bool, isCorrect: Bool) -> Color {
        if quizSubmitted {
            return isCorrect ? Color.success : (isSelected ? Color.error : Color.white.opacity(0.2))
        }
        return isSelected ? Color.brandLight : Color.white.opacity(0.3)
    }
    
    private func optionTextColor(isSelected: Bool, isCorrect: Bool) -> Color {
        if quizSubmitted {
            return isCorrect ? .white : (isSelected ? Color.error : .secondary)
        }
        return isSelected ? .white : .secondary
    }
    
    private func optionBgColor(isSelected: Bool, isCorrect: Bool) -> Color {
        if quizSubmitted {
            return isCorrect ? Color.success.opacity(0.12) : (isSelected ? Color.error.opacity(0.12) : Color.white.opacity(0.02))
        }
        return isSelected ? Color.brand.opacity(0.12) : Color.white.opacity(0.02)
    }
    
    private func optionBorderColor(isSelected: Bool, isCorrect: Bool) -> Color {
        if quizSubmitted {
            return isCorrect ? Color.success.opacity(0.4) : (isSelected ? Color.error.opacity(0.4) : Color.white.opacity(0.05))
        }
        return isSelected ? Color.brandLight.opacity(0.5) : Color.white.opacity(0.05)
    }
    
    private func explanationView(question: QuizQuestionResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: {
                withAnimation {
                    showExplanation[question.id] = !(showExplanation[question.id] ?? false)
                }
            }) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text(showExplanation[question.id] == true ? "Hide Explanation" : "Reveal Explanation")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.brandLight)
                    Spacer()
                }
            }
            
            if showExplanation[question.id] == true, let explanation = question.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(10)
                    .background(Color.yellow.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.leading, 32)
    }
    
    private func submitButton(module: CurriculumModuleResponse) -> some View {
        Button(action: {
            let totalQuestions = module.quizQuestions.count
            guard totalQuestions > 0 else { return }
            var correctCount = 0
            for q in module.quizQuestions {
                if selectedAnswers[q.id] == q.correctAnswer {
                    correctCount += 1
                }
            }
            scorePercent = Int(round((Double(correctCount) / Double(totalQuestions)) * 100))
            
            // Log SCORM and xAPI telemetry
            logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.score.raw', '\(scorePercent)') -> SUCCESS")
            logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.score.min', '0') -> SUCCESS")
            logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.score.max', '100') -> SUCCESS")
            
            let status = scorePercent >= 70 ? "passed" : "failed"
            logTelemetry("[SCORM 1.2] LMSSetValue('cmi.core.lesson_status', '\(status)') -> SUCCESS")
            logTelemetry("[SCORM 1.2] LMSCommit() -> SUCCESS")
            logTelemetry("[xAPI] Statement Generated -> ACTOR: [Simulated Learner], VERB: answered, OBJECT: Quiz, SUCCESS: \(scorePercent >= 70), SCORE: \(scorePercent)%")
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                quizSubmitted = true
            }
        }) {
            Text("Submit Answers")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.brand.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.brand.opacity(0.3), radius: 8, y: 3)
        }
        .padding(.top, Spacing.sm)
        .disabled(selectedAnswers.count < module.quizQuestions.count)
        .opacity(selectedAnswers.count < module.quizQuestions.count ? 0.5 : 1.0)
    }
    
    private func scorecardView(module: CurriculumModuleResponse) -> some View {
        VStack(spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assessment Results")
                        .font(.system(size: 16, weight: .bold))
                    Text(scorePercent >= 70 ? "Passed • Completed" : "Did not pass • Required 70%")
                        .font(.system(size: 12))
                        .foregroundStyle(scorePercent >= 70 ? Color.success : Color.error)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                        .frame(width: 54, height: 54)
                    Circle()
                        .trim(from: 0, to: CGFloat(scorePercent) / 100.0)
                        .stroke(scorePercent >= 70 ? Color.success : Color.error, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                    Text("\(scorePercent)%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            HStack(spacing: Spacing.md) {
                Button(action: {
                    resetQuiz()
                }) {
                    Label("Retry Quiz", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                if currentModuleIndex < modules.count - 1 {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            currentModuleIndex += 1
                            currentSlideIndex = 0
                            resetQuiz()
                        }
                    }) {
                        Label("Next Module", systemImage: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.brand.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }
}

// MARK: - Grounding Compliance Models & Views

struct GroundingCitation: Identifiable, Equatable {
    var id: String { "\(filename)-\(page)" }
    let filename: String
    let page: Int
}

func parseSourceInfo(_ sourceInfo: String) -> (filename: String, page: Int)? {
    let pattern = #"Document:\s*(.*?),\s*Page:\s*(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return nil
    }
    let nsString = sourceInfo as NSString
    let results = regex.matches(in: sourceInfo, options: [], range: NSRange(location: 0, length: nsString.length))
    if let match = results.first, match.numberOfRanges >= 3 {
        let filename = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        let pageStr = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let page = Int(pageStr) {
            return (filename, page)
        }
    }
    return nil
}

struct GroundingPreviewSheet: View {
    let projectId: String
    let filename: String
    let page: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var content: String = ""
    @State private var sectionTitle: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: colorScheme == .dark ? [Color(white: 0.08), Color(white: 0.15)] : [Color(white: 0.95), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color.brandLight)
                        Text("Verifying source grounding...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.error)
                        Text("Audit Trail Lookup Failed")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            // Document metadata header card
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "doc.text.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.brandLight)
                                    .frame(width: 44, height: 44)
                                    .background(Color.brandLight.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(filename)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    Text("Page \(page) • Verified Grounding")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.success)
                                }
                                
                                Spacer()
                                
                                Label("100% Grounded", systemImage: "checkmark.shield.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.success.opacity(0.15))
                                    .foregroundStyle(Color.success)
                                    .clipShape(Capsule())
                            }
                            .padding()
                            .background(Color.white.opacity(colorScheme == .dark ? 0.03 : 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            
                            if !sectionTitle.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SECTION")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(Color.brandLight)
                                        .tracking(1.0)
                                    Text(sectionTitle)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 4)
                            }
                            
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Indexed Source Passage")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                
                                Text(content)
                                    .font(.system(size: 14))
                                    .lineSpacing(6)
                                    .foregroundStyle(.primary.opacity(0.9))
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Compliance Audit Trail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandLight)
                }
            }
            .onAppear {
                fetchSourceChunk()
            }
        }
    }
    
    private func fetchSourceChunk() {
        Task {
            do {
                let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
                let path = "/api/projects/\(projectId)/documents/chunk-query?filename=\(encodedFilename)&page=\(page)"
                
                struct ChunkQueryResponse: Codable {
                    let found: Bool
                    let content: String?
                    let filename: String?
                    let page: Int?
                    let sectionTitle: String?
                    let message: String?
                }
                
                let res: ChunkQueryResponse = try await APIClient.shared.request(path: path)
                await MainActor.run {
                    self.isLoading = false
                    if res.found {
                        self.content = res.content ?? "No content found in chunk."
                        self.sectionTitle = res.sectionTitle ?? ""
                    } else {
                        self.errorMessage = res.message ?? "Source text passage could not be retrieved."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

