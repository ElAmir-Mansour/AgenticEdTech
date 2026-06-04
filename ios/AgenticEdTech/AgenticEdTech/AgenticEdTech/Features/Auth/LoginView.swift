import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var serverURL = "http://localhost:8080"
    
    // Separate loading states to fix button loader conflict
    @State private var isStandardLoading = false
    @State private var isAppleLoading = false
    
    @State private var isSignUp = false
    @State private var showServerConfig = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showSimulatorFallback = false
    @State private var fallbackName = ""
    @State private var fallbackEmail = ""
    
    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Agentic EdTech")
                    .font(.displayLarge)
                    .foregroundStyle(Color.brand)
                Text("Curriculum Design R&D Platform")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: Spacing.md) {
                if isSignUp {
                    BrandTextField(placeholder: "Display Name", text: $displayName, icon: "person")
                }
                
                BrandTextField(placeholder: "Email", text: $email, icon: "envelope")
                BrandTextField(placeholder: "Password", text: $password, isSecure: true, icon: "lock")
                
                BrandButton(title: isSignUp ? "Create Account" : "Sign In", icon: isSignUp ? "person.badge.plus" : "arrow.right.circle.fill", isLoading: isStandardLoading) {
                    performLogin()
                }
                .disabled(email.isEmpty || password.isEmpty || (isSignUp && displayName.isEmpty) || isAppleLoading)
                
                // Real Sign in with Apple button
                SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: handleAppleResult)
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        Group {
                            if isAppleLoading {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(ProgressView().tint(.white))
                            }
                        }
                    )
                    .disabled(isStandardLoading || isAppleLoading)
                
                Button(action: {
                    withAnimation {
                        isSignUp.toggle()
                        displayName = ""
                    }
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.bodySmall)
                        .foregroundStyle(Color.brandLight)
                }
                
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, Spacing.xs)
                
                Button(action: bypassLogin) {
                    Text("Bypass / Guest Mode (Offline)")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
                
                // Expandable Server Config
                VStack(spacing: Spacing.sm) {
                    Button(action: {
                        withAnimation {
                            showServerConfig.toggle()
                        }
                    }) {
                        HStack {
                            Text("Server Settings")
                            Image(systemName: showServerConfig ? "chevron.up" : "chevron.down")
                        }
                        .font(.codeSmall)
                        .foregroundStyle(.secondary)
                    }
                    
                    if showServerConfig {
                        BrandTextField(placeholder: "Server URL", text: $serverURL, icon: "network")
                            .frame(maxWidth: 280)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: 320)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color.brandDark.opacity(0.3), .black], center: .center, startRadius: 100, endRadius: 600)
        )
        .alert("Authentication Status", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showSimulatorFallback) {
            simulatorFallbackSheet
        }
    }
    
    // MARK: - Simulator Apple Sign In Fallback
    
    private var simulatorFallbackSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.yellow)
                        
                        Text("Sign in with Apple Unavailable")
                            .font(.titleMedium)
                        
                        Text("Apple Sign In requires a real device or proper entitlements. Enter your details below to sign in directly.")
                            .font(.bodySmall)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: Spacing.md) {
                        BrandTextField(placeholder: "Your Name", text: $fallbackName, icon: "person")
                        BrandTextField(placeholder: "Your Email", text: $fallbackEmail, icon: "envelope")
                    }
                    .frame(maxWidth: 300)
                    
                    BrandButton(title: "Continue", isLoading: isAppleLoading) {
                        performFallbackAppleLogin()
                    }
                    .frame(maxWidth: 300)
                    .disabled(fallbackName.isEmpty || fallbackEmail.isEmpty)
                    
                    Button("Cancel") {
                        showSimulatorFallback = false
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func performFallbackAppleLogin() {
        let stableId = "manual_\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
        showSimulatorFallback = false
        
        sendAppleCredentialsToBackend(
            appleId: stableId,
            email: fallbackEmail.trimmingCharacters(in: .whitespaces),
            displayName: fallbackName.trimmingCharacters(in: .whitespaces),
            identityToken: nil,
            authorizationCode: nil
        )
    }
    
    // MARK: - Standard Email/Password Login
    
    private func performLogin() {
        guard let url = sanitizedServerURL() else {
            alertMessage = "Invalid Server URL. Please check the address in Server Settings (e.g. http://192.168.1.5:8080)."
            showAlert = true
            return
        }
        APIClient.shared.baseURL = url
        
        isStandardLoading = true
        
        Task {
            do {
                if isSignUp {
                    let registerPayload = RegisterRequestPayload(email: email, displayName: displayName, password: password)
                    let encoder = JSONEncoder()
                    let bodyData = try encoder.encode(registerPayload)
                    
                    let _: UserResponseStub = try await APIClient.shared.request(
                        path: "/api/auth/register",
                        method: "POST",
                        body: bodyData
                    )
                }
                
                let loginPayload = LoginRequestPayload(email: email, password: password)
                let encoder = JSONEncoder()
                let bodyData = try encoder.encode(loginPayload)
                
                let tokenRes: TokenResponse = try await APIClient.shared.request(
                    path: "/api/auth/login",
                    method: "POST",
                    body: bodyData
                )
                
                await MainActor.run {
                    completeAuthentication(
                        token: tokenRes.accessToken,
                        email: email,
                        name: isSignUp ? displayName : "Authenticated User"
                    )
                    isStandardLoading = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                    isStandardLoading = false
                }
            }
        }
    }
    
    // MARK: - Sign in with Apple
    
    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }
    
    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                alertMessage = "Unexpected credential type received from Apple."
                showAlert = true
                return
            }
            
            // Extract real Apple credentials
            let userIdentifier = appleIDCredential.user
            let appleEmail = appleIDCredential.email ?? "\(userIdentifier.prefix(8))@privaterelay.appleid.com"
            
            var fullName = "Apple User"
            if let nameComponents = appleIDCredential.fullName {
                let given = nameComponents.givenName ?? ""
                let family = nameComponents.familyName ?? ""
                let composed = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
                if !composed.isEmpty {
                    fullName = composed
                }
            }
            
            // Get the identity token for backend verification
            var identityTokenString: String? = nil
            if let identityToken = appleIDCredential.identityToken,
               let tokenStr = String(data: identityToken, encoding: .utf8) {
                identityTokenString = tokenStr
            }
            
            // Get the authorization code
            var authCodeString: String? = nil
            if let authorizationCode = appleIDCredential.authorizationCode,
               let codeStr = String(data: authorizationCode, encoding: .utf8) {
                authCodeString = codeStr
            }
            
            // Send credentials to backend
            sendAppleCredentialsToBackend(
                appleId: userIdentifier,
                email: appleEmail,
                displayName: fullName,
                identityToken: identityTokenString,
                authorizationCode: authCodeString
            )
            
        case .failure(let error):
            let nsError = error as NSError
            
            // ASAuthorizationError.canceled (1001) — user dismissed the sheet
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            
            // ASAuthorizationError.unknown (1000) — simulator or missing entitlement
            // Show a dialog explaining the issue and offer manual sign-in
            if nsError.domain == ASAuthorizationError.errorDomain && nsError.code == ASAuthorizationError.unknown.rawValue {
                showSimulatorFallback = true
                return
            }
            
            // Any other error
            alertMessage = "Sign in with Apple failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func sendAppleCredentialsToBackend(
        appleId: String,
        email: String,
        displayName: String,
        identityToken: String?,
        authorizationCode: String?
    ) {
        guard let url = sanitizedServerURL() else {
            alertMessage = "Invalid Server URL. Please check the address in Server Settings."
            showAlert = true
            return
        }
        APIClient.shared.baseURL = url
        isAppleLoading = true
        
        Task {
            do {
                let applePayload = AppleLoginPayload(
                    email: email,
                    displayName: displayName,
                    appleId: appleId,
                    identityToken: identityToken,
                    authorizationCode: authorizationCode
                )
                let encoder = JSONEncoder()
                let bodyData = try encoder.encode(applePayload)
                
                let tokenRes: TokenResponse = try await APIClient.shared.request(
                    path: "/api/auth/apple",
                    method: "POST",
                    body: bodyData
                )
                
                await MainActor.run {
                    completeAuthentication(
                        token: tokenRes.accessToken,
                        email: email,
                        name: displayName
                    )
                    isAppleLoading = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Apple Sign In failed: \(error.localizedDescription)"
                    showAlert = true
                    isAppleLoading = false
                }
            }
        }
    }
    
    // MARK: - Shared Auth Completion
    
    private func completeAuthentication(token: String, email: String, name: String) {
        appState.authToken = token
        appState.currentUserEmail = email
        appState.currentUserName = name
        appState.isAuthenticated = true
        APIClient.shared.token = token
        WebSocketManager.shared.connect(token: token)
        
        // Critical: Fetch or create a project so selectedProjectID is set
        appState.fetchOrCreateDefaultProject()
    }
    
    // MARK: - Guest Bypass
    
    private func bypassLogin() {
        appState.authToken = "mock_bypass_token_123"
        appState.currentUserEmail = "guest@youredtech.me"
        appState.currentUserName = "Guest Designer"
        appState.isAuthenticated = true
        appState.isWebSocketConnected = false
        appState.selectedProjectID = "offline-mock"
        appState.selectedProjectTitle = "Offline Project"
    }
    
    // MARK: - URL Sanitizer
    
    /// Trims whitespace, auto-prepends http:// if missing, and validates the URL.
    private func sanitizedServerURL() -> URL? {
        var cleaned = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Auto-prepend http:// if the user typed just an IP or hostname
        if !cleaned.lowercased().hasPrefix("http://") && !cleaned.lowercased().hasPrefix("https://") {
            cleaned = "http://" + cleaned
        }
        
        // Remove trailing slash for consistency
        while cleaned.hasSuffix("/") {
            cleaned = String(cleaned.dropLast())
        }
        
        return URL(string: cleaned)
    }
}

// MARK: - API Payloads
private struct LoginRequestPayload: Codable {
    let email: String
    let password: String
}

private struct RegisterRequestPayload: Codable {
    let email: String
    let displayName: String
    let password: String
    
    enum CodingKeys: String, CodingKey {
        case email
        case displayName = "display_name"
        case password
    }
}

private struct AppleLoginPayload: Codable {
    let email: String
    let displayName: String
    let appleId: String
    let identityToken: String?
    let authorizationCode: String?
    
    enum CodingKeys: String, CodingKey {
        case email
        case displayName = "display_name"
        case appleId = "apple_id"
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
}

private struct UserResponseStub: Codable {
    let email: String
    let displayName: String
    
    enum CodingKeys: String, CodingKey {
        case email
        case displayName = "display_name"
    }
}
