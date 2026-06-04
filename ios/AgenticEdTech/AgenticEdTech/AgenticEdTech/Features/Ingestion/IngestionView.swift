import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Ingestion Models
struct IngestedDocumentMeta: Codable, Hashable {
    let stage: String?
    let progress: Double?
    let message: String?
    let error: String?
}

struct IngestedDocument: Identifiable, Codable {
    let id: String
    let projectId: String
    let filename: String
    let mimeType: String
    let fileSizeBytes: Int
    var processingStatus: String // "pending", "processing", "completed", "failed"
    var chunkCount: Int
    let createdAt: String
    let meta: IngestedDocumentMeta?
    
    var fileType: String {
        return mimeType == "application/pdf" ? "PDF" : "TXT"
    }
    
    var fileSize: String {
        return ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }
}

struct ConceptNode: Codable, Identifiable, Hashable {
    let id: String
    let projectId: String
    let name: String
    let description: String?
    let bloomsLevel: String?
    let sourceDocumentId: String?
    let sourcePage: Int?
}

struct ConceptEdge: Codable, Identifiable, Hashable {
    var id: String { "\(conceptId)-\(prerequisiteId)" }
    let conceptId: String
    let prerequisiteId: String
    let confidence: Double
    let relationship: String
}

struct ConceptGraphResponse: Codable {
    let concepts: [ConceptNode]
    let prerequisites: [ConceptEdge]
}

// MARK: - ViewModel
@Observable
class IngestionViewModel {
    var appState: AppState? = nil
    var documents: [IngestedDocument] = []
    
    // Concepts for Node Graph View
    var concepts: [ConceptNode] = []
    var prerequisites: [ConceptEdge] = []
    
    var isUploading = false
    var uploadProgress: Double = 0.0
    var uploadFilename = ""
    var errorMessage: String? = nil
    
    private var pollTimer: Timer? = nil
    
    func setAppState(_ state: AppState) {
        self.appState = state
        fetchDocumentsAndGraph()
        startStatusPolling()
    }
    
    func fetchDocumentsAndGraph() {
        guard let appState = appState, let projectId = appState.selectedProjectID else { return }
        
        Task {
            do {
                let docs: [IngestedDocument] = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/documents"
                )
                
                let graph: ConceptGraphResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/concepts"
                )
                
                await MainActor.run {
                    self.documents = docs.sorted(by: { $0.createdAt > $1.createdAt })
                    self.concepts = graph.concepts
                    self.prerequisites = graph.prerequisites
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not load documents: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startStatusPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.documents.contains(where: { $0.processingStatus == "pending" || $0.processingStatus == "processing" }) {
                self.fetchDocumentsAndGraph()
            }
        }
    }
    
    func deleteDocument(_ doc: IngestedDocument) {
        guard let appState = appState, let projectId = appState.selectedProjectID else { return }
        
        Task {
            do {
                let _: Data = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/documents/\(doc.id)",
                    method: "DELETE"
                )
                await MainActor.run {
                    self.documents.removeAll { $0.id == doc.id }
                    self.fetchDocumentsAndGraph()
                }
            } catch {
                await MainActor.run {
                    // Mock local deletion if offline
                    self.documents.removeAll { $0.id == doc.id }
                    self.concepts.removeAll { $0.sourceDocumentId == doc.id }
                }
            }
        }
    }
    
    func uploadFile(at url: URL) {
        guard let appState = appState, let projectId = appState.selectedProjectID else { return }
        guard !isUploading else { return }
        
        self.uploadFilename = url.lastPathComponent
        self.isUploading = true
        self.uploadProgress = 0.1
        
        Task {
            do {
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                
                let data = try Data(contentsOf: url)
                let mimeType = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "text/plain"
                
                self.uploadProgress = 0.4
                let newDoc: IngestedDocument = try await APIClient.shared.upload(
                    path: "/api/projects/\(projectId)/documents",
                    fileData: data,
                    filename: url.lastPathComponent,
                    mimeType: mimeType
                )
                
                await MainActor.run {
                    self.uploadProgress = 1.0
                    self.isUploading = false
                    withAnimation(.spring()) {
                        self.documents.insert(newDoc, at: 0)
                    }
                    self.fetchDocumentsAndGraph()
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func simulateUpload(filename: String, type: String) {
        guard let appState = appState, let projectId = appState.selectedProjectID else { return }
        guard !isUploading else { return }
        
        self.uploadFilename = filename
        self.isUploading = true
        self.uploadProgress = 0.1
        
        Task {
            do {
                let mockText = "This is simulated learning material containing core concepts on \(filename)."
                let mockData = mockText.data(using: .utf8)!
                let mimeType = type == "PDF" ? "application/pdf" : "text/plain"
                
                self.uploadProgress = 0.5
                let newDoc: IngestedDocument = try await APIClient.shared.upload(
                    path: "/api/projects/\(projectId)/documents",
                    fileData: mockData,
                    filename: filename,
                    mimeType: mimeType
                )
                
                await MainActor.run {
                    self.uploadProgress = 1.0
                    self.isUploading = false
                    withAnimation(.spring()) {
                        self.documents.insert(newDoc, at: 0)
                    }
                    self.fetchDocumentsAndGraph()
                }
            } catch {
                await MainActor.run {
                    // Fallback to local timer simulation if backend server is unreachable
                    self.uploadProgress = 0.5
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.uploadProgress = 1.0
                        self.isUploading = false
                        
                        let docId = UUID().uuidString
                        let newDoc = IngestedDocument(
                            id: docId,
                            projectId: projectId,
                            filename: filename,
                            mimeType: type == "PDF" ? "application/pdf" : "text/plain",
                            fileSizeBytes: 512000,
                            processingStatus: "completed",
                            chunkCount: 8,
                            createdAt: ISO8601DateFormatter().string(from: Date()),
                            meta: nil
                        )
                        withAnimation {
                            self.documents.insert(newDoc, at: 0)
                            
                            // Insert mock concepts
                            let c1Id = UUID().uuidString
                            let c2Id = UUID().uuidString
                            let c1 = ConceptNode(id: c1Id, projectId: projectId, name: "\(filename.replacingOccurrences(of: ".pdf", with: "").capitalized) Core", description: "Fundamental basics", bloomsLevel: "remember", sourceDocumentId: docId, sourcePage: 1)
                            let c2 = ConceptNode(id: c2Id, projectId: projectId, name: "\(filename.replacingOccurrences(of: ".pdf", with: "").capitalized) Advanced", description: "Applied constructs", bloomsLevel: "apply", sourceDocumentId: docId, sourcePage: 5)
                            self.concepts.append(contentsOf: [c1, c2])
                            self.prerequisites.append(ConceptEdge(conceptId: c2Id, prerequisiteId: c1Id, confidence: 0.9, relationship: "requires"))
                        }
                    }
                }
            }
        }
    }
    
    deinit {
        pollTimer?.invalidate()
    }
}

// MARK: - View Layout
struct IngestionView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = IngestionViewModel()
    @State private var showUploadSheet = false
    @State private var showFilePicker = false
    @State private var selectedTab = 0 // 0 = List, 1 = Node Graph Map, 2 = RAG Query
    
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    var body: some View {
        VStack(spacing: 0) {
            // Adaptive Tab Selector for mobile screen size classes
            if sizeClass == .compact {
                Picker("ViewMode", selection: $selectedTab) {
                    Text("Materials").tag(0)
                    Text("Concept Map").tag(1)
                    Text("Query").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(Color.black.opacity(0.2))
            }
            
            if sizeClass == .regular {
                // Split View Layout for iPad
                HStack(alignment: .top, spacing: Spacing.md) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            headerPanel
                            uploadStatusPanel
                            documentsListPanel
                        }
                        .padding()
                    }
                    .frame(maxWidth: 420)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Knowledge Dependency Map")
                            .font(.titleMedium)
                            .foregroundStyle(Color.brandLight)
                            .padding([.top, .leading])
                        
                        ConceptGraphVisualizer(concepts: viewModel.concepts, edges: viewModel.prerequisites, documents: viewModel.documents)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    }
                }
            } else {
                // Responsive Single Layout for iPhone
                if selectedTab == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            headerPanel
                            uploadStatusPanel
                            documentsListPanel
                        }
                        .padding()
                    }
                } else if selectedTab == 1 {
                    ConceptGraphVisualizer(concepts: viewModel.concepts, edges: viewModel.prerequisites, documents: viewModel.documents)
                        .background(Color.black.opacity(0.1))
                        .padding()
                } else {
                    RAGQueryView()
                }
            }
        }
        .onAppear {
            viewModel.setAppState(appState)
        }
        .sheet(isPresented: $showUploadSheet) {
            NavigationStack {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.brand)
                        .padding(.top, Spacing.xl)
                    
                    Text("Add Knowledge Material")
                        .font(.titleLarge)
                        .foregroundStyle(.primary)
                    
                    Text("Upload a PDF or TXT file. The system will automatically extract text, create semantic chunks, embed them in the vector database, and build a concept graph.")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    VStack(spacing: Spacing.md) {
                        BrandButton(title: "Select PDF Document", icon: "doc.richtext", style: .primary) {
                            showUploadSheet = false
                            showFilePicker = true
                        }
                        
                        BrandButton(title: "Select Text File", icon: "doc.plaintext", style: .secondary) {
                            showUploadSheet = false
                            showFilePicker = true
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showUploadSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.uploadFile(at: url)
                }
            case .failure(let error):
                viewModel.errorMessage = "File picker error: \(error.localizedDescription)"
            }
        }
        .errorBanner($viewModel.errorMessage)
    }
    
    // Core Layout Blocks
    private var headerPanel: some View {
        GlassView {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Knowledge Vault")
                        .font(.titleLarge)
                        .foregroundStyle(Color.brandLight)
                    Text("Upload course source materials. Documents are chunked and mapped into learning concepts automatically.")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                Button(action: { showUploadSheet = true }) {
                    Image(systemName: "plus")
                        .font(.titleMedium)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.brand)
                        .clipShape(Circle())
                }
            }
            .padding()
        }
    }
    
    private var uploadStatusPanel: some View {
        Group {
            if viewModel.isUploading {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Uploading \(viewModel.uploadFilename)...")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(viewModel.uploadProgress * 100))%")
                            .font(.codeSmall)
                            .foregroundStyle(Color.brand)
                    }
                    ProgressView(value: viewModel.uploadProgress)
                        .tint(Color.brand)
                }
                .padding()
                .background(Color.brand.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var documentsListPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let error = viewModel.errorMessage {
                StatusBanner(message: error, variant: .error) {
                    withAnimation { viewModel.errorMessage = nil }
                }
            }
            
            Text("Ingested Materials (\(viewModel.documents.count))")
                .font(.titleMedium)
                .foregroundStyle(.primary)
            
            LazyVStack(spacing: Spacing.md) {
                if viewModel.documents.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No documents ingested yet.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxl)
                } else {
                    ForEach(viewModel.documents) { doc in
                        IngestionDocRow(document: doc, onDelete: {
                            viewModel.deleteDocument(doc)
                        })
                    }
                }
            }
        }
    }
}

// MARK: - Row View
struct IngestionDocRow: View {
    let document: IngestedDocument
    let onDelete: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    var body: some View {
        GlassView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(typeColor(document.fileType))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(document.fileType)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(document.filename)
                            .font(.bodyLarge)
                            .bold()
                            .lineLimit(1)
                        
                        HStack(spacing: Spacing.sm) {
                            Text(document.fileSize)
                                .font(.codeSmall)
                                .foregroundStyle(.secondary)
                            if document.processingStatus == "completed" {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text("\(document.chunkCount) chunks")
                                    .font(.codeSmall)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            if document.processingStatus == "pending" || document.processingStatus == "processing" {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Indexing")
                                    .font(.caption2)
                                    .foregroundStyle(Color.warning)
                            } else if document.processingStatus == "completed" {
                                Circle()
                                    .fill(Color.success)
                                    .frame(width: 6, height: 6)
                                Text("Ready")
                                    .font(.caption2)
                                    .foregroundStyle(Color.success)
                            } else {
                                Circle()
                                    .fill(Color.error)
                                    .frame(width: 6, height: 6)
                                Text("Failed")
                                    .font(.caption2)
                                    .foregroundStyle(Color.error)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                        
                        if document.processingStatus != "pending" && document.processingStatus != "processing" {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(Color.error)
                            }
                        }
                    }
                }
                
                if document.processingStatus == "pending" || document.processingStatus == "processing" {
                    TelemetryProgressView(meta: document.meta, status: document.processingStatus)
                        .padding(.top, Spacing.xs)
                }
            }
            .padding()
        }
    }
    
    private func typeColor(_ ext: String) -> Color {
        switch ext.uppercased() {
        case "PDF": return Color.error
        case "TXT": return Color.info
        default: return Color.secondary
        }
    }
}

struct TelemetryProgressView: View {
    let meta: IngestedDocumentMeta?
    let status: String
    
    var body: some View {
        let progress = meta?.progress ?? (status == "pending" ? 0.05 : 0.15)
        let activeStage = meta?.stage ?? "parsing"
        
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(Color.brand)
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            
            HStack(spacing: 4) {
                TelemetryStep(name: "Parse", isActive: activeStage == "parsing" || progress >= 0.15, isComplete: progress > 0.15)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.3))
                Spacer()
                TelemetryStep(name: "Chunk", isActive: activeStage == "chunking" || progress >= 0.4, isComplete: progress > 0.4)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.3))
                Spacer()
                TelemetryStep(name: "Vector", isActive: activeStage == "indexing" || progress >= 0.65, isComplete: progress > 0.65)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.3))
                Spacer()
                TelemetryStep(name: "Graph", isActive: activeStage == "extracting" || progress >= 0.85, isComplete: progress >= 1.0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 2)
    }
}

struct TelemetryStep: View {
    let name: String
    let isActive: Bool
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isComplete ? Color.success : (isActive ? Color.brandLight : Color.secondary.opacity(0.2)))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10, weight: (isActive || isComplete) ? .semibold : .regular))
                .foregroundStyle((isActive || isComplete) ? .primary : .secondary)
        }
    }
}

// MARK: - Document-Grouped Concept Graph Renderer (Cytoscape-based)
struct ConceptGraphVisualizer: View {
    let concepts: [ConceptNode]
    let edges: [ConceptEdge]
    let documents: [IngestedDocument]
    
    @State private var selectedConcept: ConceptNode? = nil
    @State private var isFullScreen = false
    @State private var selectedBloomFilter: String? = nil // nil means all
    @State private var selectedDocFilter: String? = nil   // nil means all
    
    private func getDocumentName(for docId: String?) -> String {
        guard let docId = docId else { return "Project Vocabulary" }
        if let doc = documents.first(where: { $0.id == docId }) {
            return doc.filename
        }
        return "Source: \(docId.prefix(8))..."
    }
    
    private var cytoscapeElementsJSON: String {
        // Filter concepts
        let filteredConcepts = concepts.filter { concept in
            let matchesBloom = selectedBloomFilter == nil || concept.bloomsLevel?.lowercased() == selectedBloomFilter
            let matchesDoc = selectedDocFilter == nil || concept.sourceDocumentId == selectedDocFilter
            return matchesBloom && matchesDoc
        }
        
        let filteredConceptIds = Set(filteredConcepts.map { $0.id })
        
        // Filter edges
        let filteredEdges = edges.filter { edge in
            filteredConceptIds.contains(edge.conceptId) && filteredConceptIds.contains(edge.prerequisiteId)
        }
        
        struct ElementData: Codable {
            let id: String
            var label: String? = nil
            var parent: String? = nil
            var color: String? = nil
            var source: String? = nil
            var target: String? = nil
        }
        struct Element: Codable {
            let data: ElementData
        }
        
        var elements: [Element] = []
        
        // 1. Add parents for grouped documents
        let grouped = Dictionary(grouping: filteredConcepts, by: { $0.sourceDocumentId ?? "unknown" })
        for (docId, _) in grouped {
            let docName = getDocumentName(for: docId == "unknown" ? nil : docId)
            let parentId = "doc_" + docId.replacingOccurrences(of: "-", with: "_")
            elements.append(Element(data: ElementData(id: parentId, label: docName)))
        }
        
        // 2. Add child concept nodes
        for concept in filteredConcepts {
            let nodeId = "n_" + concept.id.replacingOccurrences(of: "-", with: "_")
            let docId = concept.sourceDocumentId ?? "unknown"
            let parentId = "doc_" + docId.replacingOccurrences(of: "-", with: "_")
            let blooms = (concept.bloomsLevel ?? "understand").uppercased()
            let label = "\(concept.name)\n(\(blooms))"
            
            let color = bloomColorHex(concept.bloomsLevel ?? "understand")
            
            elements.append(Element(data: ElementData(id: nodeId, label: label, parent: parentId, color: color)))
        }
        
        // 3. Add edges representing dependency relationships
        for edge in filteredEdges {
            let edgeId = "e_" + edge.prerequisiteId.replacingOccurrences(of: "-", with: "_") + "_" + edge.conceptId.replacingOccurrences(of: "-", with: "_")
            let sourceId = "n_" + edge.prerequisiteId.replacingOccurrences(of: "-", with: "_")
            let targetId = "n_" + edge.conceptId.replacingOccurrences(of: "-", with: "_")
            elements.append(Element(data: ElementData(id: edgeId, source: sourceId, target: targetId)))
        }
        
        if let data = try? JSONEncoder().encode(elements),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "[]"
    }
    
    private func bloomColorHex(_ level: String) -> String {
        switch level.lowercased() {
        case "remember": return "#2563eb"   // Blue
        case "understand": return "#16a34a" // Green
        case "apply": return "#0d9488"      // Teal
        case "analyze": return "#ea580c"    // Orange
        case "evaluate": return "#dc2626"   // Red
        case "create": return "#9333ea"     // Purple
        default: return "#4b5563"
        }
    }
    
    var body: some View {
        if concepts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "circle.dotted.and.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No Concepts Found")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Ingest materials first to build the concept graph.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Spacing.sm) {
                // Horizontal Filters Chips scroll view
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        // Document filter dropdown menu
                        Menu {
                            Button("All Documents", action: { selectedDocFilter = nil })
                            ForEach(documents) { doc in
                                Button(doc.filename, action: { selectedDocFilter = doc.id })
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text(selectedDocFilter == nil ? "All Documents" : (documents.first(where: { $0.id == selectedDocFilter })?.filename ?? "Selected Doc"))
                                Image(systemName: "chevron.down")
                            }
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(selectedDocFilter == nil ? 0.05 : 0.15))
                            .foregroundStyle(selectedDocFilter == nil ? .secondary : Color.brandLight)
                            .clipShape(Capsule())
                        }
                        
                        Divider()
                            .frame(height: 16)
                            .background(Color.white.opacity(0.1))
                        
                        FilterChip(name: "All Bloom", isSelected: selectedBloomFilter == nil) {
                            selectedBloomFilter = nil
                        }
                        
                        ForEach(["remember", "understand", "apply", "analyze", "evaluate", "create"], id: \.self) { level in
                            FilterChip(name: level.capitalized, isSelected: selectedBloomFilter == level) {
                                selectedBloomFilter = level
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 32)
                
                ZStack(alignment: .topTrailing) {
                    CytoscapeWebView(elementsJSON: cytoscapeElementsJSON) { nodeId in
                        let cleanId = nodeId.replacingOccurrences(of: "n_", with: "").replacingOccurrences(of: "_", with: "-")
                        if let matched = concepts.first(where: { $0.id == cleanId }) {
                            selectedConcept = matched
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    
                    Button(action: {
                        isFullScreen = true
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .padding(10)
                            .background(Color.black.opacity(0.65))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                            .padding(12)
                    }
                }
            }
            .sheet(item: $selectedConcept) { concept in
                ConceptDetailSheet(concept: concept, documents: documents)
            }
            .fullScreenCover(isPresented: $isFullScreen) {
                FullscreenVisualizerView(elementsJSON: cytoscapeElementsJSON, concepts: concepts, documents: documents)
            }
        }
    }
}

struct FilterChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .bold()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.brand : Color.white.opacity(0.04))
                .foregroundStyle(isSelected ? .white : .secondary)
                .clipShape(Capsule())
        }
    }
}

struct FullscreenVisualizerView: View {
    let elementsJSON: String
    let concepts: [ConceptNode]
    let documents: [IngestedDocument]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedConcept: ConceptNode? = nil
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            CytoscapeWebView(elementsJSON: elementsJSON) { nodeId in
                let cleanId = nodeId.replacingOccurrences(of: "n_", with: "").replacingOccurrences(of: "_", with: "-")
                if let matched = concepts.first(where: { $0.id == cleanId }) {
                    selectedConcept = matched
                }
            }
            .ignoresSafeArea()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .padding(12)
                    .background(Color.white.opacity(0.15))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .padding(20)
            }
        }
        .sheet(item: $selectedConcept) { concept in
            ConceptDetailSheet(concept: concept, documents: documents)
        }
    }
}

// MARK: - WebKit Wrapper for rendering Cytoscape JS
struct CytoscapeWebView: UIViewRepresentable {
    let elementsJSON: String
    let onNodeTap: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: CytoscapeWebView
        
        init(_ parent: CytoscapeWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "nodeClicked", let body = message.body as? String {
                parent.onNodeTap(body)
            }
        }
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "nodeClicked")
        configuration.userContentController = controller
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.backgroundColor = .clear
        webView.isOpaque = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
            <style>
                body {
                    background-color: #0b0f19;
                    color: #f3f4f6;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, sans-serif;
                    margin: 0;
                    padding: 0;
                    width: 100vw;
                    height: 100vh;
                    overflow: hidden;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    box-sizing: border-box;
                }
                #cy {
                    width: 100%;
                    height: 100%;
                    position: absolute;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                }
            </style>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.26.0/cytoscape.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/layout-base/layout-base.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/cose-base/cose-base.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/cytoscape-fcose/cytoscape-fcose.js"></script>
        </head>
        <body>
            <div id="cy"></div>
            <script>
                var elements = \(elementsJSON);
                
                var cy = cytoscape({
                    container: document.getElementById('cy'),
                    elements: elements,
                    boxSelectionEnabled: false,
                    autounselectify: true,
                    style: [
                        {
                            selector: 'node',
                            style: {
                                'content': 'data(label)',
                                'text-valign': 'center',
                                'text-halign': 'center',
                                'background-color': 'data(color)',
                                'color': '#ffffff',
                                'font-size': '10px',
                                'font-weight': 'bold',
                                'width': '100px',
                                'height': '40px',
                                'shape': 'round-rectangle',
                                'text-wrap': 'wrap',
                                'text-max-width': '90px',
                                'border-width': '1.5px',
                                'border-color': 'data(color)'
                            }
                        },
                        {
                            selector: '$node > node',
                            style: {
                                'label': 'data(label)',
                                'text-valign': 'top',
                                'text-halign': 'center',
                                'background-color': '#1f2937',
                                'background-opacity': 0.35,
                                'border-width': '1.5px',
                                'border-color': '#4b5563',
                                'border-style': 'dashed',
                                'color': '#60a5fa',
                                'font-size': '11px',
                                'font-weight': 'bold',
                                'padding': '15px'
                            }
                        },
                        {
                            selector: 'edge',
                            style: {
                                'width': 2,
                                'line-color': '#60a5fa',
                                'target-arrow-color': '#60a5fa',
                                'target-arrow-shape': 'triangle',
                                'curve-style': 'bezier'
                            }
                        }
                    ],
                    layout: {
                        name: 'fcose',
                        quality: 'proof',
                        nodeRepulsion: 5500,
                        idealEdgeLength: 60,
                        gravity: 0.35,
                        tile: true
                    }
                });
                
                cy.on('tap', 'node', function(evt){
                    var node = evt.target;
                    if (!node.isParent() && window.webkit && window.webkit.messageHandlers.nodeClicked) {
                        window.webkit.messageHandlers.nodeClicked.postMessage(node.id());
                    }
                });
            </script>
        </body>
        </html>
        """
        uiView.loadHTMLString(htmlContent, baseURL: URL(string: "https://localhost"))
    }
}

// MARK: - Concept Details RAG Request Helper
struct ConceptRAGRequest: Encodable {
    let question: String
    let topK: Int
    let generateAnswer: Bool
}

// MARK: - Concept Details sheet
struct ConceptDetailSheet: View {
    let concept: ConceptNode
    let documents: [IngestedDocument]
    
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var sourceChunks: [RAGChunk] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Header Card
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text(concept.name)
                                .font(.titleLarge)
                                .bold()
                                .foregroundStyle(.primary)
                            Spacer()
                            if let bloom = concept.bloomsLevel {
                                Text(bloom.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(bloomColor(bloom).gradient)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        // Source document filename attribution
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.caption)
                                .foregroundStyle(Color.brandLight)
                            Text("Source: \(sourceDocName)")
                                .font(.bodySmall.weight(.semibold))
                                .foregroundStyle(Color.brandLight)
                            
                            if let page = concept.sourcePage {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text("Page \(page)")
                                    .font(.bodySmall)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    
                    // Concept explanation
                    if let desc = concept.description, !desc.trimmingCharacters(in: .whitespaces).isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Explanation")
                                .font(.bodyMedium.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(desc)
                                .font(.bodyMedium)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 4)
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Grounded Citations List
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Grounded Source Citations")
                            .font(.bodyLarge.weight(.bold))
                            .foregroundStyle(Color.brandLight)
                        
                        if isLoading {
                            HStack {
                                Spacer()
                                VStack(spacing: Spacing.sm) {
                                    ProgressView()
                                    Text("Retrieving matching text blocks...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.xl)
                        } else if let error = loadError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Color.error)
                        } else if sourceChunks.isEmpty {
                            Text("No source references found.")
                                .font(.bodyMedium)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sourceChunks) { chunk in
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    HStack {
                                        Text("\(chunk.filename) (Page \(chunk.page ?? 1))")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.brandLight)
                                        Spacer()
                                        Text("Relevance: \(Int(chunk.score * 100))%")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text(chunk.content)
                                        .font(.bodySmall)
                                        .foregroundStyle(.primary.opacity(0.9))
                                        .padding()
                                        .background(Color.white.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Concept Source Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadSourceChunks()
            }
        }
    }
    
    private var sourceDocName: String {
        if let docId = concept.sourceDocumentId,
           let doc = documents.first(where: { $0.id == docId }) {
            return doc.filename
        }
        return "Project Vocabulary"
    }
    
    private func bloomColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "remember": return .blue
        case "understand": return .green
        case "apply": return .cyan
        case "analyze": return .orange
        case "evaluate": return .red
        case "create": return .purple
        default: return .secondary
        }
    }
    
    private func loadSourceChunks() async {
        guard let projectId = appState.selectedProjectID else { return }
        isLoading = true
        loadError = nil
        
        do {
            let requestBody = ConceptRAGRequest(question: concept.name, topK: 3, generateAnswer: false)
            let bodyData = try? JSONEncoder().encode(requestBody)
            let res: RAGQueryResponse = try await APIClient.shared.request(
                path: "/api/projects/\(projectId)/query",
                method: "POST",
                body: bodyData
            )
            await MainActor.run {
                self.sourceChunks = res.chunks
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Failed to load citation references: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

