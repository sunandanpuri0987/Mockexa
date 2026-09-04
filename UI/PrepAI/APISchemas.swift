import Foundation

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    var intValue: Int?
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Generic AnyCodable Wrapper for Dynamic Dicts
struct AnyCodable: Codable, Equatable, Hashable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let intVal = try? container.decode(Int.self) {
                value = intVal
                return
            } else if let doubleVal = try? container.decode(Double.self) {
                value = doubleVal
                return
            } else if let stringVal = try? container.decode(String.self) {
                value = stringVal
                return
            } else if let boolVal = try? container.decode(Bool.self) {
                value = boolVal
                return
            }
        }
        if let unkeyedContainer = try? decoder.unkeyedContainer() {
            var array: [Any] = []
            var containerCopy = unkeyedContainer
            while !containerCopy.isAtEnd {
                if let element = try? containerCopy.decode(AnyCodable.self) {
                    array.append(element.value)
                }
            }
            value = array
            return
        }
        if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            var dict: [String: Any] = [:]
            for key in keyedContainer.allKeys {
                if let val = try? keyedContainer.decode(AnyCodable.self, forKey: key) {
                    dict[key.stringValue] = val.value
                }
            }
            value = dict
            return
        }
        value = NSNull()
    }
    
    func encode(to encoder: Encoder) throws {
        if let intVal = value as? Int {
            var container = encoder.singleValueContainer()
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            var container = encoder.singleValueContainer()
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            var container = encoder.singleValueContainer()
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            var container = encoder.singleValueContainer()
            try container.encode(boolVal)
        } else if let arrayVal = value as? [Any] {
            var container = encoder.unkeyedContainer()
            for item in arrayVal {
                try container.encode(AnyCodable(item))
            }
        } else if let dictVal = value as? [String: Any] {
            var container = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (key, val) in dictVal {
                if let codingKey = DynamicCodingKeys(stringValue: key) {
                    try container.encode(AnyCodable(val), forKey: codingKey)
                }
            }
        } else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}

// MARK: - Health Check Schema
struct HealthResponse: Codable {
    let status: String
    let environment: String?
    let groqConfigured: Bool?
    
    enum CodingKeys: String, CodingKey {
        case status
        case environment
        case groqConfigured = "groq_configured"
    }
}

// MARK: - Technical Interview Schemas
struct TechnicalStartRequest: Codable {
    let name: String
    let targetRole: String
    let experience: String
    let skills: [String]
    let selectedDomains: [String]
    let desiredDifficulty: Int
    let mode: String
    let maxQuestions: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case targetRole = "target_role"
        case experience
        case skills
        case selectedDomains = "selected_domains"
        case desiredDifficulty = "desired_difficulty"
        case mode
        case maxQuestions = "max_questions"
    }
}

struct QuestionOut: Codable, Identifiable, Hashable {
    let id: String
    let question: String
    let domain: String
    let subtopic: String
    let difficulty: Int
    let questionType: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case question
        case domain
        case subtopic
        case difficulty
        case questionType = "question_type"
    }
}

struct TechnicalStartResponse: Codable {
    let sessionId: String
    let question: QuestionOut
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case question
    }
}

struct TechnicalAnswerRequest: Codable {
    let sessionId: String
    let answer: String
    let hintsUsed: Int
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case answer
        case hintsUsed = "hints_used"
    }
}

struct AnswerAnalysisOut: Codable {
    let classification: String
    let correctness: Double
    let completeness: Double
    let relevance: Double
    let reasoning: Double
    let missingConcepts: [String]
    let misconceptions: [String]
    let overallScore: Double
    
    enum CodingKeys: String, CodingKey {
        case classification
        case correctness
        case completeness
        case relevance
        case reasoning
        case missingConcepts = "missing_concepts"
        case misconceptions
        case overallScore = "overall_score"
    }
}

struct TechnicalAnswerResponse: Codable {
    let sessionId: String
    let analysis: AnswerAnalysisOut
    let decisionAction: String
    let nextQuestion: QuestionOut?
    let completed: Bool
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case analysis
        case decisionAction = "decision_action"
        case nextQuestion = "next_question"
        case completed
    }
}

struct TechnicalFinishResponse: Codable {
    let sessionId: String
    let report: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case report
    }
}

// MARK: - HR Interview Schemas
struct HRStartRequest: Codable {
    let name: String
    let targetRole: String
    let experience: String
    let maxQuestions: Int
    
    enum CodingKeys: String, CodingKey {
        case name
        case targetRole = "target_role"
        case experience
        case maxQuestions = "max_questions"
    }
}

struct HRQuestionOut: Codable, Identifiable, Hashable {
    let id: String
    let question: String
    let category: String
}

struct HRStartResponse: Codable {
    let sessionId: String
    let question: HRQuestionOut
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case question
    }
}

struct HRAnswerRequest: Codable {
    let sessionId: String
    let answer: String
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case answer
    }
}

struct HREvaluationOut: Codable {
    let clarity: Double
    let specificity: Double
    let ownership: Double
    let communication: Double
    let teamwork: Double
    let leadership: Double
    let problemSolving: Double
    let feedback: String
    let overallScore: Double
    
    enum CodingKeys: String, CodingKey {
        case clarity
        case specificity
        case ownership
        case communication
        case teamwork
        case leadership
        case problemSolving = "problem_solving"
        case feedback
        case overallScore = "overall_score"
    }
}

struct HRAnswerResponse: Codable {
    let sessionId: String
    let evaluation: HREvaluationOut
    let nextQuestion: HRQuestionOut?
    let completed: Bool
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case evaluation
        case nextQuestion = "next_question"
        case completed
    }
}

struct HRFinishResponse: Codable {
    let sessionId: String
    let report: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case report
    }
}

// MARK: - Group Discussion Schemas
struct GDStartRequest: Codable {
    let topic: String
    let numRounds: Int
    let mode: String
    
    enum CodingKeys: String, CodingKey {
        case topic
        case numRounds = "num_rounds"
        case mode
    }
}

struct GDStartResponse: Codable {
    let sessionId: String
    let topicAnalysis: [String: AnyCodable]
    let participants: [[String: AnyCodable]]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case topicAnalysis = "topic_analysis"
        case participants
    }
}

struct GDTurnResponse: Codable, Identifiable, Hashable {
    var id: String { "\(round)-\(speaker)" }
    let speaker: String
    let round: Int
    let action: String
    let target: String?
    let position: Double
    let claim: String
    let response: String
    let confidence: Double
    let issue: String
}

struct GDRespondRequest: Codable {
    let sessionId: String
    let userContribution: String?
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case userContribution = "user_contribution"
    }
}

struct GDRespondResponse: Codable {
    let sessionId: String
    let turn: GDTurnResponse?
    let finished: Bool
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case turn
        case finished
    }
}

struct GDFinishResponse: Codable {
    let sessionId: String
    let metrics: [String: Double]
    let summary: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case metrics
        case summary
    }
}

// MARK: - Sessions History Schema
struct SessionSummaryItem: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let topic: String
    let date: String
    let duration: String
    let score: Int
    
    var practiceKind: PracticeKind? {
        switch kind.lowercased() {
        case "gd", "group discussion": return .gd
        case "hr", "hr interview": return .hr
        case "technical", "tech", "technical interview": return .technical
        default: return nil
        }
    }
    
    var toPracticeSession: PracticeSession {
        PracticeSession(
            id: id,
            kind: practiceKind,
            date: date,
            duration: duration,
            score: score,
            topic: topic
        )
    }
}

struct TranscriptEntryItem: Codable, Identifiable, Hashable {
    var id: String { "\(speaker)-\(text.prefix(20))" }
    let speaker: String
    let text: String
}

struct SessionDetailItem: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let topic: String
    let date: String
    let duration: String
    let score: Int
    let userId: String
    let createdAt: String?
    let report: [String: AnyCodable]?
    let transcript: [TranscriptEntryItem]?
    
    var practiceKind: PracticeKind? {
        switch kind.lowercased() {
        case "gd", "group discussion": return .gd
        case "hr", "hr interview": return .hr
        case "technical", "tech", "technical interview": return .technical
        default: return nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case topic
        case date
        case duration
        case score
        case userId = "user_id"
        case createdAt = "created_at"
        case report
        case transcript
    }
}


