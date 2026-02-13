#!/usr/bin/env swift

import Foundation

// MARK: - Manifest Models

private struct HelpManifest: Decodable {
    let bookTitle: String
    let bookIdentifier: String
    let topics: [HelpManifestTopic]
}

private struct HelpManifestTopic: Decodable {
    let id: String
    let title: String
    let group: String
    let iconSystemName: String
    let iconStyle: String
    let markdownFile: String
    let showsScreenshots: Bool
}

// MARK: - Parsed Models

private struct ParsedTopic {
    let manifest: HelpManifestTopic
    let sections: [ParsedSection]

    var searchableText: String {
        let sectionText = sections
            .flatMap { section in
                var values: [String] = []
                if let header = section.header { values.append(header) }
                values.append(contentsOf: section.lines.map(\.value))
                return values
            }
            .joined(separator: " ")

        return "\(manifest.title) \(sectionText)"
    }
}

private struct ParsedSection {
    let header: String?
    let screenshotSlot: Int?
    let lines: [ParsedLine]
}

private struct ParsedLine {
    enum Kind: String {
        case text
        case bullet
    }

    let kind: Kind
    let value: String
}

// MARK: - Paths

private let fileManager = FileManager.default
private let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let sourceRootURL = rootURL.appendingPathComponent("HelpSource")
private let markdownRootURL = sourceRootURL.appendingPathComponent("en")
private let manifestURL = sourceRootURL.appendingPathComponent("help_manifest.json")
private let generatedSwiftURL = rootURL.appendingPathComponent("OffshoreBudgeting/CoreViews/Settings/GeneratedHelpContent.swift")
private let helpBundleURL = rootURL.appendingPathComponent("OffshoreHelp.help")
private let helpContentsURL = helpBundleURL.appendingPathComponent("Contents")
private let helpInfoPlistURL = helpContentsURL.appendingPathComponent("Info.plist")
private let resourcesURL = helpContentsURL.appendingPathComponent("Resources")
private let localizedHelpURL = resourcesURL.appendingPathComponent("en.lproj")
private let mediaURL = localizedHelpURL.appendingPathComponent("media")
private let cssURL = localizedHelpURL.appendingPathComponent("style.css")
private let indexURL = localizedHelpURL.appendingPathComponent("index.html")
private let assetsRootURL = rootURL.appendingPathComponent("OffshoreBudgeting/Assets.xcassets")

// MARK: - Entry

func run() throws {
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(HelpManifest.self, from: manifestData)

    let parsedTopics = try manifest.topics.map(parseTopic)

    try prepareOutputDirectories()
    try writeHelpInfoPlist(manifest: manifest)
    try writeCSS()
    try writeIndexHTML(manifest: manifest, parsedTopics: parsedTopics)

    for topic in parsedTopics {
        try writeTopicHTML(topic: topic)
    }

    try writeGeneratedSwift(manifest: manifest, parsedTopics: parsedTopics)

    print("Generated help content:")
    print("- \(generatedSwiftURL.path)")
    print("- \(helpBundleURL.path)")
}

// MARK: - Parsing

private func parseTopic(_ topic: HelpManifestTopic) throws -> ParsedTopic {
    let url = markdownRootURL.appendingPathComponent(topic.markdownFile)
    let content = try String(contentsOf: url, encoding: .utf8)
    let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

    var sections: [ParsedSection] = []
    var currentHeader: String? = nil
    var currentScreenshotSlot: Int? = nil
    var currentLines: [ParsedLine] = []
    var paragraphBuffer: [String] = []

    func flushParagraph() {
        guard !paragraphBuffer.isEmpty else { return }
        let paragraph = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty {
            currentLines.append(ParsedLine(kind: .text, value: paragraph))
        }
        paragraphBuffer.removeAll(keepingCapacity: true)
    }

    func flushSectionIfNeeded() {
        flushParagraph()
        guard currentHeader != nil || currentScreenshotSlot != nil || !currentLines.isEmpty else { return }
        sections.append(
            ParsedSection(
                header: currentHeader,
                screenshotSlot: currentScreenshotSlot,
                lines: currentLines
            )
        )
        currentHeader = nil
        currentScreenshotSlot = nil
        currentLines.removeAll(keepingCapacity: true)
    }

    for rawLine in lines {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        if line.hasPrefix("# ") {
            continue
        }

        if line.hasPrefix("## ") {
            flushSectionIfNeeded()
            currentHeader = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }

        if line.hasPrefix("[[screenshot:") && line.hasSuffix("]]"),
           let value = line.split(separator: ":").last {
            let cleaned = value.dropLast(2)
            currentScreenshotSlot = Int(cleaned)
            continue
        }

        if line.hasPrefix("- ") {
            flushParagraph()
            let bullet = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !bullet.isEmpty {
                currentLines.append(ParsedLine(kind: .bullet, value: bullet))
            }
            continue
        }

        if line.isEmpty {
            flushParagraph()
            continue
        }

        paragraphBuffer.append(line)
    }

    flushSectionIfNeeded()

    if sections.isEmpty {
        throw NSError(domain: "HelpGenerator", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "No sections parsed for topic \(topic.id)."
        ])
    }

    return ParsedTopic(manifest: topic, sections: sections)
}

// MARK: - Output Setup

private func prepareOutputDirectories() throws {
    if fileManager.fileExists(atPath: helpBundleURL.path) {
        try fileManager.removeItem(at: helpBundleURL)
    }

    try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
}

private func writeHelpInfoPlist(manifest: HelpManifest) throws {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleIdentifier</key>
        <string>\(xmlEscape(manifest.bookIdentifier))</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>\(xmlEscape(manifest.bookTitle))</string>
        <key>CFBundlePackageType</key>
        <string>BNDL</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>HPDBookAccessPath</key>
        <string>en.lproj/index.html</string>
        <key>HPDBookTitle</key>
        <string>\(xmlEscape(manifest.bookTitle))</string>
        <key>HPDBookType</key>
        <string>3</string>
    </dict>
    </plist>
    """

    try plist.write(to: helpInfoPlistURL, atomically: true, encoding: .utf8)
}

private func writeCSS() throws {
    let css = """
    body {
      margin: 0;
      padding: 20px;
      font: 14px/1.5 -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif;
      background-color: #ffffff;
      color: #111111;
    }

    #content {
      max-width: 920px;
      margin: 0 auto;
    }

    h1 { font-size: 28px; margin: 0 0 12px; }
    h2 { font-size: 20px; margin: 20px 0 8px; }
    p { margin: 8px 0 12px; }

    .topic-list {
      list-style: none;
      margin: 0;
      padding: 0;
    }

    .topic-list a {
      display: block;
      padding: 8px 0;
      color: #0b63c9;
      text-decoration: none;
    }

    .topic-list a:hover {
      text-decoration: underline;
    }

    .screenshot {
      margin: 12px 0 14px;
    }

    .screenshot img {
      width: 100%;
      height: auto;
      display: block;
      border: 1px solid #d8d8d8;
    }

    ul {
      margin: 6px 0 14px 20px;
      padding: 0;
    }

    li { margin: 4px 0; }

    .back-link {
      margin-top: 18px;
      display: inline-block;
      color: #0b63c9;
      text-decoration: none;
    }

    .back-link:hover {
      text-decoration: underline;
    }
    """

    try css.write(to: cssURL, atomically: true, encoding: .utf8)
}

// MARK: - HTML Generation

private func writeIndexHTML(manifest: HelpManifest, parsedTopics: [ParsedTopic]) throws {
    let topicLinks = parsedTopics.map { topic in
        "<li><a href=\"\(topic.manifest.id).html\">\(htmlEscape(topic.manifest.title))</a></li>"
    }.joined(separator: "\n")

    let html = """
    <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="AppleTitle" content="\(htmlEscape(manifest.bookTitle))">
      <title>\(htmlEscape(manifest.bookTitle))</title>
      <link rel="stylesheet" href="style.css">
    </head>
    <body>
      <div id="content">
        <h1>\(htmlEscape(manifest.bookTitle))</h1>
        <p>Browse topics to learn the core workflows and calculations in Offshore.</p>
        <ul class="topic-list">
          \(topicLinks)
        </ul>
      </div>
    </body>
    </html>
    """

    try html.write(to: indexURL, atomically: true, encoding: .utf8)
}

private func writeTopicHTML(topic: ParsedTopic) throws {
    let bodySections = topic.sections.map { section in
        sectionHTML(topic: topic.manifest, section: section)
    }.joined(separator: "\n")

    let html = """
    <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
    <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="AppleTitle" content="\(htmlEscape(topic.manifest.title))">
      <title>\(htmlEscape(topic.manifest.title)) - Offshore Help</title>
      <link rel="stylesheet" href="style.css">
    </head>
    <body>
      <div id="content">
        <h1>\(htmlEscape(topic.manifest.title))</h1>
        \(bodySections)
        <a class="back-link" href="index.html">Back to help topics</a>
      </div>
    </body>
    </html>
    """

    let pageURL = localizedHelpURL.appendingPathComponent("\(topic.manifest.id).html")
    try html.write(to: pageURL, atomically: true, encoding: .utf8)
}

private func sectionHTML(topic: HelpManifestTopic, section: ParsedSection) -> String {
    var fragments: [String] = []

    if let header = section.header {
        fragments.append("<h2>\(htmlEscape(header))</h2>")
    }

    if topic.showsScreenshots, let slot = section.screenshotSlot,
       let imageName = copyScreenshotIfNeeded(topicTitle: topic.title, slot: slot) {
        fragments.append(
            "<div class=\"screenshot\"><img src=\"media/\(htmlEscape(imageName))\" alt=\"\(htmlEscape(topic.title)) screenshot \(slot)\"></div>"
        )
    }

    var index = 0
    while index < section.lines.count {
        let line = section.lines[index]
        switch line.kind {
        case .text:
            fragments.append("<p>\(htmlEscape(line.value))</p>")
            index += 1
        case .bullet:
            var bullets: [String] = []
            while index < section.lines.count && section.lines[index].kind == .bullet {
                bullets.append("<li>\(htmlEscape(section.lines[index].value))</li>")
                index += 1
            }
            fragments.append("<ul>\(bullets.joined())</ul>")
        }
    }

    return fragments.joined(separator: "\n")
}

private func copyScreenshotIfNeeded(topicTitle: String, slot: Int) -> String? {
    let topicToken = topicTitle.replacingOccurrences(of: " ", with: "")
    let setName = "Help-\(topicToken)-\(slot).imageset"
    let setURL = assetsRootURL.appendingPathComponent(setName)

    guard let entries = try? fileManager.contentsOfDirectory(at: setURL, includingPropertiesForKeys: nil)
    else { return nil }

    let images = entries
        .filter { $0.lastPathComponent != "Contents.json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard let sourceImageURL = images.first else { return nil }

    let ext = sourceImageURL.pathExtension.isEmpty ? "png" : sourceImageURL.pathExtension
    let destinationName = "Help-\(topicToken)-\(slot).\(ext)"
    let destinationURL = mediaURL.appendingPathComponent(destinationName)

    if !fileManager.fileExists(atPath: destinationURL.path) {
        try? fileManager.copyItem(at: sourceImageURL, to: destinationURL)
    }

    return destinationName
}

// MARK: - Swift Generation

private func writeGeneratedSwift(manifest: HelpManifest, parsedTopics: [ParsedTopic]) throws {
    var output: [String] = []

    output.append("//")
    output.append("//  GeneratedHelpContent.swift")
    output.append("//  OffshoreBudgeting")
    output.append("//")
    output.append("//  Generated by scripts/generate_help.swift")
    output.append("//  Do not edit manually.")
    output.append("//")
    output.append("")
    output.append("import Foundation")
    output.append("")
    output.append("enum GeneratedHelpTopicGroup: String {")
    output.append("    case gettingStarted")
    output.append("    case coreScreens")
    output.append("}")
    output.append("")
    output.append("enum GeneratedHelpIconStyle: String {")
    output.append("    case gray")
    output.append("    case blue")
    output.append("    case purple")
    output.append("    case red")
    output.append("    case green")
    output.append("    case orange")
    output.append("}")
    output.append("")
    output.append("struct GeneratedHelpLine: Hashable {")
    output.append("    enum Kind: String {")
    output.append("        case text")
    output.append("        case bullet")
    output.append("    }")
    output.append("")
    output.append("    let kind: Kind")
    output.append("    let value: String")
    output.append("}")
    output.append("")
    output.append("struct GeneratedHelpSection: Identifiable, Hashable {")
    output.append("    let id: String")
    output.append("    let screenshotSlot: Int?")
    output.append("    let header: String?")
    output.append("    let lines: [GeneratedHelpLine]")
    output.append("}")
    output.append("")
    output.append("struct GeneratedHelpTopic: Identifiable, Hashable {")
    output.append("    let id: String")
    output.append("    let title: String")
    output.append("    let group: GeneratedHelpTopicGroup")
    output.append("    let iconSystemName: String")
    output.append("    let iconStyle: GeneratedHelpIconStyle")
    output.append("    let sections: [GeneratedHelpSection]")
    output.append("    let searchableText: String")
    output.append("}")
    output.append("")
    output.append("enum GeneratedHelpContent {")
    output.append("    static let bookTitle: String = \"\(swiftEscape(manifest.bookTitle))\"")
    output.append("    static let bookIdentifier: String = \"\(swiftEscape(manifest.bookIdentifier))\"")
    output.append("")
    output.append("    static let topics: [GeneratedHelpTopic] = [")

    for (topicIndex, topic) in parsedTopics.enumerated() {
        output.append("        GeneratedHelpTopic(")
        output.append("            id: \"\(swiftEscape(topic.manifest.id))\",")
        output.append("            title: \"\(swiftEscape(topic.manifest.title))\",")

        let groupCase: String = topic.manifest.group == "getting_started" ? ".gettingStarted" : ".coreScreens"
        output.append("            group: \(groupCase),")
        output.append("            iconSystemName: \"\(swiftEscape(topic.manifest.iconSystemName))\",")
        output.append("            iconStyle: .\(swiftEscape(topic.manifest.iconStyle)),")
        output.append("            sections: [")

        for (sectionIndex, section) in topic.sections.enumerated() {
            output.append("                GeneratedHelpSection(")
            output.append("                    id: \"\(swiftEscape(topic.manifest.id))-\(sectionIndex + 1)\",")

            if let slot = section.screenshotSlot {
                output.append("                    screenshotSlot: \(slot),")
            } else {
                output.append("                    screenshotSlot: nil,")
            }

            if let header = section.header {
                output.append("                    header: \"\(swiftEscape(header))\",")
            } else {
                output.append("                    header: nil,")
            }

            output.append("                    lines: [")
            for line in section.lines {
                output.append("                        GeneratedHelpLine(kind: .\(line.kind.rawValue), value: \"\(swiftEscape(line.value))\"),")
            }
            output.append("                    ]")
            output.append("                )\(sectionIndex == topic.sections.count - 1 ? "" : ",")")
        }

        output.append("            ],")
        output.append("            searchableText: \"\(swiftEscape(topic.searchableText))\"")
        output.append("        )\(topicIndex == parsedTopics.count - 1 ? "" : ",")")
    }

    output.append("    ]")
    output.append("")
    output.append("    static var gettingStartedTopics: [GeneratedHelpTopic] {")
    output.append("        topics.filter { $0.group == .gettingStarted }")
    output.append("    }")
    output.append("")
    output.append("    static var coreScreenTopics: [GeneratedHelpTopic] {")
    output.append("        topics.filter { $0.group == .coreScreens }")
    output.append("    }")
    output.append("}")

    let fileText = output.joined(separator: "\n") + "\n"
    try fileText.write(to: generatedSwiftURL, atomically: true, encoding: .utf8)
}

// MARK: - Escaping

private func swiftEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

private func htmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private func xmlEscape(_ value: String) -> String {
    htmlEscape(value)
}

// MARK: - Run

do {
    try run()
} catch {
    fputs("Help generation failed: \(error)\n", stderr)
    exit(1)
}
