import Foundation
import UIKit

// MARK: - Pure Swift ZIP Writer for DOCX Generation

struct DocxZipEntry {
    let name: String
    let data: Data
}

final class DocxZipWriter {
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    static func createZip(entries: [DocxZipEntry]) -> Data {
        var zipData = Data()
        var centralDirectory = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            let offset = UInt32(zipData.count)
            offsets.append(offset)
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            // Local File Header
            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // Signature
            localHeader.append(contentsOf: [0x14, 0x00]) // Version needed (2.0)
            localHeader.append(contentsOf: [0x00, 0x00]) // General purpose flag
            localHeader.append(contentsOf: [0x00, 0x00]) // Compression (0 = Store)
            localHeader.append(contentsOf: [0x00, 0x00]) // Mod time
            localHeader.append(contentsOf: [0x00, 0x00]) // Mod date
            localHeader.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            localHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            let nameLen = UInt16(nameData.count)
            localHeader.append(contentsOf: withUnsafeBytes(of: nameLen.littleEndian) { Array($0) })
            localHeader.append(contentsOf: [0x00, 0x00]) // Extra field len
            localHeader.append(nameData)
            localHeader.append(entry.data)

            zipData.append(localHeader)

            // Central Directory Header
            var cdHeader = Data()
            cdHeader.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // Signature
            cdHeader.append(contentsOf: [0x14, 0x00]) // Version made by
            cdHeader.append(contentsOf: [0x14, 0x00]) // Version needed
            cdHeader.append(contentsOf: [0x00, 0x00]) // Flags
            cdHeader.append(contentsOf: [0x00, 0x00]) // Compression
            cdHeader.append(contentsOf: [0x00, 0x00]) // Mod time
            cdHeader.append(contentsOf: [0x00, 0x00]) // Mod date
            cdHeader.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            cdHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            cdHeader.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
            cdHeader.append(contentsOf: withUnsafeBytes(of: nameLen.littleEndian) { Array($0) })
            cdHeader.append(contentsOf: [0x00, 0x00]) // Extra field len
            cdHeader.append(contentsOf: [0x00, 0x00]) // Comment len
            cdHeader.append(contentsOf: [0x00, 0x00]) // Disk num start
            cdHeader.append(contentsOf: [0x00, 0x00]) // Internal attrs
            cdHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // External attrs
            cdHeader.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
            cdHeader.append(nameData)

            centralDirectory.append(cdHeader)
        }

        let centralDirOffset = UInt32(zipData.count)
        let centralDirSize = UInt32(centralDirectory.count)
        let entryCount = UInt16(entries.count)

        zipData.append(centralDirectory)

        // End of Central Directory Record
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // Signature
        eocd.append(contentsOf: [0x00, 0x00]) // Disk num
        eocd.append(contentsOf: [0x00, 0x00]) // Start disk
        eocd.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: centralDirSize.littleEndian) { Array($0) })
        eocd.append(contentsOf: withUnsafeBytes(of: centralDirOffset.littleEndian) { Array($0) })
        eocd.append(contentsOf: [0x00, 0x00]) // Comment len

        zipData.append(eocd)
        return zipData
    }
}

// MARK: - DOCX Export Service

final class DOCXExportService {
    static let shared = DOCXExportService()
    private init() {}

    /// Exports a .docx file and returns its temporary URL
    func exportDOCXURL(
        from data: ResumeData,
        template: ResumeTemplate = .atsSafe,
        customStyle: CustomTemplateStyle? = nil,
        targetJobTitle: String? = nil
    ) -> URL? {
        let docxData = generateDOCXData(from: data, template: template, customStyle: customStyle)
        let fileName = suggestedFileName(for: data, targetJobTitle: targetJobTitle, extension: "docx")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try docxData.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to write DOCX file: \(error)")
            return nil
        }
    }

    /// Computes filename e.g.:
    /// Standard: Alex_Resume.docx
    /// Tailored: Alex_SDE_Internship_Resume.docx
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

    /// Generates raw DOCX package binary data
    func generateDOCXData(
        from data: ResumeData,
        template: ResumeTemplate = .atsSafe,
        customStyle: CustomTemplateStyle? = nil
    ) -> Data {
        let docXML = buildDocumentXML(from: data, template: template, customStyle: customStyle)
        let stylesXML = buildStylesXML(template: template, customStyle: customStyle)
        
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        </Types>
        """

        let mainRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let docRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

        let entries = [
            DocxZipEntry(name: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            DocxZipEntry(name: "_rels/.rels", data: Data(mainRelsXML.utf8)),
            DocxZipEntry(name: "word/_rels/document.xml.rels", data: Data(docRelsXML.utf8)),
            DocxZipEntry(name: "word/styles.xml", data: Data(stylesXML.utf8)),
            DocxZipEntry(name: "word/document.xml", data: Data(docXML.utf8))
        ]

        return DocxZipWriter.createZip(entries: entries)
    }

    private func xmlEscape(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func primaryColorHex(template: ResumeTemplate, customStyle: CustomTemplateStyle?) -> String {
        switch template {
        case .atsSafe:
            return "111827" // Slate dark
        case .modern:
            return "0F5A47" // Emerald green accent
        case .compact:
            return "1E3A8A" // Deep navy accent
        case .custom:
            let hex = customStyle?.accentColorHex.replacingOccurrences(of: "#", with: "") ?? "0F5A47"
            return hex.isEmpty ? "0F5A47" : hex
        }
    }

    private func buildStylesXML(template: ResumeTemplate, customStyle: CustomTemplateStyle?) -> String {
        let color = primaryColorHex(template: template, customStyle: customStyle)
        let fontName = (template == .custom ? customStyle?.fontFamily : nil) ?? "Calibri"

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="\(fontName)" w:hAnsi="\(fontName)" w:cs="\(fontName)"/>
                <w:sz w:val="20"/>
                <w:color w:val="111827"/>
              </w:rPr>
            </w:rPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/>
            <w:rPr>
              <w:rFonts w:ascii="\(fontName)" w:hAnsi="\(fontName)"/>
              <w:b/>
              <w:sz w:val="36"/>
              <w:color w:val="\(color)"/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="heading 2"/>
            <w:pPr>
              <w:spacing w:before="160" w:after="60"/>
            </w:pPr>
            <w:rPr>
              <w:rFonts w:ascii="\(fontName)" w:hAnsi="\(fontName)"/>
              <w:b/>
              <w:sz w:val="24"/>
              <w:color w:val="\(color)"/>
            </w:rPr>
          </w:style>
        </w:styles>
        """
    }

    private func buildDocumentXML(
        from data: ResumeData,
        template: ResumeTemplate,
        customStyle: CustomTemplateStyle?
    ) -> String {
        var bodyXML = ""
        let color = primaryColorHex(template: template, customStyle: customStyle)

        // 1. Header Section
        let name = xmlEscape(data.personalInfo.fullName.isEmpty ? "Your Name" : data.personalInfo.fullName)
        bodyXML += """
        <w:p>
          <w:pPr>
            <w:jc w:val="center"/>
            <w:spacing w:before="0" w:after="40"/>
          </w:pPr>
          <w:r>
            <w:rPr>
              <w:b/>
              <w:sz w:val="38"/>
              <w:color w:val="\(color)"/>
            </w:rPr>
            <w:t>\(name)</w:t>
          </w:r>
        </w:p>
        """

        if !data.personalInfo.headline.isEmpty {
            let headline = xmlEscape(data.personalInfo.headline)
            bodyXML += """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:after="60"/>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:i/>
                  <w:sz w:val="22"/>
                  <w:color w:val="4B5563"/>
                </w:rPr>
                <w:t>\(headline)</w:t>
              </w:r>
            </w:p>
            """
        }

        // Contact info bar
        var contactItems: [String] = []
        if !data.personalInfo.email.isEmpty { contactItems.append(data.personalInfo.email) }
        if !data.personalInfo.phone.isEmpty { contactItems.append(data.personalInfo.phone) }
        if !data.personalInfo.location.isEmpty { contactItems.append(data.personalInfo.location) }
        if !data.personalInfo.linkedIn.isEmpty { contactItems.append(data.personalInfo.linkedIn) }
        if !data.personalInfo.github.isEmpty { contactItems.append(data.personalInfo.github) }
        if !data.personalInfo.portfolio.isEmpty { contactItems.append(data.personalInfo.portfolio) }

        if !contactItems.isEmpty {
            let contactString = xmlEscape(contactItems.joined(separator: "  |  "))
            bodyXML += """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:after="160"/>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:sz w:val="18"/>
                  <w:color w:val="4B5563"/>
                </w:rPr>
                <w:t>\(contactString)</w:t>
              </w:r>
            </w:p>
            """
        }

        // Section Divider Helper
        func addSectionHeader(_ title: String) -> String {
            return """
            <w:p>
              <w:pPr>
                <w:pStyle w:val="Heading2"/>
                <w:spacing w:before="180" w:after="60"/>
                <w:pBdr>
                  <w:bottom w:val="single" w:sz="6" w:space="2" w:color="\(color)"/>
                </w:pBdr>
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:b/>
                  <w:sz w:val="22"/>
                  <w:color w:val="\(color)"/>
                </w:rPr>
                <w:t>\(title)</w:t>
              </w:r>
            </w:p>
            """
        }

        // 2. Summary
        if !data.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyXML += addSectionHeader("PROFESSIONAL SUMMARY")
            bodyXML += """
            <w:p>
              <w:pPr><w:spacing w:after="100"/></w:pPr>
              <w:r><w:t>\(xmlEscape(data.summary))</w:t></w:r>
            </w:p>
            """
        }

        // 3. Education
        if !data.education.isEmpty {
            bodyXML += addSectionHeader("EDUCATION")
            for edu in data.education {
                let inst = xmlEscape(edu.institution)
                let degree = xmlEscape(edu.degree)
                let field = xmlEscape(edu.fieldOfStudy)
                let dates = xmlEscape("\(edu.startYear)\(edu.startYear.isEmpty ? "" : " - ")\(edu.graduationYear)")
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:before="40" w:after="20"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>\(inst)</w:t></w:r>
                  <w:r><w:t>  —  \(degree)\(field.isEmpty ? "" : " in \(field)")</w:t></w:r>
                  <w:r><w:rPr><w:color w:val="6B7280"/></w:rPr><w:t> (\(dates))</w:t></w:r>
                </w:p>
                """
                if !edu.gpa.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="20"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:rPr><w:i/></w:rPr><w:t>GPA / Score: \(xmlEscape(edu.gpa))</w:t></w:r>
                    </w:p>
                    """
                }
                if !edu.relevantCoursework.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="20"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:t>Relevant Coursework: \(xmlEscape(edu.relevantCoursework))</w:t></w:r>
                    </w:p>
                    """
                }
                if !edu.academicAchievement.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="60"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:t>Academic Honors: \(xmlEscape(edu.academicAchievement))</w:t></w:r>
                    </w:p>
                    """
                }
            }
        }

        // 4. Skills
        let skills = data.skills
        let hasSkills = !skills.programmingLanguages.isEmpty || !skills.frameworks.isEmpty ||
                        !skills.libraries.isEmpty || !skills.databases.isEmpty ||
                        !skills.cloudDevOps.isEmpty || !skills.tools.isEmpty ||
                        !skills.softSkills.isEmpty || !skills.other.isEmpty
        if hasSkills {
            bodyXML += addSectionHeader("SKILLS & COMPETENCIES")
            func addSkillRow(_ cat: String, _ items: [String]) -> String {
                guard !items.isEmpty else { return "" }
                return """
                <w:p>
                  <w:pPr><w:spacing w:after="40"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>\(cat): </w:t></w:r>
                  <w:r><w:t>\(xmlEscape(items.joined(separator: ", ")))</w:t></w:r>
                </w:p>
                """
            }
            bodyXML += addSkillRow("Programming Languages", skills.programmingLanguages)
            bodyXML += addSkillRow("Frameworks", skills.frameworks)
            bodyXML += addSkillRow("Libraries", skills.libraries)
            bodyXML += addSkillRow("Databases", skills.databases)
            bodyXML += addSkillRow("Cloud & DevOps", skills.cloudDevOps)
            bodyXML += addSkillRow("Tools & Software", skills.tools)
            bodyXML += addSkillRow("Soft Skills", skills.softSkills)
            bodyXML += addSkillRow("Other", skills.other)
        }

        // 5. Experience / Internships
        if !data.experience.isEmpty {
            bodyXML += addSectionHeader("EXPERIENCE & INTERNSHIPS")
            for exp in data.experience {
                let role = xmlEscape(exp.role)
                let comp = xmlEscape(exp.company)
                let dates = xmlEscape("\(exp.startDate)\(exp.startDate.isEmpty ? "" : " - ")\(exp.currentlyWorking ? "Present" : exp.endDate)")
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:before="60" w:after="20"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>\(role)</w:t></w:r>
                  <w:r><w:t> @ \(comp)</w:t></w:r>
                  <w:r><w:rPr><w:color w:val="6B7280"/></w:rPr><w:t>  (\(dates))</w:t></w:r>
                </w:p>
                """
                if !exp.responsibilities.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="20"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:t>• \(xmlEscape(exp.responsibilities))</w:t></w:r>
                    </w:p>
                    """
                }
                if !exp.achievements.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="60"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:rPr><w:b/></w:rPr><w:t>• Key Achievement: </w:t></w:r>
                      <w:r><w:t>\(xmlEscape(exp.achievements))</w:t></w:r>
                    </w:p>
                    """
                }
            }
        }

        // 6. Projects
        if !data.projects.isEmpty {
            bodyXML += addSectionHeader("PROJECTS")
            for proj in data.projects {
                let pName = xmlEscape(proj.name)
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:before="60" w:after="20"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>\(pName)</w:t></w:r>
                </w:p>
                """
                if !proj.description.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="20"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:t>\(xmlEscape(proj.description))</w:t></w:r>
                    </w:p>
                    """
                }
                if !proj.keyContributions.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="20"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:rPr><w:b/></w:rPr><w:t>• Contribution: </w:t></w:r>
                      <w:r><w:t>\(xmlEscape(proj.keyContributions))</w:t></w:r>
                    </w:p>
                    """
                }
                if !proj.technologies.isEmpty {
                    bodyXML += """
                    <w:p>
                      <w:pPr><w:spacing w:after="60"/><w:ind w:left="240"/></w:pPr>
                      <w:r><w:rPr><w:i/></w:rPr><w:t>Technologies: \(xmlEscape(proj.technologies))</w:t></w:r>
                    </w:p>
                    """
                }
            }
        }

        // 7. Certifications
        if !data.certifications.isEmpty {
            bodyXML += addSectionHeader("CERTIFICATIONS")
            for cert in data.certifications {
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:after="40"/><w:ind w:left="240"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>• \(xmlEscape(cert.name))</w:t></w:r>
                  <w:r><w:t> — \(xmlEscape(cert.issuer)) (\(xmlEscape(cert.date)))</w:t></w:r>
                </w:p>
                """
            }
        }

        // 8. Key Achievements
        if !data.achievements.isEmpty {
            bodyXML += addSectionHeader("KEY ACHIEVEMENTS")
            for ach in data.achievements {
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:after="40"/><w:ind w:left="240"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>• \(xmlEscape(ach.title))</w:t></w:r>
                  <w:r><w:t>: \(xmlEscape(ach.description))</w:t></w:r>
                </w:p>
                """
            }
        }

        // 9. Positions of Responsibility
        if !data.positionsOfResponsibility.isEmpty {
            bodyXML += addSectionHeader("POSITIONS OF RESPONSIBILITY")
            for pos in data.positionsOfResponsibility {
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:after="40"/><w:ind w:left="240"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>• \(xmlEscape(pos.position)) @ \(xmlEscape(pos.organization))</w:t></w:r>
                  <w:r><w:t> (\(xmlEscape(pos.duration))): \(xmlEscape(pos.responsibilities))</w:t></w:r>
                </w:p>
                """
            }
        }

        // 10. Languages
        if !data.languages.isEmpty {
            bodyXML += addSectionHeader("LANGUAGES")
            let langStr = data.languages.map { "\($0.language)\($0.proficiency.isEmpty ? "" : " (\($0.proficiency))")" }.joined(separator: ", ")
            bodyXML += """
            <w:p>
              <w:pPr><w:spacing w:after="60"/></w:pPr>
              <w:r><w:t>\(xmlEscape(langStr))</w:t></w:r>
            </w:p>
            """
        }

        // 11. Extracurriculars
        if !data.extracurriculars.isEmpty {
            bodyXML += addSectionHeader("EXTRACURRICULAR ACTIVITIES")
            for extra in data.extracurriculars {
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:after="40"/><w:ind w:left="240"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>• \(xmlEscape(extra.activity))</w:t></w:r>
                  <w:r><w:t>: \(xmlEscape(extra.description))</w:t></w:r>
                </w:p>
                """
            }
        }

        // 12. Volunteering
        if !data.volunteering.isEmpty {
            bodyXML += addSectionHeader("VOLUNTEERING")
            for vol in data.volunteering {
                bodyXML += """
                <w:p>
                  <w:pPr><w:spacing w:after="40"/><w:ind w:left="240"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>• \(xmlEscape(vol.role)) — \(xmlEscape(vol.organization))</w:t></w:r>
                  <w:r><w:t>: \(xmlEscape(vol.description))</w:t></w:r>
                </w:p>
                """
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(bodyXML)
          </w:body>
        </w:document>
        """
    }
}
