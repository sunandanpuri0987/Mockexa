import Foundation
import Combine
import SwiftUI

enum ResumeBuilderStep: Int, CaseIterable, Identifiable {
    case personalInfo = 0
    case summary = 1
    case education = 2
    case skills = 3
    case projects = 4
    case experience = 5
    case certifications = 6
    case achievements = 7
    case positions = 8
    case languages = 9
    case extracurriculars = 10
    case coursework = 11
    case volunteering = 12

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .personalInfo: return "Personal Information"
        case .summary: return "Professional Summary"
        case .education: return "Education"
        case .skills: return "Skills"
        case .projects: return "Projects"
        case .experience: return "Experience / Internships"
        case .certifications: return "Certifications"
        case .achievements: return "Achievements"
        case .positions: return "Positions of Responsibility"
        case .languages: return "Languages"
        case .extracurriculars: return "Extracurricular Activities"
        case .coursework: return "Relevant Coursework"
        case .volunteering: return "Volunteering"
        }
    }

    var isOptional: Bool {
        switch self {
        case .personalInfo, .education, .skills:
            return false
        default:
            return true
        }
    }
}

@MainActor
final class ResumeViewModel: ObservableObject {
    @Published var profiles: [ResumeProfile] = []
    @Published var activeProfileId: String? = nil
    
    @Published var resumeData: ResumeData = ResumeData() {
        didSet {
            syncActiveProfileData()
        }
    }
    
    @Published var currentStep: ResumeBuilderStep = .personalInfo
    @Published var validationError: String? = nil
    @Published var isResetConfirmPresented: Bool = false
    
    private let profilesBaseKey = "mockexa_resume_profiles_list"
    private let activeProfileBaseKey = "mockexa_active_profile_id"
    private let legacyUserDefaultsKey = "mockexa_resume_builder_data"
    private let storageOwnerKey = "mockexa_resume_storage_owner"
    private var storageUserId = ""

    private var profilesKey: String {
        storageUserId.isEmpty ? profilesBaseKey : "\(profilesBaseKey)_\(storageUserId)"
    }

    private var activeProfileIdKey: String {
        storageUserId.isEmpty ? activeProfileBaseKey : "\(activeProfileBaseKey)_\(storageUserId)"
    }

    init() {
        loadFromUserDefaults()
    }

    var activeProfile: ResumeProfile? {
        guard let id = activeProfileId else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    func activateStorage(for userId: String) {
        let cleanId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, storageUserId != cleanId else { return }

        let defaults = UserDefaults.standard
        let scopedProfilesKey = "\(profilesBaseKey)_\(cleanId)"
        let scopedActiveKey = "\(activeProfileBaseKey)_\(cleanId)"
        if defaults.data(forKey: scopedProfilesKey) == nil,
           defaults.string(forKey: storageOwnerKey) == nil {
            if let existingProfiles = defaults.data(forKey: profilesBaseKey) {
                defaults.set(existingProfiles, forKey: scopedProfilesKey)
            }
            if let existingActive = defaults.string(forKey: activeProfileBaseKey) {
                defaults.set(existingActive, forKey: scopedActiveKey)
            }
        }
        defaults.set(cleanId, forKey: storageOwnerKey)
        storageUserId = cleanId
        loadFromUserDefaults()
    }

    // MARK: - Navigation & Validation

    var canGoNext: Bool {
        currentStep.rawValue < ResumeBuilderStep.allCases.count - 1
    }

    var canGoBack: Bool {
        currentStep.rawValue > 0
    }

    func nextStep() {
        if validateCurrentStep() {
            if canGoNext, let next = ResumeBuilderStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
                validationError = nil
            }
        }
    }

    func previousStep() {
        if canGoBack, let prev = ResumeBuilderStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
            validationError = nil
        }
    }

    func validateCurrentStep() -> Bool {
        validationError = nil
        switch currentStep {
        case .personalInfo:
            let name = resumeData.personalInfo.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                validationError = "Please enter your full name."
                return false
            }
            let email = resumeData.personalInfo.email.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty, !email.matchesResumeEmailFormat {
                validationError = "Enter a valid email address or leave it blank."
                return false
            }
        case .education:
            let completeEducation = resumeData.education.contains {
                !$0.institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.degree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !completeEducation {
                validationError = "Add at least one education entry with an institution and degree."
                return false
            }
        case .skills:
            if resumeData.skills.allSkills.isEmpty {
                validationError = "Add at least one relevant skill."
                return false
            }
        default:
            break
        }
        return true
    }

    // MARK: - Profile Management & Persistence

    private func syncActiveProfileData() {
        guard let activeId = activeProfileId ?? profiles.first?.id,
              let index = profiles.firstIndex(where: { $0.id == activeId }) else { return }
        if profiles[index].resumeData != resumeData {
            profiles[index].resumeData = resumeData
            profiles[index].updatedAt = Date()
            saveProfilesToUserDefaults()
        }
    }

    func selectProfile(id: String) {
        guard let target = profiles.first(where: { $0.id == id }) else { return }
        self.activeProfileId = target.id
        self.resumeData = target.resumeData
        UserDefaults.standard.set(target.id, forKey: activeProfileIdKey)
        saveProfilesToUserDefaults()
        Haptics.selection()
    }

    func createNewProfile(name: String, targetJobTitle: String? = nil, initialData: ResumeData = ResumeData()) -> ResumeProfile {
        let profileName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "New Resume" : name
        let newProfile = ResumeProfile(
            id: UUID().uuidString,
            name: profileName,
            resumeData: initialData,
            targetJobTitle: targetJobTitle,
            isSample: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        profiles.append(newProfile)
        selectProfile(id: newProfile.id)
        saveProfilesToUserDefaults()
        return newProfile
    }

    func duplicateProfile(id: String) -> ResumeProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        let copy = ResumeProfile(
            id: UUID().uuidString,
            name: "\(source.name) (Copy)",
            resumeData: source.resumeData,
            targetJobTitle: source.targetJobTitle,
            isSample: false,
            parentProfileId: source.parentProfileId,
            createdAt: Date(),
            updatedAt: Date()
        )
        profiles.append(copy)
        saveProfilesToUserDefaults()
        Haptics.success()
        return copy
    }

    func renameProfile(id: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = trimmed
        profiles[idx].updatedAt = Date()
        saveProfilesToUserDefaults()
    }

    func deleteProfile(id: String) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            if let first = profiles.first {
                selectProfile(id: first.id)
            } else {
                let defaultProf = createNewProfile(name: "My Master Resume", initialData: ResumeData())
                selectProfile(id: defaultProf.id)
            }
        } else {
            saveProfilesToUserDefaults()
        }
        Haptics.selection()
    }

    func addTailoredProfile(_ profile: ResumeProfile) {
        profiles.append(profile)
        selectProfile(id: profile.id)
        saveProfilesToUserDefaults()
    }

    func saveToUserDefaults() {
        saveProfilesToUserDefaults()
    }

    func saveProfilesToUserDefaults() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: profilesKey)
            if let activeId = activeProfileId {
                UserDefaults.standard.set(activeId, forKey: activeProfileIdKey)
            }
        } catch {
            print("Failed to save resume profiles: \(error)")
        }
    }

    // MARK: - Import Real Resume Document (PDF / Text)
    func importResumeDocument(url: URL) -> Result<ResumeProfile, Error> {
        do {
            let rawText = try ResumeDocumentParser.shared.extractText(from: url)
            let fileName = url.deletingPathExtension().lastPathComponent
            let parsedData = ResumeDocumentParser.shared.parseResume(from: rawText, fallbackName: fileName)
            
            let profileName = !parsedData.personalInfo.fullName.isEmpty 
                ? "\(parsedData.personalInfo.fullName)'s Resume"
                : (!fileName.isEmpty ? fileName : "Uploaded Resume")

            let newProfile = ResumeProfile(
                id: UUID().uuidString,
                name: profileName,
                resumeData: parsedData,
                targetJobTitle: !parsedData.personalInfo.headline.isEmpty ? parsedData.personalInfo.headline : "Software Engineer",
                targetJobDescription: nil,
                rawResumeText: rawText,
                isSample: false,
                createdAt: Date(),
                updatedAt: Date()
            )

            self.profiles.insert(newProfile, at: 0)
            self.selectProfile(id: newProfile.id)
            saveProfilesToUserDefaults()
            Haptics.success()
            return .success(newProfile)
        } catch {
            return .failure(error)
        }
    }

    func updateJobDescription(for profileId: String, jd: String, jobTitle: String? = nil) {
        if let idx = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[idx].targetJobDescription = jd
            if let title = jobTitle, !title.isEmpty {
                profiles[idx].targetJobTitle = title
            }
            profiles[idx].updatedAt = Date()
            saveProfilesToUserDefaults()
            Haptics.selection()
        }
    }

    static func getActiveResumeContext() -> (context: String, role: String, jobDescription: String, name: String)? {
        let defaults = UserDefaults.standard
        let owner = defaults.string(forKey: "mockexa_resume_storage_owner") ?? ""
        let profilesKey = owner.isEmpty ? "mockexa_resume_profiles_list" : "mockexa_resume_profiles_list_\(owner)"
        let activeIdKey = owner.isEmpty ? "mockexa_active_profile_id" : "mockexa_active_profile_id_\(owner)"

        let rawData = defaults.data(forKey: profilesKey)
        guard let data = rawData,
              let list = try? JSONDecoder().decode([ResumeProfile].self, from: data),
              !list.isEmpty else { return nil }

        let activeId = defaults.string(forKey: activeIdKey)
        let active = (activeId != nil ? list.first(where: { $0.id == activeId }) : nil) ?? list.first!
        guard !active.isSample else { return nil }
        let context = ResumeService.shared.buildResumeContext(for: active)
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let role = active.targetJobTitle ?? "Software Engineer"
        let jd = active.targetJobDescription ?? ""
        return (context, role, jd, active.name)
    }

    func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([ResumeProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
            let savedActiveId = UserDefaults.standard.string(forKey: activeProfileIdKey)
            if let activeId = savedActiveId, let matched = profiles.first(where: { $0.id == activeId }) {
                self.activeProfileId = matched.id
                self.resumeData = matched.resumeData
            } else {
                self.activeProfileId = profiles.first!.id
                self.resumeData = profiles.first!.resumeData
            }
            saveProfilesToUserDefaults()
            return
        }

        // Automatic migration from legacy single ResumeData
        if storageUserId.isEmpty,
           let legacyData = UserDefaults.standard.data(forKey: legacyUserDefaultsKey),
           let decodedLegacy = try? JSONDecoder().decode(ResumeData.self, from: legacyData) {
            let migratedProfile = ResumeProfile(
                id: UUID().uuidString,
                name: "My Master Resume",
                resumeData: decodedLegacy,
                targetJobTitle: "Software Engineer",
                isSample: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            self.profiles = [migratedProfile]
            self.activeProfileId = migratedProfile.id
            self.resumeData = migratedProfile.resumeData
            saveProfilesToUserDefaults()
            return
        }

        loadCleanProfile()
    }

    private func loadCleanProfile() {
        let master = ResumeProfile(name: "My Master Resume", resumeData: ResumeData())
        profiles = [master]
        activeProfileId = master.id
        resumeData = master.resumeData
        saveProfilesToUserDefaults()
    }

    func loadSampleResume() {
        self.resumeData = ResumeData.sample
        self.validationError = nil
        Haptics.success()
    }

    func resetResumeData() {
        self.resumeData = ResumeData()
        self.currentStep = .personalInfo
        self.validationError = nil
        Haptics.selection()
    }


    // MARK: - Array Item Handlers

    func addEducation() {
        resumeData.education.append(EducationEntry())
    }

    func removeEducation(at offsets: IndexSet) {
        resumeData.education.remove(atOffsets: offsets)
    }

    func addProject() {
        resumeData.projects.append(ProjectEntry())
    }

    func removeProject(at offsets: IndexSet) {
        resumeData.projects.remove(atOffsets: offsets)
    }

    func addExperience() {
        resumeData.experience.append(ExperienceEntry())
    }

    func removeExperience(at offsets: IndexSet) {
        resumeData.experience.remove(atOffsets: offsets)
    }

    func addCertification() {
        resumeData.certifications.append(CertificationEntry())
    }

    func removeCertification(at offsets: IndexSet) {
        resumeData.certifications.remove(atOffsets: offsets)
    }

    func addAchievement() {
        resumeData.achievements.append(AchievementEntry())
    }

    func removeAchievement(at offsets: IndexSet) {
        resumeData.achievements.remove(atOffsets: offsets)
    }

    func addPosition() {
        resumeData.positionsOfResponsibility.append(PositionOfResponsibilityEntry())
    }

    func removePosition(at offsets: IndexSet) {
        resumeData.positionsOfResponsibility.remove(atOffsets: offsets)
    }

    func addLanguage() {
        resumeData.languages.append(LanguageEntry())
    }

    func removeLanguage(at offsets: IndexSet) {
        resumeData.languages.remove(atOffsets: offsets)
    }

    func addExtracurricular() {
        resumeData.extracurriculars.append(ExtracurricularEntry())
    }

    func removeExtracurricular(at offsets: IndexSet) {
        resumeData.extracurriculars.remove(atOffsets: offsets)
    }

    func addVolunteering() {
        resumeData.volunteering.append(VolunteeringEntry())
    }

    func removeVolunteering(at offsets: IndexSet) {
        resumeData.volunteering.remove(atOffsets: offsets)
    }

    // MARK: - Skills Handlers

    func addSkill(to category: KeyPath<CategorizedSkills, [String]>, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch category {
        case \CategorizedSkills.programmingLanguages:
            if !resumeData.skills.programmingLanguages.contains(trimmed) { resumeData.skills.programmingLanguages.append(trimmed) }
        case \CategorizedSkills.frameworks:
            if !resumeData.skills.frameworks.contains(trimmed) { resumeData.skills.frameworks.append(trimmed) }
        case \CategorizedSkills.libraries:
            if !resumeData.skills.libraries.contains(trimmed) { resumeData.skills.libraries.append(trimmed) }
        case \CategorizedSkills.databases:
            if !resumeData.skills.databases.contains(trimmed) { resumeData.skills.databases.append(trimmed) }
        case \CategorizedSkills.cloudDevOps:
            if !resumeData.skills.cloudDevOps.contains(trimmed) { resumeData.skills.cloudDevOps.append(trimmed) }
        case \CategorizedSkills.tools:
            if !resumeData.skills.tools.contains(trimmed) { resumeData.skills.tools.append(trimmed) }
        case \CategorizedSkills.softSkills:
            if !resumeData.skills.softSkills.contains(trimmed) { resumeData.skills.softSkills.append(trimmed) }
        case \CategorizedSkills.other:
            if !resumeData.skills.other.contains(trimmed) { resumeData.skills.other.append(trimmed) }
        default: break
        }
    }

    func removeSkill(from category: KeyPath<CategorizedSkills, [String]>, item: String) {
        switch category {
        case \CategorizedSkills.programmingLanguages:
            resumeData.skills.programmingLanguages.removeAll { $0 == item }
        case \CategorizedSkills.frameworks:
            resumeData.skills.frameworks.removeAll { $0 == item }
        case \CategorizedSkills.libraries:
            resumeData.skills.libraries.removeAll { $0 == item }
        case \CategorizedSkills.databases:
            resumeData.skills.databases.removeAll { $0 == item }
        case \CategorizedSkills.cloudDevOps:
            resumeData.skills.cloudDevOps.removeAll { $0 == item }
        case \CategorizedSkills.tools:
            resumeData.skills.tools.removeAll { $0 == item }
        case \CategorizedSkills.softSkills:
            resumeData.skills.softSkills.removeAll { $0 == item }
        case \CategorizedSkills.other:
            resumeData.skills.other.removeAll { $0 == item }
        default: break
        }
    }
}

private extension String {
    var matchesResumeEmailFormat: Bool {
        range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
