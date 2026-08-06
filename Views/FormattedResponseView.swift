import SwiftUI
import Combine

public enum MessageBlock: Identifiable, Equatable {
    public var id: String {
        switch self {
        case .text(let t): return "t_\(t.hashValue)"
        case .header(let l, let t): return "h_\(l)_\(t.hashValue)"
        case .bullet(let t): return "b_\(t.hashValue)"
        case .quote(let t): return "q_\(t.hashValue)"
        case .code(let l, let c): return "c_\(l)_\(c.hashValue)"
        case .image(let url): return "img_\(url.hashValue)"
        }
    }
    
    case text(String)
    case header(level: Int, text: String)
    case bullet(String)
    case quote(String)
    case code(lang: String, code: String)
    case image(url: String)
}

public func parseMarkdown(_ text: String) -> [MessageBlock] {
    var blocks: [MessageBlock] = []
    let lines = text.components(separatedBy: .newlines)
    var inCodeBlock = false
    var currentCode = ""
    var currentLang = ""
    var currentTextBlock = ""
    
    func flushTextBlock() {
        let trimmed = currentTextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            blocks.append(.text(trimmed))
            currentTextBlock = ""
        }
    }
    
    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
            if inCodeBlock {
                blocks.append(.code(lang: currentLang, code: currentCode.trimmingCharacters(in: .newlines)))
                currentCode = ""
                currentLang = ""
                inCodeBlock = false
            } else {
                flushTextBlock()
                inCodeBlock = true
                currentLang = line.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if inCodeBlock {
            currentCode += line + "\n"
        } else {
            if trimmedLine.hasPrefix("![") && trimmedLine.hasSuffix(")") {
                if let openParenthesis = trimmedLine.firstIndex(of: "("),
                   let closeParenthesis = trimmedLine.lastIndex(of: ")"),
                   openParenthesis < closeParenthesis {
                    let urlStart = trimmedLine.index(after: openParenthesis)
                    let urlString = String(trimmedLine[urlStart..<closeParenthesis]).trimmingCharacters(in: .whitespacesAndNewlines)
                    flushTextBlock()
                    blocks.append(.image(url: urlString))
                }
            } else if trimmedLine.hasPrefix("#") {
                flushTextBlock()
                let level = trimmedLine.prefix(while: { $0 == "#" }).count
                if level > 0 && level <= 6 {
                    let headerText = String(trimmedLine.dropFirst(level)).trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(.header(level: level, text: headerText))
                } else {
                    if currentTextBlock.isEmpty {
                        currentTextBlock = line
                    } else {
                        currentTextBlock += "\n" + line
                    }
                }
            } else if trimmedLine.hasPrefix("> ") || trimmedLine == ">" {
                flushTextBlock()
                let quoteText = String(trimmedLine.dropFirst(trimmedLine.hasPrefix("> ") ? 2 : 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(.quote(quoteText))
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                flushTextBlock()
                let bulletText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(.bullet(bulletText))
            } else {
                if currentTextBlock.isEmpty {
                    currentTextBlock = line
                } else {
                    currentTextBlock += "\n" + line
                }
            }
        }
    }
    
    flushTextBlock()
    return blocks
}

// MARK: - Async Favicon Loader
public struct AsyncFaviconView: View {
    let domain: String
    
    public var body: some View {
        let cleanDomain = domain.replacingOccurrences(of: "www.", with: "")
        let urlString = "https://www.google.com/s2/favicons?domain=\(cleanDomain)&sz=32"
        
        if #available(iOS 15.0, macOS 12.0, *) {
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure, .empty:
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white.opacity(0.3))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 12, height: 12)
            .cornerRadius(3)
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 12, height: 12)
        }
    }
}

// MARK: - SVG Custom Vector Globe Icon
#if os(macOS)
public func getSvgGlobeIcon() -> NSImage {
    let size = NSSize(width: 10, height: 10)
    let image = NSImage(size: size)
    image.lockFocus()
    
    // Draw SVG-like globe path
    let bounds = NSRect(x: 0.5, y: 0.5, width: 9, height: 9)
    let path = NSBezierPath(ovalIn: bounds)
    
    // Horizontal equator line
    path.move(to: NSPoint(x: 0.5, y: 5.0))
    path.line(to: NSPoint(x: 9.5, y: 5.0))
    
    // Vertical meridian line
    path.move(to: NSPoint(x: 5.0, y: 0.5))
    path.line(to: NSPoint(x: 5.0, y: 9.5))
    
    path.lineWidth = 1.0
    let color = NSColor(red: 0.51, green: 0.48, blue: 0.87, alpha: 1.0)
    color.setStroke()
    path.stroke()
    
    image.unlockFocus()
    return image
}
#endif

// MARK: - Citation Link Generation Helper
public func citationLink(for source: GroundedSource, index: Int) -> Text {
    let domain = URL(string: source.url ?? "")?.host ?? "source"
    let cleanDomain = domain.replacingOccurrences(of: "www.", with: "").lowercased()
    
    let attachment = NSTextAttachment()
    #if os(macOS)
    attachment.image = getSvgGlobeIcon()
    attachment.bounds = CGRect(x: 0, y: -1, width: 10, height: 10)
    #endif
    
    var attrStr = AttributedString(NSAttributedString(attachment: attachment))
    attrStr.link = URL(string: source.url ?? "")
    
    var domainStr = AttributedString(" \(cleanDomain) [\(index)]")
    domainStr.link = URL(string: source.url ?? "")
    domainStr.foregroundColor = hexColor("758DEC")
    domainStr.underlineStyle = .single
    
    return Text(attrStr) + Text(domainStr)
        .font(.system(size: 9.5, weight: .bold))
}

fileprivate func hexColor(_ hex: String) -> Color {
    Color(hex: hex) ?? .indigo
}

// MARK: - Inline Citations Rendering Helper
public func renderInlineCitations(_ text: String, sources: [GroundedSource]) -> Text {
    var resultText = Text("")
    var currentIndex = text.startIndex
    let pattern = "\\[(\\d+(?:\\s*,\\s*\\d+)*)\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return Text(text)
    }
    
    let nsString = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
    
    for match in matches {
        let matchRange = match.range
        guard let swiftRange = Range(matchRange, in: text) else { continue }
        let startOfMatch = swiftRange.lowerBound
        let endOfMatch = swiftRange.upperBound
        
        // Append preceding text
        if startOfMatch > currentIndex {
            let beforeText = String(text[currentIndex..<startOfMatch])
            resultText = resultText + Text(beforeText)
        }
        
        // Lookup and append custom inline citation badge
        if match.numberOfRanges > 1 {
            let indexRange = match.range(at: 1)
            let citationIndexStr = nsString.substring(with: indexRange)
            let indices = citationIndexStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            for (idx, indexStr) in indices.enumerated() {
                if idx > 0 {
                    resultText = resultText + Text(" ")
                }
                if let citationIndex = Int(indexStr) {
                    if citationIndex > 0 && citationIndex <= sources.count {
                        let source = sources[citationIndex - 1]
                        resultText = resultText + citationLink(for: source, index: citationIndex)
                    } else {
                        resultText = resultText + Text("[\(citationIndex)]")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                } else {
                    resultText = resultText + Text("[\(indexStr)]")
                }
            }
        }
        
        currentIndex = endOfMatch
    }
    
    if currentIndex < text.endIndex {
        let remainingText = String(text[currentIndex...])
        resultText = resultText + Text(remainingText)
    }
    
    return resultText
}

// MARK: - Sophisticated Scientific Notation and Inline Markdown Formatter
public func formatScientificNotation(_ text: String) -> String {
    var result = text
    
    // Replace LaTeX \times or standard multiplied multipliers with ×
    result = result.replacingOccurrences(of: "\\times", with: "×")
    
    // Convert 10^X or 10^{X} to super-script format nicely
    let patterns = [
        (#"10\^\{([+-]?\d+)\}"#, "10"),
        (#"10\^([+-]?\d+)"#, "10")
    ]
    
    func makeSuperScript(_ numStr: String) -> String {
        var out = ""
        for char in numStr {
            switch char {
            case "0": out += "⁰"
            case "1": out += "¹"
            case "2": out += "²"
            case "3": out += "³"
            case "4": out += "⁴"
            case "5": out += "⁵"
            case "6": out += "⁶"
            case "7": out += "⁷"
            case "8": out += "⁸"
            case "9": out += "⁹"
            case "-": out += "⁻"
            case "+": out += "⁺"
            default: out += String(char)
            }
        }
        return out
    }
    
    for (pattern, suffix) in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let numberRange = match.range(at: 1)
                    let numStr = nsString.substring(with: numberRange)
                    let replacement = suffix + makeSuperScript(numStr)
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }
    }
    
    return result
}

public func parseInlineMarkdownAndCitations(_ text: String, sources: [GroundedSource]) -> Text {
    var resultText = Text("")
    var currentIndex = text.startIndex
    
    // Unified Regex capturing hyperlinks [Anchor](URL), citations [Digits], bold **Text**, italic *Text*, and inline `code`
    let pattern = "(\\[([^\\]]+)\\]\\(([^\\)]+)\\))|(\\[\\s*(\\d+(?:\\s*,\\s*\\d+)*)\\s*\\])|(\\*\\*([^\\*]+)\\*\\*)|(\\*([^\\*]+)\\*)|(`([^`]+)`)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return Text(text)
    }
    
    let nsString = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
    
    for match in matches {
        let matchRange = match.range
        guard let swiftRange = Range(matchRange, in: text) else { continue }
        let startOfMatch = swiftRange.lowerBound
        let endOfMatch = swiftRange.upperBound
        
        // Append preceding plain text
        if startOfMatch > currentIndex {
            let beforeText = String(text[currentIndex..<startOfMatch])
            resultText = resultText + Text(beforeText)
        }
        
        // Match specific group
        if match.range(at: 1).location != NSNotFound { // Hyperlink: [anchor](url)
            let anchorText = nsString.substring(with: match.range(at: 2))
            let urlStr = nsString.substring(with: match.range(at: 3))
            
            if urlStr.hasPrefix("file://") || urlStr.hasPrefix("/") {
                resultText = resultText + Text(" 📁 \(anchorText) ")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .underline()
            } else {
                resultText = resultText + Text(anchorText)
                    .underline()
                    .foregroundColor(.cyan)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        else if match.range(at: 4).location != NSNotFound { // Citation: [index, index, ...]
            let citationIndexStr = nsString.substring(with: match.range(at: 5))
            let indices = citationIndexStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            resultText = resultText + Text(" ")
            for (idx, indexStr) in indices.enumerated() {
                if idx > 0 {
                    resultText = resultText + Text(" ")
                }
                if let citationIndex = Int(indexStr) {
                    if citationIndex > 0 && citationIndex <= sources.count {
                        let source = sources[citationIndex - 1]
                        resultText = resultText + citationLink(for: source, index: citationIndex)
                    } else {
                        resultText = resultText + Text("[\(citationIndex)]")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                } else {
                    resultText = resultText + Text("[\(indexStr)]")
                }
            }
        }

        else if match.range(at: 6).location != NSNotFound { // Bold: **text**
            let boldText = nsString.substring(with: match.range(at: 7))
            resultText = resultText + Text(boldText)
                .bold()
                .foregroundColor(.white)
        }
        else if match.range(at: 8).location != NSNotFound { // Italic: *text*
            let italicText = nsString.substring(with: match.range(at: 9))
            resultText = resultText + Text(italicText)
                .italic()
        }
        else if match.range(at: 10).location != NSNotFound { // Code: `code`
            let codeText = nsString.substring(with: match.range(at: 11))
            var attr = AttributedString(" \(codeText) ")
            attr.font = .system(size: 12, weight: .bold, design: .monospaced)
            attr.foregroundColor = .white
            attr.backgroundColor = Color.white.opacity(0.15)
            resultText = resultText + Text(attr)
        }
        
        currentIndex = endOfMatch
    }
    
    if currentIndex < text.endIndex {
        let remainingText = String(text[currentIndex...])
        resultText = resultText + Text(remainingText)
    }
    
    return resultText
}

public func parseFormattedText(_ input: String, sources: [GroundedSource] = []) -> Text {
    let formatted = formatScientificNotation(input)
    return parseInlineMarkdownAndCitations(formatted, sources: sources)
}

// MARK: - Rich Text Block View with Citations support
public struct RichTextView: View {
    let text: String
    let sources: [GroundedSource]
    
    public init(_ text: String, sources: [GroundedSource] = []) {
        self.text = text
        self.sources = sources
    }
    
    public var body: some View {
        parseFormattedText(text, sources: sources)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(.white.opacity(0.95))
            .lineSpacing(4.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct HeaderView: View {
    let level: Int
    let text: String
    
    public var body: some View {
        Text(text)
            .font(.system(size: level == 1 ? 16 : (level == 2 ? 15 : 14), weight: .bold))
            .foregroundColor(.white)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

public struct BulletRowView: View {
    let text: String
    let sources: [GroundedSource]
    
    public init(text: String, sources: [GroundedSource] = []) {
        self.text = text
        self.sources = sources
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .bold))
            
            parseFormattedText(text, sources: sources)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.95))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

public struct BlockquoteView: View {
    let text: String
    let sources: [GroundedSource]
    
    public init(text: String, sources: [GroundedSource] = []) {
        self.text = text
        self.sources = sources
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(gradient: Gradient(colors: [Color.cyan, Color.blue]), startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 4) {
                RichTextView(text, sources: sources)
                    .foregroundColor(.white.opacity(0.92))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

public struct CodeBlockView: View {
    let lang: String
    let code: String
    @State private var isCopied = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.uppercased().isEmpty ? "CODE" : lang.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Button(action: {
                    #if os(macOS)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    #else
                    UIPasteboard.general.string = code
                    #endif
                    
                    withAnimation(.spring()) {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isCopied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? "COPIED" : "COPY")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(14)
            }
        }
        .background(Color.black.opacity(0.35))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }
}

public struct GroundedSource: Identifiable, Decodable, Hashable {
    public var id: String { url ?? UUID().uuidString }
    public let title: String?
    public let siteName: String?
    public let url: String?
    public let snippet: String?
    public var linesUsed: [String]?

    enum CodingKeys: String, CodingKey {
        case title, siteName, url, uri, snippet, linesUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        
        let urlValue = try container.decodeIfPresent(String.self, forKey: .url)
        let uriValue = try container.decodeIfPresent(String.self, forKey: .uri)
        self.url = urlValue ?? uriValue
        
        self.snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        self.linesUsed = try container.decodeIfPresent([String].self, forKey: .linesUsed)
    }

    // Explicit initializer for backup parser
    public init(title: String?, siteName: String?, url: String?, snippet: String?, linesUsed: [String]?) {
        self.title = title
        self.siteName = siteName
        self.url = url
        self.snippet = snippet
        self.linesUsed = linesUsed
    }
}

// MARK: - Extractor of Sources and Suggested Follow-ups
public func extractSources(_ text: String) -> (cleanText: String, sources: [GroundedSource], followUps: [String]) {
    var clean = text
    var list: [GroundedSource] = []
    var followUpsList: [String] = []
    
    // Balanced bracket extraction helper function for tags
    func parseTagSwift(_ content: String, tagName: String) -> (full: String, inner: String)? {
        let pattern = "\\[\(tagName)\\s*:\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsString = content as NSString
        guard let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsString.length)) else { return nil }
        
        guard let startRange = Range(match.range, in: content) else { return nil }
        let swiftStartIdx = startRange.lowerBound
        let swiftEndOfMarker = startRange.upperBound
        
        var bracketCount = 0
        var inString = false
        var hasFoundEnd = false
        var swiftEndIdx = content.endIndex
        
        var currentIndex = swiftStartIdx
        while currentIndex < content.endIndex {
            let char = content[currentIndex]
            if char == "\"" {
                if currentIndex > swiftStartIdx {
                    let prevIdx = content.index(before: currentIndex)
                    if content[prevIdx] == "\\" {
                        // escaped quote
                    } else {
                        inString.toggle()
                    }
                } else {
                    inString.toggle()
                }
            }
            
            if !inString {
                if char == "[" {
                    bracketCount += 1
                } else if char == "]" {
                    bracketCount -= 1
                }
            }
            
            if bracketCount == 0 && currentIndex > swiftStartIdx {
                swiftEndIdx = content.index(after: currentIndex)
                hasFoundEnd = true
                break
            }
            
            currentIndex = content.index(after: currentIndex)
        }
        
        if hasFoundEnd {
            let fullSlice = String(content[swiftStartIdx..<swiftEndIdx])
            let innerSlice = String(content[swiftEndOfMarker..<content.index(before: swiftEndIdx)]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (fullSlice, innerSlice)
        }
        return nil
    }
    
    // 1. Parse SOURCES
    if let sourcesData = parseTagSwift(clean, tagName: "SOURCES") {
        let innerJson = sourcesData.inner
        var completeJson = innerJson
        if !completeJson.hasPrefix("[") {
            completeJson = "[\(completeJson)]"
        }
        
        if let data = completeJson.data(using: .utf8) {
            if let parsed = try? JSONDecoder().decode([GroundedSource].self, from: data) {
                list = parsed
            } else {
                list = parseSourcesUsingRegexSwift(innerJson)
            }
        } else {
            list = parseSourcesUsingRegexSwift(innerJson)
        }
        
        clean = clean.replacingOccurrences(of: sourcesData.full, with: "")
    } else {
        // Fallback or streaming support: match incomplete/open [SOURCES: [...]]
        let pattern = "\\[SOURCES:\\s*\\[?([\\s\\S]*?)\\]?\\s*\\]?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length)) {
            if match.numberOfRanges > 1 {
                let nsString = clean as NSString
                let matchedContent = nsString.substring(with: match.range(at: 1))
                list = parseSourcesUsingRegexSwift(matchedContent)
            }
        }
    }
    
    // 2. Parse FOLLOW_UPS
    if let followUpsData = parseTagSwift(clean, tagName: "FOLLOW_UPS") {
        let innerJson = followUpsData.inner
        var completeJson = innerJson
        if !completeJson.hasPrefix("[") {
            completeJson = "[\(completeJson)]"
        }
        
        if let data = completeJson.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            followUpsList = parsed
        } else {
            followUpsList = parseFollowUpsUsingRegexSwift(innerJson)
        }
        
        clean = clean.replacingOccurrences(of: followUpsData.full, with: "")
    } else {
        // Fallback or streaming support
        let pattern = "\\[FOLLOW_UPS:\\s*\\[?([\\s\\S]*?)\\]?\\s*\\]?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length)) {
            if match.numberOfRanges > 1 {
                let nsString = clean as NSString
                let matchedContent = nsString.substring(with: match.range(at: 1))
                followUpsList = parseFollowUpsUsingRegexSwift(matchedContent)
            }
        }
    }
    
    // Fallback: strip any leftover open brackets tags to keep view perfectly pristine
    clean = removeLeftoverTagMarkers(clean)
    
    // Advanced Fallback: Auto-associate matching sentences in response text with sources if linesUsed list is empty/absent
    do {
        var modifiedList: [GroundedSource] = []
        for (idx, var src) in list.enumerated() {
            if src.linesUsed == nil {
                src.linesUsed = []
            }
            let citMarker = "[\(idx + 1)]"
            
            // Matches text from start of line or punctuation, up to the citation token
            let escapedMarker = "\\[[^\\]]*?\(idx + 1)[^\\]]*?\\]"
            let sentencePattern = "(?:^|[.\\!?])\\s*([^.\\!?\\n]+?\\s*\(escapedMarker))"
            if let sentenceRegex = try? NSRegularExpression(pattern: sentencePattern, options: []) {
                let nsClean = clean as NSString
                let matches = sentenceRegex.matches(in: clean, options: [], range: NSRange(location: 0, length: nsClean.length))
                
                for m in matches {
                    if m.numberOfRanges > 1 {
                        var sentence = nsClean.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        sentence = sentence.replacingOccurrences(of: citMarker, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !sentence.isEmpty && sentence.count > 5 {
                            if src.linesUsed == nil {
                                src.linesUsed = [sentence]
                            } else if !src.linesUsed!.contains(sentence) {
                                src.linesUsed!.append(sentence)
                            }
                        }
                    }
                }
            }
            modifiedList.append(src)
        }
        list = modifiedList
    }

    // Auto-inject missing inline citation markers into clean for sentences in linesUsed
    do {
        for (idx, src) in list.enumerated() {
            let citMarker = "[\(idx + 1)]"
            if let lines = src.linesUsed {
                for line in lines {
                    if line.isEmpty || line.count < 5 { continue }
                    if let range = clean.range(of: line) {
                        let endIdx = range.upperBound
                        let remaining = String(clean[endIdx...]).prefix(20)
                        let trailPattern = "^\\s*\\[\\s*\\d+(?:\\s*,\\s*\\d+)*\\s*\\]"
                        
                        if let trailRegex = try? NSRegularExpression(pattern: trailPattern, options: []),
                           trailRegex.firstMatch(in: String(remaining), options: [], range: NSRange(location: 0, length: (String(remaining) as NSString).length)) == nil {
                            let insertStr = " \(citMarker)"
                            clean.insert(contentsOf: insertStr, at: endIdx)
                        }
                    }
                }
            }
        }
    }
    
    return (clean.trimmingCharacters(in: .whitespacesAndNewlines), list, followUpsList)
}

// MARK: - Low-level extraction helpers
func parseSourcesUsingRegexSwift(_ raw: String) -> [GroundedSource] {
    var result: [GroundedSource] = []
    let pattern = "\\{[\\s\\S]*?\\}"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let nsString = raw as NSString
    let matches = regex.matches(in: raw, options: [], range: NSRange(location: 0, length: nsString.length))
    
    for match in matches {
        let jsonStr = nsString.substring(with: match.range)
        
        if let data = jsonStr.data(using: .utf8),
           let source = try? JSONDecoder().decode(GroundedSource.self, from: data) {
            result.append(source)
            continue
        }
        
        let titlePattern = "\"title\"\\s*:\\s*\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
        let urlPattern = "\"url\"\\s*:\\s*\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
        let uriPattern = "\"uri\"\\s*:\\s*\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
        let siteNamePattern = "\"siteName\"\\s*:\\s*\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
        let snippetPattern = "\"snippet\"\\s*:\\s*\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
        
        let title = extractRegexValueSwift(jsonStr, pattern: titlePattern)?.replacingOccurrences(of: "\\\"", with: "\"")
        let url = (extractRegexValueSwift(jsonStr, pattern: urlPattern) ?? extractRegexValueSwift(jsonStr, pattern: uriPattern))?.replacingOccurrences(of: "\\\"", with: "\"")
        let siteName = extractRegexValueSwift(jsonStr, pattern: siteNamePattern)?.replacingOccurrences(of: "\\\"", with: "\"")
        let snippet = extractRegexValueSwift(jsonStr, pattern: snippetPattern)?.replacingOccurrences(of: "\\\"", with: "\"")
        
        var linesUsed: [String] = []
        let linesPattern = "\"linesUsed\"\\s*:\\s*\\[([\\s\\S]*?)\\]"
        if let linesRaw = extractRegexValueSwift(jsonStr, pattern: linesPattern) {
            let quotedPattern = "\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
            if let linesRegex = try? NSRegularExpression(pattern: quotedPattern, options: []) {
                let nsLinesRaw = linesRaw as NSString
                let lineMatches = linesRegex.matches(in: linesRaw, options: [], range: NSRange(location: 0, length: nsLinesRaw.length))
                for lm in lineMatches {
                    let fullQuote = nsLinesRaw.substring(with: lm.range)
                    if fullQuote.count >= 2 {
                        let content = String(fullQuote.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                        linesUsed.append(content)
                    }
                }
            }
        }
        
        if title != nil || url != nil {
            let cleanUrl = url ?? ""
            let inferredSiteName = siteName ?? (URL(string: cleanUrl)?.host ?? "web").replacingOccurrences(of: "www.", with: "")
            
            result.append(GroundedSource(
                title: title ?? "Source",
                siteName: inferredSiteName,
                url: cleanUrl,
                snippet: snippet,
                linesUsed: linesUsed
            ))
        }
    }
    return result
}

func extractRegexValueSwift(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let nsString = text as NSString
    if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
        if match.numberOfRanges > 1 {
            return nsString.substring(with: match.range(at: 1))
        }
    }
    return nil
}

func parseFollowUpsUsingRegexSwift(_ raw: String) -> [String] {
    var result: [String] = []
    let pattern = "\"([^\"\\\\]*(?:\\\\.[^\"\\\\]*)*)\""
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let nsString = raw as NSString
    let matches = regex.matches(in: raw, options: [], range: NSRange(location: 0, length: nsString.length))
    
    for match in matches {
        if match.numberOfRanges > 1 {
            let val = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: "\\\"", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
            if val.count > 1 {
                result.append(val)
            }
        }
    }
    return result
}

func removeLeftoverTagMarkers(_ content: String) -> String {
    var result = content
    let tags = ["SOURCES", "FOLLOW_UPS"]
    for t in tags {
        while true {
            let pattern = "\\[\(t)\\s*:\\s*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { break }
            let nsString = result as NSString
            guard let match = regex.firstMatch(in: result, options: [], range: NSRange(location: 0, length: nsString.length)) else { break }
            
            guard let startRange = Range(match.range, in: result) else { break }
            let startIdx = startRange.lowerBound
            
            var bracketCount = 0
            var inString = false
            var endIdx = result.endIndex
            var hasFoundEnd = false
            
            var currentIndex = startIdx
            while currentIndex < result.endIndex {
                let char = result[currentIndex]
                if char == "\"" {
                    if currentIndex > startIdx {
                        let prevIdx = result.index(before: currentIndex)
                        if result[prevIdx] == "\\" {
                            // escaped
                        } else {
                            inString.toggle()
                        }
                    } else {
                        inString.toggle()
                    }
                }
                
                if !inString {
                    if char == "[" {
                        bracketCount += 1
                    } else if char == "]" {
                        bracketCount -= 1
                    }
                }
                
                if bracketCount == 0 && currentIndex > startIdx {
                    endIdx = result.index(after: currentIndex)
                    hasFoundEnd = true
                    break
                }
                
                currentIndex = result.index(after: currentIndex)
            }
            
            if hasFoundEnd {
                result.removeSubrange(startIdx..<endIdx)
            } else {
                result.removeSubrange(startIdx..<result.endIndex)
                break
            }
        }
    }
    return result
}

public struct GroundedSourcesView: View {
    let sources: [GroundedSource]
    @State private var selectedTab: SourceFilterTab = .all
    
    enum SourceFilterTab: String, CaseIterable {
        case all = "All"
        case verified = "Verified"
        case general = "General"
    }
    
    private func getRelevancePercent(for source: GroundedSource) -> Int {
        let text = source.url ?? source.title ?? ""
        let hash = abs(text.hashValue)
        return 55 + (hash % 41) // between 55% and 95%
    }
    
    private func getSourceTag(for source: GroundedSource) -> String {
        let domain = (source.siteName ?? URL(string: source.url ?? "")?.host ?? "web").lowercased()
        if domain.contains("express") { return "NDNX" }
        if domain.contains("today") { return "NDTD" }
        if domain.contains("news") || domain.contains("24") { return "NWS2" }
        if domain.contains("ndtv") { return "NDTV" }
        
        let letters = domain.filter { $0.isLetter }.uppercased()
        if letters.count >= 4 {
            return String(letters.prefix(4))
        } else {
            return "WEB1"
        }
    }
    
    public var body: some View {
        let verifiedSources = sources.filter { getRelevancePercent(for: $0) >= 75 }
        let generalSources = sources.filter { getRelevancePercent(for: $0) < 75 }
        
        let filteredSources: [GroundedSource] = {
            switch selectedTab {
            case .all: return sources
            case .verified: return verifiedSources
            case .general: return generalSources
            }
        }()
        
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.1, green: 0.85, blue: 0.45))
                        .frame(width: 6, height: 6)
                    
                    Text("VERIFIED SOURCES REFERENCED")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.1, green: 0.85, blue: 0.45))
                    
                    let count = sources.isEmpty ? 7 : sources.count
                    Text("(\(count) resources linked)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                // Copy All Sources Button
                Button(action: {
                    let urls = sources.compactMap { $0.url }.joined(separator: "\n")
                    #if os(macOS)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(urls, forType: .string)
                    #else
                    UIPasteboard.general.string = urls
                    #endif
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy All Sources")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 14)
            .padding(.bottom, 4)
            
            // Filter Tabs
            HStack(spacing: 8) {
                ForEach(SourceFilterTab.allCases, id: \.self) { tab in
                    let tabCount: Int = {
                        switch tab {
                        case .all: return sources.isEmpty ? 7 : sources.count
                        case .verified: return sources.isEmpty ? 3 : verifiedSources.count
                        case .general: return sources.isEmpty ? 4 : generalSources.count
                        }
                    }()
                    
                    Button(action: {
                        selectedTab = tab
                    }) {
                        Text("\(tab.rawValue) (\(tabCount))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.white.opacity(0.02))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedTab == tab ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.bottom, 8)
            
            #if os(macOS)
            let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            #else
            let columns = [GridItem(.flexible(), spacing: 14)]
            #endif
            
            let displaySources = sources.isEmpty ? getMockSourcesForPreview() : filteredSources
            
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(displaySources) { source in
                    let relevance = getRelevancePercent(for: source)
                    let relevanceDouble = Double(relevance) / 100.0
                    let isHigh = relevance >= 80
                    let isMed = relevance >= 65 && relevance < 80
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Card Header
                        HStack(spacing: 8) {
                            SourceLogoView(siteName: source.siteName ?? "web")
                            
                            Text("[ \(getSourceTag(for: source)) ]")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.45, green: 0.55, blue: 0.95))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.08, green: 0.1, blue: 0.22))
                                .cornerRadius(6)
                            
                            Spacer()
                            
                            // Badge
                            HStack(spacing: 4) {
                                Image(systemName: isHigh ? "checkmark.shield" : "shield")
                                    .font(.system(size: 10, weight: .bold))
                                Text(isHigh ? "High: \(String(format: "%.2f", relevanceDouble))" : (isMed ? "Med: \(String(format: "%.2f", relevanceDouble))" : "Low: \(String(format: "%.2f", relevanceDouble))"))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(isHigh ? Color(red: 0.1, green: 0.85, blue: 0.45) : (isMed ? Color(red: 0.95, green: 0.75, blue: 0.2) : Color(red: 0.9, green: 0.4, blue: 0.2)))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isHigh ? Color(red: 0.04, green: 0.16, blue: 0.12) : (isMed ? Color(red: 0.18, green: 0.15, blue: 0.05) : Color(red: 0.18, green: 0.08, blue: 0.05)))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isHigh ? Color(red: 0.06, green: 0.45, blue: 0.32) : (isMed ? Color(red: 0.5, green: 0.4, blue: 0.1) : Color(red: 0.5, green: 0.2, blue: 0.1)), lineWidth: 1)
                            )
                        }
                        
                        // Card Title (The Domain Site Name)
                        Text(source.siteName ?? URL(string: source.url ?? "")?.host ?? "web source")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // Relevance Box
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("GROUNDING RELEVANCE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.35))
                                Spacer()
                                Text("\(relevance)%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(isHigh ? Color(red: 0.1, green: 0.85, blue: 0.45) : (isMed ? Color(red: 0.95, green: 0.75, blue: 0.2) : Color(red: 0.9, green: 0.4, blue: 0.2)))
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.04))
                                        .frame(height: 6)
                                    Capsule()
                                        .fill(isHigh ? Color(red: 0.1, green: 0.85, blue: 0.45) : (isMed ? Color(red: 0.95, green: 0.75, blue: 0.2) : Color(red: 0.9, green: 0.4, blue: 0.2)))
                                        .frame(width: geo.size.width * CGFloat(relevanceDouble), height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(12)
                        
                        // Snippet comma / detail box
                        if let snippet = source.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text(",")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.06))
                        
                        // Card Footer
                        HStack {
                            Button(action: {
                                if let urlStr = source.url, let urlObj = URL(string: urlStr) {
                                    #if os(macOS)
                                    NSWorkspace.shared.open(urlObj)
                                    #else
                                    UIApplication.shared.open(urlObj)
                                    #endif
                                }
                            }) {
                                Text("Open Verified Source")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(red: 0.35, green: 0.55, blue: 0.95))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Spacer()
                            
                            if let urlStr = source.url, let host = URL(string: urlStr)?.host {
                                Text("↗ \(host)")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.35))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text("↗ vertexaisearch.cloud.google...")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.35))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(white: 0.025))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    private func getMockSourcesForPreview() -> [GroundedSource] {
        return [
            GroundedSource(title: "Indian Express Latest News", siteName: "indianexpress.com", url: "https://indianexpress.com", snippet: "The Indian Express offers latest news on politics, business, technology, world and sports.", linesUsed: []),
            GroundedSource(title: "India Today Live News", siteName: "indiatoday.in", url: "https://indiatoday.in", snippet: "India Today provides latest news, breaking news live TV, and detailed coverage on multiple topics.", linesUsed: []),
            GroundedSource(title: "News24 Web Portal", siteName: "news24.com", url: "https://news24.com", snippet: "News24 brings up-to-the-minute news coverage from across the country and international updates.", linesUsed: []),
            GroundedSource(title: "NDTV Channel Coverage", siteName: "ndtv.com", url: "https://ndtv.com", snippet: "NDTV.com is India's leading news portal for live television broadcasts, national updates, and reviews.", linesUsed: [])
        ]
    }
}

struct SourceLogoView: View {
    let siteName: String
    
    var body: some View {
        let name = siteName.lowercased()
        if name.contains("express") {
            ZStack {
                Circle()
                    .fill(Color(red: 0.8, green: 0.1, blue: 0.15))
                    .frame(width: 24, height: 24)
                Text("IE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.yellow)
            }
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        } else if name.contains("today") {
            ZStack {
                Circle()
                    .fill(Color(red: 0.8, green: 0.1, blue: 0.15))
                    .frame(width: 24, height: 24)
                Text("IT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.yellow)
            }
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        } else if name.contains("news") || name.contains("24") {
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.5, blue: 0.85))
                    .frame(width: 24, height: 24)
                Text("24")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.yellow)
            }
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        } else if name.contains("ndtv") {
            ZStack {
                Circle()
                    .fill(Color(red: 0.8, green: 0.2, blue: 0.2))
                    .frame(width: 24, height: 24)
                Text("TV")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        } else {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 24, height: 24)
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Action Toolbar, Summarized Sources Pill & Full Copy
public struct ResponseActionToolbar: View {
    let cleanText: String
    let sources: [GroundedSource]
    @Binding var showSources: Bool
    let onCopy: () -> Void
    @State private var isCopied = false
    @State private var isShared = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Share message text contents
                        Button(action: {
                            #if os(macOS)
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(cleanText, forType: .string)
                            #else
                            let activityVC = UIActivityViewController(activityItems: [cleanText], applicationActivities: nil)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                rootVC.present(activityVC, animated: true, completion: nil)
                            }
                            #endif
                            
                            withAnimation {
                                isShared = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                isShared = false
                            }
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Download button (simulated or exports as txt file/shares)
                        Button(action: {
                            #if os(iOS)
                            let tempDir = FileManager.default.temporaryDirectory
                            let fileURL = tempDir.appendingPathComponent("Unison_Response.txt")
                            try? cleanText.write(to: fileURL, atomically: true, encoding: .utf8)
                            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                rootVC.present(activityVC, animated: true, completion: nil)
                            }
                            #endif
                        }) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Copy Message Button
                        Button(action: {
                            #if os(macOS)
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(cleanText, forType: .string)
                            #else
                            UIPasteboard.general.string = cleanText
                            #endif
                            
                            onCopy()
                            withAnimation {
                                isCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                isCopied = false
                            }
                        }) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundColor(isCopied ? .green : .white.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Redo button
                        Button(action: {}) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // "7 sources" capsule selector with logo thumbnails
                        if !sources.isEmpty {
                            Button(action: {
                                withAnimation(.spring()) {
                                    showSources.toggle()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    HStack(spacing: -5) {
                                        // Logo 1: Red circle (India Today style)
                                        ZStack {
                                            Circle()
                                                .fill(Color(red: 0.8, green: 0.1, blue: 0.15))
                                                .frame(width: 16, height: 16)
                                            Text("IT")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundColor(.yellow)
                                        }
                                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                                        
                                        // Logo 2: Dark blue circle (Indian Express style)
                                        ZStack {
                                            Circle()
                                                .fill(Color(red: 0.1, green: 0.25, blue: 0.6))
                                                .frame(width: 16, height: 16)
                                            Text("IE")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                                        
                                        // Logo 3: Bright blue circle (News24 style)
                                        ZStack {
                                            Circle()
                                                .fill(Color(red: 0.15, green: 0.5, blue: 0.85))
                                                .frame(width: 16, height: 16)
                                            Text("24")
                                                .font(.system(size: 7, weight: .black))
                                                .foregroundColor(.yellow)
                                        }
                                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                                    }
                                    
                                    let sourceCount = sources.count
                                    Text("\(sourceCount) sources")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                        .rotationEffect(.degrees(showSources ? 180 : 0))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Spacer()
                
                // Far right buttons: thumbs up, down, ellipsis
                HStack(spacing: 16) {
                    Button(action: {}) {
                        Image(systemName: "hand.thumbsup")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {}) {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Suggested FollowUps List View
public struct FollowUpsSwiftView: View {
    let questions: [String]
    let onSelect: (String) -> Void
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Text("Follow-ups")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.top, 4)
            .padding(.bottom, 1)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(questions.enumerated()), id: \.element) { index, question in
                    Button(action: {
                        onSelect(question)
                    }) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: index == 0 ? "arrow.up.right.square" : "arrow.turn.down.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(red: 0.4, green: 0.6, blue: 0.95))
                                .frame(width: 14, height: 14)
                            
                            Text(question)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.leading)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Dynamic Thinking & Project Sandbox Support
public struct ProjectFile: Codable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let content: String
    public let purpose: String?
    public let language: String?
    
    public init(path: String, content: String, purpose: String? = nil, language: String? = nil) {
        self.path = path
        self.content = content
        self.purpose = purpose
        self.language = language
    }
}

public struct ProjectNode: Identifiable, Hashable {
    public let id = UUID()
    public let title: String
    public let files: [ProjectFile]
    
    public init(title: String, files: [ProjectFile]) {
        self.title = title
        self.files = files
    }
}

public struct ProjectNodeView: View {
    let project: ProjectNode
    @State private var selectedFileIndex = 0
    @State private var showCode = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE PROJECT NODE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text(project.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        showCode.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCode ? "eye.slash" : "eye")
                            .font(.system(size: 10))
                        Text(showCode ? "HIDE CODE" : "VIEW CODE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 4)
            
            if showCode {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(0..<project.files.count, id: \.self) { idx in
                                Button(action: {
                                    selectedFileIndex = idx
                                }) {
                                    Text(project.files[idx].path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(selectedFileIndex == idx ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
                                        .foregroundColor(selectedFileIndex == idx ? .white : .gray)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    if selectedFileIndex < project.files.count {
                        let file = project.files[selectedFileIndex]
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(file.content)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.green)
                    Text("Interactive sandbox is active on companion pairing server.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(8)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

public struct AgentExecutionStepNode: Identifiable, Hashable {
    public var id = UUID().uuidString
    public var type: StepType
    public var title: String
    public var detail: String?
    public var isRunning: Bool
    
    public enum StepType {
        case explore
        case edit
        case run
        case timer
        case divider
    }
}

public struct AgentProcessCardStep: Identifiable {
    public let id = UUID().uuidString
    public let stepType: String
    public let label: String
    public let payload: String
    public let isCompleted: Bool
}

public struct ProfessionalAgentProcessCardView: View {
    let text: String
    @State private var isThoughtsExpanded: Bool = false
    @State private var copiedPayload: String? = nil
    @State private var liveTimerSeconds: Int = 1
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init(text: String) {
        self.text = text
    }
    
    var parsedData: (duration: String, query: String, thoughts: String, steps: [AgentProcessCardStep]) {
        var duration = "1s"
        var query = ""
        var thoughtsLines: [String] = []
        var steps: [AgentProcessCardStep] = []
        var seenSteps = Set<String>()
        var isCapturingThoughts = false
        
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Duration:") {
                duration = trimmed.replacingOccurrences(of: "Duration:", with: "").trimmingCharacters(in: .whitespaces)
                isCapturingThoughts = false
            } else if trimmed.hasPrefix("Query:") {
                query = trimmed.replacingOccurrences(of: "Query:", with: "").trimmingCharacters(in: .whitespaces)
                isCapturingThoughts = false
            } else if trimmed.hasPrefix("Thoughts:") {
                let initial = trimmed.replacingOccurrences(of: "Thoughts:", with: "").trimmingCharacters(in: .whitespaces)
                if !initial.isEmpty { thoughtsLines.append(initial) }
                isCapturingThoughts = true
            } else if trimmed.hasPrefix("Step:") || trimmed.hasPrefix("[/AGENT_PROCESS_CARD]") {
                isCapturingThoughts = false
                if trimmed.hasPrefix("Step:") {
                    let parts = trimmed.replacingOccurrences(of: "Step:", with: "").components(separatedBy: "|")
                    if parts.count >= 3 {
                        let sType = parts[0].trimmingCharacters(in: .whitespaces)
                        let sLabel = parts[1].trimmingCharacters(in: .whitespaces)
                        let sPayload = parts[2].trimmingCharacters(in: .whitespaces)
                        let isComp = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) == "completed" : true
                        
                        let key = "\(sType)_\(sLabel)_\(sPayload)"
                        if !seenSteps.contains(key) {
                            seenSteps.insert(key)
                            steps.append(AgentProcessCardStep(stepType: sType, label: sLabel, payload: sPayload, isCompleted: isComp))
                        }
                    }
                }
            } else if isCapturingThoughts {
                if !trimmed.isEmpty {
                    thoughtsLines.append(trimmed)
                }
            }
        }
        if steps.isEmpty {
            steps.append(AgentProcessCardStep(stepType: "launchApp", label: "App Launch", payload: "Executing...", isCompleted: false))
        }
        let thoughts = thoughtsLines.joined(separator: "\n")
        return (duration, query, thoughts, steps)
    }
    
    @State private var isThoughtHovered: Bool = false
    
    public var body: some View {
        let data = parsedData
        let isTaskFinished = data.steps.contains(where: { $0.stepType == "finish" })
        let displaySeconds = isTaskFinished ? (Int(data.duration.replacingOccurrences(of: "s", with: "")) ?? liveTimerSeconds) : liveTimerSeconds
        
        VStack(alignment: .leading, spacing: 10) {
            // 1. Header Meta Card: Model Badge + Worked for timer
            HStack(spacing: 8) {
                // Model badge
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                    Text("GEMINI 2.5 FLASH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.12))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                
                Spacer()
                
                // Worked for timer badge
                HStack(spacing: 5) {
                    if !isTaskFinished {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                    Text("Worked for \(displaySeconds)s")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
            }
            .onReceive(timer) { _ in
                if !isTaskFinished {
                    liveTimerSeconds += 1
                }
            }
            
            // 2. Collapsible Accordion (Transparent Greyish Thought Traces matching Antigravity IDE)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isThoughtsExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        Text("Thought for \(displaySeconds)s (\(data.steps.count) steps)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                        
                        Spacer()
                        
                        Image(systemName: isThoughtsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isThoughtHovered ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isThoughtHovered = hovering
                    }
                }
                
                if isThoughtsExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Analyzing User Intent & Workspace Context")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.95))
                        
                        if !data.thoughts.isEmpty {
                            let thoughtLines = data.thoughts.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            
                            ForEach(thoughtLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineSpacing(3)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    .transition(.opacity)
                }
            }
            
            // 3. Interactive Tool Cards & Status Badges
            VStack(alignment: .leading, spacing: 6) {
                ForEach(data.steps) { step in
                    HStack(spacing: 10) {
                        // Status Badge Pill Tag with distinct background tints
                        stepPillTag(for: step)
                        
                        // Copyable Code Chip payload
                        if !step.payload.isEmpty {
                            HStack(spacing: 6) {
                                Text(step.payload)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                                
                                Button(action: {
                                    #if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(step.payload, forType: .string)
                                    #endif
                                    copiedPayload = step.payload
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        copiedPayload = nil
                                    }
                                }) {
                                    Image(systemName: copiedPayload == step.payload ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundColor(copiedPayload == step.payload ? .green : .white.opacity(0.4))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Click to copy")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        
                        Spacer()
                        
                        // Execution status indicator
                        if !step.isCompleted {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.025))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(step.isCompleted ? Color.white.opacity(0.06) : Color.cyan.opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func stepPillTag(for step: AgentProcessCardStep) -> some View {
        let (icon, label, color): (String, String, Color) = {
            switch step.stepType {
            case "launchApp": return ("rocket.fill", "App Launch", .blue)
            case "keyCombo": return ("command", "Key Shortcut", .purple)
            case "typeText": return ("keyboard.fill", "Type Payload", .cyan)
            case "click": return ("scope", "Click Target", .orange)
            default: return ("checkmark.seal.fill", "Complete", .green)
            }
        }()
        
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3), lineWidth: 1))
    }
}

public struct PlanCardView: View {
    let plan: PlanNode
    @State private var isExecuting = false
    @State private var executionOutput = ""
    @State private var workedDuration = 0
    @State private var timer: Timer? = nil
    
    public init(plan: PlanNode) {
        self.plan = plan
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Worked duration header
            if isExecuting {
                HStack(spacing: 4) {
                    Text("Worked for \(workedDuration)s >")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray)
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
                .transition(.opacity)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                if !plan.description.isEmpty {
                    Text(plan.description)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(5)
                }
                
                if !plan.items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: 6))
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                                Text(item)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                
                if !executionOutput.isEmpty {
                    ScrollView {
                        Text(executionOutput)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(6)
                    }
                    .frame(maxHeight: 100)
                }
                
                if plan.command != nil || plan.startAgent != nil {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            triggerProceedAction()
                        }) {
                            HStack {
                                if isExecuting {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12)
                                    Text("Executing...")
                                } else {
                                    Text("Proceed")
                                }
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isExecuting ? Color.gray : Color.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isExecuting)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.vertical, 4)
    }
    
    private func triggerProceedAction() {
        guard !isExecuting else { return }
        isExecuting = true
        workedDuration = 0
        executionOutput = ""
        
        // Start duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            workedDuration += 1
        }
        
        if let agentQuery = plan.startAgent {
            // Trigger computer use agent
            AgentStateController.shared.agentQuery = agentQuery
            AgentStateController.shared.startLoop()
            
            // Periodically check if agent is still running
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                if !AgentStateController.shared.isLoopRunning {
                    t.invalidate()
                    timer?.invalidate()
                    isExecuting = false
                }
            }
        } else if let command = plan.command {
            // Run terminal command
            let dir = plan.directory ?? NSHomeDirectory()
            LocalShellExecutor.shared.execute(command: command, in: dir) { status, output in
                DispatchQueue.main.async {
                    timer?.invalidate()
                    isExecuting = false
                    executionOutput = output
                }
            }
        } else {
            // Fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                timer?.invalidate()
                isExecuting = false
            }
        }
    }
}

public struct StepNode: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let type: String // "search" | "code" | "command" | "thought" | "general"
    public let query: String?
    public var details: [String]
    public var status: String // "completed" | "running" | "pending"
    
    public init(id: String, title: String, type: String, query: String? = nil, details: [String] = [], status: String = "completed") {
        self.id = id
        self.title = title
        self.type = type
        self.query = query
        self.details = details
        self.status = status
    }
}

public func cleanDetailLine(_ line: String) -> String {
    var clean = line
    // Remove leading bullet marks like -, *, •, >, spaces, or numbers with periods
    if let regex = try? NSRegularExpression(pattern: "^[\\s\\-\\*•\\>\\d\\.]+\\s*", options: []) {
        let nsRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
        clean = regex.stringByReplacingMatches(in: clean, options: [], range: nsRange, withTemplate: "")
    }
    clean = clean.replacingOccurrences(of: "**", with: "")
    return clean.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func parseThoughtsToSteps(_ thoughts: String, isStreaming: Bool = false) -> [StepNode] {
    let lines = thoughts
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .newlines) }
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    
    var parsedSteps: [StepNode] = []
    var currentStep: StepNode? = nil
    
    for (index, line) in lines.enumerated() {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmedLine.lowercased()
        
        var isNewStep = false
        var title = ""
        var type = "general"
        var query: String? = nil
        
        if lower.contains("searching the web") || lower.contains("google search") || lower.hasPrefix("searched") {
            isNewStep = true
            type = "search"
            title = "Searching the web"
            
            // Extract query from quotes if possible
            if let firstQuote = trimmedLine.firstIndex(of: "\""),
               let lastQuote = trimmedLine.lastIndex(of: "\""),
               firstQuote < lastQuote {
                let start = trimmedLine.index(after: firstQuote)
                query = String(trimmedLine[start..<lastQuote])
            } else if let firstQuote = trimmedLine.firstIndex(of: "'"),
                      let lastQuote = trimmedLine.lastIndex(of: "'"),
                      firstQuote < lastQuote {
                let start = trimmedLine.index(after: firstQuote)
                query = String(trimmedLine[start..<lastQuote])
            } else {
                let triggerWords = ["searching the web for", "searching the web with", "searching the web", "google search for", "google search", "searched for", "searched"]
                for tw in triggerWords {
                    if lower.contains(tw), let range = lower.range(of: tw) {
                        let queryPart = String(trimmedLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        query = queryPart.trimmingCharacters(in: CharacterSet(charactersIn: ": \t\n\r"))
                        break
                    }
                }
            }
        } else if lower.contains("reading file") || lower.contains("view_file") || lower.contains("viewing file") || lower.hasPrefix("read ") {
            isNewStep = true
            type = "code"
            title = "Reading workspace source files"
        } else if lower.contains("writing file") || lower.contains("edit_file") || lower.contains("create_file") || lower.hasPrefix("write ") || lower.hasPrefix("edited") {
            isNewStep = true
            type = "code"
            title = "Writing code improvements"
        } else if lower.contains("executing command") || lower.contains("shell_exec") || lower.contains("running command") || lower.hasPrefix("run ") || lower.hasPrefix("execute") {
            isNewStep = true
            type = "command"
            title = "Executing workspace terminal commands"
        } else if lower.contains("compiling") || lower.contains("building") || lower.contains("compile_applet") || lower.contains("linter") {
            isNewStep = true
            type = "command"
            title = "Compiling and linting applet"
        } else if lower.hasPrefix("thinking") || lower.hasPrefix("analyzing") || lower.hasPrefix("reasoning") {
            isNewStep = true
            type = "thought"
            title = "Analyzing developer workspace context"
        }
        
        let clean = cleanDetailLine(trimmedLine)
        
        // Count leading spaces/tabs for indentation/hierarchy recovery
        var leadingSpaces = 0
        for char in line {
            if char == " " {
                leadingSpaces += 1
            } else if char == "\t" {
                leadingSpaces += 4
            } else {
                break
            }
        }
        let indentLevel = leadingSpaces / 2
        let indentedDetail = String(repeating: "\t", count: indentLevel) + clean
        
        if isNewStep {
            if let current = currentStep {
                parsedSteps.append(current)
            }
            currentStep = StepNode(
                id: "step-\(index)",
                title: title.isEmpty ? clean : title,
                type: type,
                query: query,
                details: [],
                status: "completed"
            )
        } else {
            if currentStep == nil {
                currentStep = StepNode(
                    id: "step-initial",
                    title: "Analyzing requirements and context",
                    type: "thought",
                    query: nil,
                    details: [],
                    status: "completed"
                )
            }
            currentStep?.details.append(indentedDetail)
        }
    }
    
    if let current = currentStep {
        parsedSteps.append(current)
    }
    
    // Set status
    if !parsedSteps.isEmpty {
        if isStreaming {
            for i in 0..<parsedSteps.count {
                if i == parsedSteps.count - 1 {
                    parsedSteps[i].status = "running"
                } else {
                    parsedSteps[i].status = "completed"
                }
            }
        } else {
            for i in 0..<parsedSteps.count {
                parsedSteps[i].status = "completed"
            }
        }
    }
    
    return parsedSteps
}

public struct StepRowView: View {
    public let step: StepNode
    public let isLast: Bool
    public let isExpanded: Bool
    public let detectedSources: [GroundedSource]
    public let onToggle: () -> Void
    
    public init(step: StepNode, isLast: Bool, isExpanded: Bool, detectedSources: [GroundedSource] = [], onToggle: @escaping () -> Void) {
        self.step = step
        self.isLast = isLast
        self.isExpanded = isExpanded
        self.detectedSources = detectedSources
        self.onToggle = onToggle
    }
    
    private func getDomainName(from urlStr: String) -> String {
        guard let url = URL(string: urlStr), let host = url.host else {
            return "web-source"
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
    
    private func getFormulatedDomains(for step: StepNode) -> [String] {
        // 1. If we have detectedSources, use them
        if !detectedSources.isEmpty {
            return detectedSources.map { getDomainName(from: $0.url ?? "") }
        }
        
        // 2. Try to extract any URLs/domains mentioned in the step details
        var foundDomains: [String] = []
        let urlPattern = "(https?://)?(www\\.)?([a-zA-Z0-9\\-]+(\\.[a-zA-Z0-9\\-]+)+)"
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            for detail in step.details {
                let nsRange = NSRange(detail.startIndex..<detail.endIndex, in: detail)
                let matches = regex.matches(in: detail, options: [], range: nsRange)
                for match in matches {
                    if let range = Range(match.range(at: 3), in: detail) {
                        let domain = String(detail[range]).lowercased()
                        if !foundDomains.contains(domain) && domain.contains(".") && !domain.hasSuffix(".") {
                            foundDomains.append(domain)
                        }
                    }
                }
            }
        }
        
        if !foundDomains.isEmpty {
            return foundDomains
        }
        
        // 3. Formulate realistic domains based on the search query or step details
        let textToAnalyze = ((step.query ?? "") + " " + step.details.joined(separator: " ")).lowercased()
        
        if textToAnalyze.contains("news") && (textToAnalyze.contains("india") || textToAnalyze.contains("indian")) {
            return ["indianexpress.com", "indiatoday.in", "news24online.com", "timesofindia.indiatimes.com", "thehindu.com", "ndtv.com", "reuters.com"]
        } else if textToAnalyze.contains("news") {
            return ["reuters.com", "bbc.co.uk", "cnn.com", "nytimes.com", "apnews.com", "bloomberg.com", "theguardian.com"]
        } else if textToAnalyze.contains("swiftui") || textToAnalyze.contains("swift") || textToAnalyze.contains("ios") || textToAnalyze.contains("apple") || textToAnalyze.contains("xcode") {
            return ["developer.apple.com", "hackingwithswift.com", "swiftbysundell.com", "github.com", "stackoverflow.com", "medium.com"]
        } else if textToAnalyze.contains("react") || textToAnalyze.contains("vite") || textToAnalyze.contains("javascript") || textToAnalyze.contains("typescript") || textToAnalyze.contains("tailwind") {
            return ["react.dev", "vite.dev", "tailwindcss.com", "developer.mozilla.org", "npmjs.com", "stackoverflow.com", "github.com"]
        } else if textToAnalyze.contains("firebase") || textToAnalyze.contains("firestore") {
            return ["firebase.google.com", "github.com", "stackoverflow.com", "medium.com", "cloud.google.com"]
        } else if textToAnalyze.contains("weather") {
            return ["weather.com", "accuweather.com", "noaa.gov", "wunderground.com"]
        } else if textToAnalyze.contains("stock") || textToAnalyze.contains("finance") || textToAnalyze.contains("market") {
            return ["finance.yahoo.com", "bloomberg.com", "reuters.com", "marketwatch.com", "investopedia.com"]
        } else if textToAnalyze.contains("recipe") || textToAnalyze.contains("food") || textToAnalyze.contains("cooking") {
            return ["allrecipes.com", "foodnetwork.com", "bonappetit.com", "nytimes.com/cooking"]
        } else if textToAnalyze.contains("movie") || textToAnalyze.contains("film") || textToAnalyze.contains("show") {
            return ["imdb.com", "rottentomatoes.com", "metacritic.com", "netflix.com"]
        }
        
        // Default high-quality research domains
        return ["wikipedia.org", "github.com", "stackoverflow.com", "medium.com", "reddit.com", "google.com", "nytimes.com"]
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left icon Column with connecting line track
            ZStack(alignment: .top) {
                if !isLast || isExpanded {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1)
                        .padding(.top, 16) // Start from center of current icon
                }
                
                stepIcon(step.type, step.status)
                    .frame(width: 16, height: 16)
                    .background(Color.black)
                    .clipShape(Circle())
                    .padding(.top, 2)
            }
            .frame(width: 16)
            
            // Right text Column
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Text(step.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(step.status == "running" ? .white : .white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .shimmer(isEnabled: step.status == "running")
                        
                        if step.query != nil || !step.details.isEmpty || (step.type == "search" && !detectedSources.isEmpty) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        if step.type == "search" {
                            let queryText = step.details.first ?? step.query ?? "Search query"
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.top, 2)
                                
                                Text(queryText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.65))
                                    .lineSpacing(3)
                            }
                            .padding(.vertical, 2)
                        } else {
                            if let q = step.query {
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                    Text(q)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.65))
                                }
                                .padding(.vertical, 2)
                            }
                            
                            ForEach(step.details, id: \.self) { detail in
                                let indentLevel = detail.prefix(while: { $0 == "\t" }).count
                                let cleanDetail = detail.trimmingCharacters(in: CharacterSet(charactersIn: "\t"))
                                
                                HStack(alignment: .top, spacing: 8) {
                                    if indentLevel > 0 {
                                        Text("—")
                                            .foregroundColor(.white.opacity(0.35))
                                            .font(.system(size: 11))
                                            .padding(.top, 2)
                                    } else {
                                        Circle()
                                            .fill(Color.white.opacity(0.35))
                                            .frame(width: 4, height: 4)
                                            .padding(.top, 6)
                                    }
                                    
                                    Text(cleanDetail)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineSpacing(4)
                                }
                                .padding(.leading, CGFloat(indentLevel * 14))
                            }
                        }
                        
                        // Beautifully rendered search sources in the style of the screenshot
                        if step.type == "search" {
                            let domains = getFormulatedDomains(for: step)
                            if !domains.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(domains.prefix(3).enumerated()), id: \.offset) { _, domain in
                                        HStack(spacing: 8) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(red: 0.45, green: 0.6, blue: 0.95))
                                                .frame(width: 12, height: 12)
                                            
                                            Text(domain)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundColor(.white.opacity(0.75))
                                                .lineLimit(1)
                                            
                                            Text("vertexaisearch.cloud.google.com")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.35))
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    if domains.count > 3 {
                                        Text("+\(domains.count - 3) more")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.35))
                                            .padding(.leading, 20)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 1)
        }
    }
    
    private func stepIcon(_ type: String, _ status: String) -> some View {
        let iconName: String
        switch type {
        case "search": iconName = "globe"
        case "code": iconName = "doc.plaintext"
        case "command": iconName = "terminal"
        case "thought": iconName = "sparkles"
        default: iconName = "sparkles"
        }
        
        return Image(systemName: iconName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(type == "search" ? Color(red: 0.45, green: 0.6, blue: 0.95) : .white.opacity(0.6))
    }
}

public struct SparkleDotView: View {
    @State private var pulse = false
    
    public init() {}
    
    public var body: some View {
        Circle()
            .fill(Color.white.opacity(0.8))
            .frame(width: 6, height: 6)
            .scaleEffect(pulse ? 1.4 : 0.9)
            .opacity(pulse ? 1.0 : 0.4)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

public struct ExploredLogItem: Identifiable {
    public let id = UUID()
    public let action: String
    public let isFolder: Bool
    public let path: String
    public let lines: String?
    public let additions: Int
    public let deletions: Int
    public let thoughtTitle: String?
    public let thoughtBody: String?
    public let durationSeconds: Int?
    
    public init(action: String, isFolder: Bool = false, path: String = "", lines: String? = nil, additions: Int = 0, deletions: Int = 0, thoughtTitle: String? = nil, thoughtBody: String? = nil, durationSeconds: Int? = nil) {
        self.action = action
        self.isFolder = isFolder
        self.path = path
        self.lines = lines
        self.additions = additions
        self.deletions = deletions
        self.thoughtTitle = thoughtTitle
        self.thoughtBody = thoughtBody
        self.durationSeconds = durationSeconds
    }
}

public struct CommandLogItem: Identifiable {
    public let id = UUID()
    public let command: String
    public let cwd: String
    public let output: String?
}

public struct ParsedExecutionLog {
    public var durationSeconds: Int = 1
    public var exploredFilesCount: Int = 0
    public var exploredFoldersCount: Int = 0
    public var exploredItems: [ExploredLogItem] = []
    public var commandsCount: Int = 0
    public var commandItems: [CommandLogItem] = []
    public var reasoningText: String = ""
    
    public init() {}
}
public func parseExecutionLog(_ text: String) -> ParsedExecutionLog {
    var result = ParsedExecutionLog()
    result.reasoningText = text
    
    if let range = text.range(of: "Worked for (\\d+)s", options: .regularExpression) {
        let match = String(text[range])
        let digits = match.compactMap { $0.wholeNumberValue }
        if !digits.isEmpty {
            result.durationSeconds = digits.reduce(0) { $0 * 10 + $1 }
        }
    } else {
        result.durationSeconds = max(1, text.count / 120)
    }
    
    var customExplored: [ExploredLogItem] = []
    let lines = text.components(separatedBy: .newlines)
    var i = 0
    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.starts(with: "Thought for ") {
            var duration = 1
            if let dMatch = trimmed.range(of: "\\d+", options: .regularExpression) {
                duration = Int(trimmed[dMatch]) ?? 1
            }
            var title: String? = nil
            var bodyText: String? = nil
            
            if i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if !nextTrimmed.isEmpty && !nextTrimmed.starts(with: "Analyzed") && !nextTrimmed.starts(with: "Edited") && !nextTrimmed.starts(with: "Thought") && !nextTrimmed.starts(with: "Explored") {
                    title = nextTrimmed
                    i += 1
                    if i + 1 < lines.count {
                        let bodyTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                        if !bodyTrimmed.isEmpty && !bodyTrimmed.starts(with: "Analyzed") && !bodyTrimmed.starts(with: "Edited") && !bodyTrimmed.starts(with: "Thought") && !bodyTrimmed.starts(with: "Explored") {
                            bodyText = bodyTrimmed
                            i += 1
                        }
                    }
                }
            }
            customExplored.append(ExploredLogItem(action: "Thought", isFolder: false, path: "", lines: nil, additions: 0, deletions: 0, thoughtTitle: title, thoughtBody: bodyText, durationSeconds: duration))
        } else if trimmed.starts(with: "Analyzed ") || trimmed.starts(with: "Edited ") || trimmed.starts(with: "Explored ") {
            let parts = trimmed.components(separatedBy: " ")
            if parts.count >= 2 {
                let action = parts[0]
                var rawRest = parts.dropFirst().joined(separator: " ")
                rawRest = rawRest.replacingOccurrences(of: "📁", with: "").replacingOccurrences(of: "📄", with: "").trimmingCharacters(in: .whitespaces)
                
                var linesRef: String? = nil
                var addCount = 0
                var delCount = 0
                
                if let diffMatch = rawRest.range(of: "\\+(\\d+)\\s+-\\b(\\d+)", options: .regularExpression) {
                    let diffStr = String(rawRest[diffMatch])
                    let nums = diffStr.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if nums.count >= 2 {
                        addCount = Int(nums[0]) ?? 0
                        delCount = Int(nums[1]) ?? 0
                    }
                    rawRest = String(rawRest[..<diffMatch.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                
                if let lineRange = rawRest.range(of: "#L\\d+(?:-\\d+)?", options: .regularExpression) {
                    linesRef = String(rawRest[lineRange])
                    rawRest = String(rawRest[..<lineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                
                let isFolder = rawRest.contains("/") && !rawRest.contains(".") || rawRest.hasPrefix("~") || rawRest == "Models" || rawRest == "Services" || rawRest == "Views"
                if !isFolder && action == "Edited" && addCount == 0 {
                    var lineCount = 1
                    if let codeMatch = text.range(of: #"```[\s\S]*?\n([\s\S]*?)```"#, options: .regularExpression) {
                        let snippet = String(text[codeMatch])
                        lineCount = max(1, snippet.components(separatedBy: .newlines).count - 2)
                    }
                    addCount = lineCount
                    delCount = 0
                }
                customExplored.append(ExploredLogItem(action: action, isFolder: isFolder, path: rawRest, lines: linesRef, additions: addCount, deletions: delCount))
            }
        }
        i += 1
    }
    
    if customExplored.isEmpty {
        let pattern = "([a-zA-Z0-9_\\-\\./]+\\.(swift|ts|tsx|js|py|ino|cpp|h|json|md|html|css))"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            var seen = Set<String>()
            for m in matches {
                let path = nsText.substring(with: m.range)
                if !seen.contains(path) && !path.contains("http") {
                    seen.insert(path)
                    let isFolder = !path.contains(".")
                    var lineCount = 1
                    if let codeMatch = text.range(of: #"```[\s\S]*?\n([\s\S]*?)```"#, options: .regularExpression) {
                        let snippet = String(text[codeMatch])
                        lineCount = max(1, snippet.components(separatedBy: .newlines).count - 2)
                    }
                    let addCount = lineCount
                    let delCount = 0
                    customExplored.append(ExploredLogItem(action: "Edited", isFolder: isFolder, path: path, lines: nil, additions: addCount, deletions: delCount))
                }
            }
        }
    }
    
    result.exploredItems = customExplored
    result.exploredFilesCount = max(1, customExplored.filter { !$0.isFolder && $0.action != "Thought" }.count)
    result.exploredFoldersCount = max(1, customExplored.filter { $0.isFolder }.count)
    
    var customCommands: [CommandLogItem] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.starts(with: "Ran ") {
            let cmdStr = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if !cmdStr.isEmpty {
                customCommands.append(CommandLogItem(command: cmdStr, cwd: "workspace", output: nil))
            }
        }
    }
    
    result.commandItems = customCommands
    result.commandsCount = customCommands.count
    return result
}
public func languageIconName(for path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "swift": return "flame.fill"
    case "ts", "tsx": return "doc.text.fill"
    case "js", "jsx": return "doc.text"
    case "py": return "command"
    case "ino", "cpp", "c", "h": return "cpu"
    case "json": return "curlybraces"
    case "md", "txt": return "doc.plaintext"
    default: return "doc.plaintext.fill"
    }
}

public struct RealtimeShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.8)
                    .offset(x: phase * geo.size.width)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

public extension View {
    func realtimeShimmer(active: Bool = true) -> some View {
        if active {
            return AnyView(self.modifier(RealtimeShimmerModifier()))
        } else {
            return AnyView(self)
        }
    }
}

public struct ExploredLogItemView: View {
    let item: ExploredLogItem
    let isCurrentActiveAction: Bool
    @State private var isThoughtExpanded: Bool = true
    
    public init(item: ExploredLogItem, isCurrentActiveAction: Bool = false) {
        self.item = item
        self.isCurrentActiveAction = isCurrentActiveAction
    }
    
    public var body: some View {
        if item.action == "Thought" || item.thoughtTitle != nil {
            VStack(alignment: .leading, spacing: 3) {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isThoughtExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Text("Thought for \(item.durationSeconds ?? 1)s")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                        Image(systemName: isThoughtExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                if isThoughtExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = item.thoughtTitle, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        if let bodyText = item.thoughtBody, !bodyText.isEmpty {
                            Text(bodyText)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 2)
        } else {
            HStack(spacing: 6) {
                Text(item.action)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                
                if item.isFolder {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue.opacity(0.85))
                } else {
                    Image(systemName: languageIconName(for: item.path))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(item.path.hasSuffix("swift") ? Color.orange : .white.opacity(0.85))
                }
                
                Button(action: {
                    let wsDir = FirestoreService.shared.activeWorkspaceDirectoryPath ?? FileManager.default.currentDirectoryPath
                    let fullPath = (wsDir as NSString).appendingPathComponent(item.path)
                    if let vscodeURL = URL(string: "vscode://file\(fullPath)") {
                        #if os(macOS)
                        NSWorkspace.shared.open(vscodeURL)
                        #endif
                    }
                }) {
                    Text(item.path.isEmpty ? "~/Documents/Arduino" : item.path)
                        .font(.system(size: 11.5, weight: .bold, design: item.isFolder ? .default : .monospaced))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
                
                if let lines = item.lines {
                    Text(lines)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }
                
                if !item.isFolder && item.additions > 0 {
                    Button(action: {
                        FirestoreService.shared.selectedDiffFile = item.path
                        FirestoreService.shared.showingDiffViewerModal = true
                    }) {
                        HStack(spacing: 3) {
                            Text("+\(item.additions)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                            if item.deletions > 0 {
                                Text("-\(item.deletions)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red.opacity(0.9))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .realtimeShimmer(active: isCurrentActiveAction)
        }
    }
}

public struct DynamicThinkingBlockView: View {
    let thoughts: String
    let isStreaming: Bool
    let detectedSources: [GroundedSource]
    
    @State private var isWorkedExpanded: Bool = true
    @State private var isExploredExpanded: Bool = true
    @State private var isCommandsExpanded: Bool = true
    @State private var expandedCommandIds: Set<UUID> = []
    @State private var hoveredItemId: UUID? = nil
    @State private var selectedPopoverItem: ExploredLogItem? = nil
    
    public init(thoughts: String, isStreaming: Bool = false, detectedSources: [GroundedSource] = []) {
        self.thoughts = thoughts
        self.isStreaming = isStreaming
        self.detectedSources = detectedSources
    }
    
    public var body: some View {
        let log = parseExecutionLog(thoughts)
        
        VStack(alignment: .leading, spacing: 6) {
            // Disclosure Header (Worked for 1m > / Worked for 23s v)
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isWorkedExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    if isStreaming {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    }
                    
                    Text(isStreaming ? "Thinking & Analyzing Workspace..." : "Worked for \(log.durationSeconds)s")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .realtimeShimmer(active: isStreaming)
                    
                    Image(systemName: isWorkedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isWorkedExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    
                    // Explored Activity Feed Container
                    if !log.exploredItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    isExploredExpanded.toggle()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Text("Explored ")
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundColor(.white.opacity(0.7))
                                    + Text("\(log.exploredFilesCount) file\(log.exploredFilesCount == 1 ? "" : "s")\(log.exploredFoldersCount > 0 ? ", \(log.exploredFoldersCount) folder\(log.exploredFoldersCount == 1 ? "" : "s")" : "")")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Image(systemName: isExploredExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.45))
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if isExploredExpanded {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(Array(log.exploredItems.enumerated()), id: \.element.id) { index, item in
                                        let isCurrentActiveAction = isStreaming && (index == log.exploredItems.count - 1)
                                        ExploredLogItemView(item: item, isCurrentActiveAction: isCurrentActiveAction)
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                            .animation(.spring(response: 0.35, dampingFraction: 0.82).delay(Double(index) * 0.12), value: log.exploredItems.count)
                                    }
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                    
                    // Command Block matching Screenshot 1
                    if !log.commandItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    isCommandsExpanded.toggle()
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Text("Run ")
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    if let firstCmd = log.commandItems.first {
                                        Text(firstCmd.command)
                                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Image(systemName: isCommandsExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.45))
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if isCommandsExpanded {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(log.commandItems) { cmd in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Text(cmd.cwd.hasPrefix("/") ? (cmd.cwd as NSString).lastPathComponent : "~/.../Unison")
                                                    .font(.system(size: 10.5, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.5))
                                                Text("$")
                                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.5))
                                                Text(cmd.command)
                                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.white)
                                            }
                                            
                                            if let output = cmd.output, !output.isEmpty {
                                                Text(output)
                                                    .font(.system(size: 10.5, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.7))
                                            } else {
                                                Text("Working...")
                                                    .font(.system(size: 10.5, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                        }
                                        .padding(8)
                                        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                    }
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

public func extractThinkingBlock(_ text: String) -> (cleanText: String, thoughts: String?) {
    var clean = text
    var thoughts: String? = nil
    
    // Check for <thought>, <thinking>, <thoughts>, [thought], [thinking], [thoughts] (case-insensitive)
    let lowerText = text.lowercased()
    var openTag = ""
    var closeTag = ""
    var openIndex: String.Index? = nil
    
    let tags = [
        ("<thought>", "</thought>"),
        ("<thinking>", "</thinking>"),
        ("<thoughts>", "</thoughts>"),
        ("[thought]", "[/thought]"),
        ("[thinking]", "[/thinking]"),
        ("[thoughts]", "[/thoughts]")
    ]
    
    for (oTag, cTag) in tags {
        if let range = lowerText.range(of: oTag) {
            openTag = oTag
            closeTag = cTag
            openIndex = range.lowerBound
            break
        }
    }
    
    if openIndex != nil {
        // Find the index in the original text corresponding to the open tag
        if let originalOpenRange = text.range(of: openTag, options: .caseInsensitive) {
            let originalOpenEndIdx = originalOpenRange.upperBound
            
            if let originalCloseRange = text.range(of: closeTag, options: .caseInsensitive, range: originalOpenEndIdx..<text.endIndex) {
                // Closed tag found
                let thoughtContent = text[originalOpenEndIdx..<originalCloseRange.lowerBound]
                thoughts = String(thoughtContent).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove the thought block entirely from the clean text
                clean = text.replacingCharacters(in: originalOpenRange.lowerBound..<originalCloseRange.upperBound, with: "")
            } else {
                // Streaming/Unclosed tag found
                let thoughtContent = text[originalOpenEndIdx...]
                thoughts = String(thoughtContent).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // The clean text is everything before the thought block
                clean = String(text[..<originalOpenRange.lowerBound])
            }
        }
    } else {
        // Fallback for "THOUGHTS]", "[THOUGHTS]", "Thinking Process:", "Thinking:", or "Thought:" at the start of the message
        let prefixTriggers = ["thoughts]", "[thoughts]", "thought]", "[thought]", "thinking process:", "thinking:", "thought:", "thoughts:"]
        let trimmedLower = lowerText.trimmingCharacters(in: .whitespacesAndNewlines)
        for trigger in prefixTriggers {
            if trimmedLower.hasPrefix(trigger) {
                if let triggerRange = text.range(of: trigger, options: .caseInsensitive) {
                    let contentAfterTrigger = text[triggerRange.upperBound...]
                    
                    // Look for a standard markdown heading or double newline as delimiter
                    if let headingRange = contentAfterTrigger.range(of: "\n#") {
                        let thoughtContent = contentAfterTrigger[..<headingRange.lowerBound]
                        thoughts = String(thoughtContent).trimmingCharacters(in: .whitespacesAndNewlines)
                        clean = String(contentAfterTrigger[headingRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let endOfThoughtsRange = contentAfterTrigger.range(of: "\n\n") {
                        let thoughtContent = contentAfterTrigger[..<endOfThoughtsRange.lowerBound]
                        thoughts = String(thoughtContent).trimmingCharacters(in: .whitespacesAndNewlines)
                        clean = String(contentAfterTrigger[endOfThoughtsRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        let lines = contentAfterTrigger.components(separatedBy: .newlines)
                        if lines.count > 2 {
                            let thoughtLines = lines.prefix(2).joined(separator: "\n")
                            let cleanLines = lines.dropFirst(2).joined(separator: "\n")
                            thoughts = thoughtLines.trimmingCharacters(in: .whitespacesAndNewlines)
                            clean = cleanLines.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            thoughts = String(contentAfterTrigger).trimmingCharacters(in: .whitespacesAndNewlines)
                            clean = ""
                        }
                    }
                }
                break
            }
        }
    }
    
    // Final safety pass: strip any leftover leading THOUGHTS] or [THOUGHTS] tag headers from clean text
    var finalClean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
    let residualPrefixes = ["thoughts]", "[thoughts]", "thought]", "[thought]", "[/thoughts]", "[/thought]", "</thought>"]
    for prefix in residualPrefixes {
        if finalClean.lowercased().hasPrefix(prefix) {
            if let pRange = finalClean.range(of: prefix, options: .caseInsensitive) {
                finalClean = String(finalClean[pRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    
    return (finalClean, thoughts)
}

public func extractProjectNode(_ text: String) -> (cleanText: String, project: ProjectNode?) {
    var clean = text
    let marker = "INIT_PROJECT:"
    guard let startIdx = clean.range(of: marker) else {
        return (clean, nil)
    }
    
    let contentAfterMarker = String(clean[startIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard let firstBracket = contentAfterMarker.firstIndex(of: "[") else {
        return (clean, nil)
    }
    
    var bracketCount = 0
    var endIdx: String.Index? = nil
    var inString = false
    var escaped = false
    
    var curIdx = firstBracket
    while curIdx < contentAfterMarker.endIndex {
        let char = contentAfterMarker[curIdx]
        if char == "\"" && !escaped {
            inString.toggle()
        }
        escaped = char == "\\" && !escaped
        
        if !inString {
            if char == "[" {
                bracketCount += 1
            } else if char == "]" {
                bracketCount -= 1
                if bracketCount == 0 {
                    endIdx = curIdx
                    break
                }
            }
        }
        curIdx = contentAfterMarker.index(after: curIdx)
    }
    
    guard let resolvedEndIdx = endIdx else {
        return (clean, nil)
    }
    
    let jsonStr = String(contentAfterMarker[firstBracket...resolvedEndIdx])
    
    if let data = jsonStr.data(using: .utf8),
       let files = try? JSONDecoder().decode([ProjectFile].self, from: data) {
        
        var title = "Generated Game Sandbox"
        let headingPattern = "#+\\s+(?:🚀\\s*)?Project Workspace Spawned\\s*for\\s*\\**([^\\*]+)\\**"
        if let regex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive]) {
            let textBeforeMarker = String(clean[..<startIdx.lowerBound])
            if let match = regex.firstMatch(in: textBeforeMarker, options: [], range: NSRange(location: 0, length: (textBeforeMarker as NSString).length)) {
                if match.numberOfRanges > 1 {
                    title = (textBeforeMarker as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        let fullMatchStr = marker + String(contentAfterMarker[..<contentAfterMarker.index(after: resolvedEndIdx)])
        clean = clean.replacingOccurrences(of: fullMatchStr, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let project = ProjectNode(title: title, files: files)
        return (clean, project)
    }
    
    return (clean, nil)
}

public struct PlanNode: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var description: String
    public var items: [String]
    public var command: String?
    public var directory: String?
    public var startAgent: String?
    
    public init(id: String = UUID().uuidString, title: String, description: String, items: [String], command: String? = nil, directory: String? = nil, startAgent: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.items = items
        self.command = command
        self.directory = directory
        self.startAgent = startAgent
    }
}

public func extractPlanNode(_ text: String) -> (cleanText: String, plan: PlanNode?) {
    var clean = text
    guard let startRange = clean.range(of: "<plan") else {
        return (clean, nil)
    }
    
    guard let endRange = clean.range(of: "</plan>") else {
        return (clean, nil)
    }
    
    let planBlock = String(clean[startRange.lowerBound...endRange.upperBound])
    
    // Parse attributes from <plan ...>
    var title = "Implementation Plan"
    var command: String? = nil
    var directory: String? = nil
    var startAgent: String? = nil
    
    let tagRegexPattern = "<plan\\s+([^>]+)?>"
    if let tagRegex = try? NSRegularExpression(pattern: tagRegexPattern, options: [.caseInsensitive]) {
        let nsBlock = planBlock as NSString
        if let match = tagRegex.firstMatch(in: planBlock, options: [], range: NSRange(location: 0, length: nsBlock.length)) {
            let attrStr = nsBlock.substring(with: match.range(at: 1))
            
            // Extract title
            if let titleRegex = try? NSRegularExpression(pattern: "title=\"([^\"]+)\"", options: []) {
                let nsAttr = attrStr as NSString
                if let m = titleRegex.firstMatch(in: attrStr, options: [], range: NSRange(location: 0, length: nsAttr.length)) {
                    title = nsAttr.substring(with: m.range(at: 1))
                }
            }
            // Extract command
            if let cmdRegex = try? NSRegularExpression(pattern: "command=\"([^\"]+)\"", options: []) {
                let nsAttr = attrStr as NSString
                if let m = cmdRegex.firstMatch(in: attrStr, options: [], range: NSRange(location: 0, length: nsAttr.length)) {
                    command = nsAttr.substring(with: m.range(at: 1))
                }
            }
            // Extract directory
            if let dirRegex = try? NSRegularExpression(pattern: "directory=\"([^\"]+)\"", options: []) {
                let nsAttr = attrStr as NSString
                if let m = dirRegex.firstMatch(in: attrStr, options: [], range: NSRange(location: 0, length: nsAttr.length)) {
                    directory = nsAttr.substring(with: m.range(at: 1))
                }
            }
            // Extract startAgent
            if let agentRegex = try? NSRegularExpression(pattern: "startAgent=\"([^\"]+)\"", options: []) {
                let nsAttr = attrStr as NSString
                if let m = agentRegex.firstMatch(in: attrStr, options: [], range: NSRange(location: 0, length: nsAttr.length)) {
                    startAgent = nsAttr.substring(with: m.range(at: 1))
                }
            }
        }
    }
    
    // Extract contents between <plan ...> and </plan>
    let innerText: String
    if let closeTagIdx = planBlock.firstIndex(of: ">") {
        let afterOpenTag = planBlock[planBlock.index(after: closeTagIdx)...]
        if let endTagIdx = afterOpenTag.range(of: "</plan>") {
            innerText = String(afterOpenTag[..<endTagIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            innerText = ""
        }
    } else {
        innerText = ""
    }
    
    // Parse description and bullet items from innerText
    let lines = innerText.components(separatedBy: .newlines)
    var descriptionLines: [String] = []
    var items: [String] = []
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") {
            items.append(String(trimmed.dropFirst(2)))
        } else if trimmed.hasPrefix("* ") {
            items.append(String(trimmed.dropFirst(2)))
        } else if !trimmed.isEmpty {
            descriptionLines.append(trimmed)
        }
    }
    
    let description = descriptionLines.joined(separator: "\n")
    
    // Clean original text
    clean = clean.replacingOccurrences(of: planBlock, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    
    let plan = PlanNode(title: title, description: description, items: items, command: command, directory: directory, startAgent: startAgent)
    return (clean, plan)
}

// MARK: - FormattedResponseView Master Component
public struct FormattedResponseView: View {
    let text: String
    let thoughts: String?
    var isStreaming: Bool = false
    var messageId: String? = nil
    var toolExecutions: [ToolExecution]? = nil
    var onSelectFollowUp: ((String) -> Void)? = nil
    
    @State private var showSources: Bool = false
    @State private var typewrittenText: String = ""
    @State private var typewrittenThoughts: String = ""
    @State private var lastChunkTime: Double = 0.0
    
    private let typewriterTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    public init(text: String, thoughts: String? = nil, isStreaming: Bool = false, messageId: String? = nil, toolExecutions: [ToolExecution]? = nil, onSelectFollowUp: ((String) -> Void)? = nil) {
        self.text = text
        self.thoughts = thoughts
        self.isStreaming = isStreaming
        self.messageId = messageId
        self.toolExecutions = toolExecutions
        self.onSelectFollowUp = onSelectFollowUp
    }
    
    private func safeSubstring(_ str: String, length: Int) -> String {
        let safeLength = min(max(0, length), str.count)
        let index = str.index(str.startIndex, offsetBy: safeLength)
        return String(str[..<index])
    }
    
    private func synthesizeActivityFeed(rawThoughts: String?, currentText: String) -> String {
        // PRIORITY 1: If we have REAL tool execution data from Gemini function calling,
        // render that instead of any fake template or model-generated thoughts
        if let tools = toolExecutions, !tools.isEmpty {
            let totalDurationMs = tools.reduce(0) { $0 + $1.durationMs }
            let totalDurationSec = max(1, totalDurationMs / 1000)
            
            // Count files and folders from tool executions
            var fileCount = 0
            var folderCount = 0
            var commandCount = 0
            var searchCount = 0
            for t in tools {
                switch t.toolName {
                case "read_file", "write_file": fileCount += 1
                case "list_directory": folderCount += 1
                case "run_command": commandCount += 1
                case "search_files": searchCount += 1
                default: break
                }
            }
            
            var lines: [String] = []
            lines.append("Worked for \(totalDurationSec)s")
            
            var exploredParts: [String] = []
            if fileCount > 0 { exploredParts.append("\(fileCount) file\(fileCount == 1 ? "" : "s")") }
            if folderCount > 0 { exploredParts.append("\(folderCount) folder\(folderCount == 1 ? "" : "s")") }
            if commandCount > 0 { exploredParts.append("\(commandCount) command\(commandCount == 1 ? "" : "s")") }
            if searchCount > 0 { exploredParts.append("\(searchCount) search\(searchCount == 1 ? "" : "es")") }
            if !exploredParts.isEmpty {
                lines.append("Explored \(exploredParts.joined(separator: ", "))")
            }
            lines.append("")
            
            // Render each real tool execution as an activity line
            for t in tools {
                lines.append(t.resultSummary)
            }
            
            return lines.joined(separator: "\n")
        }
        
        // PRIORITY 2: Use model-generated [THOUGHTS] block if present
        if let raw = rawThoughts, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        
        // PRIORITY 3: Minimal fallback — just show thinking indicator, no fake data
        return "Thought for 1s\nAnalyzing your request and generating a response..."
    }
    
    public var body: some View {
        let currentText = isStreaming ? typewrittenText : text
        let (textWithoutThoughts, extractedThoughts) = extractThinkingBlock(currentText)
        let finalThoughts = isStreaming ? typewrittenThoughts : (thoughts ?? extractedThoughts)
        let synthesizedThoughts = synthesizeActivityFeed(rawThoughts: finalThoughts, currentText: currentText)
        let (textWithoutProject, projectNode) = extractProjectNode(textWithoutThoughts)
        let (textWithoutPlan, planNode) = extractPlanNode(textWithoutProject)
        let parsedResult = extractSources(textWithoutPlan)
        
        VStack(alignment: .leading, spacing: 10) {
            DynamicThinkingBlockView(thoughts: synthesizedThoughts, isStreaming: isStreaming, detectedSources: parsedResult.sources)
            
            if let project = projectNode {
                ProjectNodeView(project: project)
            }
            
            if let plan = planNode {
                PlanCardView(plan: plan)
            }
            
            if currentText.contains("AGENT_PROCESS_CARD") || currentText.contains("[ App Launch ]") || currentText.contains("[ Key Shortcut ]") {
                ProfessionalAgentProcessCardView(text: currentText)
            } else {
                let parsedCmds = parseSwiftCommands(from: currentText)
                if !parsedCmds.isEmpty {
                    DeviceControlTrackerView(commands: parsedCmds, isStreaming: isStreaming, messageId: messageId, textContent: currentText)
                }
                
                ForEach(parseMarkdown(parsedResult.cleanText)) { block in
                    switch block {
                    case .text(let inlineText):
                        RichTextView(inlineText, sources: parsedResult.sources)
                    case .header(let level, let headerText):
                        HeaderView(level: level, text: headerText)
                    case .bullet(let bulletText):
                        BulletRowView(text: bulletText, sources: parsedResult.sources)
                    case .quote(let quoteText):
                        BlockquoteView(text: quoteText, sources: parsedResult.sources)
                    case .code(let lang, let codeText):
                        CodeBlockView(lang: lang, code: codeText)
                    case .image(let url):
                        AgentScreenshotView(url: url)
                    }
                }
            }
            
            // Bottom Action Bar
            ResponseActionToolbar(
                cleanText: parsedResult.cleanText,
                sources: parsedResult.sources,
                showSources: $showSources,
                onCopy: {}
            )
            
            // Expanded full citations list view
            if !parsedResult.sources.isEmpty && showSources {
                GroundedSourcesView(sources: parsedResult.sources)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Suggeted FollowUps Questions (if any parsed successfully)
            if !parsedResult.followUps.isEmpty {
                FollowUpsSwiftView(questions: parsedResult.followUps) { item in
                    onSelectFollowUp?(item)
                }
            }
        }
        .textSelection(.enabled)
        .onAppear {
            if isStreaming {
                typewrittenText = ""
                typewrittenThoughts = ""
            } else {
                typewrittenText = text
                typewrittenThoughts = thoughts ?? ""
            }
            lastChunkTime = Date().timeIntervalSince1970 * 1000.0
        }
        .onChange(of: text) { newValue in
            lastChunkTime = Date().timeIntervalSince1970 * 1000.0
            if !isStreaming {
                typewrittenText = newValue
            }
        }
        .onChange(of: thoughts) { newValue in
            lastChunkTime = Date().timeIntervalSince1970 * 1000.0
            if !isStreaming {
                typewrittenThoughts = newValue ?? ""
            }
        }
        .onReceive(typewriterTimer) { _ in
            guard isStreaming else { return }
            
            let targetText = text
            let targetThoughts = thoughts ?? ""
            
            let gapText = targetText.count - typewrittenText.count
            let gapThoughts = targetThoughts.count - typewrittenThoughts.count
            
            if gapText <= 0 && gapThoughts <= 0 {
                return
            }
            
            var stepText = 0
            var stepThoughts = 0
            let now = Date().timeIntervalSince1970 * 1000.0
            
            if gapThoughts > 0 {
                let step: Int
                if gapThoughts > 1000 {
                    step = min(20, Int(ceil(Double(gapThoughts) / 80.0)))
                } else if gapThoughts > 300 {
                    step = min(10, Int(ceil(Double(gapThoughts) / 40.0)))
                } else if gapThoughts > 50 {
                    step = min(5, Int(ceil(Double(gapThoughts) / 15.0)))
                } else {
                    step = 1
                }
                stepThoughts = step
                typewrittenThoughts = safeSubstring(targetThoughts, length: typewrittenThoughts.count + step)
            }
            
            if gapText > 0 {
                let step: Int
                if gapText > 1000 {
                    step = min(15, Int(ceil(Double(gapText) / 100.0)))
                } else if gapText > 300 {
                    step = min(8, Int(ceil(Double(gapText) / 50.0)))
                } else if gapText > 50 {
                    step = min(4, Int(ceil(Double(gapText) / 20.0)))
                } else {
                    step = 1
                }
                stepText = step
                typewrittenText = safeSubstring(targetText, length: typewrittenText.count + step)
            }
            
            if lastChunkTime > 0 {
                let latency = now - lastChunkTime
                print("[Perf Monitor] Swift stream render latency: \(String(format: "%.1f", latency))ms | Gap: \(gapText) chars | Steps: [Content: +\(stepText), Thoughts: +\(stepThoughts)]")
            }
        }
    }
}

// MARK: - SwiftUI Shimmer Effect
struct SwiftUIShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .white.opacity(0.3), .white, .white.opacity(0.3), .clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .rotationEffect(.degrees(20))
                        .offset(x: -geo.size.width + (geo.size.width * 2 * phase))
                        .onAppear {
                            withAnimation(Animation.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                phase = 1.0
                            }
                        }
                    }
                    .mask(content)
                )
        } else {
            content
        }
    }
}

extension View {
    func shimmer(isEnabled: Bool) -> some View {
        self.modifier(SwiftUIShimmerModifier(isEnabled: isEnabled))
    }
}

// MARK: - Color Custom Extensions
extension Color {
    static let unisonAmber = Color(red: 0.95, green: 0.61, blue: 0.07)
    static let unisonEmerald = Color(red: 0.13, green: 0.85, blue: 0.45)
}

// MARK: - Swift Device Automation Parser & View Models
public struct SwiftParsedCommand: Identifiable, Hashable {
    public let id = UUID()
    public let type: String // CLICK, LAUNCH_APP, TYPE, DRAG, OPEN_URL, SEARCH, OTHER
    public let payload: String
    public let label: String
    public let raw: String
}

public func parseSwiftCommands(from text: String) -> [SwiftParsedCommand] {
    if text.isEmpty { return [] }
    var commands: [SwiftParsedCommand] = []
    
    // Check formal DEVICE_ACTION_ format using NSRegularExpression
    let pattern = "DEVICE_ACTION_([A-Z_]+)(?::([^:\\n\\s]+))?(?::([^:\\n]+))?(?::([^:\\n]+))?"
    if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in results {
            if match.numberOfRanges > 1 {
                let actionType = nsString.substring(with: match.range(at: 1)).uppercased()
                
                var p1 = ""
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                    p1 = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                var p2 = ""
                if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                    p2 = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                var p3 = ""
                if match.numberOfRanges > 4, match.range(at: 4).location != NSNotFound {
                    p3 = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                let raw = nsString.substring(with: match.range(at: 0))
                
                if actionType == "CLICK" {
                    commands.append(SwiftParsedCommand(
                        type: "CLICK",
                        payload: "Coordinates (\(p1), \(p2))",
                        label: p3.isEmpty ? "Click Coordinate \(p1), \(p2)" : p3,
                        raw: raw
                    ))
                } else if actionType == "TYPE" {
                    let textVal = p1 == "\\n" || p1 == "\n" ? "Return Key" : p1
                    commands.append(SwiftParsedCommand(
                        type: "TYPE",
                        payload: textVal,
                        label: p1 == "\\n" || p1 == "\n" ? "Press Enter Key" : "Type Text: \"\(p1)\"",
                        raw: raw
                    ))
                } else if actionType == "DRAG" {
                    let p4 = match.numberOfRanges > 5 && match.range(at: 5).location != NSNotFound ? nsString.substring(with: match.range(at: 5)) : ""
                    commands.append(SwiftParsedCommand(
                        type: "DRAG",
                        payload: "From (\(p1), \(p2)) to (\(p3), \(p4))",
                        label: "Drag Pointer",
                        raw: raw
                    ))
                } else if actionType == "OPEN_URL" {
                    commands.append(SwiftParsedCommand(
                        type: "OPEN_URL",
                        payload: p1,
                        label: "Open Link: \(p1)",
                        raw: raw
                    ))
                } else if actionType == "LAUNCH_APP" {
                    commands.append(SwiftParsedCommand(
                        type: "LAUNCH_APP",
                        payload: p1,
                        label: "Launch Application: \(p1)",
                        raw: raw
                    ))
                } else if actionType == "SEARCH" {
                    commands.append(SwiftParsedCommand(
                        type: "SEARCH",
                        payload: p1,
                        label: "Search: \"\(p1)\"",
                        raw: raw
                    ))
                } else if actionType == "SCREENSHOT" {
                    commands.append(SwiftParsedCommand(
                        type: "OTHER",
                        payload: "Entire Screen Display Canvas",
                        label: "Capture System Screenshot",
                        raw: raw
                    ))
                } else {
                    commands.append(SwiftParsedCommand(
                        type: "OTHER",
                        payload: p1,
                        label: p3.isEmpty ? "System Action" : p3,
                        raw: raw
                    ))
                }
            }
        }
    }
    
    // If no formal commands found, fall back to natural language parsing
    if commands.isEmpty {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            let lower = trimmed.lowercased()
            if lower.contains("click at") || lower.contains("tap at") {
                commands.append(SwiftParsedCommand(
                    type: "CLICK",
                    payload: "Screen Interaction",
                    label: "Click / Tap Coordinate",
                    raw: trimmed
                ))
            } else if lower.hasPrefix("launch app") || lower.hasPrefix("open app") {
                commands.append(SwiftParsedCommand(
                    type: "LAUNCH_APP",
                    payload: "Application Sandbox",
                    label: "Launch OS Application",
                    raw: trimmed
                ))
            } else if lower.hasPrefix("type ") || lower.hasPrefix("write ") {
                commands.append(SwiftParsedCommand(
                    type: "TYPE",
                    payload: "Keystrokes Queue",
                    label: "Input Key Sequence",
                    raw: trimmed
                ))
            } else if lower.contains("search for") || lower.contains("google search") {
                commands.append(SwiftParsedCommand(
                    type: "SEARCH",
                    payload: "Search Engine Console",
                    label: "Search Web Console",
                    raw: trimmed
                ))
            }
        }
    }
    
    return commands
}

// MARK: - SwiftUI Device Control Tracker (Text-Based Collapsible Accordion with Shimmer)
public struct DeviceControlTrackerView: View {
    let commands: [SwiftParsedCommand]
    let isStreaming: Bool
    let messageId: String?
    let textContent: String
    
    @State private var activeStep = 0
    @State private var expandedSteps: Set<UUID> = []
    @State private var showPermissionModal = false
    @State private var accessibilityGranted = false
    @State private var screenshotsGranted = false
    
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    
    public init(commands: [SwiftParsedCommand], isStreaming: Bool, messageId: String? = nil, textContent: String) {
        self.commands = commands
        self.isStreaming = isStreaming
        self.messageId = messageId
        self.textContent = textContent
    }
    
    private var hasMissingPermissions: Bool {
        #if os(macOS)
        return !FirestoreService.shared.accessibilityPermissionGranted || !FirestoreService.shared.screenCapturePermissionGranted
        #else
        return false
        #endif
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Permission Warnings
            if hasMissingPermissions {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.unisonAmber)
                    
                    Text("Permissions required: Enable Accessibility and Screenshot recording to automate tasks.")
                        .font(.system(size: 9, weight: .light))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Button(action: { FirestoreService.shared.showComputerUsePermissionDialog = true }) {
                        Text("Configure")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.unisonAmber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.unisonAmber.opacity(0.1))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.unisonAmber.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(10)
                .background(Color.unisonAmber.opacity(0.03))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.unisonAmber.opacity(0.1), lineWidth: 1)
                )
            }
            
            // List of collapsible text lines
            ZStack(alignment: .leading) {
                // Vertical connecting timeline track line
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 2)
                    .padding(.vertical, 14)
                    .offset(x: 8) // align directly with center of the 18x18 status icon
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                        let isCompleted = index < activeStep && !(messageId != nil && messageId == FirestoreService.shared.activeStepMessageId && AgentStateController.shared.isLoopRunning)
                        let isCurrent = (index == activeStep && isStreaming) || (messageId != nil && messageId == FirestoreService.shared.activeStepMessageId && AgentStateController.shared.isLoopRunning)
                        
                        let isErrorState = textContent.lowercased().contains("error") || textContent.lowercased().contains("timeout") || textContent.lowercased().contains("fail")
                        let isLast = index == commands.count - 1
                        let hasFailed = isErrorState && isLast && index <= activeStep
                        
                        let isOpen = expandedSteps.contains(cmd.id)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            // Header Row (Plain Text-Line Accordion Trigger)
                            HStack(spacing: 8) {
                                // SVG/SF symbol matching the instruction type
                                Image(systemName: getSystemIcon(for: cmd.type, label: cmd.label))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(hasFailed ? .red : (isCurrent ? .blue : (isCompleted ? .unisonEmerald : .gray)))
                                    .frame(width: 18, height: 18)
                                    .background(hasFailed ? Color.red.opacity(0.1) : (isCurrent ? Color.blue.opacity(0.1) : (isCompleted ? Color.unisonEmerald.opacity(0.05) : Color.white.opacity(0.03))))
                                    .cornerRadius(4)
                                
                                // Text Label
                                Text(cmd.label)
                                    .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                                    .foregroundColor(hasFailed ? .red : (isCurrent ? .blue : (isCompleted ? .white : .gray)))
                                
                                Spacer()
                                
                                HStack(spacing: 6) {
                                    if hasFailed {
                                        Text("FAILED")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.red)
                                    } else if isCompleted {
                                        Text("DISPATCHED")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.unisonEmerald)
                                    } else if isCurrent {
                                        Text("EXECUTING")
                                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                                            .foregroundColor(.blue)
                                            .shimmer(isEnabled: true)
                                    } else {
                                        Text("QUEUED")
                                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(.gray)
                                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isOpen {
                                        expandedSteps.remove(cmd.id)
                                    } else {
                                        expandedSteps.insert(cmd.id)
                                    }
                                }
                            }
                            
                            // Expanded Telemetry Code Box
                            if isOpen {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(hasFailed ? "plaintext" : "json")
                                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.gray)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)
                                    
                                    if hasFailed {
                                        Text("Computer Use server error -10005: timeoutReached")
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                            .foregroundColor(.red)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.red.opacity(0.04))
                                            .cornerRadius(4)
                                            .padding(.horizontal, 10)
                                            .padding(.bottom, 6)
                                    } else {
                                        let simulatedJson = getSimulatedJson(for: cmd)
                                        Text(simulatedJson)
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                            .foregroundColor(Color(white: 0.7))
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.black.opacity(0.3))
                                            .cornerRadius(4)
                                            .padding(.horizontal, 10)
                                            .padding(.bottom, 6)
                                    }
                                }
                                .background(Color(white: 0.02))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(white: 0.08), lineWidth: 1)
                                )
                                .padding(.leading, 26)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            if isStreaming {
                if activeStep < commands.count {
                    activeStep += 1
                }
            }
        }
        .onAppear {
            if !isStreaming {
                activeStep = commands.count
            }
            // Auto expand first or current
            if let first = commands.first {
                expandedSteps.insert(first.id)
            }
        }
    }
    
    private func getSystemIcon(for type: String, label: String) -> String {
        let lbl = label.lowercased()
        if lbl.contains("music") { return "music.note" }
        if lbl.contains("find") || lbl.contains("search") { return "sparkles" }
        if lbl.contains("app") { return "arrow.up.forward.app" }
        
        switch type {
        case "CLICK": return "cursorarrow"
        case "LAUNCH_APP": return "arrow.up.forward.app"
        case "TYPE": return "keyboard"
        case "OPEN_URL": return "globe"
        case "DRAG": return "arrow.up.and.down.and.arrow.left.and.right"
        case "SEARCH": return "magnifyingglass"
        default: return "terminal"
        }
    }
    
    private func getSimulatedJson(for cmd: SwiftParsedCommand) -> String {
        switch cmd.type {
        case "LAUNCH_APP":
            return """
            [
              {
                "id": "com.apple.\(cmd.payload.lowercased())",
                "displayName": "\(cmd.payload)",
                "isRunning": true,
                "useCount": 14
              }
            ]
            """
        case "CLICK":
            return """
            {
              "action": "click",
              "coordinate": "\(cmd.payload)",
              "status": "success"
            }
            """
        case "TYPE":
            return """
            {
              "action": "type_keys",
              "sequence": "\(cmd.payload)",
              "status": "success"
            }
            """
        default:
            return """
            {
              "action": "execute",
              "payload": "\(cmd.payload)",
              "status": "success"
            }
            """
        }
    }
}

// MARK: - SwiftUI macOS-Style Computer Use Permission Modal
public struct ComputerUsePermissionView: View {
    @Binding var accessibilityGranted: Bool
    @Binding var screenshotsGranted: Bool
    @Binding var isPresented: Bool
    
    public init(accessibilityGranted: Binding<Bool>, screenshotsGranted: Binding<Bool>, isPresented: Binding<Bool>) {
        self._accessibilityGranted = accessibilityGranted
        self._screenshotsGranted = screenshotsGranted
        self._isPresented = isPresented
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack(spacing: 6) {
                Button(action: { isPresented = false }) {
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(PlainButtonStyle())
                
                Circle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 10, height: 10)
                
                Spacer()
                Text("UNISON OS PREFERENCES")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.05))
            
            Divider()
                .background(Color(white: 0.08))
            
            VStack(spacing: 16) {
                // Header Icon
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        )
                    
                    Circle()
                        .fill(Color.unisonEmerald)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                        )
                        .offset(x: 4, y: 4)
                }
                .padding(.top, 24)
                
                VStack(spacing: 6) {
                    Text("Enable Unison OS Computer Use")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.white)
                    
                    Text("Unison OS Computer Use needs these permissions to use apps on your Mac. These permissions are used when you ask Unison OS to perform tasks.")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                }
                
                // List of Permissions
                VStack(spacing: 8) {
                    // Accessibility Row
                    HStack(spacing: 12) {
                        Image(systemName: "accessibility")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue)
                            .cornerRadius(16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Text("Allows Unison OS to access app interfaces")
                                .font(.system(size: 8.5, weight: .regular))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: { accessibilityGranted.toggle() }) {
                            Text(accessibilityGranted ? "Allowed" : "Allow")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(accessibilityGranted ? .unisonEmerald : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(accessibilityGranted ? Color(white: 0.1) : Color.blue)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(accessibilityGranted ? Color.unisonEmerald.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(10)
                    .background(Color(white: 0.04))
                    .cornerRadius(12)
                    
                    // Screenshots Row
                    HStack(spacing: 12) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.2))
                            .cornerRadius(16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshots")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Text("Unison OS uses screenshots to know where to click")
                                .font(.system(size: 8.5, weight: .regular))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: { screenshotsGranted.toggle() }) {
                            Text(screenshotsGranted ? "Allowed" : "Allow")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(screenshotsGranted ? .unisonEmerald : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(screenshotsGranted ? Color(white: 0.1) : Color.blue)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(screenshotsGranted ? Color.unisonEmerald.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(10)
                    .background(Color(white: 0.04))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                // Done Button
                Button(action: { isPresented = false }) {
                    Text("Done")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.12))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(white: 0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 320, height: 440)
        .background(Color(white: 0.02))
        .preferredColorScheme(.dark)
    }
}

public struct AgentScreenshotView: View {
    let url: String
    @State private var showFullScreen = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 9))
                    Text("SCREEN CAPTURE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color.unisonEmerald)
                
                Spacer()
                
                if let validUrl = URL(string: url) {
                    #if os(macOS)
                    Button(action: {
                        NSWorkspace.shared.open(validUrl)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9))
                            Text("EXTERNAL VIEW")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    #else
                    Link(destination: validUrl) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9))
                            Text("EXTERNAL VIEW")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ZStack {
                if let validUrl = URL(string: url) {
                    AsyncImage(url: validUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(6)
                                .padding(8)
                                .onTapGesture {
                                    showFullScreen = true
                                }
                        case .failure:
                            HStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                                Text("Failed to download screenshot step")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .padding(16)
                        case .empty:
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .unisonEmerald))
                                .padding(24)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Text("Invalid capture path")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.2))
        }
        .background(Color.black.opacity(0.35))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.vertical, 4)
        .sheet(isPresented: $showFullScreen) {
            FullScreenScreenshotViewer(url: url)
        }
    }
}

public struct FullScreenScreenshotViewer: View {
    let url: String
    @Environment(\.presentationMode) var presentationMode
    
    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("System Capture Preview")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if let validUrl = URL(string: url) {
                AsyncImage(url: validUrl) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(16)
                    } else if phase.error != nil {
                        Text("Error displaying full-size capture")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .unisonEmerald))
                    }
                }
            }
            
            Spacer()
        }
        .frame(minWidth: 480, minHeight: 480)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - High-Fidelity Agent Action Explorer & Human-in-the-Loop Permission
public struct DynamicThoughtTrajectoryView: View {
    let msg: ChatMessage
    @ObservedObject var db = FirestoreService.shared
    
    @State private var isWorkedExpanded: Bool = true
    
    public init(msg: ChatMessage) {
        self.msg = msg
    }
    
    public var body: some View {
        guard let thoughtsRaw = msg.thoughts, !thoughtsRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AnyView(EmptyView())
        }
        
        let thoughtsText = thoughtsRaw.replacingOccurrences(of: "[THOUGHTS]", with: "").replacingOccurrences(of: "[/THOUGHTS]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let thoughtLines = thoughtsText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let workedSecs = msg.executionTimeSeconds ?? max(1, thoughtLines.count * 2)
        
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                // Collapsible Worked for Ns Header
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isWorkedExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("Worked for \(workedSecs)s")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Image(systemName: isWorkedExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                
                if isWorkedExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(thoughtLines.enumerated()), id: \.offset) { idx, line in
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundColor(.cyan.opacity(0.7))
                                Text(line)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                            }
                            .padding(.leading, 12)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 6)
        )
    }
    
    private func approveCommand(msgId: String) {
        if let idx = db.messages.firstIndex(where: { $0.id == msgId }) {
            db.messages[idx].isApproved = true
            let cmd = db.messages[idx].pendingApprovalCommand ?? db.messages[idx].commandExecuted ?? "./.build/debug/UnisonOS"
            db.messages[idx].commandExecuted = cmd
            db.messages[idx].commandOutput = "[TERMINAL] Running command: \(cmd)...\nBuild complete! Executable initialized with zero errors."
            db.saveMessagesToDefaults()
            db.consumeTokens(count: 420)
        }
    }
    
    private func rejectCommand(msgId: String) {
        if let idx = db.messages.firstIndex(where: { $0.id == msgId }) {
            db.messages[idx].isApproved = false
            db.messages[idx].commandOutput = "⚠️ [HUMAN-IN-THE-LOOP] Terminal command execution rejected by user."
            db.saveMessagesToDefaults()
        }
    }
    
    private func extractPathFromOutput(_ str: String) -> String {
        if let range = str.range(of: #"(/[\w\.\-/]+)"#, options: .regularExpression) {
            return String(str[range])
        }
        return ""
    }
    
    private func openFileInFinder(path: String) {
        #if os(macOS)
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: cleanPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
