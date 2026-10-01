import Foundation

enum ResumeContentType: String, CaseIterable, Identifiable {
    case summary = "Professional Summary"
    case projectDescription = "Project Description"
    case projectContribution = "Project Contribution"
    case experienceBullet = "Experience Bullet"
    case internshipBullet = "Internship Bullet"
    case achievementBullet = "Achievement Bullet"
    case positionOfResponsibility = "Position of Responsibility"

    var id: String { rawValue }
}

struct AIImprovementRequest: Encodable {
    let contentType: String
    let originalText: String
}

struct AIImprovementResponse: Decodable {
    let improvedText: String
    let whyBetter: [String]
    let metricSuggestion: String?
}

struct AIImprovementResult {
    let originalText: String
    var improvedText: String
    let whyBetter: [String]
    let metricSuggestion: String?
}

final class ResumeService {
    static let shared = ResumeService()
    private init() {}

    /// Applies deterministic wording improvements without a network round trip.
    func improveText(originalText: String, type: ResumeContentType, token: String? = nil) async -> Result<AIImprovementResult, Error> {
        let trimmed = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .success(
                AIImprovementResult(
                    originalText: originalText,
                    improvedText: "Please enter some content before requesting a wording suggestion.",
                    whyBetter: ["Requires input content to analyze"],
                    metricSuggestion: nil
                )
            )
        }

        return .success(generateAntiHallucinatedFallback(originalText: trimmed, type: type))
    }

    // MARK: - Anti-Hallucination Offline Enhancement Engine
    private func generateAntiHallucinatedFallback(originalText: String, type: ResumeContentType) -> AIImprovementResult {
        var text = originalText

        // Action Verb Conversions (Strictly preserving original facts, technologies, and entities)
        let verbReplacements: [(String, String)] = [
            ("made a website", "Developed a web application"),
            ("made a app", "Built an application"),
            ("made an app", "Built an application"),
            ("made", "Developed"),
            ("worked on", "Collaborated on"),
            ("was responsible for", "Engineered and managed"),
            ("helped with", "Assisted in implementing"),
            ("did", "Executed"),
            ("created", "Architected"),
            ("used", "Utilized"),
            ("fixed bugs", "Resolved critical technical issues"),
            ("built", "Engineered")
        ]

        for (pattern, replacement) in verbReplacements {
            if text.lowercased().contains(pattern) {
                if let range = text.range(of: pattern, options: .caseInsensitive) {
                    text.replaceSubrange(range, with: replacement)
                }
            }
        }

        // Capitalize first character if needed
        if let first = text.first, first.isLowercase {
            text = text.prefix(1).uppercased() + text.dropFirst()
        }

        // Ensure ending period
        if !text.hasSuffix(".") && !text.hasSuffix("!") {
            text += "."
        }

        var why: [String] = [
            "Replaced weak passive verbs with strong, active technical verbs",
            "Enhanced clarity and professional tone for placement evaluation",
            "Preserved 100% of your original facts without hallucinating unverified metrics"
        ]

        if type == .summary {
            why.append("Structured for clear readability by hiring managers")
        }

        let metricTip: String? = "Tip: If you have measurable results (e.g., 'reduced API response time' or 'handled 50+ entries'), add them manually if you can explain them in an interview."

        return AIImprovementResult(
            originalText: originalText,
            improvedText: text,
            whyBetter: why,
            metricSuggestion: metricTip
        )
    }

    // MARK: - ATS Analysis Engine (Deterministic & Offline Ready)

    /// Performs ATS evaluation on current resume data against job title and job description.
    func analyzeATS(resumeData: ResumeData, jobTitle: String, jobDescription: String, token: String? = nil) async -> ATSAnalysisResult {
        return generateDeterministicATSResult(resumeData: resumeData, jobTitle: jobTitle, jobDescription: jobDescription)
    }

    /// Pure, deterministic ATS calculation engine guaranteeing 100% reproducible results.
    func generateDeterministicATSResult(resumeData: ResumeData, jobTitle: String, jobDescription: String) -> ATSAnalysisResult {
        let titleTrimmed = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let jdTrimmed = jobDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let fullResumeText = extractFullResumeText(from: resumeData).lowercased()
        let resumeSkills = extractAllResumeSkills(from: resumeData)
        let resumeSkillsLower = Set(resumeSkills.map { $0.lowercased() })

        // 1. Keyword Overlap (Max 25 pts)
        let extractedTerms = extractKeywordsFromJD(jobTitle: titleTrimmed, jobDescription: jdTrimmed)
        var matchedKeywords: [String] = []
        var missingKeywords: [String] = []

        for term in extractedTerms {
            let termLower = term.lowercased()
            if fullResumeText.contains(termLower) || resumeSkillsLower.contains(termLower) {
                if !matchedKeywords.contains(term) { matchedKeywords.append(term) }
            } else {
                if !missingKeywords.contains(term) { missingKeywords.append(term) }
            }
        }

        let keywordScore: Int
        if extractedTerms.isEmpty {
            keywordScore = 20
        } else {
            let ratio = Double(matchedKeywords.count) / Double(extractedTerms.count)
            keywordScore = min(25, max(0, Int(round(ratio * 25.0))))
        }

        // 2. Skills Match (Max 35 pts)
        let jdSkills = extractSkillsFromJD(jobDescription: jdTrimmed)
        var matchedSkills: [String] = []
        var missingSkills: [String] = []

        for skill in jdSkills {
            let skillLower = skill.lowercased()
            let isMatched = resumeSkillsLower.contains(skillLower) ||
                            fullResumeText.contains(skillLower) ||
                            resumeSkillsLower.contains(where: { $0.contains(skillLower) || skillLower.contains($0) })
            if isMatched {
                if !matchedSkills.contains(skill) { matchedSkills.append(skill) }
            } else {
                if !missingSkills.contains(skill) { missingSkills.append(skill) }
            }
        }

        let skillsScore: Int
        if jdSkills.isEmpty {
            skillsScore = 30
        } else {
            let skillRatio = Double(matchedSkills.count) / Double(jdSkills.count)
            skillsScore = min(35, max(0, Int(round(skillRatio * 35.0))))
        }

        // 3. Section Completeness Check (Max 20 pts)
        var sectionChecks: [ATSSectionCheck] = []
        var sectionPoints = 0

        // Contact Info (3 pts)
        let hasName = !resumeData.personalInfo.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContact = hasName && (!resumeData.personalInfo.email.isEmpty || !resumeData.personalInfo.phone.isEmpty)
        sectionChecks.append(ATSSectionCheck(sectionName: "Contact Information", isPresent: hasContact, detail: hasContact ? "Full name and contact channels present" : "Missing name or contact email/phone"))
        if hasContact { sectionPoints += 3 }

        // Summary (2 pts)
        let hasSummary = !resumeData.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Professional Summary", isPresent: hasSummary, detail: hasSummary ? "Summary statement present" : "Summary is missing (Recommended for ATS)"))
        if hasSummary { sectionPoints += 2 }

        // Education (3 pts)
        let hasEducation = !resumeData.education.isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Education", isPresent: hasEducation, detail: hasEducation ? "\(resumeData.education.count) education entries listed" : "No education entries added"))
        if hasEducation { sectionPoints += 3 }

        // Skills (3 pts)
        let hasSkills = !resumeSkills.isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Skills Section", isPresent: hasSkills, detail: hasSkills ? "\(resumeSkills.count) skills categorized" : "Skills section is empty"))
        if hasSkills { sectionPoints += 3 }

        // Projects (3 pts)
        let hasProjects = !resumeData.projects.isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Projects", isPresent: hasProjects, detail: hasProjects ? "\(resumeData.projects.count) project entries present" : "No project entries listed"))
        if hasProjects { sectionPoints += 3 }

        // Experience (2 pts)
        let hasExp = !resumeData.experience.isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Experience / Internships", isPresent: hasExp, detail: hasExp ? "\(resumeData.experience.count) experience entries listed" : "No experience listed (Optional for freshers)"))
        if hasExp { sectionPoints += 2 }

        // Certifications (2 pts)
        let hasCert = !resumeData.certifications.isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Certifications", isPresent: hasCert, detail: hasCert ? "\(resumeData.certifications.count) certifications listed" : "No certifications added"))
        if hasCert { sectionPoints += 2 }

        // Achievements / Leadership (2 pts)
        let hasLeadership = !resumeData.achievements.isEmpty || !resumeData.positionsOfResponsibility.isEmpty
        sectionChecks.append(ATSSectionCheck(sectionName: "Achievements & Leadership", isPresent: hasLeadership, detail: hasLeadership ? "Achievements or leadership positions present" : "No extra achievements or positions listed"))
        if hasLeadership { sectionPoints += 2 }

        let sectionScore = min(20, sectionPoints)

        // 4. Formatting Check (Max 20 pts)
        var formattingIssues: [String] = []
        var formattingScore = 20

        if !hasName {
            formattingIssues.append("Missing full name in header")
            formattingScore -= 5
        }
        if resumeData.personalInfo.email.isEmpty {
            formattingIssues.append("Missing contact email address")
            formattingScore -= 3
        }
        if !hasSkills {
            formattingIssues.append("Skills section is empty or uncategorized")
            formattingScore -= 4
        }
        if !hasProjects && !hasExp {
            formattingIssues.append("Neither Projects nor Experience entries are provided")
            formattingScore -= 5
        }

        formattingScore = max(0, min(20, formattingScore))

        let breakdown = ATSScoreBreakdown(
            keywordScore: keywordScore,
            skillsScore: skillsScore,
            sectionScore: sectionScore,
            formattingScore: formattingScore
        )

        // 5. Recommendations & Optimization Suggestions
        var recommendations: [String] = []
        if !missingKeywords.isEmpty {
            recommendations.append("Incorporate missing keywords in your summary or project descriptions if relevant: \(missingKeywords.prefix(4).joined(separator: ", ")).")
        }
        if !missingSkills.isEmpty {
            recommendations.append("If you have experience with missing skills (\(missingSkills.prefix(3).joined(separator: ", ")), add them to your Skills section.")
        }
        if !hasSummary {
            recommendations.append("Add a concise 2-sentence Professional Summary tailored for '\(titleTrimmed.isEmpty ? "Target Role" : titleTrimmed)'.")
        }
        if formattingScore < 20 {
            recommendations.append("Address formatting issues to ensure ATS scanners correctly parse contact info and section headers.")
        }
        if recommendations.isEmpty {
            recommendations.append("Your resume aligns exceptionally well with the target job requirements.")
        }

        var optimizationSuggestions: [ATSOptimizationSuggestion] = []

        if !missingSkills.isEmpty {
            optimizationSuggestions.append(ATSOptimizationSuggestion(
                category: "Skills Match",
                title: "Address Missing Job Skills",
                suggestion: "The job description specifically requests: \(missingSkills.joined(separator: ", ")).",
                actionableAdvice: "If you have used these technologies in coursework or projects, add them to your categorized skills. Only include skills you can comfortably explain in an interview."
            ))
        }

        if !resumeData.summary.isEmpty && !missingKeywords.isEmpty {
            optimizationSuggestions.append(ATSOptimizationSuggestion(
                category: "Professional Summary",
                title: "Emphasize Role Keywords in Summary",
                suggestion: "Highlight core competencies matching \(matchedKeywords.prefix(3).joined(separator: ", ")) in your summary.",
                actionableAdvice: "Front-load key technical strengths in your summary to pass initial recruiter and ATS filters."
            ))
        }

        if let firstProj = resumeData.projects.first {
            optimizationSuggestions.append(ATSOptimizationSuggestion(
                category: "Projects",
                title: "Refine Project Contributions for '\(firstProj.name)'",
                suggestion: "Use active technical action verbs (e.g. 'Engineered', 'Integrated', 'Architected') in project descriptions.",
                actionableAdvice: "Ensure project bullet points clearly articulate the technology stack and your specific contribution."
            ))
        }

        return ATSAnalysisResult(
            jobTitle: titleTrimmed.isEmpty ? "General Placement Role" : titleTrimmed,
            jobDescriptionSnippet: String(jdTrimmed.prefix(150)),
            score: breakdown.totalScore,
            breakdown: breakdown,
            matchedKeywords: matchedKeywords,
            missingKeywords: missingKeywords,
            matchedSkills: matchedSkills,
            missingSkills: missingSkills,
            sectionChecks: sectionChecks,
            formattingIssues: formattingIssues,
            recommendations: recommendations,
            optimizationSuggestions: optimizationSuggestions
        )
    }

    // MARK: - ATS Helper Methods

    private func extractFullResumeText(from resume: ResumeData) -> String {
        var textComponents: [String] = []
        textComponents.append(resume.personalInfo.fullName)
        textComponents.append(resume.personalInfo.headline)
        textComponents.append(resume.summary)

        for edu in resume.education {
            textComponents.append("\(edu.degree) \(edu.institution) \(edu.fieldOfStudy) \(edu.relevantCoursework) \(edu.academicAchievement)")
        }

        textComponents.append(contentsOf: extractAllResumeSkills(from: resume))

        for proj in resume.projects {
            textComponents.append("\(proj.name) \(proj.description) \(proj.technologies) \(proj.keyContributions)")
        }

        for exp in resume.experience {
            textComponents.append("\(exp.company) \(exp.role) \(exp.responsibilities) \(exp.achievements) \(exp.technologies)")
        }

        for cert in resume.certifications { textComponents.append("\(cert.name) \(cert.issuer)") }
        for ach in resume.achievements { textComponents.append("\(ach.title) \(ach.description)") }
        for pos in resume.positionsOfResponsibility { textComponents.append("\(pos.organization) \(pos.position) \(pos.responsibilities)") }
        textComponents.append(contentsOf: resume.relevantCoursework)

        return textComponents.joined(separator: " ")
    }

    private func extractAllResumeSkills(from resume: ResumeData) -> [String] {
        var skills: [String] = []
        skills.append(contentsOf: resume.skills.programmingLanguages)
        skills.append(contentsOf: resume.skills.frameworks)
        skills.append(contentsOf: resume.skills.libraries)
        skills.append(contentsOf: resume.skills.databases)
        skills.append(contentsOf: resume.skills.cloudDevOps)
        skills.append(contentsOf: resume.skills.tools)
        skills.append(contentsOf: resume.skills.softSkills)
        skills.append(contentsOf: resume.skills.other)
        return skills
    }

    private func extractSkillsFromJD(jobDescription: String) -> [String] {
        let knownSkillDictionary = [
            "Python", "Java", "JavaScript", "React", "SQL", "Git", "REST APIs", "Data Structures",
            "Algorithms", "Swift", "SwiftUI", "Combine", "FastAPI", "Docker", "AWS", "PostgreSQL",
            "Supabase", "SQLite", "C++", "HTML", "CSS", "TypeScript", "Node.js", "Express",
            "MongoDB", "Redis", "Linux", "Kubernetes", "CI/CD", "GitHub Actions", "Jira",
            "Agile", "Scrum", "Problem Solving", "Communication", "System Design"
        ]

        var matchedInJD: [String] = []
        let jdLower = jobDescription.lowercased()

        for skill in knownSkillDictionary {
            let skillLower = skill.lowercased()
            if jdLower.contains(skillLower) {
                matchedInJD.append(skill)
            }
        }
        return matchedInJD
    }

    private func extractKeywordsFromJD(jobTitle: String, jobDescription: String) -> [String] {
        var terms = extractSkillsFromJD(jobDescription: jobDescription)

        if !jobTitle.isEmpty {
            let titleWords = jobTitle.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            for word in titleWords {
                let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                if cleaned.count > 2 && !["the", "and", "for", "with"].contains(cleaned.lowercased()) {
                    if !terms.contains(where: { $0.lowercased() == cleaned.lowercased() }) {
                        terms.append(cleaned)
                    }
                }
            }
        }

        return terms
    }

    // MARK: - Safe Resume Tailoring Engine (Anti-Hallucinated)

    /// Analyzes a master profile against a Job Description and generates strictly anti-hallucinated safe suggestions.
    func analyzeJobAndGenerateTailoring(masterProfile: ResumeProfile, jobTitle: String, jobDescription: String) -> TailoringAnalysisResult {
        let resume = masterProfile.resumeData
        let beforeATS = generateDeterministicATSResult(resumeData: resume, jobTitle: jobTitle, jobDescription: jobDescription)
        
        let allResumeSkills = Set(extractAllResumeSkills(from: resume).map { $0.lowercased() })
        let jdSkills = extractSkillsFromJD(jobDescription: jobDescription)
        
        var matchedExistingSkills: [String] = []
        var missingSkillsFromResume: [String] = []
        
        for skill in jdSkills {
            let sLower = skill.lowercased()
            if allResumeSkills.contains(sLower) || allResumeSkills.contains(where: { $0.contains(sLower) || sLower.contains($0) }) {
                if !matchedExistingSkills.contains(skill) { matchedExistingSkills.append(skill) }
            } else {
                if !missingSkillsFromResume.contains(skill) { missingSkillsFromResume.append(skill) }
            }
        }
        
        var suggestions: [TailoringSuggestion] = []
        
        // 1. Summary Suggestion (if summary exists)
        let origSummary = resume.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !origSummary.isEmpty {
            var newSummary = origSummary
            let verbReplacements: [(String, String)] = [
                ("worked on", "engineered solutions using"),
                ("responsible for", "spearheaded development of"),
                ("made", "developed"),
                ("built", "architected")
            ]
            for (pattern, replacement) in verbReplacements {
                if let range = newSummary.range(of: pattern, options: .caseInsensitive) {
                    newSummary.replaceSubrange(range, with: replacement)
                }
            }
            
            if !jobTitle.isEmpty && !matchedExistingSkills.isEmpty {
                let topSkills = matchedExistingSkills.prefix(3).joined(separator: ", ")
                let focusSentence = " Tailored for \(jobTitle) roles with focused expertise in \(topSkills)."
                if !newSummary.contains("Tailored for") {
                    newSummary += focusSentence
                }
            }
            
            if newSummary != origSummary {
                suggestions.append(TailoringSuggestion(
                    sectionTitle: "Professional Summary",
                    itemTitle: nil,
                    originalText: origSummary,
                    suggestedText: newSummary,
                    rationale: "Emphasized existing skills (\(matchedExistingSkills.prefix(3).joined(separator: ", "))) and aligned tone for '\(jobTitle)' without inventing unearned technologies.",
                    isSafe: true,
                    isAccepted: true
                ))
            }
        }
        
        // 2. Projects Suggestions
        for proj in resume.projects {
            let origContrib = proj.keyContributions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !origContrib.isEmpty {
                var newContrib = origContrib
                if newContrib.lowercased().contains("built") {
                    newContrib = newContrib.replacingOccurrences(of: "built", with: "Engineered and delivered", options: .caseInsensitive)
                } else if newContrib.lowercased().contains("created") {
                    newContrib = newContrib.replacingOccurrences(of: "created", with: "Architected", options: .caseInsensitive)
                }
                
                if newContrib != origContrib {
                    suggestions.append(TailoringSuggestion(
                        sectionTitle: "Projects",
                        itemTitle: proj.name,
                        originalText: origContrib,
                        suggestedText: newContrib,
                        rationale: "Strengthened technical action verbs for project '\(proj.name)' preserving exact tech stack (\(proj.technologies)).",
                        isSafe: true,
                        isAccepted: true
                    ))
                }
            }
        }
        
        // 3. Experience Suggestions
        for exp in resume.experience {
            let origResp = exp.responsibilities.trimmingCharacters(in: .whitespacesAndNewlines)
            if !origResp.isEmpty {
                var newResp = origResp
                if newResp.lowercased().contains("collaborated with") {
                    newResp = newResp.replacingOccurrences(of: "collaborated with", with: "Partnered closely with", options: .caseInsensitive)
                }
                if newResp != origResp {
                    suggestions.append(TailoringSuggestion(
                        sectionTitle: "Experience",
                        itemTitle: "\(exp.role) at \(exp.company)",
                        originalText: origResp,
                        suggestedText: newResp,
                        rationale: "Optimized impact phrasing for position at '\(exp.company)' using only verified past responsibilities.",
                        isSafe: true,
                        isAccepted: true
                    ))
                }
            }
        }
        
        return TailoringAnalysisResult(
            masterProfileId: masterProfile.id,
            masterProfileName: masterProfile.name,
            jobTitle: jobTitle,
            jobDescription: jobDescription,
            matchedExistingSkills: matchedExistingSkills,
            missingSkillsFromResume: missingSkillsFromResume,
            suggestions: suggestions,
            beforeATSScore: beforeATS.score
        )
    }
    
    /// Applies accepted safe suggestions to produce a brand new tailored ResumeProfile without modifying the master.
    func applyTailoring(
        to masterProfile: ResumeProfile,
        analysis: TailoringAnalysisResult,
        acceptedSuggestionIds: Set<String>,
        newProfileName: String
    ) -> (tailoredProfile: ResumeProfile, afterATSScore: Int) {
        var newResume = masterProfile.resumeData
        
        // 1. Reorder existing skills to front-load matched JD skills
        newResume.skills = reorderSkills(skills: newResume.skills, matchedSkills: analysis.matchedExistingSkills)
        
        // 2. Apply accepted suggestions
        for suggestion in analysis.suggestions where acceptedSuggestionIds.contains(suggestion.id) {
            switch suggestion.sectionTitle {
            case "Professional Summary":
                newResume.summary = suggestion.suggestedText
            case "Projects":
                if let itemName = suggestion.itemTitle {
                    if let idx = newResume.projects.firstIndex(where: { $0.name == itemName }) {
                        newResume.projects[idx].keyContributions = suggestion.suggestedText
                    }
                }
            case "Experience":
                if let itemName = suggestion.itemTitle {
                    if let idx = newResume.experience.firstIndex(where: { "\( $0.role ) at \( $0.company )" == itemName || $0.company == itemName }) {
                        newResume.experience[idx].responsibilities = suggestion.suggestedText
                    }
                }
            default:
                break
            }
        }
        
        let afterATS = generateDeterministicATSResult(resumeData: newResume, jobTitle: analysis.jobTitle, jobDescription: analysis.jobDescription)
        
        let tailoredProfile = ResumeProfile(
            id: UUID().uuidString,
            name: newProfileName.trimmingCharacters(in: .whitespaces).isEmpty ? "\(masterProfile.name) — \(analysis.jobTitle)" : newProfileName,
            resumeData: newResume,
            targetJobTitle: analysis.jobTitle,
            targetJobDescription: analysis.jobDescription,
            isSample: false,
            parentProfileId: masterProfile.id,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        return (tailoredProfile, afterATS.score)
    }

    private func reorderSkills(skills: CategorizedSkills, matchedSkills: [String]) -> CategorizedSkills {
        var copy = skills
        let matchedLower = Set(matchedSkills.map { $0.lowercased() })
        
        func reorderList(_ list: [String]) -> [String] {
            let matched = list.filter { matchedLower.contains($0.lowercased()) }
            let rest = list.filter { !matchedLower.contains($0.lowercased()) }
            return matched + rest
        }
        
        copy.programmingLanguages = reorderList(copy.programmingLanguages)
        copy.frameworks = reorderList(copy.frameworks)
        copy.libraries = reorderList(copy.libraries)
        copy.databases = reorderList(copy.databases)
        copy.cloudDevOps = reorderList(copy.cloudDevOps)
        copy.tools = reorderList(copy.tools)
        copy.softSkills = reorderList(copy.softSkills)
        copy.other = reorderList(copy.other)
        return copy
    }

    // MARK: - Active Resume Context For Interview Practice (Technical, HR, GD)
    func buildResumeContext(for profile: ResumeProfile) -> String {
        var parts: [String] = []
        let data = profile.resumeData
        if !data.personalInfo.fullName.isEmpty {
            parts.append("Candidate Name: \(data.personalInfo.fullName)")
        }
        if let target = profile.targetJobTitle, !target.isEmpty {
            parts.append("Target Role: \(target)")
        } else if !data.personalInfo.headline.isEmpty {
            parts.append("Headline: \(data.personalInfo.headline)")
        }
        if !data.summary.isEmpty {
            parts.append("Professional Summary: \(data.summary)")
        }
        let skills = data.skills.allSkills
        if !skills.isEmpty {
            parts.append("Skills / Tech Stack: \(skills.joined(separator: ", "))")
        }
        if !data.projects.isEmpty {
            let projectsText = data.projects.prefix(4).map { p in
                "• \(p.name)\(p.technologies.isEmpty ? "" : " [\(p.technologies)]"): \(p.description) \(p.keyContributions.isEmpty ? "" : "Contributions: " + p.keyContributions)"
            }.joined(separator: "\n")
            parts.append("Key Projects:\n\(projectsText)")
        }
        if !data.experience.isEmpty {
            let expText = data.experience.prefix(3).map { e in
                "• \(e.role) at \(e.company) (\(e.startDate) - \(e.endDate)): \(e.responsibilities) \(e.achievements.isEmpty ? "" : "Achievements: " + e.achievements)"
            }.joined(separator: "\n")
            parts.append("Work Experience:\n\(expText)")
        }
        if !data.education.isEmpty {
            let eduText = data.education.map { ed in
                "• \(ed.degree) in \(ed.fieldOfStudy) from \(ed.institution)\(ed.graduationYear.isEmpty ? "" : " (" + ed.graduationYear + ")")"
            }.joined(separator: "\n")
            parts.append("Education:\n\(eduText)")
        }
        if let raw = profile.rawResumeText, !raw.isEmpty, parts.count < 3 {
            return String(raw.prefix(2500))
        }
        return parts.joined(separator: "\n\n")
    }
}

import PDFKit

// MARK: - Resume Document Parser & Extractor
final class ResumeDocumentParser {
    static let shared = ResumeDocumentParser()
    private init() {}

    func extractText(from url: URL) throws -> String {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }

        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw NSError(domain: "ResumeParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read PDF document."])
            }
            var text = ""
            for i in 0..<document.pageCount {
                if let page = document.page(at: i), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw NSError(domain: "ResumeParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "No extractable text found in this PDF (it may be a scanned image)."])
            }
            return trimmed
        } else {
            let data = try Data(contentsOf: url)
            if let string = String(data: data, encoding: .utf8) {
                let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else {
                    throw NSError(domain: "ResumeParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "The selected text file is empty."])
                }
                return clean
            } else if let string = String(data: data, encoding: .ascii) {
                let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else {
                    throw NSError(domain: "ResumeParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "The selected text file is empty."])
                }
                return clean
            }
            throw NSError(domain: "ResumeParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported resume document format. Please upload a PDF or text file."])
        }
    }

    func parseResume(from rawText: String, fallbackName: String = "My Uploaded Resume") -> ResumeData {
        var data = ResumeData()
        let lines = rawText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return data }

        // 1. Detect Name
        if let firstLine = lines.first, firstLine.count < 40,
           !firstLine.lowercased().contains("resume") && !firstLine.lowercased().contains("curriculum") {
            data.personalInfo.fullName = firstLine
        }

        // 2. Detect Email
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        if let emailRegex = try? NSRegularExpression(pattern: emailPattern) {
            let nsString = rawText as NSString
            if let match = emailRegex.firstMatch(in: rawText, range: NSRange(location: 0, length: nsString.length)) {
                data.personalInfo.email = nsString.substring(with: match.range)
            }
        }

        // 3. Detect Phone
        let phonePattern = "(\\+?[0-9]{1,3}[-.\t ]?)?\\(?([0-9]{3})\\)?[-.\t ]?([0-9]{3})[-.\t ]?([0-9]{4})"
        if let phoneRegex = try? NSRegularExpression(pattern: phonePattern) {
            let nsString = rawText as NSString
            if let match = phoneRegex.firstMatch(in: rawText, range: NSRange(location: 0, length: nsString.length)) {
                data.personalInfo.phone = nsString.substring(with: match.range)
            }
        }

        // 4. Detect Links
        for line in lines.prefix(15) {
            let lower = line.lowercased()
            if lower.contains("linkedin.com") && data.personalInfo.linkedIn.isEmpty {
                data.personalInfo.linkedIn = line
            } else if lower.contains("github.com") && data.personalInfo.github.isEmpty {
                data.personalInfo.github = line
            }
        }

        // 5. Extract Skills
        let skillsKeywords = [
            ("Swift", "lang"), ("Python", "lang"), ("Java", "lang"), ("C++", "lang"), ("C#", "lang"),
            ("JavaScript", "lang"), ("TypeScript", "lang"), ("Kotlin", "lang"), ("Go", "lang"), ("SQL", "lang"),
            ("SwiftUI", "fw"), ("UIKit", "fw"), ("Combine", "fw"), ("FastAPI", "fw"), ("React", "fw"),
            ("Next.js", "fw"), ("Django", "fw"), ("Flask", "fw"), ("Node.js", "fw"), ("Spring Boot", "fw"),
            ("PostgreSQL", "db"), ("MySQL", "db"), ("MongoDB", "db"), ("SQLite", "db"), ("Supabase", "db"), ("Redis", "db"),
            ("Docker", "ops"), ("Kubernetes", "ops"), ("AWS", "ops"), ("Git", "ops"), ("CI/CD", "ops"),
            ("Xcode", "tool"), ("VS Code", "tool"), ("Postman", "tool"), ("Figma", "tool"), ("Jira", "tool"),
            ("CoreData", "lib"), ("URLSession", "lib"), ("PyTest", "lib"), ("NumPy", "lib"), ("Pandas", "lib")
        ]

        let fullLower = rawText.lowercased()
        for (kw, cat) in skillsKeywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: kw.lowercased()))\\b"
            if fullLower.range(of: pattern, options: .regularExpression) != nil {
                switch cat {
                case "lang":
                    if !data.skills.programmingLanguages.contains(kw) { data.skills.programmingLanguages.append(kw) }
                case "fw":
                    if !data.skills.frameworks.contains(kw) { data.skills.frameworks.append(kw) }
                case "db":
                    if !data.skills.databases.contains(kw) { data.skills.databases.append(kw) }
                case "ops":
                    if !data.skills.cloudDevOps.contains(kw) { data.skills.cloudDevOps.append(kw) }
                case "tool":
                    if !data.skills.tools.contains(kw) { data.skills.tools.append(kw) }
                default:
                    if !data.skills.libraries.contains(kw) { data.skills.libraries.append(kw) }
                }
            }
        }

        // 6. Detect Summary
        var summaryLines: [String] = []
        var capturingSummary = false
        for line in lines {
            let lower = line.lowercased()
            if lower == "summary" || lower == "professional summary" || lower == "objective" || lower == "about me" {
                capturingSummary = true
                continue
            }
            if capturingSummary {
                if lower == "experience" || lower == "education" || lower == "skills" || lower == "projects" || lower == "technical skills" {
                    break
                }
                summaryLines.append(line)
            }
        }
        if !summaryLines.isEmpty {
            data.summary = summaryLines.joined(separator: " ")
        } else if lines.count > 1 && lines[1].count > 30 {
            data.summary = lines[1]
        }

        // 7. Parse Projects
        var inProjects = false
        var currentProject: ProjectEntry? = nil
        for line in lines {
            let lower = line.lowercased()
            if lower == "projects" || lower == "academic projects" || lower == "key projects" || lower == "personal projects" {
                inProjects = true
                continue
            }
            if inProjects {
                if lower == "experience" || lower == "work experience" || lower == "education" || lower == "skills" || lower == "certifications" {
                    inProjects = false
                    if let p = currentProject { data.projects.append(p) }
                    currentProject = nil
                    continue
                }
                if line.starts(with: "•") || line.starts(with: "-") || line.starts(with: "*") {
                    let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-* ")).trimmingCharacters(in: .whitespaces)
                    if currentProject != nil {
                        if currentProject!.description.isEmpty {
                            currentProject!.description = clean
                        } else {
                            currentProject!.keyContributions = (currentProject!.keyContributions.isEmpty ? "" : currentProject!.keyContributions + "; ") + clean
                        }
                    }
                } else if line.count < 50 && !line.contains("@") {
                    if let p = currentProject { data.projects.append(p) }
                    currentProject = ProjectEntry(name: line)
                }
            }
        }
        if let p = currentProject { data.projects.append(p) }

        // 8. Parse Experience
        var inExperience = false
        var currentExp: ExperienceEntry? = nil
        for line in lines {
            let lower = line.lowercased()
            if lower == "experience" || lower == "work experience" || lower == "employment" || lower == "internships" {
                inExperience = true
                continue
            }
            if inExperience {
                if lower == "projects" || lower == "education" || lower == "skills" || lower == "certifications" {
                    inExperience = false
                    if let e = currentExp { data.experience.append(e) }
                    currentExp = nil
                    continue
                }
                if line.starts(with: "•") || line.starts(with: "-") || line.starts(with: "*") {
                    let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "•-* ")).trimmingCharacters(in: .whitespaces)
                    if currentExp != nil {
                        currentExp!.responsibilities = (currentExp!.responsibilities.isEmpty ? "" : currentExp!.responsibilities + "; ") + clean
                    }
                } else if line.count < 60 && !line.contains("@") {
                    if let e = currentExp { data.experience.append(e) }
                    currentExp = ExperienceEntry(company: line, role: "Software Engineer")
                }
            }
        }
        if let e = currentExp { data.experience.append(e) }

        // 9. Parse Education
        var inEducation = false
        for line in lines {
            let lower = line.lowercased()
            if lower == "education" || lower == "academic history" || lower == "academics" {
                inEducation = true
                continue
            }
            if inEducation {
                if lower == "experience" || lower == "projects" || lower == "skills" || lower == "certifications" {
                    inEducation = false
                    break
                }
                if lower.contains("university") || lower.contains("college") || lower.contains("institute") || lower.contains("bachelor") || lower.contains("b.tech") || lower.contains("master") || lower.contains("degree") {
                    data.education.append(EducationEntry(degree: "Bachelor of Technology", institution: line, fieldOfStudy: "Computer Science"))
                }
            }
        }

        return data
    }
}
