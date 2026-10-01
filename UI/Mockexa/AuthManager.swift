import Foundation
import Combine
import Security
import AuthenticationServices
import CryptoKit

/// AuthSession represents an active user session
struct AuthSession: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let userId: String
    let email: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case user
        case userId = "user_id"
        case email
        case createdAt = "created_at"
    }
    
    struct User: Codable {
        let id: String
        let email: String?
    }
    
    var isExpired: Bool {
        // Evaluates expiration based on real Supabase expires_in metadata with a 60s buffer
        let expirationCutoff = createdAt.addingTimeInterval(Double(expiresIn - 60))
        return Date() >= expirationCutoff
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "bearer"
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 3600
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        
        if let user = try? container.decode(User.self, forKey: .user) {
            userId = user.id
            email = user.email ?? ""
        } else {
            userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? "unknown"
            email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encode(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encode(userId, forKey: .userId)
        try container.encode(email, forKey: .email)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    init(accessToken: String, userId: String, email: String, expiresIn: Int = 3600, refreshToken: String? = nil, createdAt: Date = Date()) {
        self.accessToken = accessToken
        self.tokenType = "bearer"
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.userId = userId
        self.email = email
        self.createdAt = createdAt
    }
}

// MARK: - Keychain Helper
private struct KeychainHelper {
    static let service = "com.mockexa.auth"
    
    static func save(key: String, data: Data) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data
        ] as [CFString: Any]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(key: String) -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [CFString: Any]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }
    
    static func delete(key: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ] as [CFString: Any]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AuthManager: ObservableObject {
#if targetEnvironment(simulator)
    /// Free, no-SMS credentials used only by local prototype builds.
    static let prototypePhoneNumber = "+12025550123"
    static let prototypePhoneOTP = "789012"
#endif

    @Published var isAuthenticated: Bool = false
    @Published var currentUserEmail: String = ""
    @Published var currentUserPhone: String = ""
    @Published var currentUserId: String = ""
    @Published var currentUserFullName: String = ""
    @Published var currentUserAge: Int? = nil
    @Published var currentUserPhotoData: Data? = nil
    @Published var accessToken: String? = nil
    @Published var authError: String? = nil
    @Published var isLoading: Bool = false
    @Published var isRestoringSession: Bool = true
    
    /// Returns the first name of the authenticated user, or a clean fallback if not available
    var currentFirstName: String {
        let trimmed = currentUserFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let components = trimmed.components(separatedBy: .whitespaces)
            if let first = components.first, !first.isEmpty {
                return first
            }
        }
        if !currentUserEmail.isEmpty {
            let emailName = currentUserEmail.components(separatedBy: "@").first ?? ""
            let cleaned = emailName.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
            if let first = cleaned.components(separatedBy: .whitespaces).first, !first.isEmpty {
                return first.capitalized
            }
        }
        return "there"
    }
    
    /// Returns full name for profile display, or clean name/profile fallback
    var profileDisplayName: String {
        let trimmed = currentUserFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if currentFirstName != "there" {
            return currentFirstName
        }
        return "Your Profile"
    }

    var profileContact: String {
        if !currentUserEmail.isEmpty { return currentUserEmail }
        if !currentUserPhone.isEmpty { return currentUserPhone }
        return "Candidate"
    }
    
    /// Returns 2-letter uppercase initials for profile avatar
    var profileInitials: String {
        let trimmed = currentUserFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2 {
                let first = parts[0].prefix(1)
                let last = parts[parts.count - 1].prefix(1)
                return "\(first)\(last)".uppercased()
            } else if let first = parts.first {
                return String(first.prefix(2)).uppercased()
            }
        }
        if !currentUserEmail.isEmpty {
            return String(currentUserEmail.prefix(2)).uppercased()
        }
        return "ME"
    }
    
    private let keychainKey = "MOCKEXA_ACTIVE_SESSION"
    private let installFlagKey = "MOCKEXA_APP_INSTALLED_FLAG"
    private let preferencesOwnerKey = "MOCKEXA_PREFERENCES_OWNER"
    
    init() {
        restoreSession()
    }
    
    /// Restores a previously saved real session from Keychain or UserDefaults
    func restoreSession() {
        let isAppInstalled = UserDefaults.standard.bool(forKey: installFlagKey)
        if !isAppInstalled {
            // Fresh app installation / re-install: clear stale Keychain session
            KeychainHelper.delete(key: keychainKey)
            UserDefaults.standard.removeObject(forKey: keychainKey)
            UserDefaults.standard.set(true, forKey: installFlagKey)
            isRestoringSession = false
            return
        }
        
        guard let savedData = KeychainHelper.load(key: keychainKey) ?? UserDefaults.standard.data(forKey: keychainKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: savedData) else {
            isRestoringSession = false
            return
        }
        
        if session.isExpired {
            if let refreshToken = session.refreshToken, !refreshToken.isEmpty {
                Task {
                    let refreshed = await self.refreshSession(with: refreshToken)
                    if !refreshed {
                        self.signOut()
                    }
                    self.isRestoringSession = false
                }
            } else {
                self.signOut()
                self.isRestoringSession = false
            }
        } else {
            self.accessToken = session.accessToken
            self.currentUserId = session.userId
            self.currentUserEmail = session.email
            if self.currentUserEmail.isEmpty,
               let cachedEmail = UserDefaults.standard.string(forKey: "MOCKEXA_USER_EMAIL_\(session.userId)"), !cachedEmail.isEmpty {
                self.currentUserEmail = cachedEmail
            }
            self.currentUserPhone = UserDefaults.standard.string(forKey: "MOCKEXA_USER_PHONE_\(session.userId)") ?? ""
            if UserDefaults.standard.bool(forKey: "MOCKEXA_PROTOTYPE_PHONE_USER_\(session.userId)") {
                self.currentUserEmail = ""
            }
            self.isAuthenticated = true
            activatePreferences(for: session.userId)
            
            if let cachedName = UserDefaults.standard.string(forKey: "MOCKEXA_USER_FULL_NAME_\(session.userId)"), !cachedName.isEmpty {
                self.currentUserFullName = cachedName
            }
            self.currentUserPhotoData = UserDefaults.standard.data(forKey: "MOCKEXA_USER_PHOTO_\(session.userId)")
            
            let ageKey = "MOCKEXA_USER_AGE_\(session.userId)"
            if UserDefaults.standard.object(forKey: ageKey) != nil {
                let cachedAge = UserDefaults.standard.integer(forKey: ageKey)
                if cachedAge > 0 {
                    self.currentUserAge = cachedAge
                }
            } else {
                self.currentUserAge = nil
            }
            
            Task {
                await self.fetchUserMetadataFromSupabase()
                self.isRestoringSession = false
            }
        }
    }
    
    /// Checks whether onboarding has been completed for the specified or active user account
    func isOnboardingCompleted(for userId: String? = nil) -> Bool {
        let uid = (userId != nil && !userId!.isEmpty) ? userId! : currentUserId
        guard !uid.isEmpty else { return false }
        
        // Clean up legacy global key if present so it never contaminates any account
        if UserDefaults.standard.object(forKey: "MOCKEXA_ONBOARDING_COMPLETED") != nil {
            UserDefaults.standard.removeObject(forKey: "MOCKEXA_ONBOARDING_COMPLETED")
        }
        
        return UserDefaults.standard.bool(forKey: "MOCKEXA_ONBOARDING_COMPLETED_\(uid)")
    }
    
    /// Marks onboarding as completed for the specified or active user account and syncs to Supabase user_metadata
    func setOnboardingCompleted(for userId: String? = nil, completed: Bool = true) {
        let uid = (userId != nil && !userId!.isEmpty) ? userId! : currentUserId
        guard !uid.isEmpty else { return }
        
        // Update user-scoped local cache immediately
        UserDefaults.standard.set(completed, forKey: "MOCKEXA_ONBOARDING_COMPLETED_\(uid)")
        // Ensure legacy global key is removed
        UserDefaults.standard.removeObject(forKey: "MOCKEXA_ONBOARDING_COMPLETED")
        
        // Sync to Supabase Auth user_metadata asynchronously
        Task {
            await self.syncOnboardingCompletionToSupabase(completed: completed)
        }
    }

    func updateProfile(fullName: String, age: Int?, email: String? = nil) {
        let cleanName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentUserId.isEmpty, !cleanName.isEmpty else { return }
        currentUserFullName = cleanName
        currentUserAge = age
        UserDefaults.standard.set(cleanName, forKey: "MOCKEXA_USER_FULL_NAME_\(currentUserId)")
        if let age {
            UserDefaults.standard.set(age, forKey: "MOCKEXA_USER_AGE_\(currentUserId)")
        } else {
            UserDefaults.standard.removeObject(forKey: "MOCKEXA_USER_AGE_\(currentUserId)")
        }
        if let email {
            let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanEmail.isEmpty {
                currentUserEmail = cleanEmail
                UserDefaults.standard.set(cleanEmail, forKey: "MOCKEXA_USER_EMAIL_\(currentUserId)")
                UserDefaults.standard.set(cleanEmail, forKey: "MOCKEXA_LAST_EMAIL")
                persistUpdatedEmailInSession(cleanEmail)
            }
        }
        Task {
            await syncProfileMetadataToSupabase(fullName: cleanName, age: age)
            if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await syncEmailToSupabase(email.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func updateEmail(_ newEmail: String) {
        let cleanEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else { return }
        currentUserEmail = cleanEmail
        if !currentUserId.isEmpty {
            UserDefaults.standard.set(cleanEmail, forKey: "MOCKEXA_USER_EMAIL_\(currentUserId)")
        }
        UserDefaults.standard.set(cleanEmail, forKey: "MOCKEXA_LAST_EMAIL")
        persistUpdatedEmailInSession(cleanEmail)
        Task {
            await syncEmailToSupabase(cleanEmail)
        }
    }

    private func persistUpdatedEmailInSession(_ newEmail: String) {
        if let savedData = KeychainHelper.load(key: keychainKey) ?? UserDefaults.standard.data(forKey: keychainKey),
           let session = try? JSONDecoder().decode(AuthSession.self, from: savedData) {
            let updated = AuthSession(
                accessToken: session.accessToken,
                userId: session.userId,
                email: newEmail,
                expiresIn: session.expiresIn,
                refreshToken: session.refreshToken,
                createdAt: session.createdAt
            )
            if let data = try? JSONEncoder().encode(updated) {
                KeychainHelper.save(key: keychainKey, data: data)
                UserDefaults.standard.set(data, forKey: keychainKey)
            }
        }
    }

    private func syncEmailToSupabase(_ email: String) async {
        guard let token = accessToken, !token.isEmpty,
              let url = URL(string: "\(MockexaConfig.supabaseURL)/auth/v1/user") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(MockexaConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "data": ["email": email]])
        _ = try? await URLSession.shared.data(for: request)
    }

    func setProfilePhotoData(_ data: Data?) {
        guard !currentUserId.isEmpty else { return }
        currentUserPhotoData = data
        let key = "MOCKEXA_USER_PHOTO_\(currentUserId)"
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func saveOnboardingPreferences(study: String, role: String, companies: String, confidence: Int) {
        guard !currentUserId.isEmpty else { return }
        let defaults = UserDefaults.standard
        let values: [(String, Any)] = [
            ("MOCKEXA_STUDY_FIELD", study),
            ("MOCKEXA_TARGET_ROLE", role),
            ("MOCKEXA_TARGET_COMPANIES", companies),
            ("MOCKEXA_CONFIDENCE_LEVEL", confidence),
        ]
        for (key, value) in values {
            defaults.set(value, forKey: key)
            defaults.set(value, forKey: "\(key)_\(currentUserId)")
        }
        defaults.set(currentUserId, forKey: preferencesOwnerKey)
    }

    func saveTargetPreference(key: String, value: String) {
        guard !currentUserId.isEmpty,
              key == "MOCKEXA_TARGET_ROLE" || key == "MOCKEXA_TARGET_COMPANIES" else { return }
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.set(value, forKey: "\(key)_\(currentUserId)")
        UserDefaults.standard.set(currentUserId, forKey: preferencesOwnerKey)
    }

    private func activatePreferences(for userId: String) {
        guard !userId.isEmpty else { return }
        let defaults = UserDefaults.standard
        let keys = ["MOCKEXA_STUDY_FIELD", "MOCKEXA_TARGET_ROLE", "MOCKEXA_TARGET_COMPANIES", "MOCKEXA_CONFIDENCE_LEVEL"]
        let owner = defaults.string(forKey: preferencesOwnerKey)

        // One-time migration for an existing installation created before
        // preferences became account-scoped.
        if owner == nil {
            for key in keys where defaults.object(forKey: key) != nil {
                defaults.set(defaults.object(forKey: key), forKey: "\(key)_\(userId)")
            }
        }

        for key in keys {
            let scopedKey = "\(key)_\(userId)"
            if let value = defaults.object(forKey: scopedKey) {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(userId, forKey: preferencesOwnerKey)
    }

    private func syncProfileMetadataToSupabase(fullName: String, age: Int?) async {
        guard let token = accessToken, !token.isEmpty,
              let url = URL(string: "\(MockexaConfig.supabaseURL)/auth/v1/user") else { return }
        var metadata: [String: Any] = ["full_name": fullName]
        if let age { metadata["age"] = age }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(MockexaConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["data": metadata])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                print("Supabase profile metadata sync failed")
                return
            }
        } catch {
            print("Supabase profile metadata sync error: \(error.localizedDescription)")
        }
    }
    
    /// Syncs onboarding completion state to Supabase Auth user_metadata via PUT /auth/v1/user
    func syncOnboardingCompletionToSupabase(completed: Bool) async {
        guard let token = accessToken, !token.isEmpty else {
            print("Supabase onboarding metadata sync skipped: No active access token")
            return
        }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/user") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "data": [
                "onboarding_completed": completed
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Supabase onboarding metadata successfully synced for user: \(currentUserId)")
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("Supabase onboarding metadata sync failed with status code: \(statusCode)")
            }
        } catch {
            print("Supabase onboarding metadata sync error: \(error.localizedDescription)")
        }
    }
    
    /// Fetches user metadata from Supabase Auth (GET /auth/v1/user) and updates local cache
    func fetchUserMetadataFromSupabase() async {
        guard let token = accessToken, !token.isEmpty, !currentUserId.isEmpty else { return }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/user") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let isPrototypePhoneUser = UserDefaults.standard.bool(forKey: "MOCKEXA_PROTOTYPE_PHONE_USER_\(currentUserId)")
                if !isPrototypePhoneUser, let email = json["email"] as? String, !email.isEmpty {
                    self.currentUserEmail = email
                    UserDefaults.standard.set(email, forKey: "MOCKEXA_USER_EMAIL_\(currentUserId)")
                    UserDefaults.standard.set(email, forKey: "MOCKEXA_LAST_EMAIL")
                }
                if let phone = json["phone"] as? String, !phone.isEmpty {
                    self.currentUserPhone = phone
                    UserDefaults.standard.set(phone, forKey: "MOCKEXA_USER_PHONE_\(currentUserId)")
                }
                let metadata = json["user_metadata"] as? [String: Any]
                if let completed = metadata?["onboarding_completed"] as? Bool, completed {
                    UserDefaults.standard.set(true, forKey: "MOCKEXA_ONBOARDING_COMPLETED_\(currentUserId)")
                }
                if let name = (metadata?["full_name"] as? String ?? metadata?["name"] as? String), !name.isEmpty {
                    self.currentUserFullName = name
                    UserDefaults.standard.set(name, forKey: "MOCKEXA_USER_FULL_NAME_\(currentUserId)")
                }
                if let ageVal = metadata?["age"] as? Int {
                    self.currentUserAge = ageVal
                    UserDefaults.standard.set(ageVal, forKey: "MOCKEXA_USER_AGE_\(currentUserId)")
                } else if let ageStr = metadata?["age"] as? String, let ageVal = Int(ageStr) {
                    self.currentUserAge = ageVal
                    UserDefaults.standard.set(ageVal, forKey: "MOCKEXA_USER_AGE_\(currentUserId)")
                }
            }
        } catch {
            print("Failed to fetch user metadata from Supabase: \(error.localizedDescription)")
        }
    }
    
    /// Refreshes the real Supabase Auth session using the stored refresh token
    func refreshSession(with refreshToken: String) async -> Bool {
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "refresh_token": refreshToken
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let newSession = try JSONDecoder().decode(AuthSession.self, from: data)
                saveSession(newSession, rawData: data)
                return true
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    /// Sign in using real Supabase Auth REST API (`/auth/v1/token?grant_type=password`)
    func signIn(email: String, password: String) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedEmail.isEmpty else {
            authError = "Please enter your email."
            return false
        }
        
        guard !trimmedPassword.isEmpty else {
            authError = "Please enter your password."
            return false
        }
        
        isLoading = true
        authError = nil
        
        defer { isLoading = false }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else {
            authError = "Invalid Supabase URL"
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "email": trimmedEmail,
            "password": trimmedPassword
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "Invalid server response"
                return false
            }
            
            if httpResponse.statusCode == 200 {
                UserDefaults.standard.set(trimmedEmail, forKey: "MOCKEXA_LAST_EMAIL")
                var session = try JSONDecoder().decode(AuthSession.self, from: data)
                if session.email.isEmpty && !trimmedEmail.isEmpty {
                    session = AuthSession(
                        accessToken: session.accessToken,
                        userId: session.userId,
                        email: trimmedEmail,
                        expiresIn: session.expiresIn,
                        refreshToken: session.refreshToken,
                        createdAt: session.createdAt
                    )
                }
                saveSession(session, rawData: data)
                return true
            } else {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = errJson["error_description"] as? String ?? errJson["msg"] as? String ?? errJson["error"] as? String {
                    authError = msg
                } else {
                    authError = "Invalid email or password (\(httpResponse.statusCode))"
                }
                return false
            }
        } catch {
            authError = "Network error. Please check your connection and try again."
            return false
        }
    }
    
    /// Sign up using real Supabase Auth REST API (`/auth/v1/signup`)
    func signUp(email: String, password: String, fullName: String? = nil, age: Int? = nil) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if fullName != nil && trimmedName.isEmpty {
            authError = "Please enter your full name."
            return false
        }
        
        guard !trimmedEmail.isEmpty else {
            authError = "Please enter your email."
            return false
        }
        
        guard !trimmedPassword.isEmpty else {
            authError = "Please enter your password."
            return false
        }
        
        isLoading = true
        authError = nil
        
        defer { isLoading = false }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/signup") else {
            authError = "Invalid Supabase URL"
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        var body: [String: Any] = [
            "email": trimmedEmail,
            "password": trimmedPassword
        ]
        
        var userMetadata: [String: Any] = [:]
        if !trimmedName.isEmpty {
            userMetadata["full_name"] = trimmedName
        }
        if let userAge = age {
            userMetadata["age"] = userAge
        }
        if !userMetadata.isEmpty {
            body["data"] = userMetadata
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "Invalid server response"
                return false
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                UserDefaults.standard.set(trimmedEmail, forKey: "MOCKEXA_LAST_EMAIL")
                if var session = try? JSONDecoder().decode(AuthSession.self, from: data) {
                    if session.email.isEmpty && !trimmedEmail.isEmpty {
                        session = AuthSession(
                            accessToken: session.accessToken,
                            userId: session.userId,
                            email: trimmedEmail,
                            expiresIn: session.expiresIn,
                            refreshToken: session.refreshToken,
                            createdAt: session.createdAt
                        )
                    }
                    saveSession(session, rawData: data)
                    return true
                }
                // If email confirmation is disabled, token sign in succeeds immediately
                return await signIn(email: trimmedEmail, password: trimmedPassword)
            } else {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = errJson["error_description"] as? String ?? errJson["msg"] as? String ?? errJson["error"] as? String {
                    if msg.lowercased().contains("already") || msg.lowercased().contains("exists") || msg.lowercased().contains("registered") {
                        authError = "An account with this email already exists. Please log in."
                    } else {
                        authError = msg
                    }
                } else {
                    authError = "Sign up failed (\(httpResponse.statusCode))"
                }
                return false
            }
        } catch {
            authError = "Network error. Please check your connection and try again."
            return false
        }
    }
    
    // MARK: - Password Recovery (Supabase /auth/v1/recover)
    func sendPasswordReset(email: String) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            authError = "Please enter your email."
            return false
        }
        
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/recover") else {
            authError = "Invalid Supabase URL"
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "email": trimmedEmail
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "Invalid server response"
                return false
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                return true
            } else {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = errJson["error_description"] as? String ?? errJson["msg"] as? String ?? errJson["error"] as? String {
                    authError = msg
                } else {
                    authError = "Password recovery failed (\(httpResponse.statusCode)). Please verify your email and try again."
                }
                return false
            }
        } catch {
            authError = "Network error. Please check your connection and try again."
            return false
        }
    }
    
    /// Sign out and clear stored real session
    func signOut() {
        KeychainHelper.delete(key: keychainKey)
        UserDefaults.standard.removeObject(forKey: keychainKey)
        accessToken = nil
        currentUserId = ""
        currentUserEmail = ""
        currentUserPhone = ""
        currentUserFullName = ""
        currentUserAge = nil
        currentUserPhotoData = nil
        isAuthenticated = false
    }
    
    private func saveSession(_ session: AuthSession, rawData: Data? = nil) {
        self.accessToken = session.accessToken
        self.currentUserId = session.userId
        
        var effectiveEmail = session.email
        if let rawData = rawData,
           let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            let userObj = json["user"] as? [String: Any]
            if let email = (userObj?["email"] as? String ?? json["email"] as? String), !email.isEmpty {
                effectiveEmail = email
            }
        }
        if effectiveEmail.isEmpty,
           let cachedEmail = UserDefaults.standard.string(forKey: "MOCKEXA_USER_EMAIL_\(session.userId)"), !cachedEmail.isEmpty {
            effectiveEmail = cachedEmail
        }
        self.currentUserEmail = effectiveEmail
        if !effectiveEmail.isEmpty {
            UserDefaults.standard.set(effectiveEmail, forKey: "MOCKEXA_USER_EMAIL_\(session.userId)")
            UserDefaults.standard.set(effectiveEmail, forKey: "MOCKEXA_LAST_EMAIL")
        }
        if let rawData,
           let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
           let phone = ((json["user"] as? [String: Any])?["phone"] as? String ?? json["phone"] as? String),
           !phone.isEmpty {
            self.currentUserPhone = phone
            UserDefaults.standard.set(phone, forKey: "MOCKEXA_USER_PHONE_\(session.userId)")
        } else {
            self.currentUserPhone = UserDefaults.standard.string(forKey: "MOCKEXA_USER_PHONE_\(session.userId)") ?? ""
        }

        let sessionToStore = (session.email.isEmpty && !effectiveEmail.isEmpty)
            ? AuthSession(
                accessToken: session.accessToken,
                userId: session.userId,
                email: effectiveEmail,
                expiresIn: session.expiresIn,
                refreshToken: session.refreshToken,
                createdAt: session.createdAt
            )
            : session

        if let data = try? JSONEncoder().encode(sessionToStore) {
            KeychainHelper.save(key: keychainKey, data: data)
            UserDefaults.standard.set(data, forKey: keychainKey)
        }
        self.isAuthenticated = true
        activatePreferences(for: session.userId)
        self.currentUserPhotoData = UserDefaults.standard.data(forKey: "MOCKEXA_USER_PHOTO_\(session.userId)")
        if UserDefaults.standard.bool(forKey: "MOCKEXA_PROTOTYPE_PHONE_USER_\(session.userId)") {
            self.currentUserEmail = ""
        }
        
        // Extract onboarding_completed & full_name from raw user_metadata in Supabase response if available
        if let rawData = rawData,
           let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            let userObj = json["user"] as? [String: Any]
            let metadata = (userObj?["user_metadata"] as? [String: Any]) ?? (json["user_metadata"] as? [String: Any])
            if let completed = metadata?["onboarding_completed"] as? Bool, completed {
                UserDefaults.standard.set(true, forKey: "MOCKEXA_ONBOARDING_COMPLETED_\(session.userId)")
            }
            if let name = (metadata?["full_name"] as? String ?? metadata?["name"] as? String), !name.isEmpty {
                self.currentUserFullName = name
                UserDefaults.standard.set(name, forKey: "MOCKEXA_USER_FULL_NAME_\(session.userId)")
            }
            if let ageVal = metadata?["age"] as? Int {
                self.currentUserAge = ageVal
                UserDefaults.standard.set(ageVal, forKey: "MOCKEXA_USER_AGE_\(session.userId)")
            } else if let ageStr = metadata?["age"] as? String, let ageVal = Int(ageStr) {
                self.currentUserAge = ageVal
                UserDefaults.standard.set(ageVal, forKey: "MOCKEXA_USER_AGE_\(session.userId)")
            }
        }
    }
    
    // MARK: - Apple Sign In
    private var appleAuthDelegate: AppleAuthDelegate?
    
    func startAppleSignIn() async -> Bool {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        let delegate = AppleAuthDelegate()
        self.appleAuthDelegate = delegate
        
        return await withCheckedContinuation { continuation in
            delegate.startSignIn { result in
                Task { @MainActor in
                    switch result {
                    case .success(let payload):
                        let success = await self.signInWithApple(
                            idToken: payload.idToken,
                            rawNonce: payload.rawNonce,
                            fullName: payload.fullName,
                            email: payload.email
                        )
                        continuation.resume(returning: success)
                    case .failure(let error):
                        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                            continuation.resume(returning: false)
                        } else {
                            self.authError = "Apple Sign In error: \(error.localizedDescription)"
                            continuation.resume(returning: false)
                        }
                    }
                    self.appleAuthDelegate = nil
                }
            }
        }
    }
    
    func signInWithApple(idToken: String, rawNonce: String, fullName: String? = nil, email: String? = nil) async -> Bool {
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token") else {
            authError = "Invalid Supabase URL"
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        var body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken,
            "nonce": rawNonce
        ]
        
        var userMetadata: [String: Any] = [:]
        if let fullName, !fullName.isEmpty {
            userMetadata["full_name"] = fullName
        }
        if let email, !email.isEmpty {
            userMetadata["email"] = email
        }
        if !userMetadata.isEmpty {
            body["user_metadata"] = userMetadata
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "Invalid server response"
                return false
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                var session = try JSONDecoder().decode(AuthSession.self, from: data)
                if session.email.isEmpty, let email, !email.isEmpty {
                    session = AuthSession(
                        accessToken: session.accessToken,
                        userId: session.userId,
                        email: email,
                        expiresIn: session.expiresIn,
                        refreshToken: session.refreshToken,
                        createdAt: session.createdAt
                    )
                }
                saveSession(session, rawData: data)
                return true
            } else {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = errJson["error_description"] as? String ?? errJson["msg"] as? String ?? errJson["error"] as? String {
                    authError = msg
                } else {
                    authError = "Apple authentication failed (\(httpResponse.statusCode)). Please verify Supabase Apple provider settings."
                }
                return false
            }
        } catch {
            authError = "Network error: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Google Sign In (ASWebAuthenticationSession)
    func signInWithGoogle() async -> Bool {
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let scheme = "mockexa"
        let redirectURL = "mockexa://auth/callback"
        
        let allowedQuery = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encodedRedirect = redirectURL.addingPercentEncoding(withAllowedCharacters: allowedQuery),
              let authURL = URL(string: "\(supabaseURL)/auth/v1/authorize?provider=google&redirect_to=\(encodedRedirect)&prompt=select_account") else {
            authError = "Invalid Supabase OAuth URL"
            return false
        }
        
        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: false)
                    return
                }
                
                if let error = error {
                    Task { @MainActor in
                        self.authError = "Google authentication failed: \(error.localizedDescription)"
                    }
                    continuation.resume(returning: false)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    Task { @MainActor in
                        self.authError = "Invalid callback URL received."
                    }
                    continuation.resume(returning: false)
                    return
                }
                
                Task { @MainActor in
                    let success = self.handleOAuthCallback(url: callbackURL)
                    continuation.resume(returning: success)
                }
            }
            
            let contextProvider = GoogleAuthContextProvider()
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    
    @discardableResult
    func handleOAuthCallback(url: URL) -> Bool {
        var paramString = url.fragment ?? url.query ?? ""
        if paramString.isEmpty {
            if let hashRange = url.absoluteString.range(of: "#") {
                paramString = String(url.absoluteString[hashRange.upperBound...])
            } else if let queryRange = url.absoluteString.range(of: "?") {
                paramString = String(url.absoluteString[queryRange.upperBound...])
            }
        }
        
        let params = parseQueryString(paramString)
        
        guard let accessToken = params["access_token"], !accessToken.isEmpty else {
            if let errorDesc = params["error_description"] ?? params["error"] {
                self.authError = errorDesc.replacingOccurrences(of: "+", with: " ")
            } else {
                self.authError = "Google Sign In failed to return an access token. Please check Supabase Google provider configuration."
            }
            return false
        }
        
        let refreshToken = params["refresh_token"]
        let expiresIn = Int(params["expires_in"] ?? "3600") ?? 3600
        let tokenEmail = extractEmailFromJWT(accessToken)
        let email = params["email"] ?? tokenEmail ?? ""
        let userId = params["user_id"] ?? extractSubjectFromJWT(accessToken) ?? (!email.isEmpty ? "google_\(email)" : "google_user")
        
        let session = AuthSession(
            accessToken: accessToken,
            userId: userId,
            email: email,
            expiresIn: expiresIn,
            refreshToken: refreshToken,
            createdAt: Date()
        )
        
        saveSession(session)
        Task {
            await self.fetchUserMetadataFromSupabase()
        }
        return true
    }
    
    private func parseQueryString(_ string: String) -> [String: String] {
        var results = [String: String]()
        let pairs = string.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                let key = kv[0]
                let value = kv[1].removingPercentEncoding ?? kv[1]
                results[key] = value
            }
        }
        return results
    }
    
    private func extractSubjectFromJWT(_ jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        return sub
    }

    private func extractEmailFromJWT(_ jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (json["email"] as? String ?? (json["user_metadata"] as? [String: Any])?["email"] as? String)
    }

    // MARK: - Phone Authentication (SMS OTP)
#if targetEnvironment(simulator)
    private struct PrototypePhoneCredentials: Codable {
        let email: String
        let password: String
    }

    private var prototypeCredentialsKey: String { "MOCKEXA_PROTOTYPE_PHONE_CREDENTIALS" }

    private func finishPrototypePhoneLogin(phone: String) {
        guard !currentUserId.isEmpty else { return }
        UserDefaults.standard.set(phone, forKey: "MOCKEXA_USER_PHONE_\(currentUserId)")
        UserDefaults.standard.set(true, forKey: "MOCKEXA_PROTOTYPE_PHONE_USER_\(currentUserId)")
        UserDefaults.standard.removeObject(forKey: "MOCKEXA_USER_EMAIL_\(currentUserId)")
        currentUserPhone = phone
        currentUserEmail = ""
    }

    /// Creates/reuses a real Supabase session behind the prototype phone UI so every
    /// authenticated backend feature continues to receive a valid JWT.
    private func authenticatePrototypePhone(_ phone: String) async -> Bool {
        if let saved = KeychainHelper.load(key: prototypeCredentialsKey),
           let credentials = try? JSONDecoder().decode(PrototypePhoneCredentials.self, from: saved),
           await signIn(email: credentials.email, password: credentials.password) {
            finishPrototypePhoneLogin(phone: phone)
            return true
        }

        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let credentials = PrototypePhoneCredentials(
            email: "prototype.phone.\(id)@example.com",
            password: "\(UUID().uuidString)Aa1!\(UUID().uuidString.prefix(20))"
        )
        guard await signUp(email: credentials.email, password: credentials.password) else {
            authError = authError ?? "Prototype sign-in could not be created. Please try again."
            return false
        }
        if let data = try? JSONEncoder().encode(credentials) {
            KeychainHelper.save(key: prototypeCredentialsKey, data: data)
        }
        finishPrototypePhoneLogin(phone: phone)
        return true
    }
#endif

    private func isPhoneAuthEnabled(supabaseURL: String, anonKey: String) async -> Bool? {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/settings") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let external = json["external"] as? [String: Any] else { return nil }
            return external["phone"] as? Bool
        } catch {
            // The OTP request below remains the source of truth if settings are unavailable.
            return nil
        }
    }

    private func phoneAuthError(from data: Data, fallback: String) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["error_description"] as? String ?? json["message"] as? String ?? json["msg"] as? String ?? json["error"] as? String else {
            return fallback
        }
        let lower = raw.lowercased()
        if lower.contains("phone provider") || lower.contains("unsupported provider") {
            return "Phone sign-in is temporarily unavailable. Please use email or Google while SMS setup is completed."
        }
        if lower.contains("rate") || lower.contains("too many") {
            return "Too many code requests. Please wait a few minutes and try again."
        }
        if lower.contains("valid phone") {
            return "That mobile number is not valid for the selected country."
        }
        return raw
    }

    func sendPhoneOTP(phone: String) async -> Bool {
        let digits = phone.dropFirst()
        guard phone.hasPrefix("+"), (8...15).contains(digits.count),
              digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            authError = "Enter a valid phone number with country code."
            return false
        }
#if targetEnvironment(simulator)
        if phone == Self.prototypePhoneNumber {
            authError = nil
            return true
        }
#endif
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey

        if await isPhoneAuthEnabled(supabaseURL: supabaseURL, anonKey: anonKey) == false {
            authError = "Phone sign-in is temporarily unavailable. Please use email or Google while SMS setup is completed."
            return false
        }
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/otp") else {
            authError = "Invalid Supabase URL"
            return false
        }
        
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = ["phone": phone, "create_user": true]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "Invalid server response"
                return false
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                return true
            } else {
                authError = phoneAuthError(
                    from: data,
                    fallback: "We couldn't send the code right now. Please try again shortly."
                )
                return false
            }
        } catch {
            authError = "Network error: \(error.localizedDescription)"
            return false
        }
    }

    func verifyPhoneOTP(phone: String, token: String) async -> Bool {
        guard token.count == 6, token.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            authError = "Enter the 6-digit verification code."
            return false
        }
#if targetEnvironment(simulator)
        if phone == Self.prototypePhoneNumber {
            guard token == Self.prototypePhoneOTP else {
                authError = "Incorrect prototype code. Use \(Self.prototypePhoneOTP)."
                return false
            }
            authError = nil
            return await authenticatePrototypePhone(phone)
        }
#endif
        isLoading = true
        authError = nil
        defer { isLoading = false }
        
        let supabaseURL = MockexaConfig.supabaseURL
        let anonKey = MockexaConfig.supabaseAnonKey
        
        guard let url = URL(string: "\(supabaseURL)/auth/v1/verify") else {
            authError = "Invalid Supabase URL"
            return false
        }
        
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "type": "sms",
            "phone": phone,
            "token": token
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authError = "Invalid server response"
                return false
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                let session = try JSONDecoder().decode(AuthSession.self, from: data)
                saveSession(session, rawData: data)
                return true
            } else {
                authError = phoneAuthError(
                    from: data,
                    fallback: "That code is invalid or expired. Request a new code and try again."
                )
                return false
            }
        } catch {
            authError = "Network error: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding Helper
@MainActor
final class GoogleAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Native Apple Auth Delegate & Nonce Helpers
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    var randomBytes = [UInt8](repeating: 0, count: length)
    let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    if errorCode != errSecSuccess {
        fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
    }
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    let nonce = randomBytes.map { byte in
        charset[Int(byte) % charset.count]
    }
    return String(nonce)
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.compactMap { String(format: "%02x", $0) }.joined()
}

@MainActor
final class AppleAuthDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var currentNonce: String?
    private var completion: ((Result<(idToken: String, rawNonce: String, fullName: String?, email: String?), Error>) -> Void)?

    func startSignIn(completion: @escaping (Result<(idToken: String, rawNonce: String, fullName: String?, email: String?), Error>) -> Void) {
        let rawNonce = randomNonceString()
        self.currentNonce = rawNonce
        self.completion = completion

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8),
              let rawNonce = currentNonce else {
            completion?(.failure(NSError(domain: "AppleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract Apple identity token."])))
            return
        }

        var fullNameString: String? = nil
        if let nameComponents = appleIDCredential.fullName {
            let given = nameComponents.givenName ?? ""
            let family = nameComponents.familyName ?? ""
            let combined = "\(given) \(family)".trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty {
                fullNameString = combined
            }
        }

        var emailString = appleIDCredential.email
        if emailString == nil || emailString!.isEmpty {
            let parts = idTokenString.components(separatedBy: ".")
            if parts.count > 1 {
                var base64 = parts[1]
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")
                while base64.count % 4 != 0 {
                    base64.append("=")
                }
                if let data = Data(base64Encoded: base64),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    emailString = json["email"] as? String
                }
            }
        }

        completion?(.success((idToken: idTokenString, rawNonce: rawNonce, fullName: fullNameString, email: emailString)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
    }
}
