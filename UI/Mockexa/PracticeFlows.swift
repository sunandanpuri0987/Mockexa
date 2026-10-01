import SwiftUI
import Combine

struct PracticeSetupView: View {
    let kind: PracticeKind
    @EnvironmentObject var auth: AuthManager
    @State private var selection: String
    @State private var duration: String
    @State private var company: String
    @State private var gdExperience = "ai"
    @State private var gdStarter = "AI starts"
    @State private var friendsAction = "create"
    @State private var roomCode = ""
    @State private var useActiveResume = true

    private var activeResumeContext: (context: String, role: String, jobDescription: String, name: String)? {
        ResumeViewModel.getActiveResumeContext()
    }

    private var supportsResumePersonalization: Bool {
        kind != .gd || gdExperience == "ai"
    }

    init(kind: PracticeKind) {
        self.kind = kind
        switch kind {
        case .gd:
            _selection = State(initialValue: "Remote work and productivity")
            _duration = State(initialValue: "10 min")
            _company = State(initialValue: "balanced")
        case .technical:
            _selection = State(initialValue: "Data Structures")
            _duration = State(initialValue: "Medium")
            _company = State(initialValue: "")
        case .hr:
            _selection = State(initialValue: "General HR")
            _duration = State(initialValue: "10 min")
            _company = State(initialValue: "Voice")
        }
    }

    private static let gdTopics = [
        "Remote work and productivity",
        "Should AI replace repetitive jobs?",
        "Should social media platforms verify every user?",
        "Is a four-day workweek practical for India?",
        "Should college education be free?",
        "Can online learning replace classrooms?",
        "Should governments regulate generative AI?",
        "Is nuclear energy essential for climate goals?",
        "Should voting be compulsory?",
        "Are electric vehicles truly sustainable?",
        "Should companies prioritize skills over degrees?",
        "Is remote healthcare better for rural communities?",
        "Should personal data be treated as private property?",
        "Can India become a fully cashless economy?",
        "Should influencers be accountable for harmful advice?",
        "Is competition better than collaboration at work?",
        "Should public transport be free in major cities?",
        "Will automation create more jobs than it removes?",
        "Should internships always be paid?",
        "Is work-life balance more important than rapid career growth?"
    ]

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(setupTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    Text(setupSubtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
                .padding(.top, 8)

                options

                if supportsResumePersonalization, let active = activeResumeContext {
                    Toggle(isOn: $useActiveResume) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Use Selected Resume (\(active.name))", systemImage: "doc.text.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.darkNavy)
                            Text(active.jobDescription.isEmpty
                                 ? "Interview tailored to \(active.name)."
                                 : "Interview tailored to \(active.name) & targeted JD.")
                                .font(.caption)
                                .foregroundStyle(MockexaTheme.textSecondary)
                        }
                    }
                    .tint(MockexaTheme.primary)
                    .padding(14)
                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(useActiveResume ? MockexaTheme.primary : MockexaTheme.border))
                }

                setupSummary

                NavigationLink {
                    destination
                } label: {
                    Text(startTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(MockexaTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                        .shadow(color: MockexaTheme.primary.opacity(0.22), radius: 12, y: 5)
                }
                .disabled(gdStartDisabled)
                .opacity(gdStartDisabled ? 0.5 : 1)
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    var setupTitle: String {
        switch kind {
        case .gd: "Set up your GD"
        case .technical: "Technical Interview"
        case .hr: "HR Interview"
        }
    }

    var setupSubtitle: String {
        switch kind {
        case .gd: "Shape the room before you enter it."
        case .technical: "Choose your challenge."
        case .hr: "Pick a conversation style."
        }
    }

    var startTitle: String {
        if kind == .technical { return "Start Technical Interview" }
        if kind == .hr { return "Start HR Interview" }
        if gdExperience == "online" { return "Find Online Group" }
        if gdExperience == "friends" { return friendsAction == "join" ? "Join Friends Room" : "Create Friends Room" }
        return "Meet Your AI Panel"
    }

    @ViewBuilder private var setupSummary: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("YOUR SETUP", systemImage: "checklist")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Text(summaryTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(MockexaTheme.darkNavy)
                Text(summaryDetail)
                    .font(.caption)
                    .foregroundStyle(MockexaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryTitle: String {
        switch kind {
        case .gd:
            if gdExperience == "online" { return "Online group • \(duration) • \(panelModeTitle)" }
            if gdExperience == "friends" { return "Friends room • \(duration) • \(panelModeTitle)" }
            return "AI panel • \(duration) • \(panelModeTitle)"
        case .technical:
            return "\(selection) • \(duration) difficulty"
        case .hr:
            return "\(selection) • \(company) responses"
        }
    }

    private var summaryDetail: String {
        switch kind {
        case .gd:
            if gdExperience == "online" { return "You will be matched with 4 candidates; the room can grow to 6. The topic is revealed after matching." }
            if gdExperience == "friends" && friendsAction == "join" { return "Enter a valid six-character code to join your friends' private room." }
            if gdExperience == "friends" { return "Create a private room, share its code, and start after at least three participants are ready." }
            return gdStarter == "AI starts" ? "An AI panelist will frame the topic before the debate begins." : "You will deliver the opening view before the panel responds."
        case .technical:
            switch duration {
            case "Easy": return "Focuses on fundamentals, clear reasoning, and a correct baseline solution."
            case "Hard": return "Expect deeper constraints, trade-offs, edge cases, and optimization questions."
            default: return "Balances core concepts with follow-up reasoning and implementation trade-offs."
            }
        case .hr:
            let style: String
            switch selection {
            case "Behavioral": style = "Uses past-experience questions and expects structured, evidence-based answers."
            case "Leadership": style = "Explores ownership, influence, conflict handling, and decision-making."
            case "Situational": style = "Tests how you would respond to realistic workplace scenarios."
            case "Stress Interview": style = "Uses pressure and challenging follow-ups while keeping the evaluation fair."
            default: style = "Covers motivation, fit, communication, strengths, and career direction."
            }
            return "\(style) Answer using \(company.lowercased()) mode."
        }
    }

    private var panelModeTitle: String {
        company == "consensus" ? "Consensus building" : "Balanced debate"
    }

    var gdStartDisabled: Bool {
        guard kind == .gd else { return false }
        if gdExperience == "friends" && friendsAction == "join" { return roomCode.count != 6 }
        return selection.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
    }

    @ViewBuilder var options: some View {
        if kind == .gd {
            GDExperiencePicker(selection: $gdExperience)
            if gdExperience == "friends" {
                OptionGroup(title: "Friends Room", values: ["create", "join"], selection: $friendsAction)
                if friendsAction == "join" {
                    TextField("Enter 6-character room code", text: $roomCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: roomCode) { _, value in roomCode = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)) }
                        .padding(14)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.border))
                }
            }
            if gdExperience != "friends" || friendsAction == "create" {
                if gdExperience != "online" {
                    GDTopicSelector(topic: $selection, topics: Self.gdTopics, onRandom: chooseRandomGDTopic)
                } else {
                    Text("A random interview-style topic is revealed when 4 users are matched. Up to 6 can join.")
                        .font(.subheadline).foregroundStyle(MockexaTheme.textSecondary)
                }
                OptionGroup(title: "Duration", values: ["5 min", "10 min", "15 min"], selection: $duration)
                GDPanelModePicker(selection: $company)
                if gdExperience == "ai" {
                    OptionGroup(title: "Who starts the discussion?", values: ["AI starts", "I start"], selection: $gdStarter)
                    Text(gdStarter == "I start"
                         ? "You will give the opening view. The panel will respond to your exact point."
                         : "The first panelist will introduce themselves, frame the topic, and open the discussion.")
                        .font(.caption)
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
            }
        } else if kind == .technical {
            OptionGroup(title: "Domain", values: ["Data Structures", "Algorithms", "Operating Systems", "DBMS", "OOP", "Software Engineering", "Programming"], selection: $selection)
            OptionGroup(title: "Difficulty", values: ["Easy", "Medium", "Hard"], selection: $duration)
        } else {
            OptionGroup(title: "Interview Style", values: ["General HR", "Behavioral", "Leadership", "Situational", "Stress Interview"], selection: $selection)
            OptionGroup(title: "Response Mode", values: ["Voice", "Type"], selection: $company)
        }
    }

    private func chooseRandomGDTopic() {
        let alternatives = Self.gdTopics.filter { $0 != selection }
        if let topic = alternatives.randomElement() ?? Self.gdTopics.randomElement() {
            Haptics.selection()
            selection = topic
        }
    }

    @ViewBuilder var destination: some View {
        if kind == .gd {
            if gdExperience == "ai" {
                PanelView(
                    topic: selection,
                    durationStr: duration,
                    modeStr: company,
                    aiStarts: gdStarter == "AI starts",
                    resumeContext: useActiveResume ? activeResumeContext?.context : "",
                    jobDescription: useActiveResume ? activeResumeContext?.jobDescription : ""
                )
            } else {
                FriendsGDRoomView(
                    intent: gdExperience == "online" ? .matchmaking : (friendsAction == "join" ? .join : .create),
                    topic: selection, durationStr: duration, mode: company, roomCode: roomCode
                )
            }
        } else {
            LiveInterviewView(
                kind: kind,
                selectedDomain: selection,
                difficultyStr: duration,
                modeStr: company,
                resumeContext: useActiveResume ? activeResumeContext?.context : "",
                jobDescription: useActiveResume ? activeResumeContext?.jobDescription : "",
                targetRole: useActiveResume ? activeResumeContext?.role : nil
            )
        }
    }
}

private struct GDExperiencePicker: View {
    @Binding var selection: String
    private let choices = [
        ("ai", "AI Panel", "cpu.fill", "Practice instantly with four AI personalities."),
        ("friends", "Friends Room", "person.3.fill", "Create or join a private room; minimum 3 friends."),
        ("online", "Find Online Group", "globe.asia.australia.fill", "Auto-match with 4–6 online candidates."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How do you want to practice?").font(.system(size: 17, weight: .bold, design: .rounded))
            ForEach(choices, id: \.0) { item in
                Button { selection = item.0; Haptics.selection() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.2).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.1).font(.subheadline.bold())
                            Text(item.3).font(.caption).foregroundStyle(selection == item.0 ? .white.opacity(0.85) : MockexaTheme.textSecondary)
                        }
                        Spacer(); Image(systemName: selection == item.0 ? "checkmark.circle.fill" : "circle")
                    }
                    .padding(14).foregroundStyle(selection == item.0 ? .white : MockexaTheme.darkNavy)
                    .background(selection == item.0 ? MockexaTheme.primary : MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct GDTopicSelector: View {
    @Binding var topic: String
    let topics: [String]
    let onRandom: () -> Void
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        let query = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard focused, !query.isEmpty else { return [] }
        return topics.filter { candidate in
            let lowered = candidate.lowercased()
            return lowered.hasPrefix(query)
                || lowered.split(separator: " ").contains(where: { $0.hasPrefix(query) })
                || lowered.contains(query)
        }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discussion Topic")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                Spacer()
                Button(action: onRandom) {
                    Label("Random", systemImage: "dice.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .tint(MockexaTheme.primary)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MockexaTheme.textSecondary)
                TextField("Type any topic, e.g. Remote work…", text: $topic)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                if !topic.isEmpty {
                    Button {
                        topic = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MockexaTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? MockexaTheme.primary : MockexaTheme.border, lineWidth: focused ? 1.5 : 1))

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            Haptics.selection()
                            topic = suggestion
                            focused = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "text.badge.checkmark")
                                    .foregroundStyle(MockexaTheme.primary)
                                Text(suggestion)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        }
                        if suggestion != suggestions.last {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.border, lineWidth: 1))
            } else if !focused {
                Text("Enter your own topic, choose a suggestion, or let Random pick one.")
                    .font(.caption)
                    .foregroundStyle(MockexaTheme.textSecondary)
            }
        }
    }
}

private struct GDPanelModePicker: View {
    @Binding var selection: String

    private let modes: [(id: String, title: String, icon: String, description: String)] = [
        (
            "balanced",
            "Balanced Debate",
            "scale.3d",
            "Independent viewpoints stay strong. Expect evidence, direct counterarguments, and no forced agreement."
        ),
        (
            "consensus",
            "Consensus Building",
            "person.3.sequence.fill",
            "The panel debates first, then tests compromises, safeguards, and a practical common position."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Panel Mode")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(MockexaTheme.darkNavy)

            ForEach(modes, id: \.id) { mode in
                Button {
                    Haptics.selection()
                    selection = mode.id
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(selection == mode.id ? .white : MockexaTheme.primary)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(selection == mode.id ? Color.white.opacity(0.85) : MockexaTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: selection == mode.id ? "checkmark.circle.fill" : "circle")
                    }
                    .foregroundStyle(selection == mode.id ? .white : MockexaTheme.darkNavy)
                    .padding(14)
                    .background(selection == mode.id ? MockexaTheme.primary : MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(selection == mode.id ? Color.clear : MockexaTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct OptionGroup: View {
    let title: String
    let values: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(MockexaTheme.darkNavy)
            FlowLayout(spacing: 9) {
                ForEach(values, id: \.self) { item in
                    Button(item) {
                        Haptics.selection()
                        selection = item
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(selection == item ? MockexaTheme.primary : MockexaTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(selection == item ? Color.clear : MockexaTheme.border, lineWidth: 1))
                    .foregroundStyle(selection == item ? .white : MockexaTheme.darkNavy)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (i, p) in result.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? 360
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var points: [CGPoint] = []

        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                x = 0
                y += row + spacing
                row = 0
            }
            points.append(CGPoint(x: x, y: y))
            row = max(row, s.height)
            x += s.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + row), points)
    }
}


enum GDInputMode: String, CaseIterable, Identifiable {
    case voice = "Voice"
    case text = "Type"
    var id: String { rawValue }
}

struct PanelView: View {
    let topic: String
    var durationStr: String = "10 min"
    var modeStr: String = "balanced"
    var aiStarts: Bool = true
    var resumeContext: String? = nil
    var jobDescription: String? = nil
    @StateObject private var gdVM = GDViewModel()
    @StateObject private var voice = VoiceFoundation.shared
    @EnvironmentObject var auth: AuthManager

    @State private var inputMode: GDInputMode = .voice
    @State private var userTextContribution: String = ""
    @State private var showEnd: Bool = false
    @State private var navigateToReport: Bool = false
    @State private var sessionEndedByTimer: Bool = false
    @State private var sessionClockStarted: Bool = false
    @State private var sessionDeadline: Date? = nil
    @State private var didRequestAIConclusion: Bool = false
    @State private var userConcluded: Bool = false
    @FocusState private var isInputFocused: Bool

    @State private var remainingSeconds: Int = 600
    private let timerPublisher = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var initialSeconds: Int {
        let digits = durationStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        let mins = Int(digits) ?? 10
        return mins * 60
    }

    var formattedTime: String {
        let m = max(0, remainingSeconds) / 60
        let s = max(0, remainingSeconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var conversationHistoryEntries: [TranscriptEntry] {
        guard let current = gdVM.currentTurn, let last = gdVM.transcriptEntries.last,
              last.speaker == current.speaker, last.text == current.response else {
            return gdVM.transcriptEntries
        }
        return Array(gdVM.transcriptEntries.dropLast())
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // MARK: - 1. SESSION HEADER
                GDSessionHeader(
                    topic: topic,
                    formattedTime: formattedTime,
                    remainingSeconds: remainingSeconds,
                    currentRound: gdVM.currentTurn?.round ?? 1,
                    isGenerating: gdVM.isGeneratingTurn
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // MARK: - 2. INTERACTIVE DISCUSSION ROOM TABLE
                        GDDiscussionRoomView(
                            participants: gdVM.participants,
                            currentSpeakerIndex: gdVM.currentSpeakerIndex,
                            isGenerating: gdVM.isGeneratingTurn,
                            isAISpeaking: voice.isSpeaking,
                            isUserListening: voice.currentState == .listening
                        )

                        if sessionClockStarted && remainingSeconds <= 60 && remainingSeconds > 0 {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label("CLOSING PHASE", systemImage: "flag.checkered")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.warning)
                                    Text("Give your final synthesis: common ground, the key trade-off, and one practical recommendation.")
                                        .font(.subheadline)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !userConcluded && !didRequestAIConclusion {
                                        Button {
                                            requestAIConclusion()
                                        } label: {
                                            Label("Ask AI to Conclude", systemImage: "sparkles")
                                                .font(.caption.bold())
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(MockexaTheme.primary)
                                        .disabled(gdVM.isGeneratingTurn || voice.isSpeaking)
                                    } else {
                                        Text(userConcluded ? "Your closing contribution is recorded." : "AI is preparing the closing synthesis.")
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.success)
                                    }
                                }
                            }
                        }

                        // MARK: - 3. COMPACT CONTEXTUAL ERROR BANNER
                        if let error = gdVM.errorMessage {
                            GDContextualErrorView(errorMessage: error) {
                                if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                                    voice.setProcessing()
                                    Task {
                                        if gdVM.sessionId == nil {
                                            await startSession(token: token)
                                        } else {
                                            await gdVM.requestNextTurn(token: token)
                                        }
                                    }
                                } else {
                                    gdVM.errorMessage = "Please log in to start a Group Discussion session."
                                }
                            }
                        }

                        // MARK: - 4. CENTRAL DISCUSSION PANEL (FEATURED & FEED)
                        VStack(spacing: 12) {
                            if let turn = gdVM.currentTurn {
                                GDFeaturedContributionCard(
                                    turn: turn,
                                    participants: gdVM.participants,
                                    currentSpeakerIndex: gdVM.currentSpeakerIndex,
                                    isAISpeaking: voice.isSpeaking,
                                    onInterrupt: {
                                        gdVM.recordInterruption()
                                        voice.interruptAndListen()
                                    }
                                )
                            } else if gdVM.isGeneratingTurn {
                                GlassCard {
                                    HStack(spacing: 12) {
                                        ProgressView().tint(MockexaTheme.primary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Discussion Starting…")
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(MockexaTheme.darkNavy)
                                            Text("AI panel members are preparing opening positions")
                                                .font(.caption)
                                                .foregroundStyle(MockexaTheme.textSecondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            } else {
                                GlassCard {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.3.sequence.fill")
                                            .font(.system(size: 28))
                                            .foregroundStyle(MockexaTheme.primary)
                                        Text("Welcome to the GD Room")
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundStyle(MockexaTheme.darkNavy)
                                        Text(aiStarts
                                             ? "Tap microphone or pass turn to continue the discussion."
                                             : "You chose to open. Share your view by voice or text; the panel will respond to your point.")
                                            .font(.caption)
                                            .foregroundStyle(MockexaTheme.textSecondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                }
                            }

                            // History feed if prior turns exist
                            if !conversationHistoryEntries.isEmpty {
                                GDConversationFeed(entries: conversationHistoryEntries)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // MARK: - 5. USER INPUT INTERACTION AREA
                VStack(spacing: 12) {
                    GDInputBar(
                        inputMode: $inputMode,
                        userTextContribution: $userTextContribution,
                        isInputFocused: $isInputFocused,
                        voiceState: voice.currentState,
                        sttStatusText: voice.sttStatusText,
                        recognizedText: voice.recognizedText,
                        isSilenceTimerRunning: voice.isSilenceTimerRunning,
                        isGeneratingTurn: gdVM.isGeneratingTurn,
                        isFinished: gdVM.isFinished,
                        onMicTap: {
                            isInputFocused = false
                            let interruptedAISpeaker = voice.isSpeaking
                            Task {
                                let granted = await voice.requestPermissions()
                                if granted {
                                    if interruptedAISpeaker { gdVM.recordInterruption() }
                                    try? voice.startListening()
                                } else {
                                    gdVM.errorMessage = "Voice input access is required."
                                }
                            }
                        },
                        onCancelVoice: { voice.stopListening() },
                        onSubmitText: { text in
                            submitTextContribution(text)
                        }
                    )

                    // MARK: - 6. SESSION FOOTER CONTROLS
                    if gdVM.isFinished {
                        Button {
                            showEnd = true
                        } label: {
                            Label(sessionEndedByTimer ? "Time's Up — View Final Report" : "View Final Discussion Report", systemImage: "doc.text.fill")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(MockexaTheme.gradient, in: RoundedRectangle(cornerRadius: 25))
                                .foregroundStyle(.white)
                                .shadow(color: MockexaTheme.primary.opacity(0.25), radius: 6, y: 2)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                                    voice.setProcessing()
                                    Task { await gdVM.requestNextTurn(token: token) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "forward.fill")
                                        .font(.caption)
                                    Text("Pass Turn")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                }
                                .frame(height: 40)
                                .padding(.horizontal, 16)
                                .background(MockexaTheme.surface, in: Capsule())
                                .overlay(Capsule().stroke(MockexaTheme.primary.opacity(0.4), lineWidth: 1))
                                .foregroundStyle(MockexaTheme.primary)
                            }
                            .disabled(gdVM.isGeneratingTurn)

                            Spacer()

                            Button {
                                showEnd = true
                            } label: {
                                Label("End Session", systemImage: "xmark")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .frame(height: 40)
                                    .padding(.horizontal, 16)
                                    .background(MockexaTheme.destructive.opacity(0.08), in: Capsule())
                                    .overlay(Capsule().stroke(MockexaTheme.destructive.opacity(0.3), lineWidth: 1))
                                    .foregroundStyle(MockexaTheme.destructive)
                            }
                            .disabled(gdVM.isFinishing)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(MockexaTheme.border, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: -2)
            }
            .foregroundStyle(MockexaTheme.darkNavy)
        }
        .onAppear {
            remainingSeconds = initialSeconds
            sessionEndedByTimer = false
            sessionClockStarted = false
            sessionDeadline = nil
            didRequestAIConclusion = false
            userConcluded = false
            setupSilenceAutoSubmit()
        }
        .onDisappear {
            voice.stopSpeaking()
            voice.stopListening()
            voice.onSilenceDetected = nil
        }
        .onChange(of: gdVM.currentTurn) { _, newTurn in
            if let turn = newTurn {
                voice.speak(text: turn.response, speakerName: turn.speaker)
            }
        }
        .onReceive(timerPublisher) { _ in
            guard sessionClockStarted, !gdVM.isFinished && !showEnd else { return }
            if let deadline = sessionDeadline {
                remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            }
            if remainingSeconds <= 45,
               remainingSeconds > 0,
               !didRequestAIConclusion,
               !userConcluded,
               !gdVM.isGeneratingTurn,
               !voice.isSpeaking,
               voice.currentState != .listening {
                requestAIConclusion()
            }
            if remainingSeconds == 0 {
                sessionEndedByTimer = true
                sessionClockStarted = false
                voice.stopSpeaking()
                voice.stopListening()
                gdVM.endForTimer()
            }
        }
        .task {
            if gdVM.sessionId == nil && !gdVM.isFinished && !gdVM.isGeneratingTurn {
                if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                    await startSession(token: token)
                } else {
                    gdVM.errorMessage = "Please log in to participate in Group Discussion."
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MockexaTheme.primary)
            }
        }
        .confirmationDialog("End this session?", isPresented: $showEnd, titleVisibility: .visible) {
            Button("End & View Report") { navigateToReport = true }
            Button("Keep Practicing", role: .cancel) {}
        }
        .navigationDestination(isPresented: $navigateToReport) {
            ReportView(kind: .gd, gdVM: gdVM)
        }
    }

    private func startSession(token: String) async {
        await gdVM.startGD(
            topic: topic,
            mode: modeStr,
            durationStr: durationStr,
            aiStarts: aiStarts,
            resumeContext: resumeContext,
            jobDescription: jobDescription,
            token: token
        )
        // The visible timer represents actual discussion time. Backend/model
        // startup latency must not consume the user's selected duration.
        if gdVM.sessionId != nil && gdVM.errorMessage == nil {
            sessionClockStarted = true
            sessionDeadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        }
    }

    private func requestAIConclusion() {
        guard !didRequestAIConclusion,
              let token = auth.accessToken,
              !token.isEmpty else { return }
        didRequestAIConclusion = true
        voice.setProcessing()
        Task { await gdVM.requestConclusion(token: token) }
    }

    private func submitTextContribution(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let validation = LanguageValidator.validateGDInput(cleanText)
        switch validation {
        case .validEnglish:
            if voice.isSpeaking { gdVM.recordInterruption() }
            userTextContribution = ""
            if remainingSeconds <= 60 { userConcluded = true }
            voice.setProcessing()
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                Task {
                    await gdVM.submitUserContribution(cleanText, token: token)
                }
            } else {
                gdVM.errorMessage = "Please log in to participate in Group Discussion."
            }
        case .rejectedNonEnglish(let reason):
            print("[VOICE][LANG_REJECTED] reason=\(reason) text=\"\(cleanText)\"")
            gdVM.errorMessage = "Please respond in English. This GD evaluates English communication."
            voice.resetToIdle()
        }
    }

    private func setupSilenceAutoSubmit() {
        voice.onSilenceDetected = { [weak gdVM, weak voice, weak auth] finalText in
            guard let gdVM = gdVM, let voice = voice, let auth = auth else { return }
            guard !gdVM.isGeneratingTurn && !gdVM.isFinished else { return }
            let cleanText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return }

            print("[VOICE][STT][SUBMIT] requestStarted=true")
            let capturedText = voice.stopListeningAndProcess()
            let textToSubmit = capturedText.isEmpty ? cleanText : capturedText

            let validation = LanguageValidator.validateGDInput(textToSubmit)
            switch validation {
            case .validEnglish:
                if remainingSeconds <= 60 { userConcluded = true }
                if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                    Task {
                        await gdVM.submitUserContribution(textToSubmit, token: token)
                        print("[VOICE][STT][SUBMIT] requestCompleted=true")
                    }
                } else {
                    gdVM.errorMessage = "Please log in to participate in Group Discussion."
                    voice.resetToIdle()
                }
            case .rejectedNonEnglish(let reason):
                print("[VOICE][LANG_REJECTED] reason=\(reason) text=\"\(textToSubmit)\"")
                gdVM.errorMessage = "Please respond in English. This GD evaluates English communication."
                voice.resetToIdle()
            }
        }
    }
}

// MARK: - Redesigned GD Helper Components

struct GDSessionHeader: View {
    let topic: String
    let formattedTime: String
    let remainingSeconds: Int
    let currentRound: Int
    let isGenerating: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(MockexaTheme.primary)
                        .frame(width: 6, height: 6)
                    Text("LIVE GROUP DISCUSSION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(MockexaTheme.primary)
                }

                Text(topic)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                // Round Pill
                Text("ROUND \(currentRound)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MockexaTheme.primary.opacity(0.1), in: Capsule())
                    .foregroundStyle(MockexaTheme.primary)

                // Timer Pill
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                    Text(formattedTime)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    remainingSeconds <= 60 ? MockexaTheme.destructive.opacity(0.12) : MockexaTheme.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(remainingSeconds <= 60 ? MockexaTheme.destructive.opacity(0.4) : MockexaTheme.border, lineWidth: 1)
                )
                .foregroundStyle(remainingSeconds <= 60 ? MockexaTheme.destructive : MockexaTheme.darkNavy)
            }
        }
    }
}

struct GDDiscussionRoomView: View {
    let participants: [GDParticipant]
    let currentSpeakerIndex: Int
    let isGenerating: Bool
    let isAISpeaking: Bool
    let isUserListening: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("DISCUSSION PANEL")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(MockexaTheme.textSecondary)
                Spacer()
                Text("4 AI Participants + You")
                    .font(.caption2)
                    .foregroundStyle(MockexaTheme.textSecondary)
            }

            // 4 Participants Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(participants.enumerated()), id: \.element.id) { i, p in
                    let isActive = (currentSpeakerIndex == i && (!isGenerating || isAISpeaking))

                    HStack(spacing: 10) {
                        ZStack {
                            if isActive {
                                Circle()
                                    .stroke(p.color.opacity(0.3), lineWidth: 4)
                                    .frame(width: 44, height: 44)
                                    .scaleEffect(1.1)
                            }

                            AIAvatar(initials: p.initials, color: p.color, active: isActive)
                                .scaleEffect(0.85)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(isActive ? MockexaTheme.primary : MockexaTheme.darkNavy)
                                .lineLimit(1)

                            Text(p.role)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(MockexaTheme.textSecondary)
                                .lineLimit(1)

                            if isActive {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MockexaTheme.primary)
                                        .symbolEffect(.variableColor.iterative, options: .repeating)
                                    Text("Speaking")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(MockexaTheme.primary)
                                }
                                .padding(.top, 1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(isActive ? MockexaTheme.primary.opacity(0.06) : MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isActive ? MockexaTheme.primary : MockexaTheme.border, lineWidth: isActive ? 1.5 : 1)
                    )
                    .shadow(color: isActive ? MockexaTheme.primary.opacity(0.1) : Color.black.opacity(0.02), radius: 4, y: 2)
                }
            }
        }
        .padding(12)
        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MockexaTheme.border, lineWidth: 1))
    }
}

struct GDFeaturedContributionCard: View {
    let turn: GDTurnResponse
    let participants: [GDParticipant]
    let currentSpeakerIndex: Int
    let isAISpeaking: Bool
    let onInterrupt: () -> Void

    var activeParticipant: GDParticipant? {
        if participants.indices.contains(currentSpeakerIndex) {
            return participants[currentSpeakerIndex]
        }
        return nil
    }

    var speakerName: String { activeParticipant?.name ?? turn.speaker }
    var speakerRole: String { activeParticipant?.role ?? "GD Panelist" }
    var initials: String { activeParticipant?.initials ?? String(speakerName.prefix(1)).uppercased() }
    var avatarColor: Color { activeParticipant?.color ?? MockexaTheme.primary }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AIAvatar(initials: initials, color: avatarColor, active: isAISpeaking)
                        .scaleEffect(0.9)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(speakerName)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(MockexaTheme.darkNavy)

                            Text("• Latest")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.primary)
                        }

                        Text(speakerRole)
                            .font(.caption)
                            .foregroundStyle(MockexaTheme.textSecondary)
                    }

                    Spacer()

                    if isAISpeaking {
                        Button {
                            onInterrupt()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 10))
                                Text("Interrupt")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MockexaTheme.destructive.opacity(0.1), in: Capsule())
                            .foregroundStyle(MockexaTheme.destructive)
                        }
                    }
                }

                Text("\"\(turn.response)\"")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(MockexaTheme.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(MockexaTheme.primary.opacity(0.15), lineWidth: 1))
            }
            .padding(.vertical, 4)
        }
    }
}

struct GDConversationFeed: View {
    let entries: [TranscriptEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIOUS CONTRIBUTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(MockexaTheme.textSecondary)
                .padding(.leading, 4)

            ForEach(Array(entries.suffix(6).reversed().enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill((entry.speaker == "You" ? MockexaTheme.secondary : MockexaTheme.primary).opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(entry.speaker == "You" ? "Y" : String(entry.speaker.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(entry.speaker == "You" ? MockexaTheme.secondary : MockexaTheme.primary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.speaker)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(MockexaTheme.darkNavy)

                        Text(entry.text)
                            .font(.system(size: 12))
                            .foregroundStyle(MockexaTheme.textSecondary)
                            .lineLimit(3)
                    }
                    Spacer()
                }
                .padding(10)
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MockexaTheme.border, lineWidth: 1))
            }
        }
    }
}

struct GDInputBar: View {
    @Binding var inputMode: GDInputMode
    @Binding var userTextContribution: String
    var isInputFocused: FocusState<Bool>.Binding

    let voiceState: VoiceFoundation.VoiceState
    let sttStatusText: String
    let recognizedText: String
    let isSilenceTimerRunning: Bool
    let isGeneratingTurn: Bool
    let isFinished: Bool

    let onMicTap: () -> Void
    let onCancelVoice: () -> Void
    let onSubmitText: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Mode Switcher Segmented Control
            HStack(spacing: 0) {
                ForEach(GDInputMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            inputMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .voice ? "mic.fill" : "keyboard.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(inputMode == mode ? MockexaTheme.surface : Color.clear, in: Capsule())
                        .shadow(color: inputMode == mode ? Color.black.opacity(0.06) : Color.clear, radius: 2, y: 1)
                        .foregroundStyle(inputMode == mode ? MockexaTheme.primary : MockexaTheme.textSecondary)
                    }
                }
            }
            .padding(3)
            .background(MockexaTheme.border.opacity(0.5), in: Capsule())

            if inputMode == .voice {
                // VOICE MODE UI
                if voiceState == .listening {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(MockexaTheme.primary.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                    .scaleEffect(isSilenceTimerRunning ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isSilenceTimerRunning)

                                Circle()
                                    .fill(MockexaTheme.primary)
                                    .frame(width: 40, height: 40)

                                Image(systemName: "mic.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sttStatusText)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text("Speak in English — auto-submits on pause")
                                    .font(.caption2)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }

                            Spacer()

                            Button("Cancel", action: onCancelVoice)
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.textSecondary)
                        }

                        // Live transcript preview box
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "waveform")
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                                Text("Live Speech Preview")
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                Spacer()
                            }

                            Text(recognizedText.isEmpty ? "Start speaking your contribution..." : recognizedText)
                                .font(.system(size: 13, weight: recognizedText.isEmpty ? .regular : .medium))
                                .foregroundStyle(recognizedText.isEmpty ? MockexaTheme.textSecondary : MockexaTheme.darkNavy)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                        }
                    }
                } else if voiceState == .processing || isGeneratingTurn {
                    HStack(spacing: 10) {
                        ProgressView().tint(MockexaTheme.primary)
                        Text("Processing discussion turn...")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MockexaTheme.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(MockexaTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    Button(action: onMicTap) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(MockexaTheme.primary)
                                    .frame(width: 44, height: 44)
                                    .shadow(color: MockexaTheme.primary.opacity(0.3), radius: 4, y: 2)
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tap Microphone to Speak")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.primary)
                                Text("English communication practice")
                                    .font(.caption2)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(MockexaTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(MockexaTheme.primary.opacity(0.2), lineWidth: 1))
                    }
                    .disabled(isGeneratingTurn || isFinished)
                }
            } else {
                // TEXT MODE UI
                HStack(spacing: 8) {
                    TextField("Type your contribution...", text: $userTextContribution)
                        .focused(isInputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(MockexaTheme.border, lineWidth: 1))
                        .foregroundStyle(MockexaTheme.darkNavy)
                        .disabled(isFinished || isGeneratingTurn)

                    Button {
                        onSubmitText(userTextContribution)
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(MockexaTheme.primary, in: Circle())
                            .shadow(color: MockexaTheme.primary.opacity(0.22), radius: 4, y: 2)
                    }
                    .disabled(userTextContribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingTurn || isFinished)
                }
            }
        }
    }
}

struct GDContextualErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MockexaTheme.destructive)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Alert")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.destructive)
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .lineLimit(2)
            }

            Spacer()

            Button("Retry", action: onRetry)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(MockexaTheme.primary, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(10)
        .background(MockexaTheme.destructive.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MockexaTheme.destructive.opacity(0.25), lineWidth: 1))
    }
}

struct LiveInterviewView: View {
    let kind: PracticeKind
    var selectedDomain: String = "Data Structures"
    var difficultyStr: String = "Medium"
    var modeStr: String = "Text"
    var resumeContext: String? = nil
    var jobDescription: String? = nil
    var targetRole: String? = nil

    @StateObject private var techVM = TechnicalViewModel()
    @StateObject private var hrVM = HRViewModel()
    @StateObject private var voice = VoiceFoundation.shared
    @EnvironmentObject var auth: AuthManager
    @AppStorage("MOCKEXA_TARGET_ROLE") private var savedTargetRole: String = ""

    @State private var answerText: String = ""
    @State private var hrInputMode: GDInputMode = .voice
    @FocusState private var isAnswerFocused: Bool

    var difficultyInt: Int {
        let clean = difficultyStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("easy") || clean.contains("1") { return 1 }
        if clean.contains("hard") || clean.contains("5") { return 5 }
        return 3
    }

    var isCodeMode: Bool {
        kind == .technical && selectedDomain == "Coding"
    }

    var currentQuestionText: String? {
        if kind == .technical {
            return techVM.currentQuestion?.question
        } else {
            return hrVM.currentQuestion?.question
        }
    }

    var isLoading: Bool {
        kind == .technical ? techVM.isLoading : hrVM.isLoading
    }

    var errorMessage: String? {
        kind == .technical ? techVM.errorMessage : hrVM.errorMessage
    }

    var isCompleted: Bool {
        kind == .technical ? techVM.isCompleted : hrVM.isCompleted
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Label(kind.displayName, systemImage: kind.icon)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(MockexaTheme.darkNavy)
                        Spacer()
                        if !isCompleted {
                            Text("Question \(kind == .technical ? techVM.questionIndex : hrVM.questionIndex) of \(kind == .technical ? techVM.totalQuestions : hrVM.totalQuestions)")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.textSecondary)
                        } else {
                            Text("Interview Complete")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.success)
                        }
                    }

                    if resumeContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text.fill")
                                .font(.caption2)
                            Text("Personalized to Candidate Resume & Projects")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(MockexaTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(MockexaTheme.primary.opacity(0.1), in: Capsule())
                    }

                    AIAvatar(initials: "AI", color: kind == .hr ? Color(red: 225/255, green: 29/255, blue: 72/255) : MockexaTheme.primary, active: isLoading || (kind == .hr && voice.isSpeaking))
                        .scaleEffect(1.4)
                        .padding(12)

                    if let err = errorMessage {
                        Text("Error: \(err)")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.destructive)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(MockexaTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.destructive.opacity(0.3), lineWidth: 1))
                    }

                    if !isCompleted {
                        // Question Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(kind == .technical ? "\(selectedDomain.uppercased())  •  DIFFICULTY \(difficultyInt)/5" : "HR • \(selectedDomain.uppercased())")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)

                                if isLoading && currentQuestionText == nil {
                                    ProgressView().tint(MockexaTheme.primary)
                                } else {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(currentQuestionText ?? "Formulating question...")
                                            .font(.system(size: 19, weight: .bold, design: .rounded))
                                            .foregroundStyle(MockexaTheme.darkNavy)
                                            .lineSpacing(4)
                                        Spacer(minLength: 4)
                                        if kind == .hr, let question = currentQuestionText {
                                            Button {
                                                if voice.isSpeaking {
                                                    voice.stopSpeaking()
                                                } else {
                                                    voice.speak(
                                                        text: question,
                                                        speakerName: "HR Interviewer",
                                                        autoListenOnFinish: hrInputMode == .voice
                                                    )
                                                }
                                            } label: {
                                                Image(systemName: voice.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .frame(width: 38, height: 38)
                                                    .background(MockexaTheme.primary.opacity(0.10), in: Circle())
                                                    .foregroundStyle(MockexaTheme.primary)
                                            }
                                            .accessibilityLabel("Replay HR question")
                                        }
                                    }
                                }
                            }
                        }

                        // Code or Text Answer Editor Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(isCodeMode ? "Solution Code Editor" : "Your Text Response")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(MockexaTheme.darkNavy)
                                    Spacer()
                                    if kind == .hr {
                                        Picker("Response mode", selection: $hrInputMode) {
                                            ForEach(GDInputMode.allCases) { mode in
                                                Label(mode.rawValue, systemImage: mode == .voice ? "mic.fill" : "keyboard.fill")
                                                    .tag(mode)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 170)
                                    } else {
                                        Text(isCodeMode ? "Code" : "Plain Text")
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.textSecondary)
                                    }
                                }

                                if kind == .hr && hrInputMode == .voice {
                                    HRVoiceAnswerPanel(
                                        voice: voice,
                                        isLoading: isLoading,
                                        onMicTap: handleHRMicTap,
                                        onSubmit: submitCurrentHRVoiceAnswer,
                                        onCancel: {
                                            voice.stopListening()
                                            voice.resetToIdle()
                                        }
                                    )
                                } else {
                                    TextEditor(text: $answerText)
                                        .focused($isAnswerFocused)
                                        .disabled(isLoading)
                                        .frame(minHeight: isCodeMode ? 160 : 120)
                                        .padding(8)
                                        .scrollContentBackground(.hidden)
                                        .background(
                                            isCodeMode ? Color(red: 15/255, green: 23/255, blue: 42/255) : MockexaTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isCodeMode ? Color.clear : MockexaTheme.border, lineWidth: 1)
                                        )
                                        .font(isCodeMode ? .system(.subheadline, design: .monospaced) : .body)
                                        .foregroundStyle(isCodeMode ? Color(red: 186/255, green: 230/255, blue: 253/255) : MockexaTheme.textPrimary)
                                }
                            }
                        }

                        if kind != .hr || hrInputMode == .text {
                            PrimaryButton(title: isLoading ? "Submitting..." : "Submit Response") {
                                Task {
                                    let submitContent = answerText
                                    answerText = ""
                                    if kind == .technical {
                                        await techVM.submitAnswer(answer: submitContent, token: auth.accessToken)
                                        if techVM.errorMessage != nil { answerText = submitContent }
                                    } else {
                                        await hrVM.submitAnswer(answer: submitContent, token: auth.accessToken)
                                        if hrVM.errorMessage != nil { answerText = submitContent }
                                    }
                                }
                            }
                            .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                            .opacity(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading ? 0.55 : 1)
                        }
                    }

                    // Live Evaluation Card if evaluated
                    if kind == .technical, let analysis = techVM.lastAnalysis {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("LATEST EVALUATION")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.primary)
                                    Spacer()
                                    Text(analysis.classification.replacingOccurrences(of: "_", with: " "))
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                                        .foregroundStyle(MockexaTheme.primary)
                                }
                                Text("Overall Score: \(Int(analysis.overallScore * 100))/100")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text("Correctness: \(Int(analysis.correctness * 100))%  •  Completeness: \(Int(analysis.completeness * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                if let fb = analysis.feedback, !fb.isEmpty {
                                    Text(fb)
                                        .font(.subheadline)
                                        .foregroundStyle(MockexaTheme.textPrimary)
                                        .padding(.top, 2)
                                }
                                if !analysis.missingConcepts.isEmpty {
                                    Text("Missing concepts: \(analysis.missingConcepts.joined(separator: ", "))")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.warning)
                                }
                                if !analysis.misconceptions.isEmpty {
                                    Text("Misconceptions: \(analysis.misconceptions.joined(separator: ", "))")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.destructive)
                                }
                            }
                        }
                    } else if kind == .hr, let eval = hrVM.lastEvaluation {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LATEST EVALUATION")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                Text("Score: \(Int(eval.overallScore * 100))/100")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text(eval.feedback)
                                    .font(.subheadline)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                        }
                    }

                    if isCompleted {
                        NavigationLink {
                            SessionCompleteView(kind: kind, techVM: techVM, hrVM: hrVM)
                        } label: {
                            Text("View Performance Summary")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(MockexaTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                                .shadow(color: MockexaTheme.primary.opacity(0.22), radius: 12, y: 5)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        }
        .foregroundStyle(MockexaTheme.darkNavy)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if kind == .hr {
                hrInputMode = modeStr.lowercased().contains("type") ? .text : .voice
                setupHRSilenceAutoSubmit()
            }
        }
        .onDisappear {
            if kind == .hr {
                voice.onSilenceDetected = nil
                voice.stopSpeaking()
                voice.stopListening()
            }
        }
        .onChange(of: hrVM.currentQuestion) { _, question in
            guard kind == .hr, let question else { return }
            voice.speak(
                text: question.question,
                speakerName: "HR Interviewer",
                autoListenOnFinish: hrInputMode == .voice
            )
        }
        .onChange(of: hrInputMode) { _, mode in
            guard kind == .hr else { return }
            if mode == .text {
                voice.resetToIdle()
            } else if let question = hrVM.currentQuestion?.question {
                voice.speak(text: question, speakerName: "HR Interviewer", autoListenOnFinish: true)
            }
        }
        .onChange(of: hrVM.isCompleted) { _, completed in
            if kind == .hr && completed {
                voice.resetToIdle()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isAnswerFocused = false
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MockexaTheme.primary)
            }
        }
        .task {
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                let rawFullName = auth.currentUserFullName.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidateName = !rawFullName.isEmpty ? rawFullName : (auth.currentFirstName != "there" ? auth.currentFirstName : "Candidate")
                let resolvedRole = targetRole ?? (savedTargetRole.isEmpty ? "Software Engineer" : savedTargetRole)

                if kind == .technical {
                    await techVM.startSession(
                        name: candidateName,
                        targetRole: resolvedRole,
                        domains: [selectedDomain],
                        difficulty: difficultyInt,
                        resumeContext: resumeContext,
                        jobDescription: jobDescription,
                        token: token
                    )
                } else {
                    if hrInputMode == .voice {
                        _ = await voice.requestPermissions()
                    }
                    await hrVM.startSession(
                        name: candidateName,
                        targetRole: resolvedRole,
                        interviewStyle: selectedDomain,
                        resumeContext: resumeContext,
                        jobDescription: jobDescription,
                        token: token
                    )
                }
            } else {
                if kind == .technical {
                    techVM.errorMessage = "Please log in to start a Technical Interview session."
                } else {
                    hrVM.errorMessage = "Please log in to start an HR Interview session."
                }
            }
        }
    }

    private func handleHRMicTap() {
        isAnswerFocused = false
        if voice.isSpeaking {
            Task {
                let granted = await voice.requestPermissions()
                if granted { voice.interruptAndListen() }
            }
        } else if voice.isListening {
            submitCurrentHRVoiceAnswer()
        } else {
            Task {
                let granted = await voice.requestPermissions()
                if granted {
                    try? voice.startListening()
                } else {
                    hrVM.errorMessage = "Microphone and speech access are required for HR voice mode."
                }
            }
        }
    }

    private func submitCurrentHRVoiceAnswer() {
        let captured = voice.stopListeningAndProcess()
        let fallback = voice.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        submitHRVoiceAnswer(captured.isEmpty ? fallback : captured)
    }

    private func submitHRVoiceAnswer(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !hrVM.isLoading, !hrVM.isCompleted else {
            voice.resetToIdle()
            return
        }
        voice.setProcessing()
        Task {
            await hrVM.submitAnswer(answer: cleanText, token: auth.accessToken)
            if hrVM.errorMessage != nil || hrVM.isCompleted {
                voice.resetToIdle()
            }
        }
    }

    private func setupHRSilenceAutoSubmit() {
        voice.onSilenceDetected = { [weak voice, weak hrVM] finalText in
            guard let voice, let hrVM, !hrVM.isLoading, !hrVM.isCompleted else { return }
            let captured = voice.stopListeningAndProcess()
            let answer = captured.isEmpty ? finalText : captured
            submitHRVoiceAnswer(answer)
        }
    }
}

private struct HRVoiceAnswerPanel: View {
    @ObservedObject var voice: VoiceFoundation
    let isLoading: Bool
    let onMicTap: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    private var transcript: String {
        let best = voice.bestRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return best.isEmpty ? voice.recognizedText : best
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: voice.isListening ? "waveform.circle.fill" : (voice.isSpeaking ? "speaker.wave.2.circle.fill" : "mic.circle.fill"))
                .font(.system(size: 46))
                .foregroundStyle(voice.isListening ? MockexaTheme.secondary : MockexaTheme.primary)
                .symbolEffect(.pulse, isActive: voice.isListening || voice.isSpeaking)

            Text(voice.isListening ? voice.sttStatusText : (voice.isSpeaking ? "Interviewer is speaking…" : (isLoading ? "Evaluating your answer…" : "Tap the microphone and answer naturally")))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(voice.silenceCountdown != nil ? MockexaTheme.warning : MockexaTheme.darkNavy)
                .animation(.easeInOut(duration: 0.2), value: voice.silenceCountdown)

            Text(transcript.isEmpty ? "Speak your answer. You can pause to think, or tap Submit when done." : transcript)
                .font(.subheadline)
                .foregroundStyle(transcript.isEmpty ? MockexaTheme.textSecondary : MockexaTheme.darkNavy)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(12)
                .background(MockexaTheme.background, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                if voice.isListening {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                    Button(action: onSubmit) {
                        if let countdown = voice.silenceCountdown {
                            Label("Submit Now (\(countdown)s)", systemImage: "arrow.up.circle.fill")
                        } else {
                            Label("Submit Answer", systemImage: "arrow.up.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onMicTap) {
                        Label(voice.isSpeaking ? "Interrupt & Answer" : "Start Answer", systemImage: "mic.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct SessionCompleteView: View {
    let kind: PracticeKind
    var techVM: TechnicalViewModel? = nil
    var hrVM: HRViewModel? = nil
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var app: AppModel

    @State private var ready = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 86))
                    .foregroundStyle(MockexaTheme.success)
                    .symbolEffect(.bounce, value: ready)

                Text("Session Complete")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                Text(ready ? "Your performance report is ready" : "Preparing your practice summary…")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(MockexaTheme.textSecondary)

                if let err = (kind == .technical ? techVM?.errorMessage : hrVM?.errorMessage) {
                    VStack(spacing: 12) {
                        Text("Session completion failed: \(err)")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.destructive)
                            .multilineTextAlignment(.center)
                        Button("Retry Finishing Session") {
                            Task {
                                if kind == .technical, let tVM = techVM {
                                    await tVM.finishSession(token: auth.accessToken)
                                } else if kind == .hr, let hVM = hrVM {
                                    await hVM.finishSession(token: auth.accessToken)
                                }
                                let hasError = (kind == .technical ? techVM?.errorMessage != nil : hrVM?.errorMessage != nil)
                                if !hasError {
                                    if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                                        await app.refreshUserSessions(token: token)
                                    }
                                    withAnimation(.spring) { ready = true }
                                }
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    }
                    .padding(14)
                    .background(MockexaTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }

                if ready {
                    NavigationLink {
                        ReportView(kind: kind, techVM: techVM, hrVM: hrVM)
                    } label: {
                        Text("View My Report")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(MockexaTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                            .shadow(color: MockexaTheme.primary.opacity(0.22), radius: 12, y: 5)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    NavigationLink {
                        TranscriptView(
                            entries: kind == .technical ? (techVM?.transcriptEntries ?? []) :
                                    (kind == .hr ? (hrVM?.transcriptEntries ?? []) : [])
                        )
                    } label: {
                        SecondaryButtonLabel(title: "View Session Transcript", icon: "chevron.right")
                    }
                }
            }
            .padding(24)
            .foregroundStyle(MockexaTheme.darkNavy)
        }
        .task {
            var finishSuccess = true
            if kind == .technical, let tVM = techVM {
                if tVM.reportData == nil {
                    await tVM.finishSession(token: auth.accessToken)
                }
                if tVM.errorMessage != nil && tVM.reportData == nil { finishSuccess = false }
            } else if kind == .hr, let hVM = hrVM {
                if hVM.reportData == nil {
                    await hVM.finishSession(token: auth.accessToken)
                }
                if hVM.errorMessage != nil && hVM.reportData == nil { finishSuccess = false }
            }
            if finishSuccess {
                if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                    await app.refreshUserSessions(token: token)
                }
                withAnimation(.spring) { ready = true }
            }
        }
    }
}



struct ReportView: View {
    let kind: PracticeKind
    var techVM: TechnicalViewModel? = nil
    var hrVM: HRViewModel? = nil
    var gdVM: GDViewModel? = nil
    var detail: SessionDetailItem? = nil
    @EnvironmentObject var auth: AuthManager

    private var activeReport: [String: AnyCodable]? {
        kind == .technical ? techVM?.reportData : hrVM?.reportData
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func stringArray(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private func formattedMetricName(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var score: Int? {
        if let d = detail {
            return d.score
        }
        if let raw = number(activeReport?["overall_score"]?.value) {
            let normalized = kind == .hr && raw <= 1 ? raw * 100 : raw
            return min(100, max(0, Int(normalized.rounded())))
        }
        if kind == .technical, let analysis = techVM?.lastAnalysis {
            return Int(analysis.overallScore * 100)
        } else if kind == .hr, let eval = hrVM?.lastEvaluation {
            return Int(eval.overallScore * 100)
        }
        return nil
    }

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your Performance")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .padding(.top, 8)

                if kind == .gd, let gVM = gdVM {
                    GDReportContentView(gVM: gVM, detail: detail)
                } else {
                    HStack {
                        Spacer()
                        if let scoreVal = score {
                            ScoreRing(score: scoreVal, size: 180)
                        } else {
                            VStack(spacing: 4) {
                                Text("N/A")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text("Not available")
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                            .frame(width: 180, height: 180)
                            .background(Circle().stroke(MockexaTheme.border, lineWidth: 12))
                        }
                        Spacer()
                    }

                    if let detail = detail, let report = detail.report {
                        ReportSection(
                            title: "Saved Session Metrics",
                            icon: "doc.text.fill",
                            color: MockexaTheme.primary,
                            items: [
                                "Topic: \(detail.topic)",
                                "Planned duration: \(detail.duration)",
                                "Overall Score: \(detail.score)/100"
                            ]
                        )

                        if let summary = report["summary"]?.value as? String {
                            ReportSection(
                                title: "Summary & Feedback",
                                icon: "quote.bubble.fill",
                                color: MockexaTheme.secondary,
                                items: [summary]
                            )
                        }
                    } else if kind == .technical, let report = techVM?.reportData {
                        let domainScores = (report["domain_scores"]?.value as? [String: Any] ?? [:])
                            .compactMap { key, value -> (String, Double)? in
                                guard let score = number(value) else { return nil }
                                return (key, score)
                            }
                            .sorted { $0.0 < $1.0 }
                        let band = report["performance_band"]?.value as? String ?? "Evaluated"
                        let answered = Int(number(report["questions_answered"]?.value) ?? 0)
                        ReportSection(
                            title: "Overall Assessment",
                            icon: "checkmark.seal.fill",
                            color: MockexaTheme.primary,
                            items: ["Performance band: \(band)", "Questions evaluated: \(answered)"]
                        )
                        if let summary = report["summary"]?.value as? String, !summary.isEmpty {
                            ReportSection(
                                title: "Interviewer Assessment",
                                icon: "quote.bubble.fill",
                                color: MockexaTheme.primary,
                                items: [summary]
                            )
                        }
                        ReportSection(
                            title: "Domain Performance",
                            icon: "chart.bar.fill",
                            color: MockexaTheme.secondary,
                            items: domainScores.isEmpty ? ["No domain breakdown available"] : domainScores.map { "\($0.0): \(Int($0.1.rounded()))%" }
                        )
                        if let qlog = report["question_log"]?.value as? [[String: Any]] {
                            let feedbackItems = qlog.compactMap { q -> String? in
                                guard let idx = q["index"] as? Int,
                                      let topic = q["subtopic"] as? String,
                                      let sc = number(q["overall_score"]) else { return nil }
                                let fb = q["feedback"] as? String ?? ""
                                let scorePct = Int((sc <= 1 ? sc * 100 : sc).rounded())
                                return "Q\(idx) [\(topic) - \(scorePct)%]: \(fb.isEmpty ? "Evaluated" : fb)"
                            }
                            if !feedbackItems.isEmpty {
                                ReportSection(
                                    title: "Question-by-Question Feedback",
                                    icon: "list.bullet.clipboard.fill",
                                    color: MockexaTheme.primary,
                                    items: feedbackItems
                                )
                            }
                        }
                        let strong = stringArray(report["strong_areas"]?.value)
                        let focus = stringArray(report["focus_areas"]?.value)
                        if !strong.isEmpty {
                            ReportSection(title: "Strong Areas", icon: "checkmark.circle.fill", color: MockexaTheme.success, items: strong)
                        }
                        if !focus.isEmpty {
                            ReportSection(title: "Focus Next", icon: "scope", color: MockexaTheme.warning, items: focus)
                        }
                    } else if kind == .technical, let analysis = techVM?.lastAnalysis {
                        ReportSection(
                            title: "Evaluation Metrics",
                            icon: "chart.bar.fill",
                            color: MockexaTheme.primary,
                            items: [
                                "Classification: \(analysis.classification)",
                                "Correctness: \(Int(analysis.correctness * 100))%",
                                "Completeness: \(Int(analysis.completeness * 100))%",
                                "Relevance: \(Int(analysis.relevance * 100))%",
                                "Reasoning: \(Int(analysis.reasoning * 100))%"
                            ]
                        )

                        if !analysis.missingConcepts.isEmpty {
                            ReportSection(
                                title: "Missing Concepts",
                                icon: "exclamationmark.triangle.fill",
                                color: MockexaTheme.warning,
                                items: analysis.missingConcepts
                            )
                        }

                        if !analysis.misconceptions.isEmpty {
                            ReportSection(
                                title: "Misconceptions Identified",
                                icon: "xmark.octagon.fill",
                                color: MockexaTheme.destructive,
                                items: analysis.misconceptions
                            )
                        }
                    } else if kind == .hr, let report = hrVM?.reportData {
                        let ratings = (report["metrics"]?.value as? [String: Any] ?? [:])
                            .compactMap { key, value -> (String, Double)? in
                                guard let score = number(value) else { return nil }
                                return (formattedMetricName(key), score <= 1 ? score * 100 : score)
                            }
                            .sorted { $0.0 < $1.0 }
                        ReportSection(
                            title: "Behavioral Ratings",
                            icon: "star.fill",
                            color: MockexaTheme.secondary,
                            items: ratings.isEmpty ? ["No rating breakdown available"] : ratings.map { "\($0.0): \(Int($0.1.rounded()))%" }
                        )
                        let strengths = stringArray(report["strengths"]?.value).map(formattedMetricName)
                        let weaknesses = stringArray(report["weaknesses"]?.value).map(formattedMetricName)
                        if !strengths.isEmpty {
                            ReportSection(title: "Strong Signals", icon: "checkmark.circle.fill", color: MockexaTheme.success, items: strengths)
                        }
                        if !weaknesses.isEmpty {
                            ReportSection(title: "Develop Next", icon: "arrow.up.right.circle.fill", color: MockexaTheme.warning, items: weaknesses)
                        }
                        if let feedback = hrVM?.lastEvaluation?.feedback, !feedback.isEmpty {
                            ReportSection(title: "Latest Interviewer Feedback", icon: "quote.bubble.fill", color: MockexaTheme.primary, items: [feedback])
                        }
                    } else if kind == .hr, let eval = hrVM?.lastEvaluation {
                        ReportSection(
                            title: "Behavioral Ratings",
                            icon: "star.fill",
                            color: MockexaTheme.secondary,
                            items: [
                                "Clarity: \(Int(eval.clarity * 100))%",
                                "Specificity: \(Int(eval.specificity * 100))%",
                                "Ownership: \(Int(eval.ownership * 100))%",
                                "Communication: \(Int(eval.communication * 100))%",
                                "Teamwork: \(Int(eval.teamwork * 100))%",
                                "Leadership: \(Int(eval.leadership * 100))%",
                                "Problem Solving: \(Int(eval.problemSolving * 100))%"
                            ]
                        )

                        ReportSection(
                            title: "Interviewer Feedback",
                            icon: "quote.bubble.fill",
                            color: MockexaTheme.primary,
                            items: [eval.feedback]
                        )
                    } else {
                        ReportSection(
                            title: "Session Feedback",
                            icon: "info.circle",
                            color: MockexaTheme.textSecondary,
                            items: ["Evaluation data recorded for session."]
                        )
                    }

                    Text("Scores reflect evidence in this practice session and are coaching signals—not a hiring prediction.")
                        .font(.caption)
                        .foregroundStyle(MockexaTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(MockexaTheme.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    NavigationLink {
                        TranscriptView(
                            entries: detail?.transcript?.map { TranscriptEntry(speaker: $0.speaker, text: $0.text, timestamp: "Recorded") } ??
                                    (kind == .technical ? (techVM?.transcriptEntries ?? []) :
                                    (kind == .hr ? (hrVM?.transcriptEntries ?? []) : []))
                        )
                    } label: {
                        SecondaryButtonLabel(title: "View Transcript", icon: "chevron.right")
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GDReportContentView: View {
    @ObservedObject var gVM: GDViewModel
    var detail: SessionDetailItem? = nil
    @State private var savedTranscript: [TranscriptEntry]? = nil
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var app: AppModel

    private func numericDictionary(_ value: Any?) -> [String: Double]? {
        guard let raw = value as? [String: Any] else { return nil }
        let converted = raw.compactMapValues { value -> Double? in
            if let value = value as? Double { return value }
            if let value = value as? Int { return Double(value) }
            if let value = value as? NSNumber { return value.doubleValue }
            return nil
        }
        return converted.isEmpty ? nil : converted
    }

    private var effectiveMetrics: [String: Double]? {
        if let metrics = gVM.metrics { return metrics }
        guard let report = detail?.report else { return nil }
        return numericDictionary(report["metrics"]?.value) ?? numericDictionary(report["scores"]?.value)
    }

    private var effectiveSummary: [String: Any]? {
        if let summary = gVM.summary {
            return summary.mapValues(\.value)
        }
        return detail?.report?["summary"]?.value as? [String: Any]
    }

    private var candidateFeedback: [String: Any]? {
        effectiveSummary?["candidate_feedback"] as? [String: Any]
    }

    private func strings(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    var isLoadingMetrics: Bool {
        if detail != nil { return false }
        if effectiveMetrics != nil { return false }
        if let err = gVM.errorMessage, !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    var score: Int? {
        if let d = detail {
            return d.score
        }
        if let metrics = effectiveMetrics, let s = metrics["overall"] ?? metrics["score"] ?? metrics["quality_score"] {
            return Int(s > 1.0 ? s : s * 100)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer()
                if isLoadingMetrics {
                    VStack(spacing: 8) {
                        ProgressView().tint(MockexaTheme.primary)
                        Text("Evaluating GD...")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.primary)
                    }
                    .frame(width: 180, height: 180)
                    .background(Circle().stroke(MockexaTheme.border, lineWidth: 12))
                } else if let scoreVal = score {
                    ScoreRing(score: scoreVal, size: 180)
                } else {
                    VStack(spacing: 4) {
                        Text("N/A")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(MockexaTheme.darkNavy)
                        Text("Not available")
                            .font(.caption)
                            .foregroundStyle(MockexaTheme.textSecondary)
                    }
                    .frame(width: 180, height: 180)
                    .background(Circle().stroke(MockexaTheme.border, lineWidth: 12))
                }
                Spacer()
            }

            if let err = gVM.errorMessage, !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, effectiveMetrics == nil {
                ReportSection(
                    title: "Evaluation Status",
                    icon: "exclamationmark.triangle.fill",
                    color: MockexaTheme.warning,
                    items: ["Couldn't evaluate this discussion: \(err)"]
                )

                Button {
                    Task {
                        gVM.errorMessage = nil
                        await gVM.finishGD(token: auth.accessToken)
                    }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(MockexaTheme.primary, in: RoundedRectangle(cornerRadius: 22))
                        .foregroundStyle(.white)
                }
            } else if effectiveMetrics == nil && detail == nil && (gVM.errorMessage == nil || gVM.errorMessage!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                GlassCard {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(MockexaTheme.primary)
                            .scaleEffect(1.2)
                        Text("Evaluating Discussion Performance...")
                            .font(.headline)
                            .foregroundStyle(MockexaTheme.darkNavy)
                        Text("Generating metrics on topic relevance, coherence, and counterarguments")
                            .font(.caption)
                            .foregroundStyle(MockexaTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else if let metrics = effectiveMetrics {
                if let feedback = candidateFeedback {
                    let band = feedback["performance_band"] as? String ?? "Candidate evaluation"
                    let overview = feedback["overview"] as? String ?? "Your human contributions were evaluated independently from the AI panel."
                    let scoreRationale = feedback["score_rationale"] as? String
                    let contributions = (feedback["contribution_count"] as? Int) ?? Int((feedback["contribution_count"] as? Double) ?? 0)
                    let averageWords = (feedback["average_words_per_contribution"] as? Int) ?? Int((feedback["average_words_per_contribution"] as? Double) ?? 0)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("HUMAN CANDIDATE ASSESSMENT", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.primary)
                            Text(band)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(MockexaTheme.darkNavy)
                            Text(overview)
                                .font(.subheadline)
                                .foregroundStyle(MockexaTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let scoreRationale, !scoreRationale.isEmpty {
                                Text(scoreRationale)
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 10) {
                                Label("\(contributions) contribution\(contributions == 1 ? "" : "s")", systemImage: "quote.bubble.fill")
                                Label("~\(averageWords) words each", systemImage: "text.word.spacing")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.secondary)
                        }
                    }

                    let strengths = strings(feedback["strengths"])
                    if !strengths.isEmpty {
                        ReportSection(title: "What You Did Well", icon: "checkmark.seal.fill", color: MockexaTheme.success, items: strengths)
                    }
                    let improvements = strings(feedback["improvement_areas"])
                    if !improvements.isEmpty {
                        ReportSection(title: "Improve Next", icon: "arrow.up.right.circle.fill", color: MockexaTheme.warning, items: improvements)
                    }
                    let observations = strings(feedback["judge_observations"])
                    if !observations.isEmpty {
                        ReportSection(title: "Judge's Evidence", icon: "text.magnifyingglass", color: MockexaTheme.primary, items: observations)
                    }
                    if let best = feedback["best_contribution"] as? String, !best.isEmpty {
                        ReportSection(title: "Your Strongest Contribution", icon: "quote.opening", color: MockexaTheme.primary, items: [best])
                    }
                    if let goal = feedback["next_session_goal"] as? String, !goal.isEmpty {
                        ReportSection(title: "Next Session Goal", icon: "target", color: MockexaTheme.secondary, items: [goal])
                    }
                } else if let report = detail?.report {
                    if let overview = report["summary"]?.value as? String, !overview.isEmpty {
                        ReportSection(title: "Judge Overview", icon: "scale.3d", color: MockexaTheme.primary, items: [overview])
                    }
                    let savedStrengths = strings(report["strengths"]?.value)
                    let savedWeaknesses = strings(report["weaknesses"]?.value)
                    if !savedStrengths.isEmpty {
                        ReportSection(title: "What You Did Well", icon: "checkmark.seal.fill", color: MockexaTheme.success, items: savedStrengths)
                    }
                    if !savedWeaknesses.isEmpty {
                        ReportSection(title: "Improve Next", icon: "arrow.up.right.circle.fill", color: MockexaTheme.warning, items: savedWeaknesses)
                    }
                    let savedRecommendations = strings(report["recommendations"]?.value).filter { !$0.isEmpty }
                    if !savedRecommendations.isEmpty {
                        ReportSection(title: "Next Session Goal", icon: "target", color: MockexaTheme.secondary, items: savedRecommendations)
                    }
                }
                let candidateKeys = [
                    "candidate_topic_relevance", "candidate_reasoning", "candidate_structure", "candidate_evidence",
                    "candidate_collaboration", "candidate_clarity", "candidate_novelty", "candidate_participation",
                    "candidate_conclusion", "candidate_turn_taking"
                ]
                let labels = [
                    "candidate_topic_relevance": "Topic relevance",
                    "candidate_reasoning": "Reasoning depth",
                    "candidate_structure": "Argument structure",
                    "candidate_evidence": "Evidence & examples",
                    "candidate_collaboration": "Listening & collaboration",
                    "candidate_clarity": "Clarity",
                    "candidate_novelty": "Original contribution",
                    "candidate_participation": "Participation",
                    "candidate_conclusion": "Closing synthesis",
                    "candidate_turn_taking": "Turn-taking discipline"
                ]
                let metricList = candidateKeys.compactMap { key -> String? in
                    guard let value = metrics[key] else { return nil }
                    return "\(labels[key] ?? key): \(Int(value.rounded()))%"
                }
                ReportSection(
                    title: "Your Skill Breakdown",
                    icon: "person.3.fill",
                    color: MockexaTheme.secondary,
                    items: metricList.isEmpty ? ["Not available"] : metricList
                )
                if let judgingStandard = candidateFeedback?["judging_standard"] as? String {
                    ReportSection(
                        title: "How This Was Judged",
                        icon: "scale.3d",
                        color: MockexaTheme.primary,
                        items: [judgingStandard]
                    )
                }
                if let panel = metrics["panel_quality_score"] {
                    ReportSection(
                        title: "Discussion Environment",
                        icon: "bubble.left.and.bubble.right.fill",
                        color: MockexaTheme.primary,
                        items: ["Panel discussion quality: \(Int(panel.rounded()))%"]
                    )
                }
                Text("Your score is based on your contributions; panel dynamics are shown separately.")
                    .font(.caption)
                    .foregroundStyle(MockexaTheme.textSecondary)
            } else {
                ReportSection(
                    title: "Session Feedback",
                    icon: "info.circle",
                    color: MockexaTheme.textSecondary,
                    items: ["Evaluation data recorded for session."]
                )
            }

            NavigationLink {
                TranscriptView(
                    entries: savedTranscript ?? detail?.transcript?.map { TranscriptEntry(speaker: $0.speaker, text: $0.text, timestamp: "Recorded") } ?? gVM.transcriptEntries
                )
            } label: {
                SecondaryButtonLabel(title: "View Transcript", icon: "chevron.right")
            }
        }
        .task {
            let hasError = gVM.errorMessage != nil && !gVM.errorMessage!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if detail == nil, gVM.metrics == nil, !gVM.isFinishing, !hasError {
                await gVM.finishGD(token: auth.accessToken)
                if gVM.metrics != nil {
                    if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                        await app.refreshUserSessions(token: token)
                    }
                }
            }
            if detail == nil, gVM.metrics != nil,
               let sessionId = gVM.sessionId,
               let token = auth.accessToken, !token.isEmpty,
               let saved = try? await APIClient.shared.fetchSessionDetail(sessionId: sessionId, token: token) {
                savedTranscript = saved.transcript?.map {
                    TranscriptEntry(speaker: $0.speaker, text: $0.text, timestamp: "Recorded")
                }
            }
        }
    }
}


struct ReportSection: View {
    let title: String
    let icon: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            GlassCard {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(items, id: \.self) { item in
                        Label(item, systemImage: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MockexaTheme.darkNavy)
                        if item != items.last {
                            Divider().overlay(MockexaTheme.border)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(color)
        }
    }
}

struct TranscriptView: View {
    var entries: [TranscriptEntry] = []

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 20) {
                Text("Transcript")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .padding(.top, 8)

                if entries.isEmpty {
                    Text("No transcript records available for this session.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(MockexaTheme.textSecondary)
                        .padding(.top, 10)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            AIAvatar(
                                initials: entry.speaker == "You" ? "YOU" : String(entry.speaker.prefix(2)).uppercased(),
                                color: entry.speaker == "You" ? MockexaTheme.secondary : MockexaTheme.primary
                            )
                            .accessibilityLabel(entry.speaker == "You" ? "Your contribution" : "AI participant \(entry.speaker)")
                            .scaleEffect(0.72)
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.speaker)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(MockexaTheme.darkNavy)
                                    Spacer()
                                    Text(entry.timestamp)
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                }
                                Text(entry.text)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                    .lineSpacing(4)
                            }
                            .padding(15)
                            .background(
                                entry.speaker == "You" ? MockexaTheme.primary.opacity(0.08) : MockexaTheme.surface,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(entry.speaker == "You" ? MockexaTheme.primary.opacity(0.2) : MockexaTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
}
