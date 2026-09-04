import SwiftUI

struct PracticeSetupView: View {
    let kind: PracticeKind
    @EnvironmentObject var auth: AuthManager
    @State private var selection = "Balanced Panel"
    @State private var duration = "10 min"
    @State private var company = "Google"
    
    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(setupTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PrepTheme.darkNavy)
                    Text(setupSubtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(PrepTheme.textSecondary)
                }
                .padding(.top, 8)
                
                options
                
                NavigationLink {
                    destination
                } label: {
                    Text(startTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(PrepTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                        .shadow(color: PrepTheme.primary.opacity(0.22), radius: 12, y: 5)
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            switch kind {
            case .gd:
                selection = "Remote work and productivity"
                duration = "10 min"
                company = "balanced"
            case .technical:
                selection = "Data Structures"
                duration = "Medium"
            case .hr:
                selection = "General HR"
                duration = "10 min"
                company = "Standard"
            }
        }
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
    
    var startTitle: String { kind == .gd ? "Meet Your Panel" : "Start Practice" }
    
    @ViewBuilder var options: some View {
        if kind == .gd {
            OptionGroup(title: "Topic", values: ["Remote work and productivity", "Artificial Intelligence & Jobs", "Social Media Impact", "Case Study"], selection: $selection)
            OptionGroup(title: "Duration", values: ["5 min", "10 min", "15 min"], selection: $duration)
            OptionGroup(title: "Panel Mode", values: ["balanced", "consensus"], selection: $company)
        } else if kind == .technical {
            OptionGroup(title: "Domain", values: ["Data Structures", "Algorithms", "Operating Systems", "DBMS", "OOP", "Software Engineering", "Programming"], selection: $selection)
            OptionGroup(title: "Difficulty", values: ["Easy", "Medium", "Hard"], selection: $duration)
        } else {
            OptionGroup(title: "Interview Style", values: ["General HR", "Behavioral", "Leadership", "Situational"], selection: $selection)
        }
    }
    
    @ViewBuilder var destination: some View {
        if kind == .gd {
            PanelView(topic: selection, durationStr: duration, modeStr: company)
        } else {
            LiveInterviewView(kind: kind, selectedDomain: selection, difficultyStr: duration, modeStr: company)
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
                .foregroundStyle(PrepTheme.darkNavy)
            FlowLayout(spacing: 9) {
                ForEach(values, id: \.self) { item in
                    Button(item) {
                        Haptics.selection()
                        selection = item
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(selection == item ? PrepTheme.primary : PrepTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(selection == item ? Color.clear : PrepTheme.border, lineWidth: 1))
                    .foregroundStyle(selection == item ? .white : PrepTheme.darkNavy)
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


struct PanelView: View {
    let topic: String
    var durationStr: String = "10 min"
    var modeStr: String = "balanced"
    @StateObject private var gdVM = GDViewModel()
    @EnvironmentObject var auth: AuthManager
    
    @State private var userTextContribution: String = ""
    @State private var showEnd: Bool = false
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
    
    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        // Header
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("GROUP DISCUSSION")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                Text(topic)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                    .lineLimit(1)
                            }
                            Spacer()
                            
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(formattedTime)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    remainingSeconds <= 60 ? PrepTheme.destructive.opacity(0.12) : PrepTheme.primary.opacity(0.08),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(remainingSeconds <= 60 ? PrepTheme.destructive.opacity(0.4) : PrepTheme.primary.opacity(0.2), lineWidth: 1)
                                )
                                .foregroundStyle(remainingSeconds <= 60 ? PrepTheme.destructive : PrepTheme.primary)
                                
                                if gdVM.isGeneratingTurn {
                                    ProgressView().tint(PrepTheme.primary)
                                } else if let turn = gdVM.currentTurn {
                                    Text("ROUND \(turn.round)")
                                        .font(.system(.subheadline, design: .monospaced).bold())
                                        .foregroundStyle(PrepTheme.primary)
                                }
                            }
                        }
                        
                        // Participant Avatars Row
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array(gdVM.participants.enumerated()), id: \.element.id) { i, p in
                                VStack(spacing: 2) {
                                    AIAvatar(
                                        initials: p.initials,
                                        color: p.color,
                                        active: gdVM.currentSpeakerIndex == i && !gdVM.isGeneratingTurn
                                    )
                                    .scaleEffect(0.78)
                                    
                                    Text(p.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(gdVM.currentSpeakerIndex == i && !gdVM.isGeneratingTurn ? PrepTheme.primary : PrepTheme.darkNavy)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: 66)
                                }
                            }
                        }
                        
                        // Active Speaker Avatar
                        if !gdVM.participants.isEmpty {
                            let activeP = gdVM.participants[gdVM.currentSpeakerIndex % gdVM.participants.count]
                            AIAvatar(initials: activeP.initials, color: activeP.color, active: true).scaleEffect(1.05)
                        } else {
                            AIAvatar(initials: "AI", color: PrepTheme.primary, active: true).scaleEffect(1.05)
                        }
                        
                        // Speech / Current AI Response Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                if let error = gdVM.errorMessage {
                                    Text("Error: \(error)")
                                        .font(.caption.bold())
                                        .foregroundStyle(PrepTheme.destructive)
                                    Button("Retry Turn") {
                                        if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                                            Task { await gdVM.requestNextTurn(token: token) }
                                        } else {
                                            gdVM.errorMessage = "Please log in to start a Group Discussion session."
                                        }
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                } else if let turn = gdVM.currentTurn {
                                    HStack {
                                        Text("\(turn.speaker.uppercased())")
                                            .font(.caption.bold())
                                            .foregroundStyle(PrepTheme.primary)
                                        Spacer()
                                        Text("ACTION: \(turn.action.uppercased())")
                                            .font(.caption2.bold())
                                            .foregroundStyle(PrepTheme.textSecondary)
                                    }
                                    Text(turn.response)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                        .lineSpacing(4)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if gdVM.isGeneratingTurn {
                                    Text("Panelist is formulating response...")
                                        .font(.headline)
                                        .foregroundStyle(PrepTheme.textSecondary)
                                    ProgressView().tint(PrepTheme.primary).padding(4)
                                } else {
                                    Text("Tap 'Next AI Turn' or type your contribution below to participate.")
                                        .font(.subheadline)
                                        .foregroundStyle(PrepTheme.textSecondary)
                                }
                            }
                        }
                        
                        // Text Contribution Field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("YOUR CONTRIBUTION")
                                .font(.caption.bold())
                                .foregroundStyle(PrepTheme.primary)
                            
                            HStack(spacing: 8) {
                                TextField("Type your GD contribution...", text: $userTextContribution)
                                    .focused($isInputFocused)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(PrepTheme.border, lineWidth: 1))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                    .disabled(gdVM.isFinished || gdVM.isGeneratingTurn)
                                
                                Button {
                                    let text = userTextContribution
                                    userTextContribution = ""
                                    if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                                        Task {
                                            await gdVM.submitUserContribution(text, token: token)
                                        }
                                    } else {
                                        gdVM.errorMessage = "Please log in to participate in Group Discussion."
                                    }
                                } label: {
                                    Image(systemName: "paperplane.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                        .background(PrepTheme.primary, in: Circle())
                                        .shadow(color: PrepTheme.primary.opacity(0.22), radius: 4, y: 2)
                                }
                                .disabled(userTextContribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gdVM.isGeneratingTurn || gdVM.isFinished)
                            }
                        }
                        
                        // Bottom Controls
                        HStack(spacing: 12) {
                            Button {
                                if gdVM.isFinished {
                                    showEnd = true
                                } else if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                                    Task { await gdVM.requestNextTurn(token: token) }
                                } else {
                                    gdVM.errorMessage = "Please log in to participate in Group Discussion."
                                }
                            } label: {
                                Label(gdVM.isFinished ? "View Report" : (gdVM.isGeneratingTurn ? "Generating..." : "Next AI Turn"), systemImage: gdVM.isFinished ? "doc.text.fill" : "arrow.clockwise")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(PrepTheme.gradient, in: RoundedRectangle(cornerRadius: 23))
                                    .foregroundStyle(.white)
                                    .shadow(color: PrepTheme.primary.opacity(0.2), radius: 6, y: 2)
                            }
                            .disabled(gdVM.isGeneratingTurn)
                            
                            Button {
                                showEnd = true
                            } label: {
                                Label("End", systemImage: "xmark")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .frame(width: 90, height: 46)
                                    .background(PrepTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 23))
                                    .overlay(RoundedRectangle(cornerRadius: 23).stroke(PrepTheme.destructive.opacity(0.3), lineWidth: 1))
                                    .foregroundStyle(PrepTheme.destructive)
                            }
                            .disabled(gdVM.isFinishing)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
            }
            .foregroundStyle(PrepTheme.darkNavy)
        }
        .onAppear {
            remainingSeconds = initialSeconds
        }
        .onReceive(timerPublisher) { _ in
            guard !gdVM.isFinished && !showEnd else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            }
        }
        .task {
            if gdVM.sessionId == nil && !gdVM.isFinished && !gdVM.isGeneratingTurn {
                if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                    await gdVM.startGD(topic: topic, mode: modeStr, durationStr: durationStr, token: token)
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
                .foregroundStyle(PrepTheme.primary)
            }
        }
        .confirmationDialog("End this session?", isPresented: $showEnd, titleVisibility: .visible) {
            NavigationLink("End & View Report") {
                ReportView(kind: .gd, gdVM: gdVM)
            }
            Button("Keep Practicing", role: .cancel) {}
        }
    }
}

struct LiveInterviewView: View {
    let kind: PracticeKind
    var selectedDomain: String = "Data Structures"
    var difficultyStr: String = "Medium"
    var modeStr: String = "Text"
    
    @StateObject private var techVM = TechnicalViewModel()
    @StateObject private var hrVM = HRViewModel()
    @EnvironmentObject var auth: AuthManager
    
    @State private var answerText: String = ""
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
                            .foregroundStyle(PrepTheme.darkNavy)
                        Spacer()
                        if !isCompleted {
                            Text("Question \(kind == .technical ? techVM.questionIndex : hrVM.questionIndex) of \(kind == .technical ? techVM.totalQuestions : hrVM.totalQuestions)")
                                .font(.caption.bold())
                                .foregroundStyle(PrepTheme.textSecondary)
                        } else {
                            Text("Interview Complete")
                                .font(.caption.bold())
                                .foregroundStyle(PrepTheme.success)
                        }
                    }
                    
                    AIAvatar(initials: "AI", color: kind == .hr ? Color(red: 225/255, green: 29/255, blue: 72/255) : PrepTheme.primary, active: isLoading)
                        .scaleEffect(1.4)
                        .padding(12)
                    
                    if let err = errorMessage {
                        Text("Error: \(err)")
                            .font(.caption.bold())
                            .foregroundStyle(PrepTheme.destructive)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(PrepTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(PrepTheme.destructive.opacity(0.3), lineWidth: 1))
                    }
                    
                    if !isCompleted {
                        // Question Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(kind == .technical ? "\(selectedDomain.uppercased())  •  DIFFICULTY \(difficultyInt)/5" : "HR BEHAVIORAL")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                
                                if isLoading && currentQuestionText == nil {
                                    ProgressView().tint(PrepTheme.primary)
                                } else {
                                    Text(currentQuestionText ?? "Formulating question...")
                                        .font(.system(size: 19, weight: .bold, design: .rounded))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                        .lineSpacing(4)
                                }
                            }
                        }
                        
                        // Code or Text Answer Editor Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(isCodeMode ? "Solution Code Editor" : "Your Text Response")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                    Spacer()
                                    Text(isCodeMode ? "Code" : "Plain Text")
                                        .font(.caption.bold())
                                        .foregroundStyle(PrepTheme.textSecondary)
                                }
                                
                                TextEditor(text: $answerText)
                                    .focused($isAnswerFocused)
                                    .disabled(isLoading)
                                    .frame(minHeight: isCodeMode ? 160 : 120)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(
                                        isCodeMode ? Color(red: 15/255, green: 23/255, blue: 42/255) : PrepTheme.background,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isCodeMode ? Color.clear : PrepTheme.border, lineWidth: 1)
                                    )
                                    .font(isCodeMode ? .system(.subheadline, design: .monospaced) : .body)
                                    .foregroundStyle(isCodeMode ? Color(red: 186/255, green: 230/255, blue: 253/255) : PrepTheme.darkNavy)
                            }
                        }
                        
                        PrimaryButton(title: isLoading ? "Submitting..." : "Submit Response") {
                            Task {
                                let submitContent = answerText
                                answerText = ""
                                if kind == .technical {
                                    await techVM.submitAnswer(answer: submitContent, token: auth.accessToken)
                                } else {
                                    await hrVM.submitAnswer(answer: submitContent, token: auth.accessToken)
                                }
                            }
                        }
                        .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                    
                    // Live Evaluation Card if evaluated
                    if kind == .technical, let analysis = techVM.lastAnalysis {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LATEST EVALUATION")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                Text("Overall Score: \(Int(analysis.overallScore * 100))/100")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                Text("Correctness: \(Int(analysis.correctness * 100))%  •  Completeness: \(Int(analysis.completeness * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(PrepTheme.textSecondary)
                                if !analysis.missingConcepts.isEmpty {
                                    Text("Missing concepts: \(analysis.missingConcepts.joined(separator: ", "))")
                                        .font(.caption.bold())
                                        .foregroundStyle(PrepTheme.warning)
                                }
                            }
                        }
                    } else if kind == .hr, let eval = hrVM.lastEvaluation {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LATEST EVALUATION")
                                    .font(.caption.bold())
                                    .foregroundStyle(PrepTheme.primary)
                                Text("Score: \(Int(eval.overallScore * 100))/100")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                Text(eval.feedback)
                                    .font(.subheadline)
                                    .foregroundStyle(PrepTheme.textSecondary)
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
                                .background(PrepTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                                .shadow(color: PrepTheme.primary.opacity(0.22), radius: 12, y: 5)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        }
        .foregroundStyle(PrepTheme.darkNavy)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isAnswerFocused = false
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PrepTheme.primary)
            }
        }
        .task {
            if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                if kind == .technical {
                    await techVM.startSession(domains: [selectedDomain], difficulty: difficultyInt, token: token)
                } else {
                    await hrVM.startSession(token: token)
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
                    .foregroundStyle(PrepTheme.success)
                    .symbolEffect(.bounce, value: ready)
                
                Text("Session Complete")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                Text(ready ? "Your performance report is ready" : "Preparing your practice summary…")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(PrepTheme.textSecondary)
                
                if let err = (kind == .technical ? techVM?.errorMessage : hrVM?.errorMessage) {
                    VStack(spacing: 12) {
                        Text("Session completion failed: \(err)")
                            .font(.caption.bold())
                            .foregroundStyle(PrepTheme.destructive)
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
                        .foregroundStyle(PrepTheme.primary)
                    }
                    .padding(14)
                    .background(PrepTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
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
                            .background(PrepTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                            .shadow(color: PrepTheme.primary.opacity(0.22), radius: 12, y: 5)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    NavigationLink {
                        TranscriptView(
                            entries: kind == .technical ? (techVM?.transcriptEntries ?? []) :
                                    (kind == .hr ? (hrVM?.transcriptEntries ?? []) : [])
                        )
                    } label: {
                        SecondaryButton(title: "View Session Transcript") {}
                    }
                }
            }
            .padding(24)
            .foregroundStyle(PrepTheme.darkNavy)
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
    
    var score: Int? {
        if let d = detail {
            return d.score
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
                    .foregroundStyle(PrepTheme.darkNavy)
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
                                    .foregroundStyle(PrepTheme.darkNavy)
                                Text("Not available")
                                    .font(.caption)
                                    .foregroundStyle(PrepTheme.textSecondary)
                            }
                            .frame(width: 180, height: 180)
                            .background(Circle().stroke(PrepTheme.border, lineWidth: 12))
                        }
                        Spacer()
                    }
                    
                    if let detail = detail, let report = detail.report {
                        ReportSection(
                            title: "Saved Session Metrics",
                            icon: "doc.text.fill",
                            color: PrepTheme.primary,
                            items: [
                                "Topic: \(detail.topic)",
                                "Duration: \(detail.duration)",
                                "Overall Score: \(detail.score)/100"
                            ]
                        )
                        
                        if let summary = report["summary"]?.value as? String {
                            ReportSection(
                                title: "Summary & Feedback",
                                icon: "quote.bubble.fill",
                                color: PrepTheme.secondary,
                                items: [summary]
                            )
                        }
                    } else if kind == .technical, let analysis = techVM?.lastAnalysis {
                        ReportSection(
                            title: "Evaluation Metrics",
                            icon: "chart.bar.fill",
                            color: PrepTheme.primary,
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
                                color: PrepTheme.warning,
                                items: analysis.missingConcepts
                            )
                        }
                        
                        if !analysis.misconceptions.isEmpty {
                            ReportSection(
                                title: "Misconceptions Identified",
                                icon: "xmark.octagon.fill",
                                color: PrepTheme.destructive,
                                items: analysis.misconceptions
                            )
                        }
                    } else if kind == .hr, let eval = hrVM?.lastEvaluation {
                        ReportSection(
                            title: "Behavioral Ratings",
                            icon: "star.fill",
                            color: PrepTheme.secondary,
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
                            color: PrepTheme.primary,
                            items: [eval.feedback]
                        )
                    } else {
                        ReportSection(
                            title: "Session Feedback",
                            icon: "info.circle",
                            color: PrepTheme.textSecondary,
                            items: ["Evaluation data recorded for session."]
                        )
                    }
                    
                    NavigationLink {
                        TranscriptView(
                            entries: detail?.transcript?.map { TranscriptEntry(speaker: $0.speaker, text: $0.text, timestamp: "Recorded") } ??
                                    (kind == .technical ? (techVM?.transcriptEntries ?? []) :
                                    (kind == .hr ? (hrVM?.transcriptEntries ?? []) : []))
                        )
                    } label: {
                        SecondaryButton(title: "View Transcript") {}
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
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var app: AppModel
    
    var isLoadingMetrics: Bool {
        if detail != nil { return false }
        if gVM.metrics != nil { return false }
        if let err = gVM.errorMessage, !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }
    
    var score: Int? {
        if let d = detail {
            return d.score
        }
        if let metrics = gVM.metrics, let s = metrics["overall"] ?? metrics["score"] ?? metrics["quality_score"] {
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
                        ProgressView().tint(PrepTheme.primary)
                        Text("Evaluating GD...")
                            .font(.caption.bold())
                            .foregroundStyle(PrepTheme.primary)
                    }
                    .frame(width: 180, height: 180)
                    .background(Circle().stroke(PrepTheme.border, lineWidth: 12))
                } else if let scoreVal = score {
                    ScoreRing(score: scoreVal, size: 180)
                } else {
                    VStack(spacing: 4) {
                        Text("N/A")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(PrepTheme.darkNavy)
                        Text("Not available")
                            .font(.caption)
                            .foregroundStyle(PrepTheme.textSecondary)
                    }
                    .frame(width: 180, height: 180)
                    .background(Circle().stroke(PrepTheme.border, lineWidth: 12))
                }
                Spacer()
            }
            
            if let err = gVM.errorMessage, !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, gVM.metrics == nil {
                ReportSection(
                    title: "Evaluation Status",
                    icon: "exclamationmark.triangle.fill",
                    color: PrepTheme.warning,
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
                        .background(PrepTheme.primary, in: RoundedRectangle(cornerRadius: 22))
                        .foregroundStyle(.white)
                }
            } else if gVM.metrics == nil && (gVM.errorMessage == nil || gVM.errorMessage!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                GlassCard {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(PrepTheme.primary)
                            .scaleEffect(1.2)
                        Text("Evaluating Discussion Performance...")
                            .font(.headline)
                            .foregroundStyle(PrepTheme.darkNavy)
                        Text("Generating metrics on topic relevance, coherence, and counterarguments")
                            .font(.caption)
                            .foregroundStyle(PrepTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else if let metrics = gVM.metrics {
                let metricList = metrics.map { key, value in
                    let valInt = Int(value > 1.0 ? value : value * 100)
                    let formattedKey = key.replacingOccurrences(of: "_", with: " ").capitalized
                    return "\(formattedKey): \(valInt)%"
                }
                ReportSection(
                    title: "Group Discussion Metrics",
                    icon: "person.3.fill",
                    color: PrepTheme.secondary,
                    items: metricList.isEmpty ? ["Not available"] : metricList
                )
            } else {
                ReportSection(
                    title: "Session Feedback",
                    icon: "info.circle",
                    color: PrepTheme.textSecondary,
                    items: ["Evaluation data recorded for session."]
                )
            }
            
            NavigationLink {
                TranscriptView(
                    entries: gVM.transcriptEntries
                )
            } label: {
                SecondaryButton(title: "View Transcript") {}
            }
        }
        .task {
            print("[GD REPORT CONTENT] .task entered. metrics nil: \(gVM.metrics == nil), isFinishing: \(gVM.isFinishing)")
            let hasError = gVM.errorMessage != nil && !gVM.errorMessage!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if detail == nil, gVM.metrics == nil, !gVM.isFinishing, !hasError {
                print("[GD REPORT CONTENT] Calling gVM.finishGD...")
                await gVM.finishGD(token: auth.accessToken)
                if gVM.metrics != nil {
                    if auth.isAuthenticated, let token = auth.accessToken, !token.isEmpty {
                        await app.refreshUserSessions(token: token)
                    }
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
                            .foregroundStyle(PrepTheme.darkNavy)
                        if item != items.last {
                            Divider().overlay(PrepTheme.border)
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
                    .foregroundStyle(PrepTheme.darkNavy)
                    .padding(.top, 8)
                
                if entries.isEmpty {
                    Text("No transcript records available for this session.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(PrepTheme.textSecondary)
                        .padding(.top, 10)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            AIAvatar(
                                initials: entry.speaker == "You" ? "YOU" : String(entry.speaker.prefix(2)).uppercased(),
                                color: entry.speaker == "You" ? PrepTheme.secondary : PrepTheme.primary
                            )
                            .scaleEffect(0.72)
                            .frame(width: 44, height: 44)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.speaker)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(PrepTheme.darkNavy)
                                    Spacer()
                                    Text(entry.timestamp)
                                        .font(.caption)
                                        .foregroundStyle(PrepTheme.textSecondary)
                                }
                                Text(entry.text)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(PrepTheme.darkNavy)
                                    .lineSpacing(4)
                            }
                            .padding(15)
                            .background(
                                entry.speaker == "You" ? PrepTheme.primary.opacity(0.08) : PrepTheme.surface,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(entry.speaker == "You" ? PrepTheme.primary.opacity(0.2) : PrepTheme.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
}
