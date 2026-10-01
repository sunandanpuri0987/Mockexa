import Foundation
import Combine
import SwiftUI

// MARK: - Transcript Entry UI Model
struct TranscriptEntry: Identifiable, Hashable {
    let id = UUID()
    let speaker: String
    let text: String
    let timestamp: String
}

// MARK: - GD Participant UI Model
struct GDParticipant: Identifiable, Hashable {
    let id: String
    let name: String
    let initials: String
    let role: String
    let color: Color
}

private func currentTimeString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "mm:ss"
    return formatter.string(from: Date())
}

// MARK: - Technical Interview ViewModel
@MainActor
final class TechnicalViewModel: ObservableObject {
    @Published var sessionId: String? = nil
    @Published var currentQuestion: QuestionOut? = nil
    @Published var lastAnalysis: AnswerAnalysisOut? = nil
    @Published var questionHistory: [QuestionOut] = []
    @Published var answersHistory: [String] = []
    @Published var transcriptEntries: [TranscriptEntry] = []
    @Published var isCompleted: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var reportData: [String: AnyCodable]? = nil
    @Published var questionIndex: Int = 1
    @Published var totalQuestions: Int = 5
    
    private let apiClient = APIClient.shared
    
    func startSession(
        name: String = "Candidate",
        targetRole: String = "Software Engineer",
        experience: String = "0-1 years",
        domains: [String] = ["Data Structures"],
        difficulty: Int = 3,
        maxQuestions: Int = 5,
        resumeContext: String? = nil,
        jobDescription: String? = nil,
        token: String?
    ) async {
        isLoading = true
        errorMessage = nil
        isCompleted = false
        currentQuestion = nil
        lastAnalysis = nil
        reportData = nil
        questionHistory = []
        answersHistory = []
        transcriptEntries = []
        questionIndex = 1
        totalQuestions = maxQuestions

        // Fallback to active resume context if not explicitly provided
        let activeCtx = ResumeViewModel.getActiveResumeContext()
        let resolvedResumeContext = resumeContext ?? activeCtx?.context
        let resolvedJobDescription = jobDescription ?? (activeCtx?.jobDescription.isEmpty == false ? activeCtx?.jobDescription : nil)

        let request = TechnicalStartRequest(
            name: name,
            targetRole: targetRole,
            experience: experience,
            skills: ["Python", "Swift", "Algorithms"],
            selectedDomains: domains,
            desiredDifficulty: difficulty,
            mode: "PRACTICE",
            maxQuestions: maxQuestions,
            resumeContext: resolvedResumeContext,
            jobDescription: resolvedJobDescription
        )

        do {
            let response: TechnicalStartResponse = try await apiClient.post(endpoint: "/technical/start", body: request, token: token)
            self.sessionId = response.sessionId
            self.currentQuestion = response.question
            self.questionHistory.append(response.question)
            self.transcriptEntries.append(TranscriptEntry(speaker: "AI Interviewer", text: response.question.question, timestamp: currentTimeString()))
        } catch let err as APIError {
            handleAPIError(err)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func submitAnswer(answer: String, hintsUsed: Int = 0, token: String?) async {
        guard let sid = sessionId, !isLoading, !isCompleted else { return }
        let cleanAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAnswer.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        let request = TechnicalAnswerRequest(sessionId: sid, answer: cleanAnswer, hintsUsed: hintsUsed)
        
        do {
            let response: TechnicalAnswerResponse = try await apiClient.post(endpoint: "/technical/answer", body: request, token: token)
            self.answersHistory.append(cleanAnswer)
            self.transcriptEntries.append(TranscriptEntry(speaker: "You", text: cleanAnswer, timestamp: currentTimeString()))
            self.lastAnalysis = response.analysis
            
            if response.completed || response.nextQuestion == nil {
                self.isCompleted = true
                self.currentQuestion = nil
            } else if let nextQ = response.nextQuestion {
                self.currentQuestion = nextQ
                self.questionHistory.append(nextQ)
                self.questionIndex += 1
                self.transcriptEntries.append(TranscriptEntry(speaker: "AI Interviewer", text: nextQ.question, timestamp: currentTimeString()))
            }
        } catch let err as APIError {
            if case .serverError(let code, _) = err, code == 409 {
                self.isCompleted = true
                self.currentQuestion = nil
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func finishSession(token: String?) async {
        if reportData != nil {
            isLoading = false
            errorMessage = nil
            return
        }
        guard let sid = sessionId else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let response: TechnicalFinishResponse = try await apiClient.postEmpty(endpoint: "/technical/finish/\(sid)", token: token)
            self.reportData = response.report
            self.isCompleted = true
        } catch let err as APIError {
            if case .serverError(let code, _) = err, code == 409 {
                self.isCompleted = true
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func handleAPIError(_ error: APIError) {
        if case .unauthorized = error {
            NotificationCenter.default.post(name: Notification.Name("PREPAI_SESSION_EXPIRED"), object: nil)
        }
        self.errorMessage = error.localizedDescription
    }
}

// MARK: - HR Interview ViewModel
@MainActor
final class HRViewModel: ObservableObject {
    @Published var sessionId: String? = nil
    @Published var currentQuestion: HRQuestionOut? = nil
    @Published var lastEvaluation: HREvaluationOut? = nil
    @Published var questionHistory: [HRQuestionOut] = []
    @Published var answersHistory: [String] = []
    @Published var transcriptEntries: [TranscriptEntry] = []
    @Published var isCompleted: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var reportData: [String: AnyCodable]? = nil
    @Published var questionIndex: Int = 1
    @Published var totalQuestions: Int = 5
    
    private let apiClient = APIClient.shared
    
    func startSession(
        name: String = "Candidate",
        targetRole: String = "Software Engineer",
        experience: String = "0-1 years",
        maxQuestions: Int = 5,
        interviewStyle: String = "General HR",
        resumeContext: String? = nil,
        jobDescription: String? = nil,
        token: String?
    ) async {
        isLoading = true
        errorMessage = nil
        isCompleted = false
        currentQuestion = nil
        lastEvaluation = nil
        reportData = nil
        questionHistory = []
        answersHistory = []
        transcriptEntries = []
        questionIndex = 1
        totalQuestions = maxQuestions
        
        // Fallback to active resume context if not explicitly provided
        let activeCtx = ResumeViewModel.getActiveResumeContext()
        let resolvedResumeContext = resumeContext ?? activeCtx?.context
        let resolvedJobDescription = jobDescription ?? (activeCtx?.jobDescription.isEmpty == false ? activeCtx?.jobDescription : nil)

        let request = HRStartRequest(
            name: name,
            targetRole: targetRole,
            experience: experience,
            maxQuestions: maxQuestions,
            interviewStyle: interviewStyle,
            resumeContext: resolvedResumeContext,
            jobDescription: resolvedJobDescription
        )
        
        do {
            let response: HRStartResponse = try await apiClient.post(endpoint: "/hr/start", body: request, token: token)
            self.sessionId = response.sessionId
            self.currentQuestion = response.question
            self.questionHistory.append(response.question)
            self.transcriptEntries.append(TranscriptEntry(speaker: "HR Interviewer", text: response.question.question, timestamp: currentTimeString()))
        } catch let err as APIError {
            handleAPIError(err)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func submitAnswer(answer: String, token: String?) async {
        guard let sid = sessionId, !isLoading, !isCompleted else { return }
        let cleanAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAnswer.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        let request = HRAnswerRequest(sessionId: sid, answer: cleanAnswer)
        
        do {
            let response: HRAnswerResponse = try await apiClient.post(endpoint: "/hr/answer", body: request, token: token)
            self.answersHistory.append(cleanAnswer)
            self.transcriptEntries.append(TranscriptEntry(speaker: "You", text: cleanAnswer, timestamp: currentTimeString()))
            self.lastEvaluation = response.evaluation
            
            if response.completed || response.nextQuestion == nil {
                self.isCompleted = true
                self.currentQuestion = nil
            } else if let nextQ = response.nextQuestion {
                self.currentQuestion = nextQ
                self.questionHistory.append(nextQ)
                self.questionIndex += 1
                self.transcriptEntries.append(TranscriptEntry(speaker: "HR Interviewer", text: nextQ.question, timestamp: currentTimeString()))
            }
        } catch let err as APIError {
            if case .serverError(let code, _) = err, code == 409 {
                self.isCompleted = true
                self.currentQuestion = nil
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func finishSession(token: String?) async {
        if reportData != nil {
            isLoading = false
            errorMessage = nil
            return
        }
        guard let sid = sessionId else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let response: HRFinishResponse = try await apiClient.postEmpty(endpoint: "/hr/finish/\(sid)", token: token)
            self.reportData = response.report
            self.isCompleted = true
        } catch let err as APIError {
            if case .serverError(let code, _) = err, code == 409 {
                self.isCompleted = true
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func handleAPIError(_ error: APIError) {
        if case .unauthorized = error {
            NotificationCenter.default.post(name: Notification.Name("PREPAI_SESSION_EXPIRED"), object: nil)
        }
        self.errorMessage = error.localizedDescription
    }
}

// MARK: - Group Discussion ViewModel
@MainActor
final class GDViewModel: ObservableObject {
    @Published var sessionId: String? = nil
    @Published var topic: String = "Remote work and productivity"
    @Published var participants: [GDParticipant] = []
    @Published var turnsHistory: [GDTurnResponse] = []
    @Published var transcriptEntries: [TranscriptEntry] = []
    @Published var currentTurn: GDTurnResponse? = nil
    @Published var isGeneratingTurn: Bool = false
    @Published var isFinished: Bool = false
    @Published var isFinishing: Bool = false
    @Published var metrics: [String: Double]? = nil
    @Published var summary: [String: AnyCodable]? = nil
    @Published var errorMessage: String? = nil
    @Published var currentSpeakerIndex: Int = 0
    @Published var interruptionCount: Int = 0
    @Published private(set) var didReachTimeLimit: Bool = false
    
    private let apiClient = APIClient.shared
    private static let avatarColors: [Color] = [PrepTheme.primary, .blue, .pink, .orange, PrepTheme.secondary]
    
    private func updateSpeakerIndex(for speakerName: String) {
        let normSpeaker = speakerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let matchedIdx = self.participants.firstIndex(where: { p in
            let pName = p.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return pName == normSpeaker || normSpeaker.contains(pName) || pName.contains(normSpeaker)
        }) {
            self.currentSpeakerIndex = matchedIdx
        }
    }
    
    func startGD(topic: String = "Remote work and productivity", numRounds: Int = 4, mode: String = "balanced", durationStr: String? = nil, aiStarts: Bool = true, resumeContext: String? = nil, jobDescription: String? = nil, token: String?) async {
        guard !isGeneratingTurn else { return }
        isGeneratingTurn = true
        errorMessage = nil
        sessionId = nil
        turnsHistory = []
        transcriptEntries = []
        currentTurn = nil
        isFinished = false
        metrics = nil
        summary = nil
        currentSpeakerIndex = 0
        interruptionCount = 0
        didReachTimeLimit = false
        self.topic = topic
        
        var resolvedRounds = numRounds
        if let dStr = durationStr {
            let cleanD = dStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if cleanD.contains("15") {
                resolvedRounds = 6
            } else if cleanD.contains("10") {
                resolvedRounds = 4
            } else if cleanD.contains("5") {
                resolvedRounds = 2
            }
        }
        let resolvedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "balanced" : mode

        let durationDigits = durationStr?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? ""
        let durationMinutes = Int(durationDigits)
        
        // Fallback to active resume context if not explicitly provided
        let activeCtx = ResumeViewModel.getActiveResumeContext()
        let resolvedResumeContext = resumeContext ?? activeCtx?.context
        let resolvedJobDescription = jobDescription ?? (activeCtx?.jobDescription.isEmpty == false ? activeCtx?.jobDescription : nil)

        let request = GDStartRequest(
            topic: topic,
            numRounds: resolvedRounds,
            durationMinutes: durationMinutes,
            mode: resolvedMode,
            resumeContext: resolvedResumeContext,
            jobDescription: resolvedJobDescription
        )
        
        do {
            let response: GDStartResponse = try await apiClient.post(endpoint: "/gd/start", body: request, token: token)
            self.sessionId = response.sessionId
            
            var parsedParticipants: [GDParticipant] = []
            for (idx, pDict) in response.participants.enumerated() {
                let name = pDict["name"]?.value as? String ?? pDict["participant_id"]?.value as? String ?? "Participant \(idx+1)"
                let role = pDict["role"]?.value as? String ?? pDict["persona"]?.value as? String ?? "Speaker"
                let initials = String(name.prefix(1)).uppercased()
                let color = Self.avatarColors[idx % Self.avatarColors.count]
                
                parsedParticipants.append(GDParticipant(id: name, name: name, initials: initials, role: role, color: color))
            }
            
            self.participants = parsedParticipants
            
            if aiStarts, let sid = self.sessionId {
                let respondReq = GDRespondRequest(sessionId: sid, userContribution: nil)
                let respondResp: GDRespondResponse = try await apiClient.post(endpoint: "/gd/respond", body: respondReq, token: token)
                
                if let turn = respondResp.turn {
                    self.currentTurn = turn
                    self.turnsHistory.append(turn)
                    self.transcriptEntries.append(TranscriptEntry(speaker: turn.speaker, text: turn.response, timestamp: currentTimeString()))
                    updateSpeakerIndex(for: turn.speaker)
                }
                
                self.isFinished = respondResp.finished
            }
        } catch is CancellationError {
            // Task cancelled by SwiftUI lifecycle, do not display error banner
        } catch let err as APIError {
            handleAPIError(err)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isGeneratingTurn = false
    }
    
    func requestNextTurn(token: String?) async {
        guard let sid = sessionId, !isFinished, !isGeneratingTurn else { return }
        isGeneratingTurn = true
        errorMessage = nil
        
        let request = GDRespondRequest(sessionId: sid, userContribution: nil)
        
        do {
            let response: GDRespondResponse = try await apiClient.post(endpoint: "/gd/respond", body: request, token: token)
            guard !didReachTimeLimit else {
                isGeneratingTurn = false
                return
            }
            
            if let turn = response.turn {
                self.currentTurn = turn
                self.turnsHistory.append(turn)
                self.transcriptEntries.append(TranscriptEntry(speaker: turn.speaker, text: turn.response, timestamp: currentTimeString()))
                updateSpeakerIndex(for: turn.speaker)
            }
            
            self.isFinished = response.finished
        } catch let err as APIError {
            if case .serverError(let code, _) = err, code == 409 {
                self.isFinished = true
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isGeneratingTurn = false
    }
    
    func submitUserContribution(_ text: String, token: String?) async {
        guard let sid = sessionId, !isFinished, !isGeneratingTurn else { return }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        isGeneratingTurn = true
        errorMessage = nil
        
        let pendingUserEntry = TranscriptEntry(speaker: "You", text: cleanText, timestamp: currentTimeString())
        transcriptEntries.append(pendingUserEntry)
        
        let request = GDRespondRequest(sessionId: sid, userContribution: cleanText)
        
        do {
            let response: GDRespondResponse = try await apiClient.post(endpoint: "/gd/respond", body: request, token: token)
            guard !didReachTimeLimit else {
                isGeneratingTurn = false
                return
            }
            
            if let turn = response.turn {
                self.currentTurn = turn
                self.turnsHistory.append(turn)
                self.transcriptEntries.append(TranscriptEntry(speaker: turn.speaker, text: turn.response, timestamp: currentTimeString()))
                updateSpeakerIndex(for: turn.speaker)
            }
            
            self.isFinished = response.finished
        } catch let err as APIError {
            // A timeout can happen after the backend has already saved the
            // user's turn. Keep it visible so Retry does not erase their words.
            if case .serverError(let code, _) = err, code == 400 || code == 422 {
                self.transcriptEntries.removeAll(where: { $0.id == pendingUserEntry.id })
            }
            if case .serverError(let code, _) = err, code == 409 {
                self.isFinished = true
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isGeneratingTurn = false
    }

    func requestConclusion(token: String?) async {
        guard let sid = sessionId, !isFinished, !isGeneratingTurn, !didReachTimeLimit else { return }
        isGeneratingTurn = true
        errorMessage = nil

        do {
            let request = GDRespondRequest(sessionId: sid, userContribution: nil, conclude: true)
            let response: GDRespondResponse = try await apiClient.post(endpoint: "/gd/respond", body: request, token: token)
            guard !didReachTimeLimit else {
                isGeneratingTurn = false
                return
            }
            if let turn = response.turn {
                currentTurn = turn
                turnsHistory.append(turn)
                transcriptEntries.append(TranscriptEntry(speaker: turn.speaker, text: turn.response, timestamp: currentTimeString()))
                updateSpeakerIndex(for: turn.speaker)
            }
            isFinished = response.finished
        } catch let err as APIError {
            handleAPIError(err)
        } catch {
            errorMessage = error.localizedDescription
        }
        isGeneratingTurn = false
    }
    
    func finishGD(token: String?) async {
        print("[GD FINISH] finishGD called. sessionId: \(sessionId ?? "nil")")
        guard let sid = sessionId else {
            print("[GD FINISH] ERROR: sessionId is nil!")
            self.errorMessage = "No active session ID found to evaluate."
            return
        }
        
        if isFinishing || metrics != nil {
            print("[GD FINISH] Already finishing or metrics present, skipping redundant request.")
            return
        }
        
        isFinishing = true
        errorMessage = nil
        
        defer {
            isFinishing = false
            print("[GD FINISH] finishGD ended. metrics loaded: \(metrics != nil), error: \(errorMessage ?? "none")")
        }
        
        do {
            print("[GD API] Requesting /gd/finish/\(sid)...")
            let request = GDFinishRequest(interruptionCount: interruptionCount)
            let response: GDFinishResponse = try await apiClient.post(endpoint: "/gd/finish/\(sid)", body: request, token: token)
            print("[GD API] /gd/finish/\(sid) returned metrics (\(response.metrics.count) keys)")
            self.metrics = response.metrics
            self.summary = response.summary
            self.isFinished = true
        } catch let err as APIError {
            print("[GD API] APIError on finishGD: \(err)")
            if case .serverError(let code, _) = err, code == 409 {
                print("[GD API] HTTP 409: Session already completed on backend.")
                self.isFinished = true
                self.errorMessage = nil
            } else {
                handleAPIError(err)
            }
        } catch {
            print("[GD API] Unexpected error on finishGD: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    func recordInterruption() {
        guard !isFinished else { return }
        interruptionCount += 1
    }

    func endForTimer() {
        guard !isFinished else { return }
        didReachTimeLimit = true
        isFinished = true
        currentTurn = nil
    }
    
    private func handleAPIError(_ error: APIError) {
        if case .unauthorized = error {
            NotificationCenter.default.post(name: Notification.Name("PREPAI_SESSION_EXPIRED"), object: nil)
        }
        switch error {
        case .serverError(let code, let msg):
            if code == 503 || msg.contains("429") || msg.lowercased().contains("rate limit") {
                self.errorMessage = "Gemini AI service is currently busy. Please wait a moment and tap 'Retry Turn'."
            } else if code == 504 || msg.lowercased().contains("timeout") {
                self.errorMessage = "Request timed out. Please tap 'Retry Turn'."
            } else {
                self.errorMessage = msg
            }
        default:
            self.errorMessage = error.localizedDescription
        }
    }
}
