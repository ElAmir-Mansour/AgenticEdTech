import SwiftUI
import Observation

@Observable
class AppState {
    var isAuthenticated: Bool = false
    var authToken: String? = nil
    var currentUserEmail: String? = nil
    var currentUserName: String? = nil
    
    var activeWorkspace: WorkspaceType = .dashboard
    var selectedProjectID: String? = nil
    var selectedProjectTitle: String? = nil
    var availableProjects: [ProjectListItem] = []
    var isWebSocketConnected: Bool = false
    
    enum WorkspaceType: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case ingestion = "Ingestion Vault"
        case canvas = "Agentic Canvas"
        case simulation = "Simulation Sandbox"
        case diagnostics = "Diagnostics & Tests"
        
        var id: String { self.rawValue }
    }
    
    /// After login, fetch all projects. If none exist, create a default one.
    func fetchOrCreateDefaultProject() {
        Task {
            do {
                let projects: [ProjectListItem] = try await APIClient.shared.request(path: "/api/projects/")
                
                if let first = projects.first {
                    await MainActor.run {
                        self.availableProjects = projects
                        self.selectedProjectID = first.id
                        self.selectedProjectTitle = first.title
                    }
                } else {
                    let body = try JSONEncoder().encode(CreateProjectPayload(
                        title: "My Curriculum",
                        description: "Default project created automatically"
                    ))
                    let created: ProjectListItem = try await APIClient.shared.request(
                        path: "/api/projects/",
                        method: "POST",
                        body: body
                    )
                    await MainActor.run {
                        self.availableProjects = [created]
                        self.selectedProjectID = created.id
                        self.selectedProjectTitle = created.title
                    }
                }
            } catch {
                await MainActor.run {
                    self.selectedProjectID = "offline-mock"
                    self.selectedProjectTitle = "Offline Project"
                }
            }
        }
    }
    
    var selectedProject: ProjectListItem? {
        availableProjects.first { $0.id == selectedProjectID }
    }
    
    func switchProject(to project: ProjectListItem) {
        selectedProjectID = project.id
        selectedProjectTitle = project.title
    }
    
    func createProject(title: String, description: String) {
        Task {
            do {
                let body = try JSONEncoder().encode(CreateProjectPayload(
                    title: title,
                    description: description
                ))
                let created: ProjectListItem = try await APIClient.shared.request(
                    path: "/api/projects/",
                    method: "POST",
                    body: body
                )
                await MainActor.run {
                    self.availableProjects.append(created)
                    self.selectedProjectID = created.id
                    self.selectedProjectTitle = created.title
                }
            } catch {
                // Silently fail — project creation is non-critical
            }
        }
    }
    
    func updateProjectSettings(settings: [String: AnyCodable]) async throws {
        guard let projectId = selectedProjectID else { return }
        guard let index = availableProjects.firstIndex(where: { $0.id == projectId }) else { return }
        
        struct UpdateProjectPayload: Codable {
            let settings: [String: AnyCodable]
        }
        
        let body = try JSONEncoder().encode(UpdateProjectPayload(settings: settings))
        let updated: ProjectListItem = try await APIClient.shared.request(
            path: "/api/projects/\(projectId)",
            method: "PUT",
            body: body
        )
        
        await MainActor.run {
            self.availableProjects[index] = updated
        }
    }
    
    func logout() {
        isAuthenticated = false
        authToken = nil
        currentUserEmail = nil
        currentUserName = nil
        selectedProjectID = nil
        selectedProjectTitle = nil
        APIClient.shared.token = nil
        WebSocketManager.shared.disconnect()
    }
}

// Models for project fetching
struct ProjectListItem: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let settings: [String: AnyCodable]?
}

struct CreateProjectPayload: Codable {
    let title: String
    let description: String
}

struct QuizQuestionResponse: Codable, Identifiable {
    let id: String
    let moduleId: String
    let questionText: String
    let questionType: String
    let options: [String]?
    let correctAnswer: String
    let bloomsLevel: String?
    let difficulty: Double?
    let explanation: String?
    let sequenceOrder: Int
    var sourceInfo: String? = nil
}

struct CurriculumModuleResponse: Codable, Identifiable {
    let id: String
    let projectId: String
    let sessionId: String?
    let title: String
    let content: String
    let bloomsLevel: String?
    let sequenceOrder: Int
    let heatmapData: [String: AnyCodable]?
    let parentModuleId: String?
    let version: Int
    let quizQuestions: [QuizQuestionResponse]
}

