import SwiftUI

// MARK: - Navigation Route Types
enum QuestionBankRoute: Hashable {
    case home
    case allCompanies
    case companyDetail(String)
}

// MARK: - Question Categories (Future Architecture - Task 8)
enum QuestionCategory: String, CaseIterable, Codable, Hashable {
    case all = "All"
    case dsa = "DSA"
    case technical = "Technical"
    case systemDesign = "System Design"
    case hr = "HR"
    case behavioral = "Behavioral"
    case coding = "Coding"
    case aptitude = "Aptitude"
    case roleSpecific = "Role-specific"
}

// MARK: - Source-backed company practice API models
struct CompanyQuestion: Identifiable, Codable, Hashable {
    let id: String
    let companyId: String
    let prompt: String
    let category: String
    let role: String
    let round: String
    let year: Int
    let difficulty: Int
    let sourceTitle: String
    let sourceURL: String
    let sourceKind: String

    var formattedYear: String {
        String(year)
    }

    enum CodingKeys: String, CodingKey {
        case id, prompt, category, role, round, year, difficulty
        case companyId = "company_id"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case sourceKind = "source_kind"
    }
}

struct CompanyQuestionReview: Codable, Hashable {
    let id: String
    let companyId: String
    let prompt: String
    let category: String
    let role: String
    let round: String
    let year: Int
    let difficulty: Int
    let sourceTitle: String
    let sourceURL: String
    let sourceKind: String
    let focusPoints: [String]
    let answerOutline: String

    var formattedYear: String {
        String(year)
    }

    enum CodingKeys: String, CodingKey {
        case id, prompt, category, role, round, year, difficulty
        case companyId = "company_id"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case sourceKind = "source_kind"
        case focusPoints = "focus_points"
        case answerOutline = "answer_outline"
    }
}

struct CompanyCatalogItem: Codable {
    let id: String
    let name: String
    let focus: String
    let questionCount: Int
    let categories: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, focus, categories
        case questionCount = "question_count"
    }
}

struct CompanyPracticeStartRequest: Codable {
    let companyId: String
    let categories: [String]
    let role: String?
    let questionCount: Int
    let evaluationMode: String

    enum CodingKeys: String, CodingKey {
        case categories, role
        case companyId = "company_id"
        case questionCount = "question_count"
        case evaluationMode = "evaluation_mode"
    }
}

struct CompanyPracticeStartResponse: Codable {
    let sessionId: String
    let company: CompanyCatalogItem
    let question: CompanyQuestion
    let questionNumber: Int
    let totalQuestions: Int

    enum CodingKeys: String, CodingKey {
        case company, question
        case sessionId = "session_id"
        case questionNumber = "question_number"
        case totalQuestions = "total_questions"
    }
}

struct CompanyPracticeAnswerRequest: Codable {
    let sessionId: String
    let answer: String

    enum CodingKeys: String, CodingKey {
        case answer
        case sessionId = "session_id"
    }
}

struct CompanyPracticeEvaluation: Codable {
    let classification: String
    let correctness: Double
    let completeness: Double
    let relevance: Double
    let reasoning: Double
    let overallScore: Double
    let missingConcepts: [String]
    let feedback: String

    enum CodingKeys: String, CodingKey {
        case classification, correctness, completeness, relevance, reasoning, feedback
        case overallScore = "overall_score"
        case missingConcepts = "missing_concepts"
    }
}

struct CompanyPracticeAnswerResponse: Codable {
    let sessionId: String
    let evaluation: CompanyPracticeEvaluation
    let reviewedQuestion: CompanyQuestionReview
    let nextQuestion: CompanyQuestion?
    let questionNumber: Int
    let totalQuestions: Int
    let averageScore: Double
    let completed: Bool

    enum CodingKeys: String, CodingKey {
        case evaluation, completed
        case sessionId = "session_id"
        case reviewedQuestion = "reviewed_question"
        case nextQuestion = "next_question"
        case questionNumber = "question_number"
        case totalQuestions = "total_questions"
        case averageScore = "average_score"
    }
}

struct CompanyPracticeReport: Codable {
    let sessionId: String
    let companyId: String
    let companyName: String
    let questionsAnswered: Int
    let overallScore: Int
    let categoryScores: [String: Int]
    let strengths: [String]
    let focusAreas: [String]

    enum CodingKeys: String, CodingKey {
        case strengths
        case sessionId = "session_id"
        case companyId = "company_id"
        case companyName = "company_name"
        case questionsAnswered = "questions_answered"
        case overallScore = "overall_score"
        case categoryScores = "category_scores"
        case focusAreas = "focus_areas"
    }
}

@MainActor
final class CompanyQuestionBankViewModel: ObservableObject {
    @Published var questions: [CompanyQuestion] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(companyId: String, token: String?) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            questions = try await APIClient.shared.get(
                endpoint: "/company/\(companyId)/questions?limit=20&shuffle=true",
                token: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class CompanyPracticeViewModel: ObservableObject {
    @Published var sessionId: String?
    @Published var currentQuestion: CompanyQuestion?
    @Published var lastEvaluation: CompanyPracticeEvaluation?
    @Published var lastReview: CompanyQuestionReview?
    @Published var report: CompanyPracticeReport?
    @Published var questionNumber = 1
    @Published var totalQuestions = 1
    @Published var averageScore = 0.0
    @Published var isLoading = false
    @Published var isCompleted = false
    @Published var errorMessage: String?

    func start(companyId: String, categories: [String], count: Int, useDeepAI: Bool, token: String?) async {
        guard sessionId == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let request = CompanyPracticeStartRequest(
                companyId: companyId,
                categories: categories,
                role: nil,
                questionCount: count,
                evaluationMode: useDeepAI ? "ai" : "fast"
            )
            let response: CompanyPracticeStartResponse = try await APIClient.shared.post(
                endpoint: "/company/start", body: request, token: token
            )
            sessionId = response.sessionId
            currentQuestion = response.question
            questionNumber = response.questionNumber
            totalQuestions = response.totalQuestions
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func submit(answer: String, token: String?) async {
        guard let sessionId, !isLoading, !isCompleted else { return }
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return }
        isLoading = true
        errorMessage = nil
        do {
            let request = CompanyPracticeAnswerRequest(sessionId: sessionId, answer: clean)
            let response: CompanyPracticeAnswerResponse = try await APIClient.shared.post(
                endpoint: "/company/answer", body: request, token: token
            )
            lastEvaluation = response.evaluation
            lastReview = response.reviewedQuestion
            currentQuestion = response.nextQuestion
            questionNumber = response.questionNumber
            totalQuestions = response.totalQuestions
            averageScore = response.averageScore
            isCompleted = response.completed
            if response.completed {
                await finish(token: token)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func finish(token: String?) async {
        guard let sessionId, report == nil else { return }
        do {
            report = try await APIClient.shared.postEmpty(
                endpoint: "/company/finish/\(sessionId)", token: token
            )
            isCompleted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Single Source of Truth: Company Info (Tasks 2, 3, 4, 5)
struct CompanyInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let logoAssetName: String
    let brandColor: Color

    // Exactly 12 supported companies for this release
    static let all: [CompanyInfo] = [
        CompanyInfo(
            id: "google",
            name: "Google",
            logoAssetName: "CompanyLogos/company_google",
            brandColor: Color(red: 66/255, green: 133/255, blue: 244/255)
        ),
        CompanyInfo(
            id: "amazon",
            name: "Amazon",
            logoAssetName: "CompanyLogos/company_amazon",
            brandColor: Color(red: 255/255, green: 153/255, blue: 0/255)
        ),
        CompanyInfo(
            id: "microsoft",
            name: "Microsoft",
            logoAssetName: "CompanyLogos/company_microsoft",
            brandColor: Color(red: 0/255, green: 120/255, blue: 212/255)
        ),
        CompanyInfo(
            id: "apple",
            name: "Apple",
            logoAssetName: "CompanyLogos/company_apple",
            brandColor: Color(red: 24/255, green: 24/255, blue: 27/255)
        ),
        CompanyInfo(
            id: "meta",
            name: "Meta",
            logoAssetName: "CompanyLogos/company_meta",
            brandColor: Color(red: 24/255, green: 119/255, blue: 242/255)
        ),
        CompanyInfo(
            id: "adobe",
            name: "Adobe",
            logoAssetName: "CompanyLogos/company_adobe",
            brandColor: Color(red: 255/255, green: 0/255, blue: 0/255)
        ),
        CompanyInfo(
            id: "flipkart",
            name: "Flipkart",
            logoAssetName: "CompanyLogos/company_flipkart",
            brandColor: Color(red: 47/255, green: 113/255, blue: 205/255)
        ),
        CompanyInfo(
            id: "atlassian",
            name: "Atlassian",
            logoAssetName: "CompanyLogos/company_atlassian",
            brandColor: Color(red: 0/255, green: 82/255, blue: 204/255)
        ),
        CompanyInfo(
            id: "accenture",
            name: "Accenture",
            logoAssetName: "CompanyLogos/company_accenture",
            brandColor: Color(red: 160/255, green: 0/255, blue: 200/255)
        ),
        CompanyInfo(
            id: "deloitte",
            name: "Deloitte",
            logoAssetName: "CompanyLogos/company_deloitte",
            brandColor: Color(red: 134/255, green: 188/255, blue: 37/255)
        ),
        CompanyInfo(
            id: "jpmorgan",
            name: "JPMorgan",
            logoAssetName: "CompanyLogos/company_jpmorgan",
            brandColor: Color(red: 0/255, green: 51/255, blue: 160/255)
        ),
        CompanyInfo(
            id: "goldman_sachs",
            name: "Goldman Sachs",
            logoAssetName: "CompanyLogos/company_goldman_sachs",
            brandColor: Color(red: 108/255, green: 117/255, blue: 125/255)
        )
    ]

    // Popular subset (exactly 6) referencing the same models (Task 4)
    static let popular: [CompanyInfo] = {
        let popularIds = ["google", "amazon", "microsoft", "apple", "meta", "adobe"]
        return popularIds.compactMap { id in all.first(where: { $0.id == id }) }
    }()

    // Lookup helper
    static func find(by nameOrId: String) -> CompanyInfo? {
        let trimmed = nameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first {
            $0.id.localizedCaseInsensitiveCompare(trimmed) == .orderedSame ||
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}

// MARK: - Reusable Company Logo View
struct CompanyLogoView: View {
    let company: CompanyInfo?
    let fallbackName: String
    var containerWidth: CGFloat = 46
    var containerHeight: CGFloat = 32

    init(company: CompanyInfo?, containerWidth: CGFloat = 46, containerHeight: CGFloat = 32) {
        self.company = company
        self.fallbackName = company?.name ?? ""
        self.containerWidth = containerWidth
        self.containerHeight = containerHeight
    }

    init(companyName: String, containerWidth: CGFloat = 46, containerHeight: CGFloat = 32) {
        self.company = CompanyInfo.find(by: companyName)
        self.fallbackName = companyName
        self.containerWidth = containerWidth
        self.containerHeight = containerHeight
    }

    // Backwards-compatible initializer
    init(company: CompanyInfo?, size: CGFloat, cornerRadius: CGFloat = 0) {
        self.company = company
        self.fallbackName = company?.name ?? ""
        self.containerWidth = size * 1.15
        self.containerHeight = size * 0.8
    }

    init(companyName: String, size: CGFloat, cornerRadius: CGFloat = 0) {
        self.company = CompanyInfo.find(by: companyName)
        self.fallbackName = companyName
        self.containerWidth = size * 1.15
        self.containerHeight = size * 0.8
    }

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: min(14, containerHeight * 0.28), style: .continuous)
                .fill((company?.brandColor ?? MockexaTheme.primary).opacity(0.09))
            RoundedRectangle(cornerRadius: min(14, containerHeight * 0.28), style: .continuous)
                .stroke((company?.brandColor ?? MockexaTheme.primary).opacity(0.16), lineWidth: 1)
            if let company {
                Image(company.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(max(6, min(containerWidth, containerHeight) * 0.18))
            } else {
                Text(initialsFor(fallbackName))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(company?.brandColor ?? MockexaTheme.primary)
            }
        }
        .frame(width: containerWidth, height: containerHeight, alignment: .center)
    }

    private func initialsFor(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        }
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Company Question Bank Home (Tasks 4, 6, 11, 12)
struct CompanyQuestionBankView: View {
    @State private var searchText = ""
    @AppStorage("MOCKEXA_TARGET_COMPANIES") private var targetCompanies = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredPopular: [CompanyInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return CompanyInfo.all.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
            }
        }
        let targets = targetCompanies
            .split(separator: ",")
            .compactMap { CompanyInfo.find(by: String($0)) }
        var seen = Set<String>()
        return (targets + CompanyInfo.popular).filter {
            seen.insert($0.id).inserted
        }
    }

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Company Question Bank")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    Text("Practice reported interview questions from top companies.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
                .padding(.top, 8)
                .staggeredEntrance(delay: 0.04)

                // Search
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MockexaTheme.textSecondary)
                    TextField("Search company...", text: $searchText)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(MockexaTheme.textSecondary)
                        }
                    }
                }
                .padding(14)
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(MockexaTheme.border, lineWidth: 1))
                .staggeredEntrance(delay: 0.08)

                // Popular Companies Section (Task 4)
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: targetCompanies.isEmpty ? "Popular Companies" : "Your Targets & Popular")

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ], spacing: 14) {
                        ForEach(Array(filteredPopular.enumerated()), id: \.element.id) { index, company in
                            NavigationLink(value: QuestionBankRoute.companyDetail(company.name)) {
                                InteractiveTouchCardBody(maxTilt: 4.0) { isPressed in
                                    CompanyCompactCard(company: company, isPressed: isPressed)
                                }
                            }
                            .buttonStyle(TouchCardButtonStyle())
                            .staggeredEntrance(delay: 0.12 + Double(index) * 0.04)
                        }
                    }

                    if filteredPopular.isEmpty {
                        GlassCard {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                Text("No supported company matches “\(searchText)”.")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                    .multilineTextAlignment(.center)
                                Button("Clear Search") { searchText = "" }
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .staggeredEntrance(delay: 0.10)

                // View All Companies Navigation Link
                NavigationLink(value: QuestionBankRoute.allCompanies) {
                    HStack {
                        Text("View All Companies")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(MockexaTheme.primary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MockexaTheme.primary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .staggeredEntrance(delay: 0.38)
            }
        }
        .navigationTitle("Question Bank")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Compact Company Card (Task 11)
private struct CompanyCompactCard: View {
    let company: CompanyInfo
    var isPressed: Bool = false

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                CompanyLogoView(company: company, containerWidth: 44, containerHeight: 44)
                    .scaleEffect(isPressed ? 1.05 : 1.0)
                Text(company.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - All Companies Screen (Tasks 2, 5, 11)
struct CompanyListView: View {
    @State private var searchText = ""

    // Exactly the 12 supported companies, filtered by search query
    private var filteredCompanies: [CompanyInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return CompanyInfo.all
        }
        return CompanyInfo.all.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("All Companies")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    Text("Browse supported companies and practice reported interview questions.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
                .padding(.top, 8)
                .staggeredEntrance(delay: 0.04)

                // Search across 12 companies (Task 5)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MockexaTheme.textSecondary)
                    TextField("Search company (e.g. Google, Amazon)...", text: $searchText)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(MockexaTheme.textSecondary)
                        }
                    }
                }
                .padding(14)
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(MockexaTheme.border, lineWidth: 1))
                .staggeredEntrance(delay: 0.08)

                // Company Rows: [ REAL LOGO ]   Company Name   >
                VStack(spacing: 10) {
                    ForEach(Array(filteredCompanies.enumerated()), id: \.element.id) { index, company in
                        NavigationLink(value: QuestionBankRoute.companyDetail(company.name)) {
                            InteractiveTouchCardBody(maxTilt: 4.0) { isPressed in
                                GlassCard {
                                    HStack(spacing: 14) {
                                        CompanyLogoView(company: company, containerWidth: 50, containerHeight: 50)
                                        Text(company.name)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(MockexaTheme.darkNavy)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(MockexaTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(TouchCardButtonStyle())
                        .staggeredEntrance(delay: 0.08 + Double(index) * 0.025)
                    }
                }

                if filteredCompanies.isEmpty {
                    GlassCard {
                        VStack(spacing: 8) {
                            Text("No supported company found.")
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.darkNavy)
                            Button("Clear Search") { searchText = "" }
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("All Companies")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Company question browser and practice setup
struct CompanyQuestionListView: View {
    let companyName: String
    @StateObject private var viewModel = CompanyQuestionBankViewModel()
    @EnvironmentObject private var auth: AuthManager
    @State private var selectedCategories = Set<String>()
    @State private var questionCount = 5
    @State private var useDeepAI = false

    private let categories = ["DSA", "Technical", "System Design", "Behavioral"]

    private var company: CompanyInfo? {
        CompanyInfo.find(by: companyName)
    }

    private var filteredQuestions: [CompanyQuestion] {
        guard !selectedCategories.isEmpty else { return viewModel.questions }
        return viewModel.questions.filter { selectedCategories.contains($0.category) }
    }

    private var availableQuestionCount: Int { filteredQuestions.count }

    private var canStartPractice: Bool {
        !viewModel.isLoading && viewModel.errorMessage == nil && availableQuestionCount > 0
    }

    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    CompanyLogoView(company: company, containerWidth: 58, containerHeight: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(companyName) Interview Questions")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(MockexaTheme.darkNavy)
                        Text("Reported questions from \(companyName) interviews.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(MockexaTheme.textSecondary)
                    }
                }
                .padding(.top, 8)
                .staggeredEntrance(delay: 0.04)

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Build a shuffled practice session")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(MockexaTheme.darkNavy)

                        Text("Choose interview areas, or leave all unselected to mix every type. Each prompt includes its source link.")
                            .font(.subheadline)
                            .foregroundStyle(MockexaTheme.textSecondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(categories, id: \.self) { category in
                                    Button {
                                        Haptics.selection()
                                        if selectedCategories.contains(category) {
                                            selectedCategories.remove(category)
                                        } else {
                                            selectedCategories.insert(category)
                                        }
                                    } label: {
                                        Text(category)
                                            .font(.caption.bold())
                                            .frame(maxWidth: .infinity)
                                            .foregroundStyle(selectedCategories.contains(category) ? .white : MockexaTheme.darkNavy)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                selectedCategories.contains(category) ? MockexaTheme.primary : MockexaTheme.surface,
                                                in: Capsule()
                                            )
                                            .overlay(Capsule().stroke(MockexaTheme.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                        }

                        Stepper(
                            "\(min(questionCount, max(1, availableQuestionCount))) shuffled questions",
                            value: $questionCount,
                            in: 1...max(1, min(10, availableQuestionCount))
                        )
                            .font(.subheadline.bold())
                            .foregroundStyle(MockexaTheme.darkNavy)

                        Toggle(isOn: $useDeepAI) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(useDeepAI ? "Deep AI evaluation" : "Fast evaluation")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text(useDeepAI ? "Richer feedback • may take a few seconds" : "Instant scoring • recommended for practice")
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                        }
                        .tint(MockexaTheme.primary)

                        NavigationLink {
                            CompanyPracticeView(
                                company: company,
                                categories: Array(selectedCategories).sorted(),
                                questionCount: min(questionCount, availableQuestionCount),
                                useDeepAI: useDeepAI
                            )
                        } label: {
                            Label("Start \(companyName) Practice", systemImage: "shuffle")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(MockexaTheme.gradient, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .disabled(!canStartPractice)
                        .opacity(canStartPractice ? 1 : 0.5)
                    }
                }
                .staggeredEntrance(delay: 0.10)

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading reported questions…")
                            .tint(MockexaTheme.primary)
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else if let error = viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Questions could not be loaded.")
                            .font(.subheadline.bold())
                            .foregroundStyle(MockexaTheme.darkNavy)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(MockexaTheme.destructive)
                        Button("Retry") {
                            guard let company else { return }
                            Task { await viewModel.load(companyId: company.id, token: auth.accessToken) }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MockexaTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    HStack {
                        SectionHeader(title: "Reported Question Preview")
                        Spacer()
                        Text("\(filteredQuestions.count) available")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.textSecondary)
                    }

                    ForEach(filteredQuestions) { question in
                        CompanyQuestionPreviewCard(question: question, brandColor: company?.brandColor ?? MockexaTheme.primary)
                    }

                    if filteredQuestions.isEmpty {
                        Text("No reported questions are available for the selected areas. Choose another interview area.")
                            .font(.subheadline)
                            .foregroundStyle(MockexaTheme.textSecondary)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .navigationTitle(companyName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let company {
                await viewModel.load(companyId: company.id, token: auth.accessToken)
            }
        }
        .onChange(of: selectedCategories) { _, _ in
            questionCount = min(questionCount, max(1, min(10, availableQuestionCount)))
        }
        .onChange(of: viewModel.questions.count) { _, _ in
            questionCount = min(questionCount, max(1, min(10, availableQuestionCount)))
        }
    }
}

private struct CompanyQuestionPreviewCard: View {
    let question: CompanyQuestion
    let brandColor: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(question.category.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(brandColor)
                    Text("• \(question.round) • \(question.formattedYear)")
                        .font(.caption2)
                        .foregroundStyle(MockexaTheme.textSecondary)
                    Spacer()
                    Text("Level \(question.difficulty)/5")
                        .font(.caption2.bold())
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
                Text(question.prompt)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MockexaTheme.darkNavy)
                    .lineLimit(4)
                if let url = URL(string: question.sourceURL) {
                    Link(destination: url) {
                        Label(question.sourceKind == "candidate_report" ? "Candidate-reported source" : "Frequently-asked collection", systemImage: "link")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.primary)
                    }
                }
            }
        }
    }
}

struct CompanyPracticeView: View {
    let company: CompanyInfo?
    let categories: [String]
    let questionCount: Int
    let useDeepAI: Bool

    @StateObject private var viewModel = CompanyPracticeViewModel()
    @StateObject private var voice = VoiceFoundation.shared
    @EnvironmentObject private var auth: AuthManager
    @State private var answer = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        CompanyLogoView(company: company, containerWidth: 52, containerHeight: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(company?.name ?? "Company") Practice")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(MockexaTheme.darkNavy)
                            Text(viewModel.isCompleted ? "Session complete" : "Question \(viewModel.questionNumber) of \(viewModel.totalQuestions)")
                                .font(.caption.bold())
                                .foregroundStyle(viewModel.isCompleted ? MockexaTheme.success : MockexaTheme.textSecondary)
                        }
                        Spacer()
                        if !viewModel.isCompleted {
                            Text("\(Int(viewModel.averageScore * 100)) avg")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.primary)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.destructive)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MockexaTheme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if viewModel.isLoading && viewModel.currentQuestion == nil && !viewModel.isCompleted {
                        ProgressView("Preparing a shuffled interview…")
                            .tint(MockexaTheme.primary)
                            .padding(.vertical, 50)
                    } else if let question = viewModel.currentQuestion {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("\(question.category.uppercased()) • \(question.round.uppercased())")
                                        .font(.caption.bold())
                                        .foregroundStyle(company?.brandColor ?? MockexaTheme.primary)
                                    Spacer()
                                    Button {
                                        if voice.isSpeaking {
                                            voice.stopSpeaking()
                                        } else {
                                            voice.speak(text: question.prompt, speakerName: "Company Interviewer", autoListenOnFinish: false)
                                        }
                                    } label: {
                                        Image(systemName: voice.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                            .frame(width: 38, height: 38)
                                            .background(MockexaTheme.primary.opacity(0.10), in: Circle())
                                            .foregroundStyle(MockexaTheme.primary)
                                    }
                                }
                                Text(question.prompt)
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                    .lineSpacing(4)
                                HStack {
                                    Text("\(question.role) • \(question.formattedYear) • Level \(question.difficulty)/5")
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    Spacer()
                                    if let url = URL(string: question.sourceURL) {
                                        Link("Source", destination: url)
                                            .font(.caption.bold())
                                    }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your answer")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                TextEditor(text: $answer)
                                    .frame(minHeight: 150)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(MockexaTheme.border, lineWidth: 1))
                                    .foregroundStyle(MockexaTheme.textPrimary)
                                    .disabled(viewModel.isLoading)
                            }
                        }

                        PrimaryButton(title: viewModel.isLoading ? "Evaluating…" : "Submit & Continue") {
                            let submitted = answer
                            answer = ""
                            Task { await viewModel.submit(answer: submitted, token: auth.accessToken) }
                        }
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || viewModel.isLoading)
                    }

                    if let evaluation = viewModel.lastEvaluation, let review = viewModel.lastReview {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("LATEST FEEDBACK")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.primary)
                                    Spacer()
                                    Text("\(Int(evaluation.overallScore * 100))/100")
                                        .font(.headline.bold())
                                        .foregroundStyle(MockexaTheme.darkNavy)
                                }
                                Text(evaluation.feedback)
                                    .font(.subheadline)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                if !evaluation.missingConcepts.isEmpty {
                                    Text("Revisit: \(evaluation.missingConcepts.joined(separator: ", "))")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.warning)
                                }
                                DisclosureGroup("Suggested answer direction") {
                                    Text(review.answerOutline)
                                        .font(.subheadline)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                        .padding(.top, 6)
                                }
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.darkNavy)
                            }
                        }
                    }

                    if let report = viewModel.report {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Practice Summary")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text("\(report.overallScore)/100")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(report.overallScore >= 70 ? MockexaTheme.success : MockexaTheme.warning)
                                Text("\(report.questionsAnswered) questions answered")
                                    .font(.subheadline)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                ForEach(report.categoryScores.keys.sorted(), id: \.self) { category in
                                    HStack {
                                        Text(category)
                                        Spacer()
                                        Text("\(report.categoryScores[category] ?? 0)%").bold()
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                }
                                if !report.focusAreas.isEmpty {
                                    Text("Focus next: \(report.focusAreas.joined(separator: ", "))")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.warning)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let company else { return }
            await viewModel.start(
                companyId: company.id,
                categories: categories,
                count: questionCount,
                useDeepAI: useDeepAI,
                token: auth.accessToken
            )
        }
        .onDisappear { voice.stopSpeaking() }
    }
}
