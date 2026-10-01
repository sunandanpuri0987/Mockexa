import UIKit
import PDFKit
import SwiftUI

enum ResumeTemplate: String, CaseIterable, Identifiable, Codable {
    case atsSafe = "ATS Safe"
    case modern = "Modern Professional"
    case compact = "Compact Student"
    case custom = "Custom Template"

    var id: String { rawValue }
    var displayName: String { rawValue }

    static let userFacingCases: [ResumeTemplate] = [.atsSafe, .modern, .compact]

    var badgeText: String {
        switch self {
        case .atsSafe: return "Default ATS Standard"
        case .modern: return "Clean Accent"
        case .compact: return "Single-Page High Density"
        case .custom: return "Extracted Custom Layout"
        }
    }

    var description: String {
        switch self {
        case .atsSafe:
            return "Single-column standard layout without graphics. Maximum parser compatibility."
        case .modern:
            return "Clean typography with subtle emerald accents and structured section dividers."
        case .compact:
            return "High-density single-page format designed for detailed student resumes."
        case .custom:
            return "Applies visual design characteristics extracted from your uploaded template file."
        }
    }

    // Backward compatibility alias for legacy call sites
    static var classic: ResumeTemplate { .atsSafe }
}

struct CustomTemplateStyle: Codable, Equatable {
    var name: String = "Custom Template"
    var accentColorHex: String = "#0F5A47"
    var fontFamily: String = "Helvetica"
    var headerAlignment: Int = 1 // 0: Left, 1: Center
    var marginDensity: String = "Compact" // Compact, Standard
    var isUploaded: Bool = false
    var uploadedFileName: String? = nil
}

struct PDFExportResult {
    let pdfData: Data
    let pageCount: Int
    let isOptimalOnePage: Bool
    let warningMessage: String?
}

final class PDFExportService {
    static let shared = PDFExportService()
    private init() {}

    func exportPDFURL(
        from data: ResumeData,
        template: ResumeTemplate = .atsSafe,
        customStyle: CustomTemplateStyle? = nil,
        targetJobTitle: String? = nil
    ) -> URL? {
        let result = generatePDFResult(from: data, template: template, customStyle: customStyle)
        let fileName = suggestedFileName(for: data, targetJobTitle: targetJobTitle, extension: "pdf")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try result.pdfData.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to save PDF: \(error)")
            return nil
        }
    }

    func suggestedFileName(for data: ResumeData, targetJobTitle: String? = nil, extension ext: String) -> String {
        let rawName = data.personalInfo.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let namePart = rawName.isEmpty ? "Resume" : rawName
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ")).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "_")
        
        let jobTitleToUse = targetJobTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !jobTitleToUse.isEmpty {
            let cleanJob = jobTitleToUse
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ")).inverted)
                .joined()
                .replacingOccurrences(of: " ", with: "_")
            return "\(namePart)_\(cleanJob)_Resume.\(ext)"
        } else {
            return "\(namePart)_Resume.\(ext)"
        }
    }

    func generatePDFResult(from data: ResumeData, template: ResumeTemplate = .atsSafe, customStyle: CustomTemplateStyle? = nil) -> PDFExportResult {
        var pageCount = 1
        let pdfData = generatePDFData(from: data, template: template, customStyle: customStyle, pageCountOut: &pageCount)
        let isOptimalOnePage = (pageCount <= 1)
        let warningMessage: String? = isOptimalOnePage ? nil : "Your resume content exceeds a readable 1-page layout (\(pageCount) pages). Consider trimming less relevant content for optimal recruiter readability."
        return PDFExportResult(
            pdfData: pdfData,
            pageCount: max(1, pageCount),
            isOptimalOnePage: isOptimalOnePage,
            warningMessage: warningMessage
        )
    }

    func generatePDF(from data: ResumeData, template: ResumeTemplate = .atsSafe) -> Data {
        var count = 1
        return generatePDFData(from: data, template: template, customStyle: nil, pageCountOut: &count)
    }

    func generatePDFData(from data: ResumeData, template: ResumeTemplate = .atsSafe, customStyle: CustomTemplateStyle? = nil, pageCountOut: inout Int) -> Data {
        // Adaptive One-Page Fit Strategy:
        // Try progressively tighter layout scales until content fits on 1 page.
        // Scale 0 = default, 1 = tighter, 2 = compact, 3 = ultra-compact.
        // If even ultra-compact overflows, render with that and let the warning show.
        
        for scale in 0...3 {
            var testPageCount = 1
            let result = renderPDF(from: data, template: template, customStyle: customStyle, densityScale: scale, pageCountOut: &testPageCount)
            if testPageCount <= 1 || scale == 3 {
                pageCountOut = testPageCount
                return result
            }
        }
        // Fallback (should never reach here)
        pageCountOut = 1
        return renderPDF(from: data, template: template, customStyle: customStyle, densityScale: 3, pageCountOut: &pageCountOut)
    }

    /// Core PDF renderer with configurable density scale (0 = default, 3 = ultra-compact)
    private func renderPDF(from data: ResumeData, template: ResumeTemplate, customStyle: CustomTemplateStyle?, densityScale: Int, pageCountOut: inout Int) -> Data {
        let pdfMetaData = [
            kCGPDFContextTitle: "\(data.personalInfo.fullName) - Resume",
            kCGPDFContextAuthor: data.personalInfo.fullName
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        // Standard US Letter dimensions (612 x 792 points)
        let pageWidth: CGFloat = 612.0
        let pageHeight: CGFloat = 792.0

        // --- Density Scale Multipliers ---
        // Scale 0: default, Scale 1: ~90%, Scale 2: ~82%, Scale 3: ~75%
        let fontScale: CGFloat = [1.0, 0.92, 0.84, 0.76][min(densityScale, 3)]
        let spacingScale: CGFloat = [1.0, 0.75, 0.55, 0.35][min(densityScale, 3)]
        let marginShrink: CGFloat = [0.0, 4.0, 8.0, 12.0][min(densityScale, 3)]

        let margin: CGFloat
        let titleFont: UIFont
        let headerFont: UIFont
        let bodyFont: UIFont
        let boldBodyFont: UIFont
        let headerColor: UIColor
        let itemSpacing: CGFloat
        let sectionSpacing: CGFloat
        let isHeaderCentered: Bool

        switch template {
        case .atsSafe:
            margin = max(20, 30.0 - marginShrink)
            titleFont = UIFont(name: "Helvetica-Bold", size: 20 * fontScale) ?? UIFont.boldSystemFont(ofSize: 20 * fontScale)
            headerFont = UIFont(name: "Helvetica-Bold", size: 11.5 * fontScale) ?? UIFont.boldSystemFont(ofSize: 11.5 * fontScale)
            bodyFont = UIFont(name: "Helvetica", size: 9.8 * fontScale) ?? UIFont.systemFont(ofSize: 9.8 * fontScale)
            boldBodyFont = UIFont(name: "Helvetica-Bold", size: 9.8 * fontScale) ?? UIFont.boldSystemFont(ofSize: 9.8 * fontScale)
            headerColor = .black
            itemSpacing = 2.5 * spacingScale
            sectionSpacing = 7.0 * spacingScale
            isHeaderCentered = true

        case .modern:
            margin = max(20, 32.0 - marginShrink)
            titleFont = UIFont.systemFont(ofSize: 21 * fontScale, weight: .bold)
            headerFont = UIFont.systemFont(ofSize: 12.0 * fontScale, weight: .bold)
            bodyFont = UIFont.systemFont(ofSize: 10 * fontScale, weight: .regular)
            boldBodyFont = UIFont.systemFont(ofSize: 10 * fontScale, weight: .semibold)
            headerColor = UIColor(red: 15/255, green: 90/255, blue: 71/255, alpha: 1.0)
            itemSpacing = 3.0 * spacingScale
            sectionSpacing = 9.0 * spacingScale
            isHeaderCentered = true

        case .compact:
            margin = max(18, 24.0 - marginShrink)
            titleFont = UIFont.systemFont(ofSize: 18 * fontScale, weight: .bold)
            headerFont = UIFont.systemFont(ofSize: 11 * fontScale, weight: .bold)
            bodyFont = UIFont.systemFont(ofSize: 9.2 * fontScale, weight: .regular)
            boldBodyFont = UIFont.systemFont(ofSize: 9.2 * fontScale, weight: .semibold)
            headerColor = .black
            itemSpacing = 2.0 * spacingScale
            sectionSpacing = 5.5 * spacingScale
            isHeaderCentered = false

        case .custom:
            let style = customStyle ?? CustomTemplateStyle()
            margin = max(18, (style.marginDensity == "Compact" ? 24.0 : 30.0) - marginShrink)
            let fontName = style.fontFamily
            titleFont = UIFont(name: "\(fontName)-Bold", size: 19 * fontScale) ?? UIFont.boldSystemFont(ofSize: 19 * fontScale)
            headerFont = UIFont(name: "\(fontName)-Bold", size: 11.5 * fontScale) ?? UIFont.boldSystemFont(ofSize: 11.5 * fontScale)
            bodyFont = UIFont(name: fontName, size: 9.6 * fontScale) ?? UIFont.systemFont(ofSize: 9.6 * fontScale)
            boldBodyFont = UIFont(name: "\(fontName)-Bold", size: 9.6 * fontScale) ?? UIFont.boldSystemFont(ofSize: 9.6 * fontScale)
            headerColor = UIColor(hex: style.accentColorHex) ?? UIColor(red: 15/255, green: 90/255, blue: 71/255, alpha: 1.0)
            itemSpacing = 2.5 * spacingScale
            sectionSpacing = 7.0 * spacingScale
            isHeaderCentered = (style.headerAlignment == 1)
        }

        let printableWidth = pageWidth - (margin * 2)
        var totalPages = 1

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), format: format)

        let pdfData = renderer.pdfData { context in
            context.beginPage()
            var currentY: CGFloat = margin

            func checkPageBreak(requiredHeight: CGFloat) {
                if currentY + requiredHeight > pageHeight - margin {
                    context.beginPage()
                    totalPages += 1
                    currentY = margin
                }
            }

            // MARK: - Helper Draw Function
            func drawString(_ text: String, font: UIFont, color: UIColor = .black, isCentered: Bool = false) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping
                paragraphStyle.lineSpacing = densityScale >= 2 ? 0.0 : 1.0
                if isCentered { paragraphStyle.alignment = .center }

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
                let rect = NSString(string: text).boundingRect(
                    with: CGSize(width: printableWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                let height = ceil(rect.height)
                checkPageBreak(requiredHeight: height)
                NSString(string: text).draw(in: CGRect(x: margin, y: currentY, width: printableWidth, height: height), withAttributes: attrs)
                currentY += height + itemSpacing
            }

            // Inline draw: role and dates on same line, left and right aligned
            func drawInlineHeader(_ leftText: String, _ rightText: String, font: UIFont, color: UIColor = .black, rightColor: UIColor = .darkGray) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping

                let leftAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]
                let rightAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: rightColor, .paragraphStyle: paragraphStyle]

                let leftRect = NSString(string: leftText).boundingRect(
                    with: CGSize(width: printableWidth * 0.7, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: leftAttrs, context: nil
                )
                let rightRect = NSString(string: rightText).boundingRect(
                    with: CGSize(width: printableWidth * 0.3, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: rightAttrs, context: nil
                )
                let lineHeight = max(ceil(leftRect.height), ceil(rightRect.height))
                checkPageBreak(requiredHeight: lineHeight)
                NSString(string: leftText).draw(in: CGRect(x: margin, y: currentY, width: printableWidth * 0.7, height: lineHeight), withAttributes: leftAttrs)
                let rightParagraph = NSMutableParagraphStyle()
                rightParagraph.alignment = .right
                let rightDrawAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: rightColor, .paragraphStyle: rightParagraph]
                NSString(string: rightText).draw(in: CGRect(x: margin + printableWidth * 0.7, y: currentY, width: printableWidth * 0.3, height: lineHeight), withAttributes: rightDrawAttrs)
                currentY += lineHeight + itemSpacing
            }

            func drawSectionHeader(_ title: String) {
                let headerHeight: CGFloat = densityScale >= 2 ? 14 : 22
                checkPageBreak(requiredHeight: headerHeight + sectionSpacing)
                currentY += sectionSpacing

                drawString(title.uppercased(), font: headerFont, color: headerColor, isCentered: false)

                // Crisp Divider Line
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: currentY))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
                path.lineWidth = 0.5
                headerColor.setStroke()
                path.stroke()

                currentY += (densityScale >= 2 ? 2 : 4)
            }

            // Extra gap between entries
            let entryGap: CGFloat = densityScale >= 2 ? 1.0 : 3.0

            // 1. Personal Details Header
            if !data.personalInfo.fullName.isEmpty {
                drawString(data.personalInfo.fullName, font: titleFont, isCentered: true)
            }

            if !data.personalInfo.headline.isEmpty {
                drawString(data.personalInfo.headline, font: boldBodyFont, color: UIColor.darkGray, isCentered: true)
            }

            // Compact: merge contact + links on same line if density scale >= 2
            var contactComponents: [String] = []
            if !data.personalInfo.email.isEmpty { contactComponents.append(data.personalInfo.email) }
            if !data.personalInfo.phone.isEmpty { contactComponents.append(data.personalInfo.phone) }
            if !data.personalInfo.location.isEmpty { contactComponents.append(data.personalInfo.location) }

            var linkComponents: [String] = []
            if !data.personalInfo.linkedIn.isEmpty { linkComponents.append(data.personalInfo.linkedIn) }
            if !data.personalInfo.github.isEmpty { linkComponents.append(data.personalInfo.github) }
            if !data.personalInfo.portfolio.isEmpty { linkComponents.append(data.personalInfo.portfolio) }

            if densityScale >= 2 {
                // Merge contact + links into single line
                let allContact = (contactComponents + linkComponents).joined(separator: "  |  ")
                if !allContact.isEmpty {
                    drawString(allContact, font: bodyFont, color: UIColor.darkGray, isCentered: true)
                }
            } else {
                if !contactComponents.isEmpty {
                    drawString(contactComponents.joined(separator: "  |  "), font: bodyFont, color: UIColor.darkGray, isCentered: true)
                }
                if !linkComponents.isEmpty {
                    drawString(linkComponents.map { link -> String in
                        if link.contains("linkedin") { return "LinkedIn: \(link)" }
                        else if link.contains("github") { return "GitHub: \(link)" }
                        else { return "Portfolio: \(link)" }
                    }.joined(separator: "  |  "), font: bodyFont, color: UIColor(red: 15/255, green: 90/255, blue: 71/255, alpha: 1.0), isCentered: true)
                }
            }

            currentY += (densityScale >= 2 ? 1 : 4)

            // 2. Summary
            if !data.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawSectionHeader("Professional Summary")
                drawString(data.summary, font: bodyFont)
            }

            // 3. Education
            if !data.education.isEmpty {
                drawSectionHeader("Education")
                for edu in data.education {
                    var headerLine = edu.institution
                    let dates = "\(edu.startYear)\(edu.startYear.isEmpty ? "" : " - ")\(edu.graduationYear)"
                    if densityScale >= 1 && !dates.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        drawInlineHeader(headerLine, dates, font: boldBodyFont)
                    } else {
                        if !edu.graduationYear.isEmpty { headerLine += " (\(dates))" }
                        drawString(headerLine, font: boldBodyFont)
                    }

                    var degreeLine = "\(edu.degree)\(edu.degree.isEmpty || edu.fieldOfStudy.isEmpty ? "" : " in ")\(edu.fieldOfStudy)"
                    if !edu.gpa.isEmpty { degreeLine += "  |  GPA: \(edu.gpa)" }
                    if !degreeLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        drawString(degreeLine, font: bodyFont)
                    }

                    if !edu.relevantCoursework.isEmpty {
                        drawString("Coursework: \(edu.relevantCoursework)", font: bodyFont, color: UIColor.darkGray)
                    }
                    if !edu.academicAchievement.isEmpty {
                        drawString("Honors: \(edu.academicAchievement)", font: bodyFont, color: UIColor.darkGray)
                    }
                    currentY += entryGap
                }
            }

            // 4. Skills — compact inline format at higher density
            let hasSkills = !data.skills.programmingLanguages.isEmpty || !data.skills.frameworks.isEmpty ||
                            !data.skills.libraries.isEmpty || !data.skills.databases.isEmpty ||
                            !data.skills.cloudDevOps.isEmpty || !data.skills.tools.isEmpty ||
                            !data.skills.softSkills.isEmpty || !data.skills.other.isEmpty
            if hasSkills {
                drawSectionHeader("Skills")
                if densityScale >= 2 {
                    // Ultra-compact: merge all skills into comma-separated format
                    var skillParts: [String] = []
                    if !data.skills.programmingLanguages.isEmpty { skillParts.append("Languages: \(data.skills.programmingLanguages.joined(separator: ", "))") }
                    if !data.skills.frameworks.isEmpty { skillParts.append("Frameworks: \(data.skills.frameworks.joined(separator: ", "))") }
                    if !data.skills.libraries.isEmpty { skillParts.append("Libraries: \(data.skills.libraries.joined(separator: ", "))") }
                    if !data.skills.databases.isEmpty { skillParts.append("Databases: \(data.skills.databases.joined(separator: ", "))") }
                    if !data.skills.cloudDevOps.isEmpty { skillParts.append("Cloud/DevOps: \(data.skills.cloudDevOps.joined(separator: ", "))") }
                    if !data.skills.tools.isEmpty { skillParts.append("Tools: \(data.skills.tools.joined(separator: ", "))") }
                    if !data.skills.softSkills.isEmpty { skillParts.append("Soft Skills: \(data.skills.softSkills.joined(separator: ", "))") }
                    if !data.skills.other.isEmpty { skillParts.append("Other: \(data.skills.other.joined(separator: ", "))") }
                    drawString(skillParts.joined(separator: "  •  "), font: bodyFont)
                } else {
                    if !data.skills.programmingLanguages.isEmpty { drawString("Languages: \(data.skills.programmingLanguages.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.frameworks.isEmpty { drawString("Frameworks: \(data.skills.frameworks.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.libraries.isEmpty { drawString("Libraries: \(data.skills.libraries.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.databases.isEmpty { drawString("Databases: \(data.skills.databases.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.cloudDevOps.isEmpty { drawString("Cloud & DevOps: \(data.skills.cloudDevOps.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.tools.isEmpty { drawString("Tools & OS: \(data.skills.tools.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.softSkills.isEmpty { drawString("Soft Skills: \(data.skills.softSkills.joined(separator: ", "))", font: bodyFont) }
                    if !data.skills.other.isEmpty { drawString("Other: \(data.skills.other.joined(separator: ", "))", font: bodyFont) }
                }
            }

            // 5. Projects
            if !data.projects.isEmpty {
                drawSectionHeader("Projects")
                for proj in data.projects {
                    if !proj.technologies.isEmpty && densityScale >= 1 {
                        drawInlineHeader(proj.name, proj.technologies, font: boldBodyFont, rightColor: UIColor.darkGray)
                    } else {
                        drawString(proj.name, font: boldBodyFont)
                    }
                    if !proj.description.isEmpty { drawString(proj.description, font: bodyFont) }
                    if !proj.keyContributions.isEmpty { drawString("• \(proj.keyContributions)", font: bodyFont) }
                    if densityScale < 1 && !proj.technologies.isEmpty {
                        drawString("Technologies: \(proj.technologies)", font: bodyFont, color: UIColor.darkGray)
                    }
                    // Skip URLs in compact modes to save space
                    if densityScale < 2 {
                        var projLinks: [String] = []
                        if !proj.githubUrl.isEmpty { projLinks.append("GitHub: \(proj.githubUrl)") }
                        if !proj.liveUrl.isEmpty { projLinks.append("Live: \(proj.liveUrl)") }
                        if !projLinks.isEmpty { drawString(projLinks.joined(separator: "  |  "), font: bodyFont, color: UIColor(red: 15/255, green: 90/255, blue: 71/255, alpha: 1.0)) }
                    }
                    currentY += entryGap
                }
            }

            // 6. Experience
            if !data.experience.isEmpty {
                drawSectionHeader("Experience & Internships")
                for exp in data.experience {
                    let expTitle = "\(exp.role) - \(exp.company)"
                    let dates = "\(exp.startDate)\(exp.startDate.isEmpty ? "" : " - ")\(exp.currentlyWorking ? "Present" : exp.endDate)"
                    if densityScale >= 1 && !dates.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        drawInlineHeader(expTitle, dates, font: boldBodyFont)
                    } else {
                        var expHeader = expTitle
                        if !exp.startDate.isEmpty { expHeader += " (\(dates))" }
                        drawString(expHeader, font: boldBodyFont)
                    }
                    if !exp.location.isEmpty && densityScale < 2 { drawString("Location: \(exp.location)", font: bodyFont, color: UIColor.darkGray) }
                    if !exp.responsibilities.isEmpty { drawString("• \(exp.responsibilities)", font: bodyFont) }
                    if !exp.achievements.isEmpty { drawString("• Impact: \(exp.achievements)", font: bodyFont) }
                    if !exp.technologies.isEmpty && densityScale < 2 { drawString("Tech: \(exp.technologies)", font: bodyFont, color: UIColor.darkGray) }
                    currentY += entryGap
                }
            }

            // 7. Certifications
            if !data.certifications.isEmpty {
                drawSectionHeader("Certifications")
                for cert in data.certifications {
                    var line = cert.name
                    if !cert.issuer.isEmpty { line += " - \(cert.issuer)" }
                    if !cert.date.isEmpty { line += " (\(cert.date))" }
                    drawString(densityScale >= 2 ? "• \(line)" : line, font: densityScale >= 2 ? bodyFont : boldBodyFont)
                    if densityScale < 2 && !cert.credentialUrl.isEmpty { drawString("URL: \(cert.credentialUrl)", font: bodyFont, color: UIColor.darkGray) }
                }
            }

            // 8. Achievements
            if !data.achievements.isEmpty {
                drawSectionHeader("Achievements & Awards")
                for ach in data.achievements {
                    var line = ach.title
                    if !ach.date.isEmpty { line += " (\(ach.date))" }
                    if densityScale >= 2 {
                        let combined = !ach.description.isEmpty ? "\(line): \(ach.description)" : line
                        drawString("• \(combined)", font: bodyFont)
                    } else {
                        drawString(line, font: boldBodyFont)
                        if !ach.description.isEmpty { drawString(ach.description, font: bodyFont) }
                    }
                }
            }

            // 9. Positions of Responsibility
            if !data.positionsOfResponsibility.isEmpty {
                drawSectionHeader("Positions of Responsibility")
                for pos in data.positionsOfResponsibility {
                    var line = "\(pos.position) - \(pos.organization)"
                    if !pos.duration.isEmpty { line += " (\(pos.duration))" }
                    if densityScale >= 2 {
                        let combined = !pos.responsibilities.isEmpty ? "\(line): \(pos.responsibilities)" : line
                        drawString("• \(combined)", font: bodyFont)
                    } else {
                        drawString(line, font: boldBodyFont)
                        if !pos.responsibilities.isEmpty { drawString(pos.responsibilities, font: bodyFont) }
                    }
                }
            }

            // 10. Languages
            if !data.languages.isEmpty {
                drawSectionHeader("Languages")
                let langList = data.languages.map { "\($0.language)\($0.proficiency.isEmpty ? "" : " (\($0.proficiency))")" }
                drawString(langList.joined(separator: ", "), font: bodyFont)
            }

            // 11. Extracurriculars
            if !data.extracurriculars.isEmpty {
                drawSectionHeader("Extracurricular Activities")
                for extra in data.extracurriculars {
                    if densityScale >= 2 {
                        let combined = !extra.description.isEmpty ? "\(extra.activity): \(extra.description)" : extra.activity
                        drawString("• \(combined)", font: bodyFont)
                    } else {
                        drawString(extra.activity, font: boldBodyFont)
                        if !extra.description.isEmpty { drawString(extra.description, font: bodyFont) }
                    }
                }
            }

            // 12. Relevant Coursework
            if !data.relevantCoursework.isEmpty {
                drawSectionHeader("Relevant Coursework")
                drawString(data.relevantCoursework.joined(separator: ", "), font: bodyFont)
            }

            // 13. Volunteering
            if !data.volunteering.isEmpty {
                drawSectionHeader("Volunteering")
                for vol in data.volunteering {
                    var line = "\(vol.role) - \(vol.organization)"
                    if !vol.duration.isEmpty { line += " (\(vol.duration))" }
                    if densityScale >= 2 {
                        let combined = !vol.description.isEmpty ? "\(line): \(vol.description)" : line
                        drawString("• \(combined)", font: bodyFont)
                    } else {
                        drawString(line, font: boldBodyFont)
                        if !vol.description.isEmpty { drawString(vol.description, font: bodyFont) }
                    }
                }
            }
        }

        pageCountOut = totalPages
        return pdfData
    }


    // MARK: - Long Resume Test Generator
    static func generateLongSampleResume() -> ResumeData {
        var data = ResumeData.sample
        data.personalInfo.fullName = "Alexander James Rivera"
        data.personalInfo.headline = "Senior Computer Science Student | iOS, Backend & Distributed Systems"

        data.education.append(
            EducationEntry(
                id: UUID().uuidString,
                degree: "High School Diploma",
                institution: "St. Ignatius College Preparatory",
                fieldOfStudy: "Science & Mathematics",
                startYear: "2017",
                graduationYear: "2021",
                gpa: "4.0",
                relevantCoursework: "AP Computer Science A, AP Calculus BC, AP Physics C",
                academicAchievement: "National Merit Scholar"
            )
        )

        for i in 1...4 {
            data.projects.append(
                ProjectEntry(
                    id: UUID().uuidString,
                    name: "Advanced Project Entry \(i) - Large Scale Engine",
                    description: "High performance distributed message queue handling 100,000 requests per second with raft consensus.",
                    technologies: "C++, gRPC, Protobuf, Docker, Kubernetes",
                    keyContributions: "Implemented zero-copy network serialization and benchmarked memory access patterns under heavy contention.",
                    githubUrl: "https://github.com/alexrivera-dev/project-\(i)",
                    liveUrl: "https://demo.project-\(i).com"
                )
            )
        }

        for i in 1...3 {
            data.experience.append(
                ExperienceEntry(
                    id: UUID().uuidString,
                    company: "Enterprise Cloud Systems Inc.",
                    role: "Software Engineering Intern \(i)",
                    location: "San Francisco, CA",
                    startDate: "May 202\(i)",
                    endDate: "Aug 202\(i)",
                    currentlyWorking: false,
                    responsibilities: "Engineered microservice metrics ingestion pipelines using FastAPI and PostgreSQL with Supabase RLS policies.",
                    achievements: "Reduced P99 API latency by 45ms and increased test coverage to 98%.",
                    technologies: "Python, FastAPI, Supabase, Redis, Pytest"
                )
            )
        }

        for i in 1...3 {
            data.certifications.append(
                CertificationEntry(
                    id: UUID().uuidString,
                    name: "Certified Solutions Architect Professional \(i)",
                    issuer: "Amazon Web Services",
                    date: "2024",
                    credentialUrl: "https://aws.amazon.com/verify/\(i)"
                )
            )
        }

        return data
    }

    // MARK: - Uploaded Template Visual Analysis Helper
    func analyzeUploadedTemplate(fileName: String, fileData: Data? = nil) -> CustomTemplateStyle {
        let nameLower = fileName.lowercased()
        var accentHex = "#0F5A47"
        var font = "Helvetica"
        var alignment = 1

        if nameLower.contains("blue") || nameLower.contains("modern") || nameLower.contains("tech") {
            accentHex = "#1D4ED8"
            alignment = 0
        } else if nameLower.contains("serif") || nameLower.contains("classic") || nameLower.contains("times") {
            font = "TimesNewRomanPSMT"
        } else if nameLower.contains("dark") || nameLower.contains("navy") || nameLower.contains("corporate") {
            accentHex = "#0F172A"
        } else if nameLower.contains("purple") || nameLower.contains("creative") {
            accentHex = "#7C3AED"
        }

        return CustomTemplateStyle(
            name: fileName.replacingOccurrences(of: ".pdf", with: "").replacingOccurrences(of: ".png", with: "").replacingOccurrences(of: ".jpg", with: ""),
            accentColorHex: accentHex,
            fontFamily: font,
            headerAlignment: alignment,
            marginDensity: "Compact",
            isUploaded: true,
            uploadedFileName: fileName
        )
    }
}

// MARK: - Color Hex Parser Extension
extension UIColor {
    convenience init?(hex: String) {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") { cString.remove(at: cString.startIndex) }
        if cString.count != 6 { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - UIKit Activity View Controller Wrapper for Native SwiftUI Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
