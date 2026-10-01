import Foundation

// MARK: - Resume Data Root
struct ResumeData: Codable, Equatable {
    var personalInfo: PersonalInfo = PersonalInfo()
    var summary: String = ""
    var education: [EducationEntry] = []
    var skills: CategorizedSkills = CategorizedSkills()
    var projects: [ProjectEntry] = []
    var experience: [ExperienceEntry] = []
    var certifications: [CertificationEntry] = []
    var achievements: [AchievementEntry] = []
    var positionsOfResponsibility: [PositionOfResponsibilityEntry] = []
    var languages: [LanguageEntry] = []
    var extracurriculars: [ExtracurricularEntry] = []
    var relevantCoursework: [String] = []
    var volunteering: [VolunteeringEntry] = []
    
    static var sample: ResumeData {
        ResumeData(
            personalInfo: PersonalInfo(
                fullName: "Alex Rivera",
                headline: "Software Engineering Graduate | iOS & Python Developer",
                email: "alex.rivera@example.com",
                phone: "+1 (555) 019-2834",
                location: "San Francisco, CA",
                linkedIn: "https://linkedin.com/in/alexrivera-dev",
                github: "https://github.com/alexrivera-dev",
                portfolio: "https://alexrivera.dev"
            ),
            summary: "Passionate Computer Science graduate with hands-on experience in native iOS (SwiftUI, Combine) and asynchronous Python REST APIs. Strong algorithmic background with a passion for building user-centric mobile applications.",
            education: [
                EducationEntry(
                    id: UUID().uuidString,
                    degree: "Bachelor of Science",
                    institution: "California State University",
                    fieldOfStudy: "Computer Science",
                    startYear: "2021",
                    graduationYear: "2025",
                    gpa: "3.85 / 4.0",
                    relevantCoursework: "Data Structures & Algorithms, Operating Systems, Database Management Systems, Software Engineering",
                    academicAchievement: "Dean's Honor List (2022 - 2024), 1st Place in University Annual Hackathon"
                )
            ],
            skills: CategorizedSkills(
                programmingLanguages: ["Swift", "Python", "Java", "SQL", "C++"],
                frameworks: ["SwiftUI", "Combine", "FastAPI", "React"],
                libraries: ["URLSession", "Pydantic", "Pytest", "NumPy"],
                databases: ["PostgreSQL", "Supabase", "SQLite"],
                cloudDevOps: ["Docker", "Git", "GitHub Actions", "AWS S3"],
                tools: ["Xcode", "VS Code", "Postman", "Figma"],
                softSkills: ["Problem Solving", "Team Leadership", "Agile/Scrum", "Technical Communication"],
                other: ["REST API Design", "System Design Basics"]
            ),
            projects: [
                ProjectEntry(
                    id: UUID().uuidString,
                    name: "Mockexa - AI Placement Simulator",
                    description: "Native iOS app paired with FastAPI backend for realistic interview preparation across GD, Technical, and HR rounds.",
                    technologies: "SwiftUI, Combine, FastAPI, Python 3.12, Supabase",
                    keyContributions: "Architected MVVM flow, integrated asynchronous Gemini REST APIs, and built interactive panel discussion views.",
                    githubUrl: "https://github.com/alexrivera-dev/Mockexa",
                    liveUrl: "https://mockexa.app"
                ),
                ProjectEntry(
                    id: UUID().uuidString,
                    name: "Smart Expense Tracker",
                    description: "Cross-platform personal finance tracker with automated categorization and insight visualizations.",
                    technologies: "Swift, CoreData, Charts",
                    keyContributions: "Designed local persistence layer and custom budget spending goal alerts.",
                    githubUrl: "https://github.com/alexrivera-dev/ExpenseTracker",
                    liveUrl: ""
                )
            ],
            experience: [
                ExperienceEntry(
                    id: UUID().uuidString,
                    company: "TechPulse Solutions",
                    role: "Software Engineering Intern",
                    location: "San Jose, CA",
                    startDate: "June 2024",
                    endDate: "August 2024",
                    currentlyWorking: false,
                    responsibilities: "Collaborated with senior iOS engineers to refactor legacy network layers to async/await syntax. Built unit tests covering key user onboarding flows.",
                    achievements: "Improved network request success logging by 30% and reduced app launch cold-start time by 150ms.",
                    technologies: "Swift, XCTest, Git, Jira"
                )
            ],
            certifications: [
                CertificationEntry(
                    id: UUID().uuidString,
                    name: "AWS Certified Cloud Practitioner",
                    issuer: "Amazon Web Services",
                    date: "Nov 2024",
                    credentialUrl: "https://aws.amazon.com/verification"
                )
            ],
            achievements: [
                AchievementEntry(
                    id: UUID().uuidString,
                    title: "Winner - National Student CodeFest 2024",
                    description: "Built real-time accessibility helper app among 120 competing university teams.",
                    date: "October 2024"
                )
            ],
            positionsOfResponsibility: [
                PositionOfResponsibilityEntry(
                    id: UUID().uuidString,
                    organization: "ACM Student Chapter",
                    position: "Vice President",
                    duration: "2023 - 2024",
                    responsibilities: "Organized weekly coding workshops, technical speaker events, and peer mentorship sessions for 200+ members.",
                    achievements: "Increased student workshop attendance by 45% over two semesters."
                )
            ],
            languages: [
                LanguageEntry(id: UUID().uuidString, language: "English", proficiency: "Native / Full Professional"),
                LanguageEntry(id: UUID().uuidString, language: "Spanish", proficiency: "Professional Working")
            ],
            extracurriculars: [
                ExtracurricularEntry(
                    id: UUID().uuidString,
                    activity: "University Open Source Club Member",
                    description: "Contributed code documentation and bug fixes to open-source Swift repositories."
                )
            ],
            relevantCoursework: [
                "Advanced Data Structures", "Design & Analysis of Algorithms", "Computer Networks", "Object-Oriented Design"
            ],
            volunteering: [
                VolunteeringEntry(
                    id: UUID().uuidString,
                    organization: "CoderDojo Youth Workshop",
                    role: "Volunteer Programming Instructor",
                    duration: "2023 - Present",
                    description: "Taught fundamental Python programming concepts to middle school students."
                )
            ]
        )
    }
}

// MARK: - Section Models

struct PersonalInfo: Codable, Equatable {
    var fullName: String = ""
    var headline: String = ""
    var email: String = ""
    var phone: String = ""
    var location: String = ""
    var linkedIn: String = ""
    var github: String = ""
    var portfolio: String = ""
}

struct EducationEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var degree: String = ""
    var institution: String = ""
    var fieldOfStudy: String = ""
    var startYear: String = ""
    var graduationYear: String = ""
    var gpa: String = ""
    var relevantCoursework: String = ""
    var academicAchievement: String = ""
}

struct CategorizedSkills: Codable, Equatable {
    var programmingLanguages: [String] = []
    var frameworks: [String] = []
    var libraries: [String] = []
    var databases: [String] = []
    var cloudDevOps: [String] = []
    var tools: [String] = []
    var softSkills: [String] = []
    var other: [String] = []

    var allSkills: [String] {
        programmingLanguages + frameworks + libraries + databases + cloudDevOps + tools + softSkills + other
    }
}

struct ProjectEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var description: String = ""
    var technologies: String = ""
    var keyContributions: String = ""
    var githubUrl: String = ""
    var liveUrl: String = ""
}

struct ExperienceEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var company: String = ""
    var role: String = ""
    var location: String = ""
    var startDate: String = ""
    var endDate: String = ""
    var currentlyWorking: Bool = false
    var responsibilities: String = ""
    var achievements: String = ""
    var technologies: String = ""
}

struct CertificationEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var issuer: String = ""
    var date: String = ""
    var credentialUrl: String = ""
}

struct AchievementEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var title: String = ""
    var description: String = ""
    var date: String = ""
}

struct PositionOfResponsibilityEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var organization: String = ""
    var position: String = ""
    var duration: String = ""
    var responsibilities: String = ""
    var achievements: String = ""
}

struct LanguageEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var language: String = ""
    var proficiency: String = ""
}

struct ExtracurricularEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var activity: String = ""
    var description: String = ""
}

struct VolunteeringEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var organization: String = ""
    var role: String = ""
    var duration: String = ""
    var description: String = ""
}

// MARK: - ATS Checker Models

struct ATSSectionCheck: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    let sectionName: String
    let isPresent: Bool
    let detail: String
}

struct ATSOptimizationSuggestion: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    let category: String
    let title: String
    let suggestion: String
    let actionableAdvice: String
}

struct ATSScoreBreakdown: Codable, Equatable {
    let keywordScore: Int    // Max 25
    let skillsScore: Int     // Max 35
    let sectionScore: Int    // Max 20
    let formattingScore: Int // Max 20

    var totalScore: Int {
        min(100, max(0, keywordScore + skillsScore + sectionScore + formattingScore))
    }
}

struct ATSAnalysisResult: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    let jobTitle: String
    let jobDescriptionSnippet: String
    let score: Int
    let breakdown: ATSScoreBreakdown
    let matchedKeywords: [String]
    let missingKeywords: [String]
    let matchedSkills: [String]
    let missingSkills: [String]
    let sectionChecks: [ATSSectionCheck]
    let formattingIssues: [String]
    let recommendations: [String]
    let optimizationSuggestions: [ATSOptimizationSuggestion]
}

// MARK: - Resume Profile Models

struct ResumeProfile: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var resumeData: ResumeData
    var targetJobTitle: String? = nil
    var targetJobDescription: String? = nil
    var rawResumeText: String? = nil
    var isSample: Bool = false
    var parentProfileId: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }

    var isTailored: Bool {
        parentProfileId != nil || (targetJobTitle != nil && !targetJobTitle!.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var hasJobDescription: Bool {
        !(targetJobDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var defaultMaster: ResumeProfile {
        ResumeProfile(
            id: "master_default_1",
            name: "Alex's Resume",
            resumeData: ResumeData.sample,
            targetJobTitle: "Software Engineer",
            isSample: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var sampleJohn: ResumeProfile {
        var johnData = ResumeData.sample
        johnData.personalInfo.fullName = "John Smith"
        johnData.personalInfo.headline = "Full Stack Web Developer | React & Python Specialist"
        johnData.personalInfo.email = "john.smith@example.com"
        johnData.personalInfo.phone = "+1 (555) 987-6543"
        johnData.personalInfo.location = "Austin, TX"
        johnData.summary = "Results-driven Full Stack Web Developer with expertise in building responsive React applications and RESTful Python backends. Skilled in database design and automated testing."
        
        return ResumeProfile(
            id: "sample_john_2",
            name: "John's Resume",
            resumeData: johnData,
            targetJobTitle: "Full Stack Developer",
            isSample: true,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date().addingTimeInterval(-86400)
        )
    }
}

// MARK: - Tailoring Models

struct TailoringSuggestion: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    let sectionTitle: String
    let itemTitle: String?
    let originalText: String
    let suggestedText: String
    let rationale: String
    let isSafe: Bool
    var isAccepted: Bool = true
}

struct TailoringAnalysisResult: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    let masterProfileId: String
    let masterProfileName: String
    let jobTitle: String
    let jobDescription: String
    let matchedExistingSkills: [String]
    let missingSkillsFromResume: [String] // Items in JD that do NOT exist in resume (Never added!)
    var suggestions: [TailoringSuggestion]
    let beforeATSScore: Int
}


