import Foundation

/// Centralized configuration layer for backend server endpoints and Supabase authentication.
struct MockexaConfig {
    /// Keys used for UserDefaults configuration overrides
    private static let baseURLKey = "MOCKEXA_BACKEND_BASE_URL"
    private static let supabaseURLKey = "MOCKEXA_SUPABASE_URL"
    private static let supabaseAnonKeyKey = "MOCKEXA_SUPABASE_ANON_KEY"
    
    /// Production HTTPS backend used by both Simulator and physical devices.
    /// Developers can still override this through UserDefaults, the process
    /// environment, or Info.plist when running a local backend.
    static let defaultBackendURL = "https://mockexa-api.onrender.com"
    
    /// Default Supabase configuration from Backend environment
    static let defaultSupabaseURL = "https://jdkpnustshxtvtdkxyvg.supabase.co"
    static let defaultSupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impka3BudXN0c2h4dHZ0ZGt4eXZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMTY5NTcsImV4cCI6MjEwMzU5Mjk1N30.wq11vg0D34L8nD0oNxMDqZSUm4OSrW2ziqElOqv0SIA"
    
    /// Gets or sets the active Backend Base URL.
    /// Priority resolution:
    /// 1. Custom user override in UserDefaults (configurable in App Settings)
    /// 2. Process environment variable (`MOCKEXA_BACKEND_BASE_URL`)
    /// 3. Info.plist configuration (`MOCKEXA_BACKEND_BASE_URL` or `BackendBaseURL`)
    /// 4. Production HTTPS default
    static var baseURL: String {
        get {
            if let custom = UserDefaults.standard.string(forKey: baseURLKey), !custom.isEmpty {
                let cleaned = custom.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let lowered = cleaned.lowercased()
                let isLegacyLocalOverride = lowered.contains("localhost")
                    || lowered.contains("127.0.0.1")
                    || lowered.contains(".local")
                    || lowered.contains("://192.168.")
                    || lowered.contains("://10.")
                if !isLegacyLocalOverride {
                    return cleaned
                }
            }
            if let envURL = ProcessInfo.processInfo.environment[baseURLKey], !envURL.isEmpty {
                return envURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if let infoURL = Bundle.main.object(forInfoDictionaryKey: baseURLKey) as? String, !infoURL.isEmpty, !infoURL.hasPrefix("$") {
                return infoURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if let infoURL = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String, !infoURL.isEmpty, !infoURL.hasPrefix("$") {
                return infoURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return defaultBackendURL
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            UserDefaults.standard.set(cleaned, forKey: baseURLKey)
        }
    }
    
    /// Gets or sets the Supabase URL
    static var supabaseURL: String {
        get {
            if let custom = UserDefaults.standard.string(forKey: supabaseURLKey), !custom.isEmpty {
                return custom.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if let env = ProcessInfo.processInfo.environment["SUPABASE_URL"], !env.isEmpty {
                return env.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return defaultSupabaseURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: supabaseURLKey)
        }
    }
    
    /// Gets or sets the Supabase Anon Key
    static var supabaseAnonKey: String {
        get {
            if let custom = UserDefaults.standard.string(forKey: supabaseAnonKeyKey), !custom.isEmpty {
                return custom
            }
            if let env = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !env.isEmpty {
                return env
            }
            return defaultSupabaseAnonKey
        }
        set {
            UserDefaults.standard.set(newValue, forKey: supabaseAnonKeyKey)
        }
    }
    
    /// Reset configuration to default values
    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: supabaseURLKey)
        UserDefaults.standard.removeObject(forKey: supabaseAnonKeyKey)
    }
}

/// Keeps onboarding's target role as the single personalization source used
/// across interview setup, company practice, GD and aptitude rounds.
enum RolePersonalization {
    private static let allTechnicalDomains = [
        "Data Structures", "Algorithms", "Operating Systems", "DBMS",
        "OOP", "Software Engineering", "Programming"
    ]

    private static func key(_ role: String) -> String {
        role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func technicalDomains(for role: String) -> [String] {
        let value = key(role)
        if value.contains("data") && value.contains("analyst") {
            return ["DBMS", "Programming", "Algorithms", "Data Structures"]
        }
        if value.contains("product") {
            return ["Software Engineering", "DBMS", "Algorithms", "OOP"]
        }
        if value.contains("business") && value.contains("analyst") {
            return ["DBMS", "Software Engineering", "Programming", "Algorithms"]
        }
        if value.contains("architect") {
            return ["Software Engineering", "Operating Systems", "DBMS", "OOP", "Algorithms"]
        }
        if value.contains("full stack") || value.contains("developer") {
            return ["Programming", "DBMS", "Data Structures", "Algorithms", "OOP", "Software Engineering"]
        }
        if value.contains("software") || value.contains("engineer") {
            return ["Data Structures", "Algorithms", "OOP", "DBMS", "Operating Systems", "Software Engineering"]
        }
        return allTechnicalDomains
    }

    static func aptitudeCategories(for role: String) -> [String] {
        let value = key(role)
        if value.contains("data") || value.contains("business analyst") {
            return ["Data Interpretation", "Quantitative Aptitude", "Logical Reasoning"]
        }
        if value.contains("product") {
            return ["Logical Reasoning", "Verbal Ability", "Data Interpretation"]
        }
        if value.contains("architect") || value.contains("software") || value.contains("developer") || value.contains("engineer") {
            return ["Logical Reasoning", "Quantitative Aptitude", "Verbal Ability"]
        }
        return []
    }

    static func companyCategories(for role: String) -> Set<String> {
        let value = key(role)
        if value.contains("product") || value.contains("business analyst") {
            return ["Behavioral", "System Design", "Technical"]
        }
        if value.contains("data") {
            return ["Technical", "DSA", "Behavioral"]
        }
        if value.contains("architect") {
            return ["System Design", "Technical", "Behavioral"]
        }
        if value.contains("software") || value.contains("developer") || value.contains("engineer") {
            return ["DSA", "Technical", "System Design"]
        }
        return []
    }

    static func hrStyle(for role: String) -> String {
        let value = key(role)
        if value.contains("product") || value.contains("architect") { return "Leadership" }
        if value.contains("analyst") { return "Situational" }
        return "Behavioral"
    }

    static func gdTopic(for role: String) -> String {
        let value = key(role)
        if value.contains("data") || value.contains("analyst") {
            return "Should personal data be treated as private property?"
        }
        if value.contains("product") {
            return "Should companies prioritize skills over degrees?"
        }
        if value.contains("architect") || value.contains("software") || value.contains("developer") || value.contains("engineer") {
            return "Will automation create more jobs than it removes?"
        }
        return "Remote work and productivity"
    }
}
