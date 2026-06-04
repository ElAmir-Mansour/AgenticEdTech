import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedWorkspace: AppState.WorkspaceType = .dashboard
    
    var body: some View {
        if !appState.isAuthenticated {
            LoginView()
        } else {
            if sizeClass == .compact {
                // iPhone Layout
                TabView(selection: $selectedWorkspace) {
                    NavigationStack {
                        WorkspaceDetailView(workspace: .dashboard)
                            .navigationTitle("Dashboard")
                            .toolbar { compactToolbar }
                    }
                    .tabItem {
                        Label("Dashboard", systemImage: "chart.bar.fill")
                    }
                    .tag(AppState.WorkspaceType.dashboard)
                    
                    NavigationStack {
                        WorkspaceDetailView(workspace: .ingestion)
                            .navigationTitle("Ingestion Vault")
                            .toolbar { compactToolbar }
                    }
                    .tabItem {
                        Label("Ingestion", systemImage: "arrow.down.doc.fill")
                    }
                    .tag(AppState.WorkspaceType.ingestion)
                    
                    NavigationStack {
                        WorkspaceDetailView(workspace: .canvas)
                            .navigationTitle("Agentic Canvas")
                            .toolbar { compactToolbar }
                    }
                    .tabItem {
                        Label("Canvas", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                    .tag(AppState.WorkspaceType.canvas)
                    
                    NavigationStack {
                        WorkspaceDetailView(workspace: .simulation)
                            .navigationTitle("Sandbox")
                            .toolbar { compactToolbar }
                    }
                    .tabItem {
                        Label("Simulation", systemImage: "play.desktopcomputer")
                    }
                    .tag(AppState.WorkspaceType.simulation)
                    
                    NavigationStack {
                        WorkspaceDetailView(workspace: .diagnostics)
                            .navigationTitle("Diagnostics")
                            .toolbar { compactToolbar }
                    }
                    .tabItem {
                        Label("Diagnostics", systemImage: "waveform.path.ecg.rectangle")
                    }
                    .tag(AppState.WorkspaceType.diagnostics)
                }
                .tint(Color.brand)
                .sheet(isPresented: $showNewProjectSheet) {
                    NewProjectSheet(title: $newProjectTitle, description: $newProjectDescription) {
                        appState.createProject(title: newProjectTitle, description: newProjectDescription)
                        newProjectTitle = ""
                        newProjectDescription = ""
                    }
                }
            } else {
                // iPad Layout (2-Column Split View with Collapsible Right inspector)
                NavigationSplitView {
                    List(selection: Binding<AppState.WorkspaceType?>(
                        get: { selectedWorkspace },
                        set: { if let val = $0 { selectedWorkspace = val } }
                    )) {
                        // Project Switcher Section
                        Section("Project") {
                            ForEach(appState.availableProjects) { project in
                                Button {
                                    appState.switchProject(to: project)
                                } label: {
                                    HStack {
                                        Image(systemName: project.id == appState.selectedProjectID ? "folder.fill" : "folder")
                                            .foregroundStyle(project.id == appState.selectedProjectID ? Color.brand : .secondary)
                                        Text(project.title)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if project.id == appState.selectedProjectID {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundStyle(Color.brand)
                                        }
                                    }
                                }
                            }
                            Button {
                                showNewProjectSheet = true
                            } label: {
                                Label("New Project", systemImage: "plus.circle")
                                    .foregroundStyle(Color.brand)
                            }
                        }
                        
                        Section("Workspaces") {
                            Label("Dashboard", systemImage: "chart.bar.fill")
                                .tag(AppState.WorkspaceType.dashboard)
                            Label("Ingestion Vault", systemImage: "arrow.down.doc.fill")
                                .tag(AppState.WorkspaceType.ingestion)
                            Label("Agentic Canvas", systemImage: "rectangle.and.pencil.and.ellipsis")
                                .tag(AppState.WorkspaceType.canvas)
                            Label("Simulation Sandbox", systemImage: "play.desktopcomputer")
                                .tag(AppState.WorkspaceType.simulation)
                            Label("Diagnostics & Tests", systemImage: "waveform.path.ecg.rectangle")
                                .tag(AppState.WorkspaceType.diagnostics)
                        }
                        
                        Section {
                            Button(role: .destructive) {
                                appState.logout()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                    .navigationTitle("EdTech Platform")
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(.ultraThinMaterial)
                } detail: {
                    HStack(spacing: 0) {
                        WorkspaceDetailView(workspace: selectedWorkspace)
                            .navigationTitle(selectedWorkspace.title)
                        
                        if showContextPanel {
                            Divider()
                            WorkspaceContextPanel(workspace: selectedWorkspace)
                                .frame(width: 320)
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showContextPanel.toggle()
                                }
                            } label: {
                                Label("Toggle Context Panel", systemImage: "sidebar.trailing")
                                    .foregroundStyle(Color.brand)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showNewProjectSheet) {
                    NewProjectSheet(title: $newProjectTitle, description: $newProjectDescription) {
                        appState.createProject(title: newProjectTitle, description: newProjectDescription)
                        newProjectTitle = ""
                        newProjectDescription = ""
                    }
                }
            }
        }
    }
    
    // MARK: - Compact Toolbar
    @State private var showNewProjectSheet = false
    @State private var newProjectTitle = ""
    @State private var newProjectDescription = ""
    @State private var showContextPanel = true
    
    @ToolbarContentBuilder
    private var compactToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                // Project list
                ForEach(appState.availableProjects) { project in
                    Button {
                        appState.switchProject(to: project)
                    } label: {
                        HStack {
                            Text(project.title)
                            if project.id == appState.selectedProjectID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    showNewProjectSheet = true
                } label: {
                    Label("New Project", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(Color.brand)
                    Text(appState.selectedProjectTitle ?? "Project")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brandLight)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let name = appState.currentUserName {
                    Label(name, systemImage: "person.circle")
                }
                Divider()
                Button(role: .destructive) {
                    appState.logout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.circle")
                    .foregroundStyle(Color.brandLight)
            }
        }
    }
}

// MARK: - New Project Sheet
struct NewProjectSheet: View {
    @Binding var title: String
    @Binding var description: String
    let onCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Project Title", text: $title)
                    TextField("Description (optional)", text: $description)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Workspace Context Panel (iPad middle column)
// MARK: - Workspace Context Panel (iPad middle column)
struct WorkspaceContextPanel: View {
    let workspace: AppState.WorkspaceType
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulseActive = false
    
    // AI Connection States
    @State private var selectedProvider: String = "groq"
    @State private var endpointURL: String = ""
    @State private var modelName: String = "llama-3.3-70b-versatile"
    @State private var apiKey: String = ""
    @State private var testStatus: String = "idle"
    @State private var testMessage: String = ""
    @State private var latencyMs: Int = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // User Avatar Header
                userAvatarHeader
                
                // Active Project Card
                activeProjectCard
                
                // AI Connection Panel
                aiConnectionCard
                
                // Workspace Specific Overview
                workspaceOverviewCard
                
                // Live Connection Status
                connectionStatusCard
            }
            .padding(20)
        }
        .onAppear {
            loadSettings()
        }
        .onChange(of: appState.selectedProjectID) {
            loadSettings()
        }
        .navigationTitle(workspace.title)
        .background(
            ZStack {
                if colorScheme == .dark {
                    Color.black.opacity(0.15)
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .ignoresSafeArea()
        )
    }
    
    private var userAvatarHeader: some View {
        HStack(spacing: 16) {
            let initials = String((appState.currentUserName ?? appState.currentUserEmail ?? "U").prefix(1)).uppercased()
            
            Text(initials)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [Color.brand, Color.brandLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: Color.brand.opacity(0.3), radius: 6, x: 0, y: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentUserName ?? "Designer Account")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if let email = appState.currentUserEmail {
                    Text(email)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var activeProjectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Project Workspace")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
                .textCase(.uppercase)
            
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(Color.brandLight)
                    .frame(width: 44, height: 44)
                    .background(Color.brand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.selectedProjectTitle ?? "No Project Selected")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Selected active sandbox database")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var workspaceOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Workspace Profile")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                    .textCase(.uppercase)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: workspaceIcon)
                        .font(.title3)
                        .foregroundStyle(.white)
                    
                    Text(workspace.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                Text(workspace.description)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.85))
                
                // Mini Feature Tags ScrollView
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(workspaceTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.15))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.brandDark, Color.brand],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.brand.opacity(0.15), radius: 10, y: 4)
        }
    }
    
    private var connectionStatusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.isWebSocketConnected ? Color.success : Color.warning)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulseActive ? 1.3 : 0.85)
                .opacity(isPulseActive ? 1.0 : 0.6)
                .shadow(color: (appState.isWebSocketConnected ? Color.success : Color.warning).opacity(0.6), radius: 3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulseActive = true
                    }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isWebSocketConnected ? "Pipeline Active" : "Connecting Pipeline")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(appState.isWebSocketConnected ? "Websocket channel connected to FastAPI" : "Re-establishing backend socket handshake...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var workspaceIcon: String {
        switch workspace {
        case .dashboard: return "chart.bar.fill"
        case .ingestion: return "arrow.down.doc.fill"
        case .canvas: return "rectangle.and.pencil.and.ellipsis"
        case .simulation: return "play.desktopcomputer"
        case .diagnostics: return "waveform.path.ecg.rectangle"
        }
    }
    
    private var workspaceTags: [String] {
        switch workspace {
        case .dashboard:
            return ["Bloom's Distribution", "KPI Counters", "Server Sync"]
        case .ingestion:
            return ["PDF Parser", "Qdrant Vector DB", "Prerequisites Graph"]
        case .canvas:
            return ["Multi-Agent Debate", "Tin Can (xAPI) ZIP", "SCORM Export"]
        case .simulation:
            return ["Gemini Personas", "Per-Question Grading", "Heatmap"]
        case .diagnostics:
            return ["WS Ping Logs", "API Health Check", "Network Testing"]
        }
    }
    
    private var aiConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Model Configuration")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.0)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 12) {
                // Segmented Picker
                Picker("Provider", selection: $selectedProvider) {
                    Text("Groq").tag("groq")
                    Text("Gemini").tag("gemini")
                    Text("Ollama").tag("local_ollama")
                    Text("LM Studio").tag("local_openai")
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedProvider) {
                    if selectedProvider == "local_ollama" && (endpointURL.isEmpty || endpointURL.contains("1234")) {
                        endpointURL = "http://localhost:11434/v1"
                        modelName = "llama3"
                    } else if selectedProvider == "local_openai" && (endpointURL.isEmpty || endpointURL.contains("11434")) {
                        endpointURL = "http://localhost:1234/v1"
                        modelName = "local-model"
                    } else if selectedProvider == "groq" {
                        endpointURL = ""
                        modelName = "llama-3.3-70b-versatile"
                    } else if selectedProvider == "gemini" {
                        endpointURL = ""
                        modelName = "gemini-2.0-flash"
                    }
                }
                
                VStack(spacing: 8) {
                    if selectedProvider.hasPrefix("local") {
                        HStack {
                            Text("Endpoint URL")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        TextField("http://localhost:11434/v1", text: $endpointURL)
                            .font(.system(.footnote, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    
                    HStack {
                        Text("Model Name")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    TextField("Model ID", text: $modelName)
                        .font(.system(.footnote, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    
                    HStack {
                        Text("API Key (Optional)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    SecureField("API Key override", text: $apiKey)
                        .font(.system(.footnote, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                
                if testStatus != "idle" {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: testStatus == "testing" ? "arrow.triangle.2.circlepath" : (testStatus == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                            .font(.footnote)
                            .foregroundStyle(testStatus == "testing" ? .primary : (testStatus == "success" ? Color.success : Color.error))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(testStatus == "testing" ? "Testing Connection..." : (testStatus == "success" ? "Connection Successful" : "Connection Failed"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(testStatus == "testing" ? .primary : (testStatus == "success" ? Color.success : Color.error))
                            
                            Text(testMessage)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            
                            if testStatus == "success" && latencyMs > 0 {
                                Text("Latency: \(latencyMs) ms")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                
                Button(action: runConnectionTest) {
                    HStack {
                        Spacer()
                        if testStatus == "testing" {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        } else {
                            Image(systemName: "bolt.horizontal.circle.fill")
                        }
                        Text(testStatus == "testing" ? "Testing..." : "Test Local Handshake")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.brand)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .disabled(testStatus == "testing")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private func loadSettings() {
        guard let project = appState.selectedProject, let settings = project.settings else {
            selectedProvider = "groq"
            endpointURL = ""
            modelName = "llama-3.3-70b-versatile"
            apiKey = ""
            return
        }
        
        selectedProvider = settings["llm_provider"]?.value as? String ?? "groq"
        endpointURL = settings["llm_url"]?.value as? String ?? ""
        modelName = settings["llm_model"]?.value as? String ?? "llama-3.3-70b-versatile"
        apiKey = settings["llm_api_key"]?.value as? String ?? ""
    }
    
    private func saveSettings() {
        var settingsDict: [String: AnyCodable] = [:]
        settingsDict["llm_provider"] = AnyCodable(selectedProvider)
        settingsDict["llm_url"] = AnyCodable(endpointURL)
        settingsDict["llm_model"] = AnyCodable(modelName)
        settingsDict["llm_api_key"] = AnyCodable(apiKey)
        
        Task {
            do {
                try await appState.updateProjectSettings(settings: settingsDict)
                await MainActor.run {
                    withAnimation {
                        testStatus = "success"
                        testMessage = "Settings saved to project database!"
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        testStatus = "error"
                        testMessage = "Failed to save settings: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func runConnectionTest() {
        guard let projectId = appState.selectedProjectID else { return }
        
        withAnimation {
            testStatus = "testing"
            testMessage = "Pinging model endpoint..."
        }
        
        struct TestRequest: Codable {
            let provider: String
            let url: String?
            let model: String
            let apiKey: String?
        }
        
        Task {
            do {
                let req = TestRequest(
                    provider: selectedProvider,
                    url: endpointURL.isEmpty ? nil : endpointURL,
                    model: modelName,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )
                let body = try JSONEncoder().encode(req)
                
                struct TestResponse: Codable {
                    let status: String
                    let message: String
                    let latencyMs: Int?
                }
                
                let resp: TestResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/llm-config/test",
                    method: "POST",
                    body: body
                )
                
                await MainActor.run {
                    withAnimation {
                        if resp.status == "success" {
                            testStatus = "success"
                            latencyMs = resp.latencyMs ?? 0
                            testMessage = resp.message
                            saveSettings()
                        } else {
                            testStatus = "error"
                            testMessage = resp.message
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        testStatus = "error"
                        testMessage = "Connection failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

extension AppState.WorkspaceType {
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .ingestion: return "Ingestion Vault"
        case .canvas: return "Agentic Canvas"
        case .simulation: return "Simulation Sandbox"
        case .diagnostics: return "Diagnostics"
        }
    }
    
    var description: String {
        switch self {
        case .dashboard: return "Real-time project metrics, document stats, simulation scores, and Bloom's taxonomy distribution."
        case .ingestion: return "Upload PDF/TXT documents. The system extracts text, creates semantic chunks, embeds them in Qdrant, and builds a concept dependency graph."
        case .canvas: return "AI agents collaboratively draft curriculum modules. Watch Planning, Content, Assessment, and Critique agents debate in real-time."
        case .simulation: return "Test curriculum with configurable synthetic student personas. Gemini LLM simulates learner behavior and generates per-question pass rates."
        case .diagnostics: return "Run integration tests against the backend. Verify network connectivity, serialization, and WebSocket health."
        }
    }
}

// MARK: - Workspace Detail View
struct WorkspaceDetailView: View {
    let workspace: AppState.WorkspaceType
    @Environment(AppState.self) private var appState
    
    var body: some View {
        Group {
            switch workspace {
            case .dashboard:
                DashboardView()
            case .ingestion:
                IngestionView()
            case .canvas:
                AgenticCanvasView()
            case .simulation:
                SimulationSandboxView()
            case .diagnostics:
                DiagnosticsView()
            }
        }
        .id("\(workspace.rawValue)-\(appState.selectedProjectID ?? "none")")
    }
}
