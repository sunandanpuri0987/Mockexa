import Foundation

/// Centralized configuration layer for backend server endpoints and Supabase authentication.
struct PrepConfig {
    /// Keys used for UserDefaults configuration overrides
    private static let baseURLKey = "PREPAI_BACKEND_BASE_URL"
    private static let supabaseURLKey = "PREPAI_SUPABASE_URL"
    private static let supabaseAnonKeyKey = "PREPAI_SUPABASE_ANON_KEY"
    
    /// Default backend URL (uses 127.0.0.1 for Simulator, Mac IP for Physical Device)
#if targetEnvironment(simulator)
    static let defaultSimulatorURL = "http://127.0.0.1:8000"
#else
    static let defaultSimulatorURL = "http://192.168.1.80:8000"
#endif
    
    /// Default Supabase configuration from Backend environment
    static let defaultSupabaseURL = "https://jdkpnustshxtvtdkxyvg.supabase.co"
    static let defaultSupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impka3BudXN0c2h4dHZ0ZGt4eXZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwMTY5NTcsImV4cCI6MjEwMzU5Mjk1N30.wq11vg0D34L8nD0oNxMDqZSUm4OSrW2ziqElOqv0SIA"
    
    /// Gets or sets the active Backend Base URL.
    static var baseURL: String {
        get {
            if let custom = UserDefaults.standard.string(forKey: baseURLKey), !custom.isEmpty {
                return custom.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if let envURL = ProcessInfo.processInfo.environment["PREPAI_BACKEND_BASE_URL"], !envURL.isEmpty {
                return envURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return defaultSimulatorURL
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
