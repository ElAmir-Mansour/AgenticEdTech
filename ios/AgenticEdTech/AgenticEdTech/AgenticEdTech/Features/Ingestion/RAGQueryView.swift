import SwiftUI

// MARK: - RAG Query Response Models

struct RAGQueryResponse: Codable {
    let question: String
    let answer: String?
    let chunks: [RAGChunk]
    let error: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decode(String.self, forKey: .question)
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        chunks = try container.decodeIfPresent([RAGChunk].self, forKey: .chunks) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct RAGChunk: Codable, Identifiable {
    var id: String { "\(documentId)-\(chunkIndex ?? 0)-\(score)" }
    let content: String
    let documentId: String
    let filename: String
    let page: Int?
    let chunkIndex: Int?
    let score: Double
}

// MARK: - ViewModel

@Observable
class RAGQueryViewModel {
    var appState: AppState? = nil
    var question = ""
    var isSearching = false
    var response: RAGQueryResponse? = nil
    var errorMessage: String? = nil
    var queryHistory: [RAGQueryResponse] = []
    
    func setAppState(_ state: AppState) {
        self.appState = state
    }
    
    func search() {
        guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let projectId = appState?.selectedProjectID else {
            errorMessage = "No project selected. Create or select a project first."
            return
        }
        
        let queryText = question
        isSearching = true
        errorMessage = nil
        
        Task {
            do {
                let payload: [String: Any] = [
                    "question": queryText,
                    "topK": 5,
                    "generateAnswer": true
                ]
                let encoder = JSONEncoder()
                let bodyData = try encoder.encode(AnyCodableDict(payload))
                
                let result: RAGQueryResponse = try await APIClient.shared.request(
                    path: "/api/projects/\(projectId)/query",
                    method: "POST",
                    body: bodyData
                )
                
                await MainActor.run {
                    self.response = result
                    self.queryHistory.insert(result, at: 0)
                    self.isSearching = false
                    self.question = ""
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not reach backend: \(error.localizedDescription)"
                    self.isSearching = false
                }
            }
        }
    }
}

// Helper for encoding dict to JSON
private struct AnyCodableDict: Encodable {
    let dict: [String: Any]
    
    init(_ dict: [String: Any]) {
        self.dict = dict
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in dict {
            let codingKey = DynamicKey(stringValue: key)!
            if let s = value as? String {
                try container.encode(s, forKey: codingKey)
            } else if let i = value as? Int {
                try container.encode(i, forKey: codingKey)
            } else if let b = value as? Bool {
                try container.encode(b, forKey: codingKey)
            } else if let d = value as? Double {
                try container.encode(d, forKey: codingKey)
            }
        }
    }
    
    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
}

// Mock fallback
extension RAGQueryResponse {
    static func mockOffline(question: String) -> RAGQueryResponse {
        return RAGQueryResponse.mock(
            question: question,
            answer: "Based on the uploaded documents, this concept relates to iterative development practices where teams work in short cycles (sprints) to deliver incremental value. The framework emphasizes transparency, inspection, and adaptation.\n\n*Source: Agile Textbook, Page 12*",
            chunks: [
                RAGChunk(content: "Agile methodologies emphasize iterative development, where requirements and solutions evolve through collaboration between self-organizing cross-functional teams.", documentId: "mock-1", filename: "agile_textbook.pdf", page: 12, chunkIndex: 3, score: 0.8921),
                RAGChunk(content: "Scrum is a framework within which people can address complex adaptive problems, while productively and creatively delivering products of the highest possible value.", documentId: "mock-1", filename: "agile_textbook.pdf", page: 15, chunkIndex: 7, score: 0.8234),
                RAGChunk(content: "Sprint planning is a time-boxed event that initiates each Sprint. The purpose is to determine what can be delivered in the increment.", documentId: "mock-2", filename: "scrum_guide.pdf", page: 8, chunkIndex: 2, score: 0.7891),
            ]
        )
    }
    
    private static func mock(question: String, answer: String, chunks: [RAGChunk]) -> RAGQueryResponse {
        let json: [String: Any] = [
            "question": question,
            "answer": answer,
            "chunks": chunks.map { c in
                [
                    "content": c.content,
                    "documentId": c.documentId,
                    "filename": c.filename,
                    "page": c.page ?? 0,
                    "chunkIndex": c.chunkIndex ?? 0,
                    "score": c.score
                ] as [String : Any]
            }
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(RAGQueryResponse.self, from: data)
    }
}

// MARK: - RAG Query View

struct RAGQueryView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = RAGQueryViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Results Area
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Header
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Knowledge Query")
                            .font(.titleLarge)
                            .foregroundStyle(Color.brandLight)
                        Text("Ask questions about your uploaded documents. Answers are grounded only in your source material.")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, Spacing.sm)
                    
                    // Error banner
                    if let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(error)
                                .font(.codeSmall)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Current Response
                    if viewModel.isSearching {
                        searchingIndicator
                    } else if let response = viewModel.response {
                        responseView(response)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            
            // Search Input Bar
            searchBar
        }
        .background(Color.black.opacity(0.02))
        .onAppear {
            viewModel.setAppState(appState)
        }
        .errorBanner($viewModel.errorMessage)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Ask about your documents...", text: $viewModel.question)
                    .font(.bodyMedium)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.search()
                    }
                
                if !viewModel.question.isEmpty {
                    Button(action: { viewModel.question = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button(action: { viewModel.search() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.question.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.secondary
                            : Color.brand
                    )
            }
            .disabled(viewModel.question.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Searching Indicator
    
    private var searchingIndicator: some View {
        GlassView {
            HStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(Color.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Searching knowledge base...")
                        .font(.bodyMedium)
                        .foregroundStyle(.primary)
                    Text("Querying vector embeddings and generating grounded answer")
                        .font(.codeSmall)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("Ask a Question")
                .font(.titleMedium)
                .foregroundStyle(.secondary)
            
            Text("Type a question below to search your uploaded documents. Answers will be sourced exclusively from your knowledge base.")
                .font(.bodySmall)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            // Suggestion chips
            VStack(spacing: Spacing.sm) {
                Text("Try asking:")
                    .font(.codeSmall)
                    .foregroundStyle(.tertiary)
                
                ForEach(["What are the key concepts?", "Explain the main methodology", "What prerequisites are needed?"], id: \.self) { suggestion in
                    Button(action: {
                        viewModel.question = suggestion
                        viewModel.search()
                    }) {
                        Text(suggestion)
                            .font(.bodySmall)
                            .foregroundStyle(Color.brandLight)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.brand.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Response View
    
    private func responseView(_ response: RAGQueryResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Question echo
            HStack(alignment: .top) {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(Color.brand)
                    .font(.title3)
                Text(response.question)
                    .font(.bodyMedium)
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brand.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // AI Answer
            if let answer = response.answer {
                GlassView {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.brand)
                            Text("Grounded Answer")
                                .font(.bodyMedium)
                                .bold()
                                .foregroundStyle(Color.brandLight)
                        }
                        
                        Text(answer)
                            .font(.bodySmall)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            }
            
            // Source Chunks
            if !response.chunks.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Sources (\(response.chunks.count) relevant chunks)")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                    
                    ForEach(response.chunks) { chunk in
                        sourceChunkCard(chunk)
                    }
                }
            }
        }
    }
    
    // MARK: - Source Chunk Card
    
    private func sourceChunkCard(_ chunk: RAGChunk) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(chunk.filename)
                    .font(.codeSmall)
                    .bold()
                    .foregroundStyle(.primary)
                
                if let page = chunk.page {
                    Text("• Page \(page)")
                        .font(.codeSmall)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Relevance score badge
                Text("\(Int(chunk.score * 100))%")
                    .font(.codeSmall)
                    .bold()
                    .foregroundStyle(chunk.score > 0.8 ? Color.success : Color.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (chunk.score > 0.8 ? Color.success : Color.warning).opacity(0.15)
                    )
                    .clipShape(Capsule())
            }
            
            Text(chunk.content)
                .font(.codeSmall)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
