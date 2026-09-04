import Foundation

enum PracticeKind: String, CaseIterable, Identifiable, Hashable {
    case gd = "Group Discussion", technical = "Technical Interview", hr = "HR Interview"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gd: return "Group Discussion"
        case .technical: return "Technical Interview"
        case .hr: return "HR Interview"
        }
    }
    var icon: String { switch self { case .gd: "person.3.fill"; case .technical: "chevron.left.forwardslash.chevron.right"; case .hr: "quote.bubble.fill" } }
    var subtitle: String { switch self { case .gd: "Speak. Challenge. Lead."; case .technical: "Think like an interviewer."; case .hr: "Build confident answers." } }
}

struct PracticeSession: Identifiable, Hashable {
    let id: String
    let kind: PracticeKind?
    let date: String
    let duration: String
    let score: Int
    let topic: String

    init(id: String = UUID().uuidString, kind: PracticeKind?, date: String, duration: String, score: Int, topic: String) {
        self.id = id
        self.kind = kind
        self.date = date
        self.duration = duration
        self.score = score
        self.topic = topic
    }
}


enum MockData {
    static let name = "Ananya"
    static let sessions = [
        PracticeSession(kind: .technical, date: "Today", duration: "18 min", score: 82, topic: "Operating Systems"),
        PracticeSession(kind: .gd, date: "Yesterday", duration: "10 min", score: 76, topic: "Remote work and productivity"),
        PracticeSession(kind: .hr, date: "Aug 27", duration: "14 min", score: 81, topic: "Behavioral interview")
    ]
    static let companies = ["Google", "Microsoft", "Amazon", "TCS", "Infosys", "Deloitte"]
}
