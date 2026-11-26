import SwiftUI
import Combine

struct AptitudeQuestion: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let category: String
    let difficulty: Int
    let options: [String]
}

private struct AptitudeStartRequest: Encodable {
    let categories: [String]
    let difficulty: Int?
    let questionCount: Int
    let durationMinutes: Int
    let targetRole: String?

    enum CodingKeys: String, CodingKey {
        case categories, difficulty
        case questionCount = "question_count"
        case durationMinutes = "duration_minutes"
        case targetRole = "target_role"
    }
}

private struct AptitudeStartResponse: Decodable {
    let sessionId: String
    let question: AptitudeQuestion
    let questionNumber: Int
    let totalQuestions: Int
    let durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case question
        case sessionId = "session_id"
        case questionNumber = "question_number"
        case totalQuestions = "total_questions"
        case durationSeconds = "duration_seconds"
    }
}

private struct AptitudeAnswerRequest: Encodable {
    let sessionId: String
    let questionId: String
    let selectedIndex: Int

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case questionId = "question_id"
        case selectedIndex = "selected_index"
    }
}

struct AptitudeAnswerResponse: Decodable {
    let selectedIndex: Int
    let correctIndex: Int
    let isCorrect: Bool
    let explanation: String
    let correctAnswers: Int
    let attempted: Int
    let nextQuestion: AptitudeQuestion?
    let questionNumber: Int
    let totalQuestions: Int
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case explanation, attempted, completed
        case selectedIndex = "selected_index"
        case correctIndex = "correct_index"
        case isCorrect = "is_correct"
        case correctAnswers = "correct_answers"
        case nextQuestion = "next_question"
        case questionNumber = "question_number"
        case totalQuestions = "total_questions"
    }
}

struct AptitudeReport: Decodable {
    let sessionId: String
    let totalQuestions: Int
    let attempted: Int
    let correct: Int
    let incorrect: Int
    let unanswered: Int
    let overallScore: Int
    let categoryScores: [String: Int]
    let timeTakenSeconds: Int
    let passed: Bool
    let strengths: [String]
    let focusAreas: [String]

    enum CodingKeys: String, CodingKey {
        case attempted, correct, incorrect, unanswered, passed, strengths
        case sessionId = "session_id"
        case totalQuestions = "total_questions"
        case overallScore = "overall_score"
        case categoryScores = "category_scores"
        case timeTakenSeconds = "time_taken_seconds"
        case focusAreas = "focus_areas"
    }
}

@MainActor
final class AptitudeRoundViewModel: ObservableObject {
    @Published var sessionId: String?
    @Published var currentQuestion: AptitudeQuestion?
    @Published var feedback: AptitudeAnswerResponse?
    @Published var report: AptitudeReport?
    @Published var questionNumber = 1
    @Published var totalQuestions = 1
    @Published var correctAnswers = 0
    @Published var attempted = 0
    @Published var remainingSeconds = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var pendingQuestion: AptitudeQuestion?
    private var roundCompleted = false

    func start(categories: [String], difficulty: Int?, count: Int, duration: Int, targetRole: String?, token: String?) async {
        guard sessionId == nil, !isLoading else { return }
        guard let token, !token.isEmpty else {
            errorMessage = "Please sign in again before starting an aptitude round."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response: AptitudeStartResponse = try await APIClient.shared.post(
                endpoint: "/aptitude/start",
                body: AptitudeStartRequest(
                    categories: categories,
                    difficulty: difficulty,
                    questionCount: count,
                    durationMinutes: duration,
                    targetRole: targetRole
                ),
                token: token
            )
            sessionId = response.sessionId
            currentQuestion = response.question
            questionNumber = response.questionNumber
            totalQuestions = response.totalQuestions
            remainingSeconds = response.durationSeconds
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func submit(selectedIndex: Int, token: String?) async {
        guard let sessionId, let question = currentQuestion, feedback == nil, !isLoading else { return }
        guard let token, !token.isEmpty else {
            errorMessage = "Your sign-in session expired. Please sign in again."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response: AptitudeAnswerResponse = try await APIClient.shared.post(
                endpoint: "/aptitude/answer",
                body: AptitudeAnswerRequest(
                    sessionId: sessionId,
                    questionId: question.id,
                    selectedIndex: selectedIndex
                ),
                token: token
            )
            feedback = response
            pendingQuestion = response.nextQuestion
            roundCompleted = response.completed
            correctAnswers = response.correctAnswers
            attempted = response.attempted
        } catch let error as APIError {
            if case .conflict(let message) = error, message.localizedCaseInsensitiveContains("time") {
                remainingSeconds = 0
                await finish(token: token)
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func continueRound(token: String?) async {
        guard feedback != nil else { return }
        if roundCompleted || pendingQuestion == nil {
            await finish(token: token)
            return
        }
        currentQuestion = pendingQuestion
        pendingQuestion = nil
        feedback = nil
        questionNumber += 1
    }

    func finish(token: String?) async {
        guard report == nil, let sessionId, !isLoading else { return }
        guard let token, !token.isEmpty else {
            errorMessage = "Your sign-in session expired. Please sign in again."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result: AptitudeReport = try await APIClient.shared.postEmpty(
                endpoint: "/aptitude/finish/\(sessionId)", token: token
            )
            report = result
            currentQuestion = nil
            feedback = nil
            remainingSeconds = 0
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct AptitudeSetupView: View {
    private let categories = ["Quantitative Aptitude", "Logical Reasoning", "Verbal Ability", "Data Interpretation"]
    @AppStorage("MOCKEXA_TARGET_ROLE") private var targetRole = ""
    @State private var selectedCategories = Set<String>()
    @State private var didApplyRoleDefaults = false
    @State private var difficulty = "Mixed"
    @State private var questionCount = 10
    @State private var durationMinutes = 15

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aptitude Round")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    Text("Timed placement-style MCQs with instant explanations.")
                        .font(.subheadline)
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
                .padding(.top, 8)

                if !targetRole.isEmpty {
                    Label("Recommended for \(targetRole)", systemImage: "scope")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Categories").font(.headline).foregroundStyle(MockexaTheme.darkNavy)
                        ForEach(categories, id: \.self) { category in
                            Button {
                                Haptics.selection()
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedCategories.contains(category) ? "checkmark.circle.fill" : "circle")
                                    Text(category).font(.subheadline.bold())
                                    Spacer()
                                }
                                .foregroundStyle(selectedCategories.contains(category) ? MockexaTheme.primary : MockexaTheme.darkNavy)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(selectedCategories.isEmpty ? "All categories will be mixed." : "\(selectedCategories.count) categories selected")
                            .font(.caption).foregroundStyle(MockexaTheme.textSecondary)
                    }
                }

                OptionGroup(title: "Difficulty", values: ["Mixed", "Easy", "Medium", "Hard"], selection: $difficulty)

                GlassCard {
                    VStack(spacing: 14) {
                        Stepper("\(questionCount) questions", value: $questionCount, in: 5...maxQuestionCount, step: 5)
                        Divider().overlay(MockexaTheme.border)
                        Stepper("\(durationMinutes) minutes", value: $durationMinutes, in: 5...30, step: 5)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(MockexaTheme.darkNavy)
                }

                NavigationLink {
                    AptitudeRoundView(
                        categories: Array(selectedCategories).sorted(),
                        difficulty: difficultyValue,
                        questionCount: questionCount,
                        durationMinutes: durationMinutes,
                        targetRole: targetRole
                    )
                } label: {
                    Label("Start Aptitude Round", systemImage: "timer")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(MockexaTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
                }
            }
        }
        .navigationTitle("Aptitude Setup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { applyRoleDefaultsIfNeeded() }
        .onChange(of: targetRole) { _, _ in
            didApplyRoleDefaults = false
            applyRoleDefaultsIfNeeded()
        }
        .onChange(of: selectedCategories) { _, _ in
            questionCount = min(questionCount, maxQuestionCount)
        }
    }

    private func applyRoleDefaultsIfNeeded() {
        guard !didApplyRoleDefaults else { return }
        didApplyRoleDefaults = true
        let recommended = RolePersonalization.aptitudeCategories(for: targetRole)
        if !recommended.isEmpty {
            selectedCategories = Set(recommended)
        }
    }

    private var maxQuestionCount: Int {
        selectedCategories.isEmpty ? 20 : min(20, max(10, selectedCategories.count * 10))
    }

    private var difficultyValue: Int? {
        switch difficulty {
        case "Easy": 1
        case "Medium": 2
        case "Hard": 3
        default: nil
        }
    }
}

struct AptitudeRoundView: View {
    let categories: [String]
    let difficulty: Int?
    let questionCount: Int
    let durationMinutes: Int
    let targetRole: String

    @StateObject private var viewModel = AptitudeRoundViewModel()
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var app: AppModel
    @State private var selectedIndex: Int?
    @State private var showFinishConfirmation = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 18) {
                    if let report = viewModel.report {
                        reportContent(report)
                    } else {
                        roundHeader

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(MockexaTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if viewModel.currentQuestion == nil {
                            ProgressView("Preparing aptitude questions…")
                                .tint(MockexaTheme.primary)
                                .padding(.vertical, 60)
                        } else if let question = viewModel.currentQuestion {
                            questionCard(question)
                            optionsCard(question)

                            if let feedback = viewModel.feedback {
                                feedbackCard(feedback)
                                PrimaryButton(title: feedback.completed ? "View Result" : "Next Question") {
                                    selectedIndex = nil
                                    Task {
                                        await viewModel.continueRound(token: auth.accessToken)
                                        if viewModel.report != nil {
                                            await app.refreshUserSessions(token: auth.accessToken)
                                        }
                                    }
                                }
                                .disabled(viewModel.isLoading)
                            } else {
                                PrimaryButton(title: viewModel.isLoading ? "Submitting…" : "Submit Answer") {
                                    guard let selectedIndex else { return }
                                    Task { await viewModel.submit(selectedIndex: selectedIndex, token: auth.accessToken) }
                                }
                                .disabled(selectedIndex == nil || viewModel.isLoading)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Aptitude Round")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.sessionId != nil && viewModel.report == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { showFinishConfirmation = true }
                        .foregroundStyle(MockexaTheme.destructive)
                }
            }
        }
        .confirmationDialog("Finish this aptitude round?", isPresented: $showFinishConfirmation) {
            Button("Finish & View Result", role: .destructive) {
                Task {
                    await viewModel.finish(token: auth.accessToken)
                    await app.refreshUserSessions(token: auth.accessToken)
                }
            }
            Button("Continue Round", role: .cancel) {}
        } message: {
            Text("Unanswered questions will be counted in the final score.")
        }
        .task {
            await viewModel.start(
                categories: categories,
                difficulty: difficulty,
                count: questionCount,
                duration: durationMinutes,
                targetRole: targetRole.isEmpty ? nil : targetRole,
                token: auth.accessToken
            )
        }
        .onReceive(timer) { _ in
            guard viewModel.sessionId != nil, viewModel.report == nil, viewModel.remainingSeconds > 0 else { return }
            viewModel.remainingSeconds -= 1
            if viewModel.remainingSeconds == 0 {
                Task {
                    await viewModel.finish(token: auth.accessToken)
                    await app.refreshUserSessions(token: auth.accessToken)
                }
            }
        }
    }

    private var roundHeader: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("QUESTION \(viewModel.questionNumber) OF \(viewModel.totalQuestions)")
                        .font(.caption.bold()).foregroundStyle(MockexaTheme.primary)
                    Text("\(viewModel.correctAnswers) correct • \(viewModel.attempted) attempted")
                        .font(.caption).foregroundStyle(MockexaTheme.textSecondary)
                }
                Spacer()
                Label(timeText, systemImage: "timer")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.remainingSeconds <= 60 ? MockexaTheme.destructive : MockexaTheme.darkNavy)
            }
        }
    }

    private var timeText: String {
        String(format: "%02d:%02d", viewModel.remainingSeconds / 60, viewModel.remainingSeconds % 60)
    }

    private func questionCard(_ question: AptitudeQuestion) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(question.category.uppercased()).font(.caption.bold()).foregroundStyle(MockexaTheme.primary)
                    Spacer()
                    Text("Level \(question.difficulty)/3").font(.caption.bold()).foregroundStyle(MockexaTheme.textSecondary)
                }
                Text(question.prompt)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .lineSpacing(4)
            }
        }
    }

    private func optionsCard(_ question: AptitudeQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard viewModel.feedback == nil else { return }
                    selectedIndex = index
                    Haptics.selection()
                } label: {
                    HStack(spacing: 12) {
                        Text(String(UnicodeScalar(65 + index)!))
                            .font(.subheadline.bold())
                            .frame(width: 34, height: 34)
                            .background(optionColor(index).opacity(0.14), in: Circle())
                        Text(option).font(.subheadline.bold()).multilineTextAlignment(.leading)
                        Spacer()
                        if selectedIndex == index || viewModel.feedback?.correctIndex == index {
                            Image(systemName: optionIcon(index)).foregroundStyle(optionColor(index))
                        }
                    }
                    .padding(14)
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .background(optionColor(index).opacity(optionIsHighlighted(index) ? 0.10 : 0.03), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(optionIsHighlighted(index) ? optionColor(index) : MockexaTheme.border, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.feedback != nil)
            }
        }
    }

    private func optionIsHighlighted(_ index: Int) -> Bool {
        selectedIndex == index || viewModel.feedback?.correctIndex == index
    }

    private func optionColor(_ index: Int) -> Color {
        guard let feedback = viewModel.feedback else {
            return selectedIndex == index ? MockexaTheme.primary : MockexaTheme.textSecondary
        }
        if index == feedback.correctIndex { return MockexaTheme.success }
        if index == feedback.selectedIndex && !feedback.isCorrect { return MockexaTheme.destructive }
        return MockexaTheme.textSecondary
    }

    private func optionIcon(_ index: Int) -> String {
        guard let feedback = viewModel.feedback else { return "checkmark.circle.fill" }
        if index == feedback.correctIndex { return "checkmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func feedbackCard(_ feedback: AptitudeAnswerResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    feedback.isCorrect ? "Correct Answer" : "Review This Concept",
                    systemImage: feedback.isCorrect ? "checkmark.seal.fill" : "lightbulb.fill"
                )
                .font(.headline)
                .foregroundStyle(feedback.isCorrect ? MockexaTheme.success : MockexaTheme.warning)
                Text(feedback.explanation)
                    .font(.subheadline)
                    .foregroundStyle(MockexaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func reportContent(_ report: AptitudeReport) -> some View {
        VStack(spacing: 18) {
            Image(systemName: report.passed ? "checkmark.seal.fill" : "chart.bar.doc.horizontal.fill")
                .font(.system(size: 50))
                .foregroundStyle(report.passed ? MockexaTheme.success : MockexaTheme.warning)
            Text("Aptitude Round Complete")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(MockexaTheme.darkNavy)
            ScoreRing(score: report.overallScore, size: 150)

            GlassCard {
                HStack {
                    StatTile(value: "\(report.correct)", label: "Correct")
                    StatTile(value: "\(report.incorrect)", label: "Incorrect")
                    StatTile(value: "\(report.unanswered)", label: "Unanswered")
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CATEGORY PERFORMANCE").font(.caption.bold()).foregroundStyle(MockexaTheme.primary)
                    ForEach(report.categoryScores.keys.sorted(), id: \.self) { category in
                        MetricBar(title: category, value: report.categoryScores[category] ?? 0, color: MockexaTheme.primary)
                    }
                }
            }

            if !report.focusAreas.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Focus Areas", systemImage: "scope").font(.headline).foregroundStyle(MockexaTheme.warning)
                        Text(report.focusAreas.joined(separator: " • "))
                            .font(.subheadline).foregroundStyle(MockexaTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                app.tab = .history
            } label: {
                Label("View in History", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(MockexaTheme.primary)
        }
    }
}
