import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Main Resume Builder View
struct ResumeBuilderView: View {
    @ObservedObject var vm: ResumeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPreview = false

    @MainActor
    init(vm: ResumeViewModel? = nil) {
        self.vm = vm ?? ResumeViewModel()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // Step Progress Header
                    VStack(spacing: 8) {
                        HStack {
                            Text("Step \(vm.currentStep.rawValue + 1) of \(ResumeBuilderStep.allCases.count)")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.primary)

                            Spacer()

                            if vm.currentStep.isOptional {
                                Text("Optional Section")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(MockexaTheme.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(MockexaTheme.primary)
                            }

                        }

                        ProgressView(value: Double(vm.currentStep.rawValue + 1), total: Double(ResumeBuilderStep.allCases.count))
                            .tint(MockexaTheme.primary)

                        Text(vm.currentStep.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(MockexaTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(MockexaTheme.surface)

                    Divider().background(MockexaTheme.border)

                    // Step Form Content
                    ScrollView {
                        VStack(spacing: 20) {
                            if let error = vm.validationError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text(error)
                                        .font(.subheadline.bold())
                                    Spacer()
                                }
                                .padding(14)
                                .background(MockexaTheme.destructive.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(MockexaTheme.destructive)
                            }

                            switch vm.currentStep {
                            case .personalInfo:
                                PersonalInfoForm(info: $vm.resumeData.personalInfo)
                            case .summary:
                                SummaryForm(summary: $vm.resumeData.summary)
                            case .education:
                                EducationForm(education: $vm.resumeData.education, onAdd: vm.addEducation, onDelete: vm.removeEducation)
                            case .skills:
                                SkillsForm(skills: $vm.resumeData.skills, vm: vm)
                            case .projects:
                                ProjectsForm(projects: $vm.resumeData.projects, onAdd: vm.addProject, onDelete: vm.removeProject)
                            case .experience:
                                ExperienceForm(experience: $vm.resumeData.experience, onAdd: vm.addExperience, onDelete: vm.removeExperience)
                            case .certifications:
                                CertificationsForm(certifications: $vm.resumeData.certifications, onAdd: vm.addCertification, onDelete: vm.removeCertification)
                            case .achievements:
                                AchievementsForm(achievements: $vm.resumeData.achievements, onAdd: vm.addAchievement, onDelete: vm.removeAchievement)
                            case .positions:
                                PositionsForm(positions: $vm.resumeData.positionsOfResponsibility, onAdd: vm.addPosition, onDelete: vm.removePosition)
                            case .languages:
                                LanguagesForm(languages: $vm.resumeData.languages, onAdd: vm.addLanguage, onDelete: vm.removeLanguage)
                            case .extracurriculars:
                                ExtracurricularsForm(items: $vm.resumeData.extracurriculars, onAdd: vm.addExtracurricular, onDelete: vm.removeExtracurricular)
                            case .coursework:
                                CourseworkForm(items: $vm.resumeData.relevantCoursework)
                            case .volunteering:
                                VolunteeringForm(items: $vm.resumeData.volunteering, onAdd: vm.addVolunteering, onDelete: vm.removeVolunteering)
                            }
                        }
                        .padding(20)
                    }

                    // Navigation Footer
                    VStack(spacing: 12) {
                        Divider().background(MockexaTheme.border)
                        HStack(spacing: 12) {
                            if vm.canGoBack {
                                SecondaryButton(title: "Back") {
                                    vm.previousStep()
                                }
                            }

                            if vm.canGoNext {
                                PrimaryButton(title: "Next", icon: "arrow.right") {
                                    vm.nextStep()
                                }
                            } else {
                                PrimaryButton(title: "Preview Resume", icon: "doc.text.magnifyingglass") {
                                    showPreview = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .background(MockexaTheme.surface)
                }
            }
            .navigationTitle("Resume Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(MockexaTheme.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Preview Resume", systemImage: "doc.text.magnifyingglass") {
                            if vm.validateCurrentStep() || vm.currentStep.isOptional { showPreview = true }
                        }
                        Button("Clear Resume", systemImage: "trash", role: .destructive) {
                            vm.isResetConfirmPresented = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(MockexaTheme.primary)
                    }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                ResumePreviewView(
                    data: vm.resumeData,
                    targetJobTitle: vm.activeProfile?.targetJobTitle,
                    vm: vm,
                    onTargetAnalyzed: { title, jd in
                        guard let profileId = vm.activeProfile?.id else { return }
                        vm.updateJobDescription(for: profileId, jd: jd, jobTitle: title)
                    }
                ) { targetStep in
                    vm.currentStep = targetStep
                    showPreview = false
                }
            }
            .alert("Reset Resume Data?", isPresented: $vm.isResetConfirmPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    vm.resetResumeData()
                }
            } message: {
                Text("This will erase all entered resume sections. Are you sure?")
            }
        }
    }
}

// MARK: - Section Forms

struct PersonalInfoForm: View {
    @Binding var info: PersonalInfo

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("PERSONAL DETAILS")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)

                FormField(label: "Full Name *", text: $info.fullName, placeholder: "e.g. Alex Rivera")
                FormField(label: "Professional Headline", text: $info.headline, placeholder: "e.g. Computer Science Student | Mobile App Dev")
                FormField(label: "Email", text: $info.email, placeholder: "alex@example.com")
                FormField(label: "Phone", text: $info.phone, placeholder: "+1 (555) 019-2834")
                FormField(label: "Location", text: $info.location, placeholder: "City, Country")
                FormField(label: "LinkedIn URL", text: $info.linkedIn, placeholder: "https://linkedin.com/in/username")
                FormField(label: "GitHub URL", text: $info.github, placeholder: "https://github.com/username")
                FormField(label: "Portfolio URL", text: $info.portfolio, placeholder: "https://myportfolio.com")
            }
        }
    }
}

struct SummaryForm: View {
    @Binding var summary: String
    @State private var showImprover = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PROFESSIONAL SUMMARY")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    Spacer()
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(MockexaTheme.textSecondary)
                }

                TextEditor(text: $summary)
                    .frame(minHeight: 140)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(MockexaTheme.border, lineWidth: 1))
                    .font(.body)
                    .foregroundStyle(MockexaTheme.textPrimary)

                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(MockexaTheme.primary)
                    Text("Polish wording while preserving your facts")
                        .font(.caption)
                        .foregroundStyle(MockexaTheme.textSecondary)
                    Spacer()
                    Button("Polish Wording") {
                        showImprover = true
                    }
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                    .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .padding(10)
                .background(MockexaTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .sheet(isPresented: $showImprover) {
            AIImproverSheet(type: .summary, originalText: summary) { newText in
                summary = newText
            }
        }
    }
}

struct EducationForm: View {
    @Binding var education: [EducationEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EDUCATION ENTRIES")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Education", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            if education.isEmpty {
                Text("No education entries added yet. Tap 'Add Education' above.")
                    .font(.subheadline)
                    .foregroundStyle(MockexaTheme.textSecondary)
                    .padding()
            }

            ForEach($education) { $edu in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(edu.institution.isEmpty ? "New Education" : edu.institution)
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.textPrimary)
                            Spacer()
                            Button(action: {
                                if let idx = education.firstIndex(where: { $0.id == edu.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(MockexaTheme.destructive)
                            }
                        }

                        FormField(label: "Degree", text: $edu.degree, placeholder: "e.g. Bachelor of Technology")
                        FormField(label: "Institution", text: $edu.institution, placeholder: "e.g. Stanford University")
                        FormField(label: "Field of Study", text: $edu.fieldOfStudy, placeholder: "e.g. Computer Science")
                        HStack {
                            FormField(label: "Start Year", text: $edu.startYear, placeholder: "2021")
                            FormField(label: "Grad Year", text: $edu.graduationYear, placeholder: "2025")
                        }
                        FormField(label: "CGPA / Percentage", text: $edu.gpa, placeholder: "e.g. 3.8 / 4.0 or 85%")
                        FormField(label: "Relevant Coursework", text: $edu.relevantCoursework, placeholder: "Data Structures, Algorithms...")
                        FormField(label: "Academic Achievements", text: $edu.academicAchievement, placeholder: "Dean's List, Merit Rank...")
                    }
                }
            }
        }
    }
}

struct SkillsForm: View {
    @Binding var skills: CategorizedSkills
    @ObservedObject var vm: ResumeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkillCategoryCard(title: "Programming Languages", items: skills.programmingLanguages, onAdd: { vm.addSkill(to: \CategorizedSkills.programmingLanguages, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.programmingLanguages, item: $0) })
            SkillCategoryCard(title: "Frameworks", items: skills.frameworks, onAdd: { vm.addSkill(to: \CategorizedSkills.frameworks, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.frameworks, item: $0) })
            SkillCategoryCard(title: "Libraries", items: skills.libraries, onAdd: { vm.addSkill(to: \CategorizedSkills.libraries, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.libraries, item: $0) })
            SkillCategoryCard(title: "Databases", items: skills.databases, onAdd: { vm.addSkill(to: \CategorizedSkills.databases, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.databases, item: $0) })
            SkillCategoryCard(title: "Cloud & DevOps", items: skills.cloudDevOps, onAdd: { vm.addSkill(to: \CategorizedSkills.cloudDevOps, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.cloudDevOps, item: $0) })
            SkillCategoryCard(title: "Tools & OS", items: skills.tools, onAdd: { vm.addSkill(to: \CategorizedSkills.tools, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.tools, item: $0) })
            SkillCategoryCard(title: "Soft Skills", items: skills.softSkills, onAdd: { vm.addSkill(to: \CategorizedSkills.softSkills, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.softSkills, item: $0) })
            SkillCategoryCard(title: "Other Skills", items: skills.other, onAdd: { vm.addSkill(to: \CategorizedSkills.other, value: $0) }, onRemove: { vm.removeSkill(from: \CategorizedSkills.other, item: $0) })
        }
    }
}

struct SkillCategoryCard: View {
    let title: String
    let items: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var newSkillInput: String = ""
    @State private var isExpanded = false

    var body: some View {
        GlassCard {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(spacing: 4) {
                                Text(item)
                                    .font(.caption.bold())
                                Button(action: { onRemove(item) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                            .foregroundStyle(MockexaTheme.textPrimary)
                        }
                    }

                    HStack {
                        TextField("Add skill", text: $newSkillInput)
                            .font(.subheadline)
                            .foregroundStyle(MockexaTheme.textPrimary)
                            .onSubmit {
                                onAdd(newSkillInput)
                                newSkillInput = ""
                            }
                        Button("Add") {
                            onAdd(newSkillInput)
                            newSkillInput = ""
                        }
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    }
                    .padding(10)
                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(MockexaTheme.darkNavy)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.caption2.bold())
                            .foregroundStyle(MockexaTheme.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                    }
                }
            }
            .tint(MockexaTheme.primary)
        }
    }
}

struct ProjectsForm: View {
    @Binding var projects: [ProjectEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    @State private var activeImprover: ImproverItemTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("PROJECTS")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Project", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            if projects.isEmpty {
                Text("No projects added yet.")
                    .font(.subheadline)
                    .foregroundStyle(MockexaTheme.textSecondary)
            }

            ForEach($projects) { $proj in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(proj.name.isEmpty ? "New Project" : proj.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.textPrimary)
                            Spacer()
                            Button(action: {
                                if let idx = projects.firstIndex(where: { $0.id == proj.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(MockexaTheme.destructive)
                            }
                        }

                        FormField(label: "Project Name", text: $proj.name, placeholder: "e.g. AI Interview Simulator")
                        FormField(label: "Description", text: $proj.description, placeholder: "Brief summary...", onImprove: {
                            activeImprover = ImproverItemTarget(type: .projectDescription, originalText: proj.description) { proj.description = $0 }
                        })
                        FormField(label: "Technologies Used", text: $proj.technologies, placeholder: "SwiftUI, Python, FastAPI")
                        FormField(label: "Key Contributions", text: $proj.keyContributions, placeholder: "Architected network layer...", onImprove: {
                            activeImprover = ImproverItemTarget(type: .projectContribution, originalText: proj.keyContributions) { proj.keyContributions = $0 }
                        })
                        FormField(label: "GitHub URL", text: $proj.githubUrl, placeholder: "https://github.com/...")
                        FormField(label: "Live / Demo URL", text: $proj.liveUrl, placeholder: "https://...")
                    }
                }
            }
        }
        .sheet(item: $activeImprover) { item in
            AIImproverSheet(type: item.type, originalText: item.originalText, onAccept: item.onAccept)
        }
    }
}

struct ExperienceForm: View {
    @Binding var experience: [ExperienceEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    @State private var activeImprover: ImproverItemTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPERIENCE / INTERNSHIPS")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    Text("Not mandatory for freshers")
                        .font(.caption2)
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
                Spacer()
                Button(action: onAdd) {
                    Label("Add Experience", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            if experience.isEmpty {
                Text("No experience added yet. Experience is optional for student resumes.")
                    .font(.subheadline)
                    .foregroundStyle(MockexaTheme.textSecondary)
            }

            ForEach($experience) { $exp in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(exp.company.isEmpty ? "New Experience" : exp.company)
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.textPrimary)
                            Spacer()
                            Button(action: {
                                if let idx = experience.firstIndex(where: { $0.id == exp.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(MockexaTheme.destructive)
                            }
                        }

                        FormField(label: "Company / Organization", text: $exp.company, placeholder: "e.g. TechPulse Solutions")
                        FormField(label: "Role / Position", text: $exp.role, placeholder: "e.g. Software Engineering Intern")
                        FormField(label: "Location", text: $exp.location, placeholder: "San Jose, CA")
                        HStack {
                            FormField(label: "Start Date", text: $exp.startDate, placeholder: "Jun 2024")
                            FormField(label: "End Date", text: $exp.endDate, placeholder: "Aug 2024")
                        }
                        Toggle("Currently working here", isOn: $exp.currentlyWorking)
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.textPrimary)
                        FormField(label: "Responsibilities", text: $exp.responsibilities, placeholder: "Key duties...", onImprove: {
                            activeImprover = ImproverItemTarget(type: .experienceBullet, originalText: exp.responsibilities) { exp.responsibilities = $0 }
                        })
                        FormField(label: "Achievements", text: $exp.achievements, placeholder: "Measurable impact...", onImprove: {
                            activeImprover = ImproverItemTarget(type: .internshipBullet, originalText: exp.achievements) { exp.achievements = $0 }
                        })
                        FormField(label: "Technologies", text: $exp.technologies, placeholder: "Swift, Xcode...")
                    }
                }
            }
        }
        .sheet(item: $activeImprover) { item in
            AIImproverSheet(type: item.type, originalText: item.originalText, onAccept: item.onAccept)
        }
    }
}

struct CertificationsForm: View {
    @Binding var certifications: [CertificationEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CERTIFICATIONS")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Certification", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            ForEach($certifications) { $cert in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(cert.name.isEmpty ? "New Certification" : cert.name)
                                .font(.subheadline.bold())
                            Spacer()
                            Button(action: {
                                if let idx = certifications.firstIndex(where: { $0.id == cert.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash").foregroundStyle(MockexaTheme.destructive)
                            }
                        }
                        FormField(label: "Certificate Name", text: $cert.name, placeholder: "AWS Practitioner")
                        FormField(label: "Issuer", text: $cert.issuer, placeholder: "Amazon Web Services")
                        FormField(label: "Date Issued", text: $cert.date, placeholder: "Nov 2024")
                        FormField(label: "Credential URL", text: $cert.credentialUrl, placeholder: "https://...")
                    }
                }
            }
        }
    }
}

struct AchievementsForm: View {
    @Binding var achievements: [AchievementEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    @State private var activeImprover: ImproverItemTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ACHIEVEMENTS")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Achievement", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            ForEach($achievements) { $ach in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(ach.title.isEmpty ? "New Achievement" : ach.title)
                                .font(.subheadline.bold())
                            Spacer()
                            Button(action: {
                                if let idx = achievements.firstIndex(where: { $0.id == ach.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash").foregroundStyle(MockexaTheme.destructive)
                            }
                        }
                        FormField(label: "Achievement Title", text: $ach.title, placeholder: "Hackathon Winner")
                        FormField(label: "Description", text: $ach.description, placeholder: "Built project...", onImprove: {
                            activeImprover = ImproverItemTarget(type: .achievementBullet, originalText: ach.description) { ach.description = $0 }
                        })
                        FormField(label: "Date", text: $ach.date, placeholder: "Oct 2024")
                    }
                }
            }
        }
        .sheet(item: $activeImprover) { item in
            AIImproverSheet(type: item.type, originalText: item.originalText, onAccept: item.onAccept)
        }
    }
}

struct PositionsForm: View {
    @Binding var positions: [PositionOfResponsibilityEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    @State private var activeImprover: ImproverItemTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("POSITIONS OF RESPONSIBILITY")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Position", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            ForEach($positions) { $pos in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(pos.position.isEmpty ? "New Position" : pos.position)
                                .font(.subheadline.bold())
                            Spacer()
                            Button(action: {
                                if let idx = positions.firstIndex(where: { $0.id == pos.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash").foregroundStyle(MockexaTheme.destructive)
                            }
                        }
                        FormField(label: "Organization", text: $pos.organization, placeholder: "ACM Student Chapter")
                        FormField(label: "Position / Role", text: $pos.position, placeholder: "Vice President")
                        FormField(label: "Duration", text: $pos.duration, placeholder: "2023 - 2024")
                        FormField(label: "Responsibilities", text: $pos.responsibilities, placeholder: "Led team...", onImprove: {
                            activeImprover = ImproverItemTarget(type: .positionOfResponsibility, originalText: pos.responsibilities) { pos.responsibilities = $0 }
                        })
                    }
                }
            }
        }
        .sheet(item: $activeImprover) { item in
            AIImproverSheet(type: item.type, originalText: item.originalText, onAccept: item.onAccept)
        }
    }
}

struct LanguagesForm: View {
    @Binding var languages: [LanguageEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LANGUAGES SPOKEN")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Language", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            ForEach($languages) { $lang in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            FormField(label: "Language", text: $lang.language, placeholder: "English")
                            FormField(label: "Proficiency", text: $lang.proficiency, placeholder: "Native / Fluent")
                            Button(action: {
                                if let idx = languages.firstIndex(where: { $0.id == lang.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash").foregroundStyle(MockexaTheme.destructive)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ExtracurricularsForm: View {
    @Binding var items: [ExtracurricularEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EXTRACURRICULAR ACTIVITIES")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Activity", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            ForEach($items) { $item in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(item.activity.isEmpty ? "New Activity" : item.activity)
                                .font(.subheadline.bold())
                            Spacer()
                            Button(action: {
                                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash").foregroundStyle(MockexaTheme.destructive)
                            }
                        }
                        FormField(label: "Activity", text: $item.activity, placeholder: "Open Source Contributor")
                        FormField(label: "Description", text: $item.description, placeholder: "Details...")
                    }
                }
            }
        }
    }
}

struct CourseworkForm: View {
    @Binding var items: [String]
    @State private var newCourse: String = ""

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("RELEVANT COURSEWORK")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)

                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { course in
                        HStack(spacing: 4) {
                            Text(course)
                                .font(.caption.bold())
                            Button(action: { items.removeAll { $0 == course } }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                        .foregroundStyle(MockexaTheme.textPrimary)
                    }
                }

                HStack {
                    TextField("Add course...", text: $newCourse)
                        .font(.subheadline)
                        .foregroundStyle(MockexaTheme.textPrimary)
                        .onSubmit {
                            let trimmed = newCourse.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !items.contains(trimmed) {
                                items.append(trimmed)
                                newCourse = ""
                            }
                        }
                    Button("Add") {
                        let trimmed = newCourse.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !items.contains(trimmed) {
                            items.append(trimmed)
                            newCourse = ""
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                }
                .padding(10)
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
            }
        }
    }
}

struct VolunteeringForm: View {
    @Binding var items: [VolunteeringEntry]
    var onAdd: () -> Void
    var onDelete: (IndexSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("VOLUNTEERING")
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Spacer()
                Button(action: onAdd) {
                    Label("Add Volunteering", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                }
            }

            ForEach($items) { $item in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(item.organization.isEmpty ? "New Volunteering" : item.organization)
                                .font(.subheadline.bold())
                            Spacer()
                            Button(action: {
                                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                                    onDelete(IndexSet(integer: idx))
                                }
                            }) {
                                Image(systemName: "trash").foregroundStyle(MockexaTheme.destructive)
                            }
                        }
                        FormField(label: "Organization", text: $item.organization, placeholder: "Youth Coding Workshop")
                        FormField(label: "Role", text: $item.role, placeholder: "Instructor")
                        FormField(label: "Duration", text: $item.duration, placeholder: "2023 - Present")
                        FormField(label: "Description", text: $item.description, placeholder: "Taught Python...")
                    }
                }
            }
        }
    }
}

// MARK: - Reusable UI Helpers

struct ImproverItemTarget: Identifiable {
    let id = UUID()
    let type: ResumeContentType
    let originalText: String
    let onAccept: (String) -> Void
}

struct FormField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var onImprove: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.textPrimary)
                Spacer()
                if let onImprove = onImprove {
                    Button(action: onImprove) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                            Text("Polish")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    }
                }
            }
            TextField(placeholder, text: $text)
                .padding(12)
                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                .foregroundStyle(MockexaTheme.textPrimary)
        }
    }
}

// MARK: - Resume Preview View
struct ResumePreviewView: View {
    let data: ResumeData
    var targetJobTitle: String? = nil
    var vm: ResumeViewModel? = nil
    var onTargetAnalyzed: ((String, String) -> Void)? = nil
    var onEditSection: ((ResumeBuilderStep) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    private let selectedTemplate: ResumeTemplate = .atsSafe
    @State private var customStyle = CustomTemplateStyle()
    @State private var previewMode: Int = 0 // 0: PDF Document, 1: Interactive Canvas
    
    @State private var exportURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var showATSChecker: Bool = false
    @State private var noticeMessage: String? = nil
    @State private var sectionBeingEdited: ResumeBuilderStep? = nil

    var activeData: ResumeData {
        vm?.resumeData ?? data
    }

    var exportResult: PDFExportResult {
        PDFExportService.shared.generatePDFResult(from: activeData, template: selectedTemplate, customStyle: customStyle)
    }

    private func editSection(_ step: ResumeBuilderStep) {
        if let vm = vm {
            vm.currentStep = step
            sectionBeingEdited = step
        } else if let onEditSection = onEditSection {
            onEditSection(step)
            dismiss()
        }
    }

    var contactParts: [String] {
        var parts: [String] = []
        if !activeData.personalInfo.email.isEmpty { parts.append(activeData.personalInfo.email) }
        if !activeData.personalInfo.phone.isEmpty { parts.append(activeData.personalInfo.phone) }
        if !activeData.personalInfo.location.isEmpty { parts.append(activeData.personalInfo.location) }
        return parts
    }

    var linkParts: [String] {
        var parts: [String] = []
        if !activeData.personalInfo.linkedIn.isEmpty { parts.append("LinkedIn") }
        if !activeData.personalInfo.github.isEmpty { parts.append("GitHub") }
        if !activeData.personalInfo.portfolio.isEmpty { parts.append("Portfolio") }
        return parts
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // Top Control Bar - Unified Best ATS Safe Standard
                VStack(spacing: 10) {
                    // Page Budget & Action Row
                    HStack(spacing: 8) {
                        // Best ATS-Safe Standard Badge
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                            Text("Best ATS-Safe Standard")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                        .foregroundStyle(MockexaTheme.primary)

                        // Page Budget Indicator Badge
                        HStack(spacing: 4) {
                            Image(systemName: exportResult.isOptimalOnePage ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text(exportResult.isOptimalOnePage ? "1 Page" : "\(exportResult.pageCount) Pages")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(exportResult.isOptimalOnePage ? MockexaTheme.success.opacity(0.12) : MockexaTheme.warning.opacity(0.15), in: Capsule())
                        .foregroundStyle(exportResult.isOptimalOnePage ? MockexaTheme.success : MockexaTheme.warning)

                        Spacer()

                        // View Mode Switcher
                        Picker("View", selection: $previewMode) {
                            Text("📄 PDF").tag(0)
                            Text("📱 Cards").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)

                        // ATS Check Button
                        Button(action: { showATSChecker = true }) {
                            Label("ATS Check", systemImage: "checkmark.shield")
                                .font(.caption.bold())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(MockexaTheme.primary.opacity(0.15), in: Capsule())
                                .foregroundStyle(MockexaTheme.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
                .background(MockexaTheme.surface)

                Divider().background(MockexaTheme.border)

                // Over One-Page Budget Warning Banner
                if let warning = exportResult.warningMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MockexaTheme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("One-Page Layout Warning")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.warning)
                            Text(warning)
                                .font(.caption2)
                                .foregroundStyle(MockexaTheme.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(MockexaTheme.warning.opacity(0.1))
                }

                // Document Preview Canvas Area
                if previewMode == 0 {
                    // Vector Crisp PDF View
                    PDFKitRepresentable(pdfData: exportResult.pdfData)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Interactive SwiftUI Cards Preview
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // Header Block
                            HStack(alignment: .top) {
                                VStack(spacing: 6) {
                                    Text(activeData.personalInfo.fullName.isEmpty ? "Your Name" : activeData.personalInfo.fullName)
                                        .font(selectedTemplate == .atsSafe ? .custom("Helvetica-Bold", size: 22) : .title2.bold())
                                        .foregroundStyle(MockexaTheme.textPrimary)

                                    if !activeData.personalInfo.headline.isEmpty {
                                        Text(activeData.personalInfo.headline)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(MockexaTheme.primary)
                                    }

                                    if !contactParts.isEmpty {
                                        Text(contactParts.joined(separator: "  •  "))
                                            .font(.caption)
                                            .foregroundStyle(MockexaTheme.textSecondary)
                                    }

                                    if !linkParts.isEmpty {
                                        Text(linkParts.joined(separator: "  •  "))
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.primary)
                                    }
                                }
                                .frame(maxWidth: .infinity)

                                Button(action: { editSection(.personalInfo) }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "pencil")
                                        Text("Edit")
                                    }
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                                }
                            }
                            .padding(16)
                            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                            // Professional Summary
                            if !activeData.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                PreviewSection(title: "PROFESSIONAL SUMMARY", onEdit: { editSection(.summary) }) {
                                    Text(activeData.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(MockexaTheme.textPrimary)
                                }
                            }

                            // Education
                            if !activeData.education.isEmpty {
                                PreviewSection(title: "EDUCATION", onEdit: { editSection(.education) }) {
                                    ForEach(activeData.education) { edu in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(edu.institution).font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                                Spacer()
                                                Text("\(edu.startYear)\(edu.startYear.isEmpty ? "" : " - ")\(edu.graduationYear)")
                                                    .font(.caption)
                                                    .foregroundStyle(MockexaTheme.textSecondary)
                                            }
                                            Text("\(edu.degree)\(edu.degree.isEmpty || edu.fieldOfStudy.isEmpty ? "" : " in ")\(edu.fieldOfStudy)")
                                                .font(.caption.bold())
                                                .foregroundStyle(MockexaTheme.primary)
                                            if !edu.gpa.isEmpty { Text("GPA / Score: \(edu.gpa)").font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                            if !edu.relevantCoursework.isEmpty { Text("Coursework: \(edu.relevantCoursework)").font(.caption).foregroundStyle(MockexaTheme.textSecondary) }
                                            if !edu.academicAchievement.isEmpty { Text("Honors: \(edu.academicAchievement)").font(.caption).foregroundStyle(MockexaTheme.textSecondary) }
                                        }
                                        .padding(.bottom, 6)
                                    }
                                }
                            }

                            // Skills
                            let hasSkills = !activeData.skills.programmingLanguages.isEmpty || !activeData.skills.frameworks.isEmpty ||
                                            !activeData.skills.libraries.isEmpty || !activeData.skills.databases.isEmpty ||
                                            !activeData.skills.cloudDevOps.isEmpty || !activeData.skills.tools.isEmpty ||
                                            !activeData.skills.softSkills.isEmpty || !activeData.skills.other.isEmpty
                            if hasSkills {
                                PreviewSection(title: "SKILLS", onEdit: { editSection(.skills) }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if !activeData.skills.programmingLanguages.isEmpty { SkillRow(label: "Languages", items: activeData.skills.programmingLanguages) }
                                        if !activeData.skills.frameworks.isEmpty { SkillRow(label: "Frameworks", items: activeData.skills.frameworks) }
                                        if !activeData.skills.libraries.isEmpty { SkillRow(label: "Libraries", items: activeData.skills.libraries) }
                                        if !activeData.skills.databases.isEmpty { SkillRow(label: "Databases", items: activeData.skills.databases) }
                                        if !activeData.skills.cloudDevOps.isEmpty { SkillRow(label: "Cloud & DevOps", items: activeData.skills.cloudDevOps) }
                                        if !activeData.skills.tools.isEmpty { SkillRow(label: "Tools & OS", items: activeData.skills.tools) }
                                        if !activeData.skills.softSkills.isEmpty { SkillRow(label: "Soft Skills", items: activeData.skills.softSkills) }
                                        if !activeData.skills.other.isEmpty { SkillRow(label: "Other", items: activeData.skills.other) }
                                    }
                                }
                            }

                            // Projects
                            if !activeData.projects.isEmpty {
                                PreviewSection(title: "PROJECTS", onEdit: { editSection(.projects) }) {
                                    ForEach(activeData.projects) { proj in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(proj.name).font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                            if !proj.description.isEmpty { Text(proj.description).font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                            if !proj.keyContributions.isEmpty { Text("Contributions: \(proj.keyContributions)").font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                            if !proj.technologies.isEmpty { Text("Tech: \(proj.technologies)").font(.caption.bold()).foregroundStyle(MockexaTheme.primary) }
                                        }
                                        .padding(.bottom, 6)
                                    }
                                }
                            }

                            // Experience
                            if !activeData.experience.isEmpty {
                                PreviewSection(title: "EXPERIENCE & INTERNSHIPS", onEdit: { editSection(.experience) }) {
                                    ForEach(activeData.experience) { exp in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("\(exp.role) @ \(exp.company)").font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                                Spacer()
                                                Text("\(exp.startDate)\(exp.startDate.isEmpty ? "" : " - ")\(exp.currentlyWorking ? "Present" : exp.endDate)")
                                                    .font(.caption)
                                                    .foregroundStyle(MockexaTheme.textSecondary)
                                            }
                                            if !exp.responsibilities.isEmpty { Text("• \(exp.responsibilities)").font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                            if !exp.achievements.isEmpty { Text("• Impact: \(exp.achievements)").font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                        }
                                        .padding(.bottom, 6)
                                    }
                                }
                            }

                            // Certifications
                            if !activeData.certifications.isEmpty {
                                PreviewSection(title: "CERTIFICATIONS", onEdit: { editSection(.certifications) }) {
                                    ForEach(activeData.certifications) { cert in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(cert.name).font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                            if !cert.issuer.isEmpty { Text("Issuer: \(cert.issuer)").font(.caption).foregroundStyle(MockexaTheme.textSecondary) }
                                        }
                                    }
                                }
                            }

                            // Achievements
                            if !activeData.achievements.isEmpty {
                                PreviewSection(title: "ACHIEVEMENTS", onEdit: { editSection(.achievements) }) {
                                    ForEach(activeData.achievements) { ach in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ach.title).font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                            if !ach.description.isEmpty { Text(ach.description).font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                        }
                                    }
                                }
                            }

                            // Positions of Responsibility
                            if !activeData.positionsOfResponsibility.isEmpty {
                                PreviewSection(title: "POSITIONS OF RESPONSIBILITY", onEdit: { editSection(.positions) }) {
                                    ForEach(activeData.positionsOfResponsibility) { pos in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(pos.position) - \(pos.organization)").font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                            if !pos.responsibilities.isEmpty { Text(pos.responsibilities).font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                        }
                                    }
                                }
                            }

                            // Languages
                            if !activeData.languages.isEmpty {
                                PreviewSection(title: "LANGUAGES", onEdit: { editSection(.languages) }) {
                                    Text(activeData.languages.map { "\($0.language)\($0.proficiency.isEmpty ? "" : " (\($0.proficiency))")" }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textPrimary)
                                }
                            }

                            // Extracurriculars
                            if !activeData.extracurriculars.isEmpty {
                                PreviewSection(title: "EXTRACURRICULAR ACTIVITIES", onEdit: { editSection(.extracurriculars) }) {
                                    ForEach(activeData.extracurriculars) { extra in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(extra.activity).font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                            if !extra.description.isEmpty { Text(extra.description).font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                        }
                                    }
                                }
                            }

                            // Coursework
                            if !activeData.relevantCoursework.isEmpty {
                                PreviewSection(title: "RELEVANT COURSEWORK", onEdit: { editSection(.coursework) }) {
                                    Text(activeData.relevantCoursework.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textPrimary)
                                }
                            }

                            // Volunteering
                            if !activeData.volunteering.isEmpty {
                                PreviewSection(title: "VOLUNTEERING", onEdit: { editSection(.volunteering) }) {
                                    ForEach(activeData.volunteering) { vol in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(vol.role) - \(vol.organization)").font(.subheadline.bold()).foregroundStyle(MockexaTheme.textPrimary)
                                            if !vol.description.isEmpty { Text(vol.description).font(.caption).foregroundStyle(MockexaTheme.textPrimary) }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }

                // Bottom Export Bar
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(MockexaTheme.border)

                    HStack {
                        Text("Export Resume")
                            .font(.subheadline.bold())
                            .foregroundStyle(MockexaTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    HStack(spacing: 12) {
                        // PDF Export Button
                        Button(action: {
                            if let url = PDFExportService.shared.exportPDFURL(
                                from: activeData,
                                template: selectedTemplate,
                                customStyle: customStyle,
                                targetJobTitle: targetJobTitle
                            ) {
                                exportURL = url
                                showShareSheet = true
                                Haptics.success()
                            } else {
                                noticeMessage = "The PDF could not be created. Please try again."
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc.richtext.fill")
                                Text("PDF")
                                    .font(.headline.bold())
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(MockexaTheme.primary, in: RoundedRectangle(cornerRadius: 12))
                        }

                        // Word (.docx) Export Button
                        Button(action: {
                            if let url = DOCXExportService.shared.exportDOCXURL(
                                from: activeData,
                                template: selectedTemplate,
                                customStyle: customStyle,
                                targetJobTitle: targetJobTitle
                            ) {
                                exportURL = url
                                showShareSheet = true
                                Haptics.success()
                            } else {
                                noticeMessage = "The Word document could not be created. Please try again."
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                Text("Word (.docx)")
                                    .font(.headline.bold())
                            }
                            .foregroundStyle(MockexaTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(MockexaTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(MockexaTheme.primary.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .background(MockexaTheme.surface)
            }
        }
        .navigationTitle("Resume Preview & Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showATSChecker) {
            ATSCheckerView(resumeData: activeData, onTargetAnalyzed: onTargetAnalyzed)
        }
        .sheet(item: $sectionBeingEdited) { step in
            if let vm = vm {
                SectionEditorSheet(vm: vm, step: step)
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { noticeMessage != nil },
            set: { if !$0 { noticeMessage = nil } }
        )) {
            Button("OK", role: .cancel) { noticeMessage = nil }
        } message: {
            Text(noticeMessage ?? "Please try again.")
        }
    }
}

// MARK: - Dedicated Section Editor Sheet
struct SectionEditorSheet: View {
    @ObservedObject var vm: ResumeViewModel
    let step: ResumeBuilderStep
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        switch step {
                        case .personalInfo:
                            PersonalInfoForm(info: $vm.resumeData.personalInfo)
                        case .summary:
                            SummaryForm(summary: $vm.resumeData.summary)
                        case .education:
                            EducationForm(education: $vm.resumeData.education, onAdd: vm.addEducation, onDelete: vm.removeEducation)
                        case .skills:
                            SkillsForm(skills: $vm.resumeData.skills, vm: vm)
                        case .projects:
                            ProjectsForm(projects: $vm.resumeData.projects, onAdd: vm.addProject, onDelete: vm.removeProject)
                        case .experience:
                            ExperienceForm(experience: $vm.resumeData.experience, onAdd: vm.addExperience, onDelete: vm.removeExperience)
                        case .certifications:
                            CertificationsForm(certifications: $vm.resumeData.certifications, onAdd: vm.addCertification, onDelete: vm.removeCertification)
                        case .achievements:
                            AchievementsForm(achievements: $vm.resumeData.achievements, onAdd: vm.addAchievement, onDelete: vm.removeAchievement)
                        case .positions:
                            PositionsForm(positions: $vm.resumeData.positionsOfResponsibility, onAdd: vm.addPosition, onDelete: vm.removePosition)
                        case .languages:
                            LanguagesForm(languages: $vm.resumeData.languages, onAdd: vm.addLanguage, onDelete: vm.removeLanguage)
                        case .extracurriculars:
                            ExtracurricularsForm(items: $vm.resumeData.extracurriculars, onAdd: vm.addExtracurricular, onDelete: vm.removeExtracurricular)
                        case .coursework:
                            CourseworkForm(items: $vm.resumeData.relevantCoursework)
                        case .volunteering:
                            VolunteeringForm(items: $vm.resumeData.volunteering, onAdd: vm.addVolunteering, onDelete: vm.removeVolunteering)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        vm.saveProfilesToUserDefaults()
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(MockexaTheme.primary)
                }
            }
        }
    }
}

struct PreviewSection<Content: View>: View {
    let title: String
    var onEdit: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    Spacer()
                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(MockexaTheme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                        }
                    }
                }
                Divider()
                content()
            }
        }
    }
}

struct SkillRow: View {
    let label: String
    let items: [String]

    var body: some View {
        HStack(alignment: .top) {
            Text("\(label):").font(.caption.bold()).frame(width: 90, alignment: .leading)
            Text(items.joined(separator: ", ")).font(.caption)
        }
    }
}

// MARK: - AI Resume Improver Sheet
struct AIImproverSheet: View {
    let type: ResumeContentType
    let originalText: String
    let onAccept: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var result: AIImprovementResult? = nil
    @State private var editableSuggestion: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Placement Guidance Banner
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(MockexaTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PLACEMENT STUDENT GUIDANCE")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                Text("Only include achievements and metrics you can comfortably explain in an interview.")
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                        }
                        .padding(14)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.border, lineWidth: 1))

                        // CURRENT Content Box
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("CURRENT CONTENT")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                Text(originalText.isEmpty ? "(No content entered yet)" : originalText)
                                    .font(.body)
                                    .foregroundStyle(MockexaTheme.textPrimary)
                            }
                        }

                        // Loading State
                        if isLoading {
                            GlassCard {
                                HStack(spacing: 14) {
                                    ProgressView()
                                    VStack(alignment: .leading, spacing: 4) {
                                Text("Polishing wording...")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(MockexaTheme.textPrimary)
                                        Text("Applying strong action verbs & professional polish...")
                                            .font(.caption)
                                            .foregroundStyle(MockexaTheme.textSecondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        } else if let error = errorMessage {
                            // Error State
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(MockexaTheme.destructive)
                                        Text("Enhancement Failed")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(MockexaTheme.destructive)
                                    }
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    Button("Retry") {
                                        Task { await processImprovement() }
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                }
                            }
                        } else if let res = result {
                            // AI SUGGESTION Box (Editable)
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("SUGGESTED WORDING (EDITABLE)")
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.primary)
                                        Spacer()
                                        Image(systemName: "sparkles")
                                            .foregroundStyle(MockexaTheme.primary)
                                    }

                                    TextEditor(text: $editableSuggestion)
                                        .frame(minHeight: 110)
                                        .padding(8)
                                        .scrollContentBackground(.hidden)
                                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                                        .font(.body)
                                        .foregroundStyle(MockexaTheme.textPrimary)
                                }
                            }

                            // WHY THIS IS BETTER
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("WHY THIS IS BETTER")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.success)

                                    ForEach(res.whyBetter, id: \.self) { reason in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(MockexaTheme.success)
                                            Text(reason)
                                                .font(.caption)
                                                .foregroundStyle(MockexaTheme.textPrimary)
                                        }
                                    }

                                    if let tip = res.metricSuggestion {
                                        Divider()
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "info.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(MockexaTheme.primary)
                                            Text(tip)
                                                .font(.caption.bold())
                                                .foregroundStyle(MockexaTheme.primary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        Divider().background(MockexaTheme.border)
                        HStack(spacing: 12) {
                            SecondaryButton(title: "Cancel") {
                                dismiss()
                            }

                            if result != nil {
                                Button("Try Again") {
                                    Task { await processImprovement() }
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(MockexaTheme.border, lineWidth: 1))
                                .foregroundStyle(MockexaTheme.textPrimary)

                                PrimaryButton(title: "Accept & Apply", icon: "checkmark") {
                                    onAccept(editableSuggestion)
                                    Haptics.success()
                                    dismiss()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .background(MockexaTheme.surface)
                }
            }
            .navigationTitle("Resume Wording Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await processImprovement()
            }
        }
    }

    private func processImprovement() async {
        isLoading = true
        errorMessage = nil
        let res = await ResumeService.shared.improveText(originalText: originalText, type: type)
        isLoading = false
        switch res {
        case .success(let outcome):
            self.result = outcome
            self.editableSuggestion = outcome.improvedText
        case .failure(let err):
            self.errorMessage = err.localizedDescription
        }
    }
}

// MARK: - ATS Resume Checker View
struct ATSCheckerView: View {
    let resumeData: ResumeData
    var initialJobTitle: String = ""
    var initialJobDescription: String = ""
    var onTargetAnalyzed: ((String, String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var jobTitle: String = ""
    @State private var jobDescription: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: ATSAnalysisResult? = nil
    @State private var showOptimizationSheet: Bool = false

    init(
        resumeData: ResumeData,
        initialJobTitle: String = "",
        initialJobDescription: String = "",
        onTargetAnalyzed: ((String, String) -> Void)? = nil
    ) {
        self.resumeData = resumeData
        self.initialJobTitle = initialJobTitle
        self.initialJobDescription = initialJobDescription
        self.onTargetAnalyzed = onTargetAnalyzed
        _jobTitle = State(initialValue: initialJobTitle.isEmpty ? resumeData.personalInfo.headline : initialJobTitle)
        _jobDescription = State(initialValue: initialJobDescription)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let result = analysisResult {
                            // RESULTS VIEW
                            ATSResultContentView(result: result, onReanalyze: {
                                analysisResult = nil
                            }, onOptimize: {
                                showOptimizationSheet = true
                            })
                        } else {
                            // INPUT FORM VIEW
                            ATSInputFormView(
                                jobTitle: $jobTitle,
                                jobDescription: $jobDescription,
                                isAnalyzing: isAnalyzing,
                                onAnalyze: performAnalysis
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("ATS Resume Checker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(MockexaTheme.primary)
                }
            }
            .sheet(isPresented: $showOptimizationSheet) {
                if let result = analysisResult {
                    ATSOptimizationSheet(result: result)
                }
            }
        }
    }

    private func performAnalysis() {
        isAnalyzing = true
        Task {
            // Short delay for smooth processing UX
            try? await Task.sleep(nanoseconds: 300_000_000)
            let outcome = await ResumeService.shared.analyzeATS(
                resumeData: resumeData,
                jobTitle: jobTitle,
                jobDescription: jobDescription
            )
            self.analysisResult = outcome
            self.isAnalyzing = false
            self.onTargetAnalyzed?(jobTitle, jobDescription)
            Haptics.success()
        }
    }
}

// MARK: - ATS Input Form Subview
struct ATSInputFormView: View {
    @Binding var jobTitle: String
    @Binding var jobDescription: String
    let isAnalyzing: Bool
    let onAnalyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Placement Info Banner
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(MockexaTheme.primary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PLACEMENT ATS ANALYSIS")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    Text("Paste the job description below to check keyword match, skill alignment, and structural formatting.")
                        .font(.caption)
                        .foregroundStyle(MockexaTheme.textSecondary)
                }
            }
            .padding(14)
            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.border, lineWidth: 1))

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FormField(label: "Target Job Title", text: $jobTitle, placeholder: "e.g. Software Engineer / SDE Intern")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Job Description *")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.darkNavy)

                        TextEditor(text: $jobDescription)
                            .frame(minHeight: 180)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                            .font(.body)
                            .foregroundStyle(MockexaTheme.textPrimary)
                    }

                    if isAnalyzing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Analyzing ATS match deterministically...")
                                .font(.subheadline.bold())
                                .foregroundStyle(MockexaTheme.darkNavy)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    } else {
                        PrimaryButton(title: "Analyze ATS Match", icon: "sparkles") {
                            onAnalyze()
                        }
                        .disabled(jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jobDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jobDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    }
                }
            }
        }
    }
}

// MARK: - ATS Result Content Subview
struct ATSResultContentView: View {
    let result: ATSAnalysisResult
    let onReanalyze: () -> Void
    let onOptimize: () -> Void

    var scoreColor: Color {
        if result.score >= 75 { return MockexaTheme.success }
        if result.score >= 50 { return MockexaTheme.warning }
        return MockexaTheme.destructive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Overall Score Header Card
            GlassCard {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ATS MATCH SCORE")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.textSecondary)
                            Text(result.jobTitle)
                                .font(.title3.bold())
                                .foregroundStyle(MockexaTheme.darkNavy)
                        }
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(scoreColor.opacity(0.18), lineWidth: 8)
                                .frame(width: 74, height: 74)
                            Circle()
                                .trim(from: 0, to: CGFloat(result.score) / 100.0)
                                .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 74, height: 74)
                                .rotationEffect(.degrees(-90))
                            Text("\(result.score)")
                                .font(.title2.bold())
                                .foregroundStyle(scoreColor)
                        }
                    }

                    Divider()

                    // Transparent Score Breakdown Grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSPARENT SCORE BREAKDOWN")
                            .font(.caption2.bold())
                            .foregroundStyle(MockexaTheme.primary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ScoreBreakdownItem(title: "Keyword Match", score: result.breakdown.keywordScore, maxScore: 25)
                            ScoreBreakdownItem(title: "Skills Match", score: result.breakdown.skillsScore, maxScore: 35)
                            ScoreBreakdownItem(title: "Section Check", score: result.breakdown.sectionScore, maxScore: 20)
                            ScoreBreakdownItem(title: "Formatting Check", score: result.breakdown.formattingScore, maxScore: 20)
                        }
                    }
                }
            }

            // Keywords Match Card
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("KEYWORD OVERLAP")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)

                    if !result.matchedKeywords.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Matched Keywords (\(result.matchedKeywords.count))")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.success)
                            FlowLayout(spacing: 6) {
                                ForEach(result.matchedKeywords, id: \.self) { kw in
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(kw).font(.caption.bold())
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(MockexaTheme.success.opacity(0.12), in: Capsule())
                                    .foregroundStyle(MockexaTheme.success)
                                }
                            }
                        }
                    }

                    if !result.missingKeywords.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Missing Keywords (\(result.missingKeywords.count))")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.warning)
                            FlowLayout(spacing: 6) {
                                ForEach(result.missingKeywords, id: \.self) { kw in
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(kw).font(.caption.bold())
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(MockexaTheme.warning.opacity(0.12), in: Capsule())
                                    .foregroundStyle(MockexaTheme.warning)
                                }
                            }
                        }
                    }
                }
            }

            // Skills Match Card
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SKILLS ALIGNMENT")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)

                    if !result.matchedSkills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Found in Resume")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.success)
                            FlowLayout(spacing: 6) {
                                ForEach(result.matchedSkills, id: \.self) { sk in
                                    Text(sk)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                                        .foregroundStyle(MockexaTheme.primary)
                                }
                            }
                        }
                    }

                    if !result.missingSkills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Requested in JD but Missing")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.destructive)
                            FlowLayout(spacing: 6) {
                                ForEach(result.missingSkills, id: \.self) { sk in
                                    Text(sk)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(MockexaTheme.destructive.opacity(0.12), in: Capsule())
                                        .foregroundStyle(MockexaTheme.destructive)
                                }
                            }
                        }
                    }
                }
            }

            // Section Check Card
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RESUME SECTION CHECK")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)

                    ForEach(result.sectionChecks) { chk in
                        HStack(spacing: 10) {
                            Image(systemName: chk.isPresent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(chk.isPresent ? MockexaTheme.success : MockexaTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chk.sectionName)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(MockexaTheme.darkNavy)
                                Text(chk.detail)
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                            Spacer()
                        }
                    }
                }
            }

            // Formatting Check Card
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("FORMATTING CHECK")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)

                    if result.formattingIssues.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(MockexaTheme.success)
                            Text("Clean ATS layout detected! Standard headings and clear structure.")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.darkNavy)
                        }
                    } else {
                        ForEach(result.formattingIssues, id: \.self) { issue in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(MockexaTheme.warning)
                                Text(issue)
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.darkNavy)
                            }
                        }
                    }
                }
            }

            // Recommendations Card
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ACTIONABLE RECOMMENDATIONS")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)

                    ForEach(result.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").font(.body.bold()).foregroundStyle(MockexaTheme.primary)
                            Text(rec)
                                .font(.caption)
                                .foregroundStyle(MockexaTheme.darkNavy)
                        }
                    }
                }
            }

            // Bottom Action Buttons
            VStack(spacing: 10) {
                PrimaryButton(title: "View Improvement Suggestions", icon: "sparkles") {
                    onOptimize()
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: "Re-analyze") {
                        onReanalyze()
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

struct ScoreBreakdownItem: View {
    let title: String
    let score: Int
    let maxScore: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(MockexaTheme.textSecondary)
                Spacer()
                Text("\(score)/\(maxScore)")
                    .font(.caption2.bold())
                    .foregroundStyle(MockexaTheme.primary)
            }
            ProgressView(value: Double(score), total: Double(maxScore))
                .tint(MockexaTheme.primary)
        }
        .padding(10)
        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MockexaTheme.border, lineWidth: 1))
    }
}

// MARK: - ATS Optimization Suggestions Sheet
struct ATSOptimizationSheet: View {
    let result: ATSAnalysisResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Integrity Guidance Banner
                        HStack(spacing: 12) {
                            Image(systemName: "shield.trianglebadge.exclamationmark")
                                .font(.system(size: 22))
                                .foregroundStyle(MockexaTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ANTI-HALLUCINATION & INTEGRITY")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                Text("Only include skills, technologies, and achievements you can comfortably explain in an interview. Never invent unearned experience.")
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                        }
                        .padding(14)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.border, lineWidth: 1))

                        Text("Target Job: \(result.jobTitle)")
                            .font(.subheadline.bold())
                            .foregroundStyle(MockexaTheme.darkNavy)

                        ForEach(result.optimizationSuggestions) { sug in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(sug.category.uppercased())
                                            .font(.caption2.bold())
                                            .foregroundStyle(MockexaTheme.primary)
                                        Spacer()
                                    }

                                    Text(sug.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(MockexaTheme.darkNavy)

                                    Text(sug.suggestion)
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textSecondary)

                                    Divider()

                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.bubble.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(MockexaTheme.success)
                                        Text(sug.actionableAdvice)
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.darkNavy)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Job Optimization Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(MockexaTheme.primary)
                }
            }
        }
    }
}

// MARK: - Resume Studio Main Hub Screen

struct ResumeStudioView: View {
    @StateObject private var vm = ResumeViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager
    
    @State private var profileToEdit: ResumeProfile? = nil
    @State private var profileToPreview: ResumeProfile? = nil
    @State private var profileToTailor: ResumeProfile? = nil
    
    @State private var showCreateProfileAlert = false
    @State private var newProfileName = ""
    
    @State private var profileToRename: ResumeProfile? = nil
    @State private var renameInputText = ""
    
    @State private var profileToDelete: ResumeProfile? = nil
    @State private var showDeleteConfirm = false
    @State private var showResumeImporter = false
    @State private var importErrorMessage: String? = nil
    @State private var importSuccessMessage: String? = nil
    @State private var profileForATS: ResumeProfile? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header Banner
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "folder.fill.badge.gearshape")
                                    .font(.title2)
                                    .foregroundStyle(MockexaTheme.primary)
                                Text("Resume Studio")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(MockexaTheme.textPrimary)
                                Spacer()
                                Menu {
                                    Button("Upload PDF or Text Resume", systemImage: "arrow.up.doc.fill") {
                                        showResumeImporter = true
                                    }
                                    Button("Create Blank Resume", systemImage: "plus") {
                                        showCreateProfileAlert = true
                                    }
                                } label: {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(MockexaTheme.primary, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                            Text("Manage your master resume profiles and create job-tailored versions without re-entering data.")
                                .font(.footnote)
                                .foregroundStyle(MockexaTheme.textSecondary)
                        }
                        .padding(16)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(MockexaTheme.border, lineWidth: 1)
                        )

                        // Prominent Upload Real Resume Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(MockexaTheme.primary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Upload Your Resume (PDF / TXT)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(MockexaTheme.textPrimary)
                                    Text("Import your actual resume to check your ATS score, customize against any Job Description, and practice Technical, HR, & GD rounds grounded in your real projects.")
                                        .font(.caption)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                }
                            }

                            Button(action: { showResumeImporter = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.doc.fill")
                                    Text("Select & Upload Resume File")
                                        .fontWeight(.semibold)
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(MockexaTheme.primary, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                            }
                        }
                        .padding(14)
                        .background(MockexaTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(MockexaTheme.primary.opacity(0.25), lineWidth: 1)
                        )

                        if let successMsg = importSuccessMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(MockexaTheme.success)
                                Text(successMsg)
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)
                                Spacer()
                                Button(action: { importSuccessMessage = nil }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                }
                            }
                            .padding(10)
                            .background(MockexaTheme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }

                        // Saved Profiles List Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SAVED RESUME PROFILES")
                                .font(.caption.bold())
                                .foregroundStyle(MockexaTheme.textSecondary)
                                .tracking(1)

                            if vm.profiles.isEmpty {
                                Text("No resume profiles saved. Tap 'Upload Your Resume' to get started.")
                                    .font(.subheadline)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                    .padding(24)
                                    .frame(maxWidth: .infinity)
                                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                ForEach(vm.profiles) { profile in
                                    ResumeProfileCardView(
                                        profile: profile,
                                        isActive: vm.activeProfileId == profile.id,
                                        onSelect: { vm.selectProfile(id: profile.id) },
                                        onEdit: {
                                            vm.selectProfile(id: profile.id)
                                            profileToEdit = profile
                                        },
                                        onPreview: {
                                            vm.selectProfile(id: profile.id)
                                            profileToPreview = profile
                                        },
                                        onTailor: { profileToTailor = profile },
                                        onDuplicate: { _ = vm.duplicateProfile(id: profile.id) },
                                        onRename: {
                                            profileToRename = profile
                                            renameInputText = profile.name
                                        },
                                        onDelete: {
                                            profileToDelete = profile
                                            showDeleteConfirm = true
                                        },
                                        onATSCheck: {
                                            profileForATS = profile
                                        }
                                    )
                                }
                            }
                        }

                        // Guidance Card
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(MockexaTheme.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep one master resume")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)
                                Text("The Active resume can personalize HR, Technical and AI GD practice. Tailored copies keep your original facts unchanged.")
                                    .font(.caption2)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(MockexaTheme.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Resume Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(MockexaTheme.primary)
                }
            }
            .alert("Create New Profile", isPresented: $showCreateProfileAlert) {
                TextField("Profile Name (e.g. Alex's Resume)", text: $newProfileName)
                Button("Cancel", role: .cancel) { newProfileName = "" }
                Button("Create") {
                    if !newProfileName.trimmingCharacters(in: .whitespaces).isEmpty {
                        _ = vm.createNewProfile(name: newProfileName)
                        newProfileName = ""
                    }
                }
            }
            .alert("Rename Profile", isPresented: Binding(
                get: { profileToRename != nil },
                set: { if !$0 { profileToRename = nil } }
            )) {
                TextField("New Profile Name", text: $renameInputText)
                Button("Cancel", role: .cancel) { profileToRename = nil }
                Button("Save") {
                    if let prof = profileToRename {
                        vm.renameProfile(id: prof.id, newName: renameInputText)
                        profileToRename = nil
                    }
                }
            }
            .alert("Delete Resume Profile?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { profileToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let prof = profileToDelete {
                        vm.deleteProfile(id: prof.id)
                        profileToDelete = nil
                    }
                }
            } message: {
                Text("Are you sure you want to delete '\(profileToDelete?.name ?? "this profile")'? This action cannot be undone.")
            }
            .sheet(item: $profileToEdit) { prof in
                ResumeBuilderView(vm: vm)
            }
            .sheet(item: $profileToPreview) { prof in
                ResumePreviewView(
                    data: prof.resumeData,
                    targetJobTitle: prof.targetJobTitle,
                    vm: vm,
                    onTargetAnalyzed: { title, jd in
                        vm.updateJobDescription(for: prof.id, jd: jd, jobTitle: title)
                    }
                )
            }
            .sheet(item: $profileToTailor) { prof in
                TailorResumeSheet(masterProfile: prof, vm: vm)
            }
            .sheet(item: $profileForATS) { prof in
                ATSCheckerView(
                    resumeData: prof.resumeData,
                    initialJobTitle: prof.targetJobTitle ?? "",
                    initialJobDescription: prof.targetJobDescription ?? ""
                )
            }
            .fileImporter(
                isPresented: $showResumeImporter,
                allowedContentTypes: [.pdf, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    switch vm.importResumeDocument(url: url) {
                    case .success(let imported):
                        vm.selectProfile(id: imported.id)
                        importSuccessMessage = "Imported '\(imported.name)'! Check ATS score or start Practice Rounds."
                    case .failure(let error):
                        importErrorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "The selected resume could not be imported.")
            }
            .task(id: auth.currentUserId) {
                vm.activateStorage(for: auth.currentUserId)
            }
        }
    }
}

// MARK: - Resume Profile Card View

struct ResumeProfileCardView: View {
    let profile: ResumeProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onPreview: () -> Void
    let onTailor: () -> Void
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    var onATSCheck: (() -> Void)? = nil

    var atsScore: Int {
        let title = profile.targetJobTitle ?? profile.resumeData.personalInfo.headline
        let result = ResumeService.shared.generateDeterministicATSResult(
            resumeData: profile.resumeData,
            jobTitle: title,
            jobDescription: profile.targetJobDescription ?? ""
        )
        return result.score
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row: Radio/Check + Profile Name + Menu
            HStack(alignment: .top, spacing: 10) {
                Button(action: onSelect) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isActive ? MockexaTheme.primary : MockexaTheme.textSecondary.opacity(0.5))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onSelect) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(MockexaTheme.textPrimary)

                            if isActive {
                                Text("Active")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MockexaTheme.primary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(MockexaTheme.primary)
                            }

                            if profile.isSample {
                                Text("Sample Resume")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MockexaTheme.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(MockexaTheme.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let target = profile.targetJobTitle, !target.isEmpty {
                        Text("Target: \(target)")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.primary)
                    } else if !profile.resumeData.personalInfo.headline.isEmpty {
                        Text(profile.resumeData.personalInfo.headline)
                            .font(.caption)
                            .foregroundStyle(MockexaTheme.textSecondary)
                            .lineLimit(1)
                    }

                    if profile.isTailored {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.caption2)
                            Text("Tailored Version")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(MockexaTheme.primary)
                    }
                }

                Spacer()

                Menu {
                    Button(action: onRename) {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(action: onDuplicate) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(MockexaTheme.textSecondary)
                        .padding(4)
                }
            }

            Divider().background(MockexaTheme.border)

            // Middle Stats Row: ATS Score & Last Edited
            HStack {
                Button(action: { onATSCheck?() }) {
                    HStack(spacing: 6) {
                        Text("ATS Score:")
                            .font(.caption)
                            .foregroundStyle(MockexaTheme.textSecondary)
                        
                        HStack(spacing: 3) {
                            Text("\(atsScore)")
                                .font(.caption.bold())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            atsScore >= 75 ? MockexaTheme.success.opacity(0.15) :
                            (atsScore >= 50 ? MockexaTheme.warning.opacity(0.15) : MockexaTheme.destructive.opacity(0.15)),
                            in: Capsule()
                        )
                        .foregroundStyle(
                            atsScore >= 75 ? MockexaTheme.success :
                            (atsScore >= 50 ? MockexaTheme.warning : MockexaTheme.destructive)
                        )
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Last edited: \(profile.formattedDate)")
                    .font(.caption2)
                    .foregroundStyle(MockexaTheme.textSecondary)
            }

            // Bottom Action Buttons Row: [Edit] [Preview] [Tailor] [ATS Check]
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("Edit")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(MockexaTheme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(MockexaTheme.textPrimary)
                }

                Button(action: onPreview) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                        Text("Preview")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(MockexaTheme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(MockexaTheme.textPrimary)
                }

                Button(action: onTailor) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Tailor JD")
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(MockexaTheme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(MockexaTheme.textPrimary)
                }

                if let onATS = onATSCheck {
                    Button(action: onATS) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("ATS Check")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(MockexaTheme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(MockexaTheme.textPrimary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            isActive ? MockexaTheme.primary.opacity(0.04) : MockexaTheme.surface,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? MockexaTheme.primary : MockexaTheme.border, lineWidth: isActive ? 1.5 : 1)
        )
    }
}

// MARK: - Tailor Resume Wizard Sheet

struct TailorResumeSheet: View {
    let masterProfile: ResumeProfile
    @ObservedObject var vm: ResumeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var jobTitle: String = ""
    @State private var jobDescription: String = ""
    @State private var customProfileName: String = ""
    
    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: TailoringAnalysisResult? = nil
    @State private var acceptedSuggestionIds: Set<String> = []
    
    @State private var tailoredOutcome: (tailoredProfile: ResumeProfile, afterATSScore: Int)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if let outcome = tailoredOutcome {
                    // Success / Comparison Screen
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(MockexaTheme.success)

                        VStack(spacing: 6) {
                            Text("Tailored Resume Created!")
                                .font(.title2.bold())
                                .foregroundStyle(MockexaTheme.textPrimary)
                            Text("Saved as '\(outcome.tailoredProfile.name)' separate from your master resume.")
                                .font(.subheadline)
                                .foregroundStyle(MockexaTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // ATS Score Comparison Box
                        if let analysis = analysisResult {
                            HStack(spacing: 20) {
                                VStack(spacing: 4) {
                                    Text("BEFORE")
                                        .font(.caption2.bold())
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    Text("\(analysis.beforeATSScore)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    Text("ATS Match")
                                        .font(.caption2)
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))

                                Image(systemName: "arrow.right")
                                    .font(.title2.bold())
                                    .foregroundStyle(MockexaTheme.primary)

                                VStack(spacing: 4) {
                                    Text("AFTER")
                                        .font(.caption2.bold())
                                        .foregroundStyle(MockexaTheme.success)
                                    Text("\(outcome.afterATSScore)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(MockexaTheme.success)
                                    Text("ATS Match")
                                        .font(.caption2)
                                        .foregroundStyle(MockexaTheme.success)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(MockexaTheme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(MockexaTheme.success, lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()

                        Button(action: {
                            vm.addTailoredProfile(outcome.tailoredProfile)
                            dismiss()
                        }) {
                            Text("Done & View Profiles")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(MockexaTheme.primary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 40)

                } else if let analysis = analysisResult {
                    // Suggestions Review Screen
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header banner
                            VStack(alignment: .leading, spacing: 6) {
                                Text("JOB MATCH & TAILORING REVIEW")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)

                                Text("Safe Wording Suggestions")
                                    .font(.title3.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)

                                Text("The original master '\(masterProfile.name)' will remain untouched.")
                                    .font(.caption)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))

                            // Matched vs Missing Skills section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SKILLS COMPARISON")
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.textSecondary)

                                if !analysis.matchedExistingSkills.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Existing Relevant Skills:")
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.success)

                                        FlowLayout(spacing: 6) {
                                            ForEach(analysis.matchedExistingSkills, id: \.self) { skill in
                                                HStack(spacing: 4) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.caption2)
                                                    Text(skill)
                                                        .font(.caption2.bold())
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(MockexaTheme.success.opacity(0.12), in: Capsule())
                                                .foregroundStyle(MockexaTheme.success)
                                            }
                                        }
                                    }
                                }

                                if !analysis.missingSkillsFromResume.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Missing from current resume:")
                                                .font(.caption.bold())
                                                .foregroundStyle(MockexaTheme.warning)
                                            Spacer()
                                            Text("(Not added to resume)")
                                                .font(.caption2)
                                                .foregroundStyle(MockexaTheme.textSecondary)
                                        }

                                        FlowLayout(spacing: 6) {
                                            ForEach(analysis.missingSkillsFromResume, id: \.self) { skill in
                                                HStack(spacing: 4) {
                                                    Image(systemName: "circle")
                                                        .font(.caption2)
                                                    Text(skill)
                                                        .font(.caption2)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(MockexaTheme.warning.opacity(0.1), in: Capsule())
                                                .foregroundStyle(MockexaTheme.warning)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))

                            // Action: Accept All Safe Changes
                            HStack {
                                Button("Accept All Safe Changes") {
                                    acceptedSuggestionIds = Set(analysis.suggestions.map { $0.id })
                                    Haptics.selection()
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(MockexaTheme.primary.opacity(0.12), in: Capsule())
                                .foregroundStyle(MockexaTheme.primary)

                                Spacer()

                                Text("\(acceptedSuggestionIds.count) of \(analysis.suggestions.count) selected")
                                    .font(.caption2)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }

                            // Suggestions List
                            if analysis.suggestions.isEmpty {
                                Text("No wording changes necessary. Your master resume already cleanly matches the job description.")
                                    .font(.subheadline)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                    .padding(20)
                                    .frame(maxWidth: .infinity)
                                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                ForEach(analysis.suggestions) { suggestion in
                                    let isAccepted = acceptedSuggestionIds.contains(suggestion.id)
                                    SuggestionCardView(
                                        suggestion: suggestion,
                                        isAccepted: isAccepted,
                                        onToggle: {
                                            if isAccepted {
                                                acceptedSuggestionIds.remove(suggestion.id)
                                            } else {
                                                acceptedSuggestionIds.insert(suggestion.id)
                                            }
                                        }
                                    )
                                }
                            }

                            // Custom Name Field for Tailored Version
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TAILORED PROFILE NAME")
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.textSecondary)

                                TextField("e.g. \(masterProfile.name) — \(jobTitle.isEmpty ? "Google SDE" : jobTitle)", text: $customProfileName)
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(MockexaTheme.textPrimary)
                            }

                            // Create Tailored Profile Button
                            Button(action: {
                                let name = customProfileName.trimmingCharacters(in: .whitespaces).isEmpty ? "\(masterProfile.name) — \(jobTitle.isEmpty ? "Tailored Version" : jobTitle)" : customProfileName
                                let outcome = ResumeService.shared.applyTailoring(
                                    to: masterProfile,
                                    analysis: analysis,
                                    acceptedSuggestionIds: acceptedSuggestionIds,
                                    newProfileName: name
                                )
                                tailoredOutcome = outcome
                            }) {
                                HStack {
                                    Image(systemName: "plus.square.on.square")
                                    Text("Create Tailored Resume Profile")
                                        .font(.headline.bold())
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(MockexaTheme.primary, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(20)
                    }

                } else {
                    // Input Form Screen
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TAILOR RESUME FOR JOB")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.primary)

                                Text("Master: \(masterProfile.name)")
                                    .font(.title3.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)

                                Text("Compare your saved resume with a target job description. We will suggest wording changes based ONLY on facts already in your resume.")
                                    .font(.footnote)
                                    .foregroundStyle(MockexaTheme.textSecondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Target Job Title *")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)

                                TextField("e.g. SDE Internship / Software Engineer", text: $jobTitle)
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                                    .foregroundStyle(MockexaTheme.textPrimary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Job Description (JD) *")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)

                                TextEditor(text: $jobDescription)
                                    .font(.subheadline)
                                    .frame(height: 180)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(MockexaTheme.surface)
                                    .foregroundStyle(MockexaTheme.textPrimary)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(MockexaTheme.border, lineWidth: 1))
                            }

                            if isAnalyzing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Analyzing Job & Generating Safe Suggestions...")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(MockexaTheme.primary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity)
                                .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                Button(action: {
                                    isAnalyzing = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        let result = ResumeService.shared.analyzeJobAndGenerateTailoring(
                                            masterProfile: masterProfile,
                                            jobTitle: jobTitle,
                                            jobDescription: jobDescription
                                        )
                                        self.analysisResult = result
                                        self.acceptedSuggestionIds = Set(result.suggestions.map { $0.id })
                                        self.isAnalyzing = false
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                        Text("Analyze Job & Review Suggestions")
                                            .font(.headline.bold())
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        jobTitle.trimmingCharacters(in: .whitespaces).isEmpty || jobDescription.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? MockexaTheme.textSecondary.opacity(0.3) : MockexaTheme.primary,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                }
                                .disabled(jobTitle.trimmingCharacters(in: .whitespaces).isEmpty || jobDescription.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Tailor Resume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(MockexaTheme.primary)
                }
            }
        }
    }
}

// MARK: - Suggestion Card Subview

struct SuggestionCardView: View {
    let suggestion: TailoringSuggestion
    let isAccepted: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(suggestion.sectionTitle)
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.primary)

                if let item = suggestion.itemTitle {
                    Text("• \(item)")
                        .font(.caption)
                        .foregroundStyle(MockexaTheme.textSecondary)
                }

                Spacer()

                Button(action: onToggle) {
                    Text(isAccepted ? "Accepted" : "Reject")
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isAccepted ? MockexaTheme.success.opacity(0.15) : MockexaTheme.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(isAccepted ? MockexaTheme.success : MockexaTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Current:")
                    .font(.caption2.bold())
                    .foregroundStyle(MockexaTheme.textSecondary)
                Text(suggestion.originalText)
                    .font(.caption)
                    .foregroundStyle(MockexaTheme.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MockexaTheme.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                Text("Suggested (Safe Wording):")
                    .font(.caption2.bold())
                    .foregroundStyle(MockexaTheme.primary)
                Text(suggestion.suggestedText)
                    .font(.caption.bold())
                    .foregroundStyle(MockexaTheme.textPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MockexaTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            Text(suggestion.rationale)
                .font(.caption2)
                .foregroundStyle(MockexaTheme.textSecondary)
        }
        .padding(12)
        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isAccepted ? MockexaTheme.primary.opacity(0.5) : MockexaTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - PDFKit Representable View for Real Vector Document Preview

struct PDFKitRepresentable: UIViewRepresentable {
    let pdfData: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor.systemGroupedBackground
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: pdfData)
    }
}

// MARK: - Resume Practice Round Sheet

struct ResumePracticeRoundSheet: View {
    let profile: ResumeProfile
    @ObservedObject var vm: ResumeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRound: PracticeRoundType = .technical
    @State private var targetRole: String = ""
    @State private var targetJobDescription: String = ""
    @State private var selectedDomain: String = "Data Structures"
    @State private var selectedDifficulty: String = "Medium"
    @State private var hrInterviewStyle: String = "General HR"
    @State private var gdTopic: String = "Impact of Generative AI on Modern Software Engineering"
    @State private var showSavedNotice: Bool = false
    @State private var activeLiveInterview: ActiveInterviewDestination? = nil

    enum PracticeRoundType: String, CaseIterable, Identifiable {
        case technical = "Technical"
        case hr = "HR Behavioral"
        case gd = "Group Discussion"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .technical: return "chevron.left.forwardslash.chevron.right"
            case .hr: return "person.crop.circle.badge.waveform"
            case .gd: return "person.3.sequence.fill"
            }
        }
    }

    struct ActiveInterviewDestination: Identifiable {
        let id = UUID()
        let kind: PracticeKind
        let domain: String
        let difficulty: String
        let resumeContext: String
        let jobDescription: String
    }

    init(profile: ResumeProfile, vm: ResumeViewModel) {
        self.profile = profile
        self.vm = vm
        let defaultRole = profile.targetJobTitle ?? (profile.resumeData.personalInfo.headline.isEmpty ? "Software Engineer" : profile.resumeData.personalInfo.headline)
        _targetRole = State(initialValue: defaultRole)
        _targetJobDescription = State(initialValue: profile.targetJobDescription ?? "")
    }

    private let techDomains = ["Data Structures", "Algorithms", "System Design", "Backend Development", "Mobile / iOS", "Databases"]
    private let difficulties = ["Easy", "Medium", "Hard"]
    private let hrStyles = ["General HR", "Behavioral (STAR)", "Leadership & Ownership", "Culture Fit"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header Resume Grounding Banner
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.title2)
                                    .foregroundStyle(MockexaTheme.primary)
                                Text("Grounded Practice: \(profile.name)")
                                    .font(.headline.bold())
                                    .foregroundStyle(MockexaTheme.textPrimary)
                                Spacer()
                                Text("ACTIVE RESUME")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(MockexaTheme.primary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(MockexaTheme.primary)
                            }
                            Text("The AI interviewer will ask questions tailored directly to your candidate background, skills, and projects from this resume.")
                                .font(.caption)
                                .foregroundStyle(MockexaTheme.textSecondary)
                        }
                        .padding(14)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(MockexaTheme.border, lineWidth: 1))

                        // Target Role & Job Description Customization
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("TARGET ROLE & JOB DESCRIPTION")
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                    .tracking(1)
                                Spacer()
                                Button(action: saveJobDetails) {
                                    HStack(spacing: 3) {
                                        Image(systemName: showSavedNotice ? "checkmark" : "square.and.arrow.down")
                                        Text(showSavedNotice ? "Saved" : "Save to Resume")
                                    }
                                    .font(.caption2.bold())
                                    .foregroundStyle(MockexaTheme.primary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Target Job Title")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                TextField("e.g. Full Stack Developer, Data Engineer", text: $targetRole)
                                    .font(.subheadline)
                                    .padding(10)
                                    .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MockexaTheme.border, lineWidth: 1))
                                    .foregroundStyle(MockexaTheme.textPrimary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Target Job Description (JD)")
                                    .font(.caption.bold())
                                    .foregroundStyle(MockexaTheme.textSecondary)
                                Text("Paste the requirements or JD here. Questions will bridge your resume projects with what the JD asks for.")
                                    .font(.caption2)
                                    .foregroundStyle(MockexaTheme.textSecondary)

                                TextEditor(text: $targetJobDescription)
                                    .frame(minHeight: 90)
                                    .font(.subheadline)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .background(MockexaTheme.surface)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MockexaTheme.border, lineWidth: 1))
                            }
                        }
                        .padding(14)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                        // Round Selector Segmented Control
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CHOOSE INTERVIEW ROUND")
                                .font(.caption2.bold())
                                .foregroundStyle(MockexaTheme.textSecondary)
                                .tracking(1)

                            Picker("Round", selection: $selectedRound) {
                                ForEach(PracticeRoundType.allCases) { r in
                                    Label(r.rawValue, systemImage: r.icon).tag(r)
                                }
                            }
                            .pickerStyle(.segmented)

                            // Round Specific Config
                            switch selectedRound {
                            case .technical:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Technical Focus Domain:")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(techDomains, id: \.self) { d in
                                                Button(action: { selectedDomain = d }) {
                                                    Text(d)
                                                        .font(.caption.bold())
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 6)
                                                        .background(selectedDomain == d ? MockexaTheme.primary : MockexaTheme.surface, in: Capsule())
                                                        .foregroundStyle(selectedDomain == d ? .white : MockexaTheme.textPrimary)
                                                        .overlay(Capsule().stroke(selectedDomain == d ? Color.clear : MockexaTheme.border, lineWidth: 1))
                                                }
                                            }
                                        }
                                    }

                                    HStack {
                                        Text("Difficulty:")
                                            .font(.caption.bold())
                                            .foregroundStyle(MockexaTheme.textSecondary)
                                        Spacer()
                                        Picker("Difficulty", selection: $selectedDifficulty) {
                                            ForEach(difficulties, id: \.self) { diff in
                                                Text(diff).tag(diff)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: 200)
                                    }
                                }
                                .padding(.top, 4)

                            case .hr:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("HR Interview Style:")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(hrStyles, id: \.self) { s in
                                                Button(action: { hrInterviewStyle = s }) {
                                                    Text(s)
                                                        .font(.caption.bold())
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 6)
                                                        .background(hrInterviewStyle == s ? MockexaTheme.primary : MockexaTheme.surface, in: Capsule())
                                                        .foregroundStyle(hrInterviewStyle == s ? .white : MockexaTheme.textPrimary)
                                                        .overlay(Capsule().stroke(hrInterviewStyle == s ? Color.clear : MockexaTheme.border, lineWidth: 1))
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)

                            case .gd:
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Discussion Topic:")
                                        .font(.caption.bold())
                                        .foregroundStyle(MockexaTheme.textSecondary)
                                    TextField("Enter GD Topic", text: $gdTopic)
                                        .font(.subheadline)
                                        .padding(10)
                                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MockexaTheme.border, lineWidth: 1))
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(14)
                        .background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                        // Launch Interview Button
                        Button(action: startPersonalizedRound) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("Start \(selectedRound.rawValue) Round")
                                    .font(.headline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [MockexaTheme.primary, MockexaTheme.primary.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(.white)
                            .shadow(color: MockexaTheme.primary.opacity(0.3), radius: 8, y: 3)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Practice with Resume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(MockexaTheme.primary)
                }
            }
            .fullScreenCover(item: $activeLiveInterview) { dest in
                LiveInterviewView(
                    kind: dest.kind,
                    selectedDomain: dest.domain,
                    difficultyStr: dest.difficulty,
                    resumeContext: dest.resumeContext,
                    jobDescription: dest.jobDescription
                )
            }
        }
    }

    private func saveJobDetails() {
        vm.updateJobDescription(for: profile.id, jd: targetJobDescription, jobTitle: targetRole)
        showSavedNotice = true
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSavedNotice = false
        }
    }

    private func startPersonalizedRound() {
        saveJobDetails()
        vm.selectProfile(id: profile.id)

        let context = ResumeService.shared.buildResumeContext(for: profile)
        let resolvedJD = targetJobDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        switch selectedRound {
        case .technical:
            activeLiveInterview = ActiveInterviewDestination(
                kind: .technical,
                domain: selectedDomain,
                difficulty: selectedDifficulty,
                resumeContext: context,
                jobDescription: resolvedJD
            )
        case .hr:
            activeLiveInterview = ActiveInterviewDestination(
                kind: .hr,
                domain: hrInterviewStyle,
                difficulty: "Medium",
                resumeContext: context,
                jobDescription: resolvedJD
            )
        case .gd:
            activeLiveInterview = ActiveInterviewDestination(
                kind: .gd,
                domain: gdTopic,
                difficulty: "Medium",
                resumeContext: context,
                jobDescription: resolvedJD
            )
        }
    }
}
