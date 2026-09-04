import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        TabView(selection: $app.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: AppTab.home.icon) }
                .tag(AppTab.home)
            
            NavigationStack(path: $app.practicePath) {
                PracticeHubView()
                    .navigationDestination(for: PracticeKind.self) { PracticeSetupView(kind: $0) }
            }
            .tabItem { Label("Practice", systemImage: AppTab.practice.icon) }
            .tag(AppTab.practice)
            
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: AppTab.dashboard.icon) }
                .tag(AppTab.dashboard)
            
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: AppTab.history.icon) }
                .tag(AppTab.history)
            
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: AppTab.profile.icon) }
                .tag(AppTab.profile)
        }
        .tint(PrepTheme.primary)
    }
}

struct ScreenContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.bottom, 40)
            }
        }
        .foregroundStyle(PrepTheme.darkNavy)
        .toolbarBackground(PrepTheme.background.opacity(0.95), for: .navigationBar)
    }
}

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    
    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 26) {
                // Greeting Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hey, \(auth.currentFirstName) 👋")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(PrepTheme.primary)
                    Text("Ready to level up today?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PrepTheme.darkNavy)
                }
                .padding(.top, 12)
                .staggeredEntrance(delay: 0.04)
                
                // Today's Focus Hero Card
                ZStack {
                    HeroAmbientGlowView()
                    
                    InteractiveTouchCard(maxTilt: 4.5, action: { open(.technical) }) { isPressed in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("TODAY’S FOCUS", systemImage: "scope")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                Text("Technical Interview")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                Text("15 min  •  Technical Interview")
                                    .font(.subheadline)
                                    .foregroundStyle(PrepTheme.textSecondary)
                                PrimaryButtonLabel(title: "Start Practice", icon: "arrow.right", isPressed: isPressed)

                            }
                        }
                    }
                }
                .staggeredEntrance(delay: 0.10)
                
                // Quick Practice Header & Cards
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Quick Practice", action: "See all", onAction: {
                        app.tab = .practice
                    })
                    let kinds: [PracticeKind] = [.gd, .technical, .hr]
                    ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                        PracticeCard(kind: kind) { open(kind) }
                            .staggeredEntrance(delay: 0.16 + Double(index) * 0.06)
                    }
                }
                .staggeredEntrance(delay: 0.16)
                
                // Progress Section
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Your Progress")
                    InteractiveTouchCard(maxTilt: 4.0, action: {
                        app.tab = .dashboard
                    }) { isPressed in
                        GlassCard {
                            HStack(spacing: 16) {
                                ScoreRing(score: app.averageReadinessScore, size: 94)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Placement Readiness")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                    if app.userSessions.isEmpty {
                                        Text("Complete your first practice session")
                                            .font(.subheadline)
                                            .foregroundStyle(PrepTheme.textSecondary)
                                    } else {
                                        Label("\(app.userSessions.count) sessions completed", systemImage: "checkmark.seal.fill")
                                            .foregroundStyle(PrepTheme.success)
                                            .font(.subheadline.bold())
                                    }
                                    Text("Score out of 100")
                                        .font(.caption)
                                        .foregroundStyle(PrepTheme.textSecondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .staggeredEntrance(delay: 0.36)
                
                // Continue Practicing Section
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Continue Practicing")
                    if let latest = app.userSessions.first {
                        NavigationLink {
                            SessionDetailView(session: latest)
                        } label: {
                            InteractiveTouchCardBody(maxTilt: 4.0) { isPressed in
                                SessionCard(session: latest, isPressed: isPressed)
                            }
                        }
                        .buttonStyle(TouchCardButtonStyle())
                    } else {


                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No practice sessions yet")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                Text("Start a technical, HR, or GD interview above to track your history.")
                                    .font(.subheadline)
                                    .foregroundStyle(PrepTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .staggeredEntrance(delay: 0.42)
            }
        }
        .navigationBarHidden(true)
        .task {
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                await app.refreshUserSessions(token: token)
            }
        }
    }
    
    func open(_ kind: PracticeKind) {
        app.tab = .practice
        app.practicePath.append(kind)
    }
}

struct PracticeCardContent: View {
    let kind: PracticeKind
    var isPressed: Bool = false
    var color: Color {
        switch kind {
        case .gd: PrepTheme.primary
        case .technical: Color(red: 37/255, green: 99/255, blue: 235/255)
        case .hr: Color(red: 225/255, green: 29/255, blue: 72/255)
        }
    }
    
    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: kind.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                        .scaleEffect(isPressed ? 1.06 : 1.0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(PrepTheme.darkNavy)
                    Text(kind.subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(PrepTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PrepTheme.textSecondary)
                    .offset(x: isPressed ? 5 : 0)
            }
        }
    }
}

struct PracticeCard: View {
    let kind: PracticeKind
    let action: () -> Void
    
    var body: some View {
        InteractiveTouchCard(maxTilt: 5.0, action: action) { isPressed in
            PracticeCardContent(kind: kind, isPressed: isPressed)
        }
    }
}

struct PracticeHubView: View {
    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Practice")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PrepTheme.darkNavy)
                    Text("Choose your challenge.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(PrepTheme.textSecondary)
                }
                .padding(.top, 12)
                .staggeredEntrance(delay: 0.04)
                
                ForEach(Array(PracticeKind.allCases.enumerated()), id: \.element) { index, kind in
                    NavigationLink(value: kind) {
                        InteractiveTouchCardBody(maxTilt: 5.0) { isPressed in
                            PracticeCardContent(kind: kind, isPressed: isPressed)
                        }
                    }
                    .buttonStyle(TouchCardButtonStyle())
                    .staggeredEntrance(delay: 0.10 + Double(index) * 0.06)
                }
            }
        }
        .navigationBarHidden(true)
    }
}


struct DashboardView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    
    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your Readiness")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                    .padding(.top, 12)
                    .staggeredEntrance(delay: 0.04)
                
                GlassCard {
                    VStack(spacing: 16) {
                        Text("PLACEMENT READINESS")
                            .font(.caption.bold())
                            .foregroundStyle(PrepTheme.primary)
                        ScoreRing(score: app.averageReadinessScore)
                        Text(app.userSessions.isEmpty ? "Complete practice to see readiness." : "Calculated from completed sessions.")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(PrepTheme.darkNavy)
                    }
                    .frame(maxWidth: .infinity)
                }
                .staggeredEntrance(delay: 0.10)
                
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Performance Trend")
                    TrendChart()
                }
                .staggeredEntrance(delay: 0.18)
                
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Breakdown")
                    GlassCard {
                        VStack(spacing: 16) {
                            let gdHasSessions = app.userSessions.contains { $0.kind == .gd }
                            let techHasSessions = app.userSessions.contains { $0.kind == .technical }
                            let hrHasSessions = app.userSessions.contains { $0.kind == .hr }
                            
                            MetricBar(title: "Group Discussion", value: app.gdAverageScore, color: PrepTheme.primary, hasSessions: gdHasSessions)
                            MetricBar(title: "Technical Interview", value: app.techAverageScore, color: Color(red: 37/255, green: 99/255, blue: 235/255), hasSessions: techHasSessions)
                            MetricBar(title: "HR Interview", value: app.hrAverageScore, color: Color(red: 225/255, green: 29/255, blue: 72/255), hasSessions: hrHasSessions)
                        }
                    }
                }
                .staggeredEntrance(delay: 0.26)
                
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Summary")
                    HStack(spacing: 12) {
                        StatTile(value: "\(app.userSessions.count)", label: "Sessions")
                        StatTile(value: "\(app.averageReadinessScore)", label: "Avg Score")
                        StatTile(value: "Active", label: "Account")
                    }
                }
                .staggeredEntrance(delay: 0.32)
            }
        }
        .navigationBarHidden(true)
        .task {
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                await app.refreshUserSessions(token: token)
            }
        }
    }
}

struct TrendChart: View {
    @EnvironmentObject var app: AppModel
    @State private var trimEnd: CGFloat = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var points: [Double] {
        guard !app.userSessions.isEmpty else { return [] }
        let reversed = Array(app.userSessions.reversed())
        let scores = reversed.map { Double($0.score) / 100.0 }
        if scores.count <= 4 {
            return scores
        }
        return Array(scores.suffix(4))
    }
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if points.isEmpty {
                    VStack(spacing: 8) {
                        Text("No performance trend yet")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(PrepTheme.darkNavy)
                        Text("Complete practice sessions to visualize your score progression.")
                            .font(.caption)
                            .foregroundStyle(PrepTheme.textSecondary)
                    }
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                } else {
                    GeometryReader { geo in
                        ZStack {
                            ForEach(0..<4) { i in
                                Path { p in
                                    let y = geo.size.height * CGFloat(i) / 3
                                    p.move(to: .init(x: 0, y: y))
                                    p.addLine(to: .init(x: geo.size.width, y: y))
                                }
                                .stroke(PrepTheme.border)
                            }
                            Path { p in
                                let total = max(1, points.count - 1)
                                for (i, value) in points.enumerated() {
                                    let x = points.count == 1 ? geo.size.width / 2 : (geo.size.width * CGFloat(i) / CGFloat(total))
                                    let y = geo.size.height * (1 - CGFloat(min(max(value, 0.0), 1.0)))
                                    i == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
                                }
                            }
                            .trim(from: 0, to: trimEnd)
                            .stroke(PrepTheme.gradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .frame(height: 130)
                    
                    HStack {
                        ForEach(0..<points.count, id: \.self) { idx in
                            Text("S\(idx + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(PrepTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion {
                trimEnd = 1.0
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.12)) {
                    trimEnd = 1.0
                }
            }
        }
    }
}


struct MetricBar: View {
    let title: String
    let value: Int
    let color: Color
    var hasSessions: Bool = true
    @State private var animatedValue: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                Spacer()
                Text(hasSessions ? "\(value)%" : "Not Started")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(hasSessions ? PrepTheme.primary : PrepTheme.textSecondary)
            }
            ProgressView(value: animatedValue, total: 100)
                .tint(color)
        }
        .onAppear {
            let target = hasSessions ? Double(value) : 0
            if reduceMotion {
                animatedValue = target
            } else {
                withAnimation(.easeOut(duration: 0.85).delay(0.1)) {
                    animatedValue = target
                }
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PrepTheme.darkNavy)
            Text(label)
                .font(.caption)
                .foregroundStyle(PrepTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(PrepTheme.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }
}

struct HistoryView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    @State private var filter = "All"
    
    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 20) {
                Text("Practice History")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                    .padding(.top, 12)
                    .staggeredEntrance(delay: 0.04)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(["All", "GD", "Technical", "HR"], id: \.self) { item in
                            Button(item) {
                                Haptics.selection()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    filter = item
                                }
                            }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(filter == item ? PrepTheme.primary : PrepTheme.surface, in: Capsule())
                            .overlay(Capsule().stroke(filter == item ? Color.clear : PrepTheme.border, lineWidth: 1))
                            .foregroundStyle(filter == item ? .white : PrepTheme.darkNavy)
                        }
                    }
                }
                .staggeredEntrance(delay: 0.10)
                
                let filtered = app.userSessions.filter { session in
                    guard let kind = session.kind else { return false }
                    switch filter {
                    case "GD": return kind == .gd
                    case "Technical": return kind == .technical
                    case "HR": return kind == .hr
                    default: return true
                    }
                }
                
                if filtered.isEmpty {
                    GlassCard {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(PrepTheme.primary.opacity(0.1))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "clock.badge.exclamationmark")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(PrepTheme.primary)
                            }
                            .padding(.top, 8)
                            
                            VStack(spacing: 6) {
                                Text("No Sessions Yet")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                
                                Text(filter == "All" ? "Complete a practice session and your results will appear here." : "No \(filter) sessions recorded yet. Complete a session to see your progress.")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(PrepTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                            
                            Button {
                                Haptics.selection()
                                app.tab = .practice
                            } label: {
                                Label("Start Practice", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(PrepTheme.gradient, in: Capsule())
                                    .shadow(color: PrepTheme.primary.opacity(0.25), radius: 8, y: 4)
                            }
                            .padding(.bottom, 8)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    }
                    .staggeredEntrance(delay: 0.16)
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            InteractiveTouchCardBody(maxTilt: 4.0) { isPressed in
                                SessionCard(session: session, isPressed: isPressed)
                            }
                        }
                        .buttonStyle(TouchCardButtonStyle())
                        .staggeredEntrance(delay: 0.16 + Double(index) * 0.06)
                    }

                }
            }
        }
        .navigationBarHidden(true)
        .task {
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                await app.refreshUserSessions(token: token)
            }
        }
    }
}

struct SessionCard: View {
    let session: PracticeSession
    var isPressed: Bool = false
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PrepTheme.primary.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: session.kind?.icon ?? "doc.text.fill")
                        .font(.title3)
                        .foregroundStyle(PrepTheme.primary)
                        .scaleEffect(isPressed ? 1.06 : 1.0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.kind?.displayName ?? "Practice Session")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(PrepTheme.darkNavy)
                    Text("\(session.date)  •  \(session.duration)")
                        .font(.caption)
                        .foregroundStyle(PrepTheme.textSecondary)
                }
                Spacer()
                Text("\(session.score)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.primary)
            }
        }
    }
}

struct SessionDetailView: View {
    let session: PracticeSession
    @EnvironmentObject var auth: AuthManager
    @State private var sessionDetail: SessionDetailItem? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ScreenContainer {
            VStack(spacing: 24) {
                Text(session.kind?.displayName ?? "Practice Session")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .staggeredEntrance(delay: 0.04)
                
                ScoreRing(score: sessionDetail?.score ?? session.score, size: 160)
                    .staggeredEntrance(delay: 0.10)
                
                if let err = errorMessage {
                    Text("Note: \(err)")
                        .font(.caption)
                        .foregroundStyle(PrepTheme.textSecondary)
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailRow(label: "Topic", value: sessionDetail?.topic ?? session.topic)
                        DetailRow(label: "Date", value: sessionDetail?.date ?? session.date)
                        DetailRow(label: "Duration", value: sessionDetail?.duration ?? session.duration)
                        DetailRow(label: "Session ID", value: String(session.id.prefix(8)))
                    }
                }
                .staggeredEntrance(delay: 0.16)
                
                if let k = session.kind {
                    NavigationLink {
                        ReportView(kind: k, detail: sessionDetail)
                    } label: {
                        Text("View Performance Report")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(PrepTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                            .shadow(color: PrepTheme.primary.opacity(0.22), radius: 12, y: 5)
                    }
                    .staggeredEntrance(delay: 0.22)
                }
                
                if let transcriptItems = sessionDetail?.transcript, !transcriptItems.isEmpty {
                    NavigationLink {
                        TranscriptView(
                            entries: transcriptItems.map { TranscriptEntry(speaker: $0.speaker, text: $0.text, timestamp: "Recorded") }
                        )
                    } label: {
                        SecondaryButton(title: "View Session Transcript") {}
                    }
                    .staggeredEntrance(delay: 0.28)
                }
            }
        }
        .task {
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                isLoading = true
                do {
                    let detail = try await APIClient.shared.fetchSessionDetail(sessionId: session.id, token: token)
                    self.sessionDetail = detail
                } catch {
                    self.errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }
}


struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(PrepTheme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundStyle(PrepTheme.darkNavy)
        }
    }
}

enum ProfileSheetDestination: String, Identifiable {
    case myProfile, targetRole, targetCompanies, practicePreferences, accessibility, accountSettings
    var id: String { rawValue }
}

struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var app: AppModel
    
    @State private var activeSheet: ProfileSheetDestination? = nil
    @State private var showSignOutConfirmation: Bool = false
    
    @AppStorage("PREPAI_TARGET_ROLE") private var targetRole: String = ""
    @AppStorage("PREPAI_TARGET_COMPANIES") private var targetCompanies: String = ""
    @AppStorage("PREPAI_PRACTICE_PREF") private var practicePref: String = ""

    var body: some View {
        ScreenContainer {
            VStack(spacing: 20) {
                Text("Profile")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .staggeredEntrance(delay: 0.04)
                
                // Profile Header
                HStack(spacing: 16) {
                    AIAvatar(initials: auth.profileInitials, color: PrepTheme.primary)
                        .scaleEffect(1.2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.profileDisplayName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(PrepTheme.darkNavy)
                        Text(auth.currentUserEmail.isEmpty ? "Candidate" : auth.currentUserEmail)
                            .font(.subheadline)
                            .foregroundStyle(PrepTheme.textSecondary)
                        
                        if let age = auth.currentUserAge {
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Age: \(age)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PrepTheme.primary.opacity(0.12), in: Capsule())
                            .foregroundStyle(PrepTheme.primary)
                            .padding(.top, 2)
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(PrepTheme.border, lineWidth: 1))
                .staggeredEntrance(delay: 0.10)
                
                // Preparation Snapshot
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeader(title: "Preparation Snapshot")
                        Spacer()
                        Text("Completed Sessions")
                            .font(.caption.bold())
                            .foregroundStyle(PrepTheme.textSecondary)
                    }
                    GlassCard {
                        HStack(spacing: 8) {
                            StatTile(value: "\(app.userSessions.filter { $0.kind != nil }.count)", label: "Total")
                            StatTile(value: "\(app.userSessions.filter { $0.kind == .gd }.count)", label: "GD")
                            StatTile(value: "\(app.userSessions.filter { $0.kind == .technical }.count)", label: "Tech")
                            StatTile(value: "\(app.userSessions.filter { $0.kind == .hr }.count)", label: "HR")
                        }
                    }
                }
                .staggeredEntrance(delay: 0.16)
                
                // Profile & Goals Section
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Profile & Goals")
                    GlassCard {
                        VStack(spacing: 0) {
                            ProfileRowButton(icon: "person.fill", title: "My Profile", subtitle: auth.profileDisplayName) {
                                activeSheet = .myProfile
                            }
                            Divider().overlay(PrepTheme.border)
                            
                            ProfileRowButton(icon: "scope", title: "Target Role", subtitle: targetRole.isEmpty ? "Not set • Tap to select" : targetRole) {
                                activeSheet = .targetRole
                            }
                            Divider().overlay(PrepTheme.border)
                            
                            ProfileRowButton(icon: "building.2.fill", title: "Target Companies", subtitle: targetCompanies.isEmpty ? "Not set • Tap to select" : targetCompanies) {
                                activeSheet = .targetCompanies
                            }
                            Divider().overlay(PrepTheme.border)
                            
                            ProfileRowButton(icon: "slider.horizontal.3", title: "Practice Preferences", subtitle: practicePref.isEmpty ? "Not set • Tap to configure" : practicePref) {
                                activeSheet = .practicePreferences
                            }
                        }
                    }
                }
                .staggeredEntrance(delay: 0.22)
                
                // Account & Settings Section
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Account")
                    GlassCard {
                        VStack(spacing: 0) {
                            ProfileRowButton(icon: "accessibility", title: "Accessibility", subtitle: "Motion & Display Settings") {
                                activeSheet = .accessibility
                            }
                            Divider().overlay(PrepTheme.border)
                            
                            ProfileRowButton(icon: "gearshape.fill", title: "Account Settings", subtitle: auth.currentUserEmail.isEmpty ? "Account Information" : auth.currentUserEmail) {
                                activeSheet = .accountSettings
                            }
                        }
                    }
                }
                .staggeredEntrance(delay: 0.26)
                
                // Sign Out Button
                Button {
                    showSignOutConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(PrepTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 25))
                    .overlay(RoundedRectangle(cornerRadius: 25).stroke(PrepTheme.destructive.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(PrepTheme.destructive)
                }
                .buttonStyle(PressButtonStyle())
                .padding(.top, 4)
                .staggeredEntrance(delay: 0.30)
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog("Sign out of Mockexa?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                auth.signOut()
                app.userSessions = []
                app.onboardingStep = 0
                withAnimation {
                    app.route = .welcome
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $activeSheet) { destination in
            switch destination {
            case .myProfile:
                MyProfileSheet()
            case .targetRole:
                TargetRoleSheet(targetRole: $targetRole)
            case .targetCompanies:
                TargetCompaniesSheet(targetCompanies: $targetCompanies)
            case .practicePreferences:
                PracticePreferencesSheet(practicePref: $practicePref)
            case .accessibility:
                AccessibilitySettingsSheet()
            case .accountSettings:
                AccountSettingsSheet()
            }
        }
    }
}

struct ProfileRowButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(PrepTheme.primary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PrepTheme.darkNavy)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(PrepTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PrepTheme.textSecondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Sheets

struct MyProfileSheet: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var fullNameText: String = ""
    @State private var ageText: String = ""
    @State private var saveSuccess: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        AIAvatar(initials: auth.profileInitials, color: PrepTheme.primary)
                            .scaleEffect(1.4)
                            .padding(.top, 12)
                        
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("PERSONAL INFORMATION")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Full Name")
                                        .font(.caption)
                                        .foregroundStyle(PrepTheme.textSecondary)
                                    TextField("Enter full name", text: $fullNameText)
                                        .padding(12)
                                        .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PrepTheme.border, lineWidth: 1))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                }
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Age")
                                        .font(.caption)
                                        .foregroundStyle(PrepTheme.textSecondary)
                                    TextField("Enter age", text: $ageText)
                                        .keyboardType(.numberPad)
                                        .padding(12)
                                        .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PrepTheme.border, lineWidth: 1))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                }
                                
                                DetailRow(label: "Email", value: auth.currentUserEmail.isEmpty ? "Not set" : auth.currentUserEmail)
                                
                                if saveSuccess {
                                    Text("Profile saved successfully!")
                                        .font(.caption.bold())
                                        .foregroundStyle(PrepTheme.success)
                                }
                            }
                        }
                        
                        PrimaryButton(title: "Save Profile", icon: "checkmark") {
                            let name = fullNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ageVal = Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines))
                            if !name.isEmpty {
                                auth.currentUserFullName = name
                            }
                            auth.currentUserAge = ageVal
                            saveSuccess = true
                            Haptics.success()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PrepTheme.primary)
                }
            }
            .onAppear {
                fullNameText = auth.currentUserFullName
                if let age = auth.currentUserAge {
                    ageText = "\(age)"
                }
            }
        }
    }
}

struct TargetRoleSheet: View {
    @Binding var targetRole: String
    @Environment(\.dismiss) private var dismiss
    
    let roles = ["Software Engineer", "Data Analyst", "Product Manager", "Business Analyst", "System Architect", "Full Stack Developer"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select your primary target role for tailored interview questions.")
                            .font(.subheadline)
                            .foregroundStyle(PrepTheme.textSecondary)
                            .padding(.top, 12)
                        
                        GlassCard {
                            VStack(spacing: 0) {
                                ForEach(Array(roles.enumerated()), id: \.offset) { idx, role in
                                    Button {
                                        Haptics.selection()
                                        targetRole = role
                                    } label: {
                                        HStack {
                                            Text(role)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(PrepTheme.darkNavy)
                                            Spacer()
                                            if targetRole == role {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(PrepTheme.primary)
                                            }
                                        }
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if idx < roles.count - 1 {
                                        Divider().overlay(PrepTheme.border)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Target Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.bold())
                        .foregroundStyle(PrepTheme.primary)
                }
            }
        }
    }
}

struct TargetCompaniesSheet: View {
    @Binding var targetCompanies: String
    @Environment(\.dismiss) private var dismiss
    
    let allCompanies = ["Google", "Microsoft", "Amazon", "Meta", "Apple", "Uber", "Product Startups"]
    @State private var selectedSet = Set<String>()
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select target companies to prioritize relevant question patterns.")
                            .font(.subheadline)
                            .foregroundStyle(PrepTheme.textSecondary)
                            .padding(.top, 12)
                        
                        GlassCard {
                            VStack(spacing: 0) {
                                ForEach(Array(allCompanies.enumerated()), id: \.offset) { idx, comp in
                                    Button {
                                        Haptics.selection()
                                        if selectedSet.contains(comp) {
                                            selectedSet.remove(comp)
                                        } else {
                                            selectedSet.insert(comp)
                                        }
                                        updateBinding()
                                    } label: {
                                        HStack {
                                            Text(comp)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(PrepTheme.darkNavy)
                                            Spacer()
                                            if selectedSet.contains(comp) {
                                                Image(systemName: "checkmark.square.fill")
                                                    .foregroundStyle(PrepTheme.primary)
                                            } else {
                                                Image(systemName: "square")
                                                    .foregroundStyle(PrepTheme.textSecondary)
                                            }
                                        }
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if idx < allCompanies.count - 1 {
                                        Divider().overlay(PrepTheme.border)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Target Companies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.bold())
                        .foregroundStyle(PrepTheme.primary)
                }
            }
            .onAppear {
                let existing = targetCompanies.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                selectedSet = Set(existing.filter { !$0.isEmpty })
            }
        }
    }
    
    private func updateBinding() {
        if selectedSet.isEmpty {
            targetCompanies = ""
        } else {
            targetCompanies = selectedSet.sorted().joined(separator: ", ")
        }
    }
}

struct PracticePreferencesSheet: View {
    @Binding var practicePref: String
    @Environment(\.dismiss) private var dismiss
    
    let preferences = [
        "Adaptive • 10 min",
        "Focused Technical • 15 min",
        "Behavioral HR • 10 min",
        "GD Leadership • 15 min"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Configure your default session duration and focus mode.")
                            .font(.subheadline)
                            .foregroundStyle(PrepTheme.textSecondary)
                            .padding(.top, 12)
                        
                        GlassCard {
                            VStack(spacing: 0) {
                                ForEach(Array(preferences.enumerated()), id: \.offset) { idx, pref in
                                    Button {
                                        Haptics.selection()
                                        practicePref = pref
                                    } label: {
                                        HStack {
                                            Text(pref)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(PrepTheme.darkNavy)
                                            Spacer()
                                            if practicePref == pref {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(PrepTheme.primary)
                                            }
                                        }
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if idx < preferences.count - 1 {
                                        Divider().overlay(PrepTheme.border)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Practice Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.bold())
                        .foregroundStyle(PrepTheme.primary)
                }
            }
        }
    }
}

struct AccessibilitySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("PREPAI_HAPTICS_ENABLED") private var hapticsEnabled: Bool = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Customize motion effects and tactile feedback preferences.")
                            .font(.subheadline)
                            .foregroundStyle(PrepTheme.textSecondary)
                            .padding(.top, 12)
                        
                        GlassCard {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Reduce Motion")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(PrepTheme.darkNavy)
                                        Text("System Setting: \(reduceMotion ? "Enabled" : "Disabled")")
                                            .font(.caption)
                                            .foregroundStyle(PrepTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: reduceMotion ? "checkmark.seal.fill" : "app.badge.checkmark")
                                        .foregroundStyle(reduceMotion ? PrepTheme.primary : PrepTheme.textSecondary)
                                }
                                
                                Divider().overlay(PrepTheme.border)
                                
                                Toggle(isOn: $hapticsEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Haptic Feedback")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(PrepTheme.darkNavy)
                                        Text("Tactile responses on button selections")
                                            .font(.caption)
                                            .foregroundStyle(PrepTheme.textSecondary)
                                    }
                                }
                                .tint(PrepTheme.primary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.bold())
                        .foregroundStyle(PrepTheme.primary)
                }
            }
        }
    }
}

struct AccountSettingsSheet: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("ACCOUNT INFORMATION")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                
                                DetailRow(label: "Account Email", value: auth.currentUserEmail.isEmpty ? "Not set" : auth.currentUserEmail)
                                DetailRow(label: "Account Status", value: auth.isAuthenticated ? "Active Account" : "Signed Out")
                                DetailRow(label: "Security", value: "Encrypted Session")
                            }
                        }
                        
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PRIVACY & DATA")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                
                                Text("Your session history and onboarding metadata are managed securely in your active profile account.")
                                    .font(.subheadline)
                                    .foregroundStyle(PrepTheme.textSecondary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Account Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PrepTheme.primary)
                }
            }
        }
    }
}
