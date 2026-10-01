import SwiftUI
import UIKit

@main
struct MockexaApp: App {
    @StateObject private var app = AppModel()
    @StateObject private var auth = AuthManager()
    @AppStorage("MOCKEXA_APPEARANCE") private var appearanceRaw = AppAppearance.light.rawValue

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .light
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(auth)
                .preferredColorScheme(selectedAppearance.colorScheme)
                .onOpenURL { url in
                    if auth.handleOAuthCallback(url: url) {
                        if auth.isOnboardingCompleted(for: auth.currentUserId) {
                            app.route = .main
                        } else {
                            app.onboardingStep = 0
                            app.route = .onboarding
                        }
                    }
                }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Route { case splash, welcome, auth, onboarding, main }
    @Published var route: Route = .splash
    @Published var tab: AppTab = .home
    @Published var practicePath = NavigationPath()
    @Published var onboardingStep = 0
    
    @Published var userSessions: [PracticeSession] = []
    @Published var isLoadingSessions: Bool = false
    @Published var sessionFetchError: String? = nil

    func enterApp() {
        tab = .home
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { route = .main }
        Haptics.success()
    }
    
    func refreshUserSessions(token: String?) async {
        guard !isLoadingSessions else { return }
        guard let token = token, !token.isEmpty else {
            self.userSessions = []
            return
        }
        self.isLoadingSessions = true
        self.sessionFetchError = nil
        do {
            let items = try await APIClient.shared.fetchSessions(token: token)
            self.userSessions = items.map { $0.toPracticeSession }
        } catch let err as APIError {
            self.sessionFetchError = err.localizedDescription
        } catch {
            self.sessionFetchError = error.localizedDescription
        }
        self.isLoadingSessions = false
    }
    
    var averageReadinessScore: Int {
        let validSessions = userSessions.filter { $0.kind != nil }
        guard !validSessions.isEmpty else { return 0 }
        let total = validSessions.reduce(0) { $0 + $1.score }
        return total / validSessions.count
    }
    
    var gdAverageScore: Int {
        let gdSessions = userSessions.filter { $0.kind == .gd }
        guard !gdSessions.isEmpty else { return 0 }
        return gdSessions.reduce(0) { $0 + $1.score } / gdSessions.count
    }
    
    var techAverageScore: Int {
        let techSessions = userSessions.filter { $0.kind == .technical }
        guard !techSessions.isEmpty else { return 0 }
        return techSessions.reduce(0) { $0 + $1.score } / techSessions.count
    }
    
    var hrAverageScore: Int {
        let hrSessions = userSessions.filter { $0.kind == .hr }
        guard !hrSessions.isEmpty else { return 0 }
        return hrSessions.reduce(0) { $0 + $1.score } / hrSessions.count
    }

    var bestReadinessScore: Int? {
        userSessions.filter { $0.kind != nil }.map(\.score).max()
    }
}


enum AppTab: String, CaseIterable {
    case home = "Home", practice = "Practice", dashboard = "Dashboard", history = "History", profile = "Profile"

    func icon(isSelected: Bool) -> String {
        switch self {
        case .home:
            return isSelected ? "house.fill" : "house"
        case .practice:
            return isSelected ? "brain.head.profile.fill" : "brain.head.profile"
        case .dashboard:
            return isSelected ? "chart.bar.fill" : "chart.bar"
        case .history:
            return isSelected ? "clock.fill" : "clock"
        case .profile:
            return isSelected ? "person.crop.circle.fill" : "person.crop.circle"
        }
    }

    var icon: String {
        icon(isSelected: false)
    }

    var selectedIcon: String {
        icon(isSelected: true)
    }
}

enum Haptics {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "MOCKEXA_HAPTICS_ENABLED") as? Bool ?? true
    }
    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
