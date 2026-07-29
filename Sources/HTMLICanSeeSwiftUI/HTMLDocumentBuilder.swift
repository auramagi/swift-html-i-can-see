import Foundation
import HTMLICanSeeTokenizer

/// Maps HTML or an existing token stream into a stable semantic document.
///
/// This mapper is intentionally smaller than HTML tree construction. Its
/// malformed-input recovery is deterministic:
///
/// - a new paragraph or list closes the current top-level paragraph;
/// - a new list item closes the preceding item in the innermost list;
/// - a list end tag closes nested lists through the nearest matching list;
/// - an inline end tag removes the nearest matching open inline tag;
/// - inline formatting opened inside a paragraph or list item does not leak
///   into the following paragraph or item.
///
/// Unsupported tags are transparent to their visible text. `script`, `style`,
/// and `template` contents are suppressed.
public struct HTMLDocumentBuilder: Sendable {
    public init() {}

    /// Tokenizes and maps an HTML string.
    ///
    /// The builder supplies the tree-construction policy needed to enter
    /// script-data and RAWTEXT tokenizer states for suppressed content.
    public func build(from html: String) -> HTMLDocument {
        var tokenizer = HTMLTokenizer(html)
        var parser = SemanticDocumentParser()

        while true {
            let token = tokenizer.nextToken()
            parser.consume(token)

            if case let .startTag(name, _, _) = token {
                switch asciiLowercased(name) {
                case "script":
                    tokenizer.switchTo(.scriptData)
                case "style":
                    tokenizer.switchTo(.rawtext)
                default:
                    break
                }
            }

            if token == .eof {
                return parser.finish()
            }
        }
    }

    /// Maps an existing token stream without reading or retaining source HTML.
    ///
    /// Tokens after the first EOF token are ignored. A stream without an EOF
    /// token is finalized at the end of the sequence.
    public func build<Tokens: Sequence>(
        from tokens: Tokens
    ) -> HTMLDocument where Tokens.Element == HTMLToken {
        var parser = SemanticDocumentParser()

        for token in tokens {
            parser.consume(token)
            if token == .eof {
                break
            }
        }

        return parser.finish()
    }
}

private struct SemanticDocumentParser {
    private final class FormattingGenerationStack {
        var generations: [Int]

        init(_ firstGeneration: Int) {
            generations = [firstGeneration]
        }
    }

    private struct FormattingFrame {
        let id: Int
        let tagName: String
        let link: URL?
    }

    private struct ItemContext {
        var content = InlineAccumulator()
        var completedParts: [HTMLListItemPart] = []
        var formattingWatermarkAtStart: Int
        var paragraphFormattingWatermark: Int?
        var isExplicit: Bool

        var shouldEmit: Bool {
            isExplicit || !content.isEmpty || !completedParts.isEmpty
        }

        mutating func makeItem() -> HTMLListItem {
            flushContent()
            return HTMLListItem(parts: completedParts)
        }

        mutating func append(_ list: HTMLList) {
            flushContent()
            completedParts.append(.list(list))
        }

        private mutating func flushContent() {
            content.finish()
            if !content.inlines.isEmpty {
                completedParts.append(.inlines(content.inlines))
            }
            content = InlineAccumulator()
        }
    }

    private struct ListContext {
        let tagName: String
        let style: HTMLListStyle
        let isSynthetic: Bool
        let formattingWatermarkAtStart: Int
        var items: [HTMLListItem] = []
        var currentItem: ItemContext?
    }

    private var blocks: [HTMLBlock] = []
    private var topLevelContent = InlineAccumulator()
    private var topLevelParagraphFormattingWatermark: Int?
    private var lists: [ListContext] = []
    private var formattingGenerations: [Int] = []
    private var activeFormatting: [Int: FormattingFrame] = [:]
    private var activeFormattingByTag: [
        String: FormattingGenerationStack
    ] = [:]
    private var nextFormattingID = 0
    private var boldFormattingCount = 0
    private var italicFormattingCount = 0
    private var strikethroughFormattingCount = 0
    private var activeLink: URL?
    private var cachedTextStyle = HTMLTextStyle.plain
    private var suppressedElements: [String] = []
    private var didFinish = false

    mutating func consume(_ token: HTMLToken) {
        guard !didFinish else {
            return
        }

        if !suppressedElements.isEmpty {
            consumeSuppressed(token)
            return
        }

        switch token {
        case let .startTag(name, attributes, _):
            consumeStartTag(
                asciiLowercased(name),
                attributes: attributes
            )
        case let .endTag(name):
            consumeEndTag(asciiLowercased(name))
        case let .character(text):
            appendText(text)
        case .doctype, .comment:
            break
        case .eof:
            didFinish = true
        }
    }

    mutating func finish() -> HTMLDocument {
        if !didFinish {
            didFinish = true
        }

        suppressedElements.removeAll(keepingCapacity: false)
        closeAllLists()
        closeTopLevelParagraph()
        return HTMLDocument(blocks: blocks)
    }

    private mutating func consumeSuppressed(_ token: HTMLToken) {
        switch token {
        case let .startTag(name, _, _):
            let normalizedName = asciiLowercased(name)
            if Self.suppressedTagNames.contains(normalizedName) {
                suppressedElements.append(normalizedName)
            }
        case let .endTag(name):
            let normalizedName = asciiLowercased(name)
            if let index = suppressedElements.lastIndex(of: normalizedName) {
                suppressedElements.removeSubrange(index...)
            }
        case .eof:
            didFinish = true
        case .doctype, .comment, .character:
            break
        }
    }

    private mutating func consumeStartTag(
        _ name: String,
        attributes: [HTMLAttribute]
    ) {
        if Self.suppressedTagNames.contains(name) {
            suppressedElements.append(name)
            return
        }

        switch name {
        case "p":
            startParagraph()
        case "ul":
            startList(tagName: name, style: .unordered)
        case "ol":
            startList(tagName: name, style: .ordered)
        case "li":
            startListItem()
        case "br":
            appendLineBreak()
        case "strong", "b", "em", "i", "del":
            pushFormatting(tagName: name, link: nil)
        case "a":
            // HTML does not nest anchors. Starting another anchor ends the
            // previous anchor's link behavior before opening the new one.
            removeFormatting(tagName: "a")
            let href = attributes.first {
                asciiLowercased($0.name) == "href"
            }?.value
            pushFormatting(
                tagName: name,
                link: href.flatMap(HTMLLinkDestination.parse)
            )
        default:
            break
        }
    }

    private mutating func consumeEndTag(_ name: String) {
        switch name {
        case "p":
            endParagraph()
        case "ul", "ol":
            closeLists(through: name)
        case "li":
            finishCurrentListItem()
        case "br":
            // HTML tree construction treats a malformed `</br>` like `<br>`.
            appendLineBreak()
        case "strong", "b", "em", "i", "del", "a":
            removeFormatting(tagName: name)
        default:
            break
        }
    }

    private mutating func startParagraph() {
        if !lists.isEmpty {
            ensureCurrentListItem(isExplicit: false)
            let listIndex = lists.count - 1
            var item = lists[listIndex].currentItem!
            closeItemParagraph(&item)
            item.content.markParagraphBoundary()
            item.paragraphFormattingWatermark = currentFormattingWatermark
            lists[listIndex].currentItem = item
            return
        }

        closeTopLevelParagraph()
        topLevelParagraphFormattingWatermark = currentFormattingWatermark
    }

    private mutating func endParagraph() {
        if !lists.isEmpty {
            guard lists[lists.count - 1].currentItem != nil else {
                return
            }
            let listIndex = lists.count - 1
            var item = lists[listIndex].currentItem!
            item.content.markParagraphBoundary()
            closeItemParagraph(&item)
            lists[listIndex].currentItem = item
            return
        }

        closeTopLevelParagraph()
    }

    private mutating func startList(
        tagName: String,
        style: HTMLListStyle
    ) {
        if lists.isEmpty {
            closeTopLevelParagraph()
        } else {
            ensureCurrentListItem(isExplicit: false)
        }

        lists.append(
            ListContext(
                tagName: tagName,
                style: style,
                isSynthetic: false,
                formattingWatermarkAtStart: currentFormattingWatermark
            )
        )
    }

    private mutating func startListItem() {
        if lists.isEmpty {
            closeTopLevelParagraph()
            lists.append(
                ListContext(
                    tagName: "ul",
                    style: .unordered,
                    isSynthetic: true,
                    formattingWatermarkAtStart: currentFormattingWatermark
                )
            )
        }

        finishCurrentListItem()
        lists[lists.count - 1].currentItem = ItemContext(
            formattingWatermarkAtStart: currentFormattingWatermark,
            paragraphFormattingWatermark: nil,
            isExplicit: true
        )
    }

    private mutating func appendText(_ text: String) {
        if lists.count == 1,
           lists[0].isSynthetic,
           lists[0].currentItem == nil,
           containsNonWhitespace(text) {
            closeAllLists()
        }

        if lists.isEmpty {
            topLevelContent.append(text, style: currentTextStyle)
            return
        }

        guard containsNonWhitespace(text) ||
              lists[lists.count - 1].currentItem != nil
        else {
            return
        }

        ensureCurrentListItem(isExplicit: false)
        let style = currentTextStyle
        mutateCurrentItem { item in
            item.content.append(text, style: style)
        }
    }

    private mutating func appendLineBreak() {
        if lists.isEmpty {
            topLevelContent.appendLineBreak()
            return
        }

        ensureCurrentListItem(isExplicit: false)
        mutateCurrentItem { item in
            item.content.appendLineBreak()
        }
    }

    private var currentTextStyle: HTMLTextStyle {
        cachedTextStyle
    }

    private mutating func closeTopLevelParagraph() {
        topLevelContent.finish()

        if !topLevelContent.inlines.isEmpty {
            blocks.append(.paragraph(topLevelContent.inlines))
        }

        topLevelContent = InlineAccumulator()

        if let watermark = topLevelParagraphFormattingWatermark {
            restoreFormatting(to: watermark)
        }
        topLevelParagraphFormattingWatermark = nil
    }

    private mutating func ensureCurrentListItem(isExplicit: Bool) {
        guard !lists.isEmpty else {
            return
        }

        let index = lists.count - 1
        if lists[index].currentItem == nil {
            lists[index].currentItem = ItemContext(
                formattingWatermarkAtStart: currentFormattingWatermark,
                paragraphFormattingWatermark: nil,
                isExplicit: isExplicit
            )
        } else if isExplicit {
            lists[index].currentItem?.isExplicit = true
        }
    }

    private mutating func mutateCurrentItem(
        _ body: (inout ItemContext) -> Void
    ) {
        let index = lists.count - 1
        guard var item = lists[index].currentItem else {
            return
        }

        body(&item)
        lists[index].currentItem = item
    }

    private mutating func closeItemParagraph(_ item: inout ItemContext) {
        if let watermark = item.paragraphFormattingWatermark {
            restoreFormatting(to: watermark)
        }
        item.paragraphFormattingWatermark = nil
    }

    private mutating func finishCurrentListItem() {
        guard !lists.isEmpty else {
            return
        }

        let listIndex = lists.count - 1
        guard var item = lists[listIndex].currentItem else {
            return
        }

        closeItemParagraph(&item)
        restoreFormatting(to: item.formattingWatermarkAtStart)

        if item.shouldEmit {
            lists[listIndex].items.append(item.makeItem())
        }
        lists[listIndex].currentItem = nil
    }

    private mutating func closeLists(through tagName: String) {
        guard let matchingIndex = lists.lastIndex(where: {
            !$0.isSynthetic && $0.tagName == tagName
        }) else {
            return
        }

        while lists.count > matchingIndex {
            closeLastList()
        }
    }

    private mutating func closeAllLists() {
        while !lists.isEmpty {
            closeLastList()
        }
    }

    private mutating func closeLastList() {
        finishCurrentListItem()
        let context = lists.removeLast()
        restoreFormatting(to: context.formattingWatermarkAtStart)
        guard !context.items.isEmpty else {
            return
        }
        let list = HTMLList(style: context.style, items: context.items)

        if lists.isEmpty {
            blocks.append(.list(list))
        } else {
            ensureCurrentListItem(isExplicit: false)
            mutateCurrentItem { item in
                item.append(list)
            }
        }
    }

    private var currentFormattingWatermark: Int {
        formattingGenerations.count
    }

    private mutating func pushFormatting(tagName: String, link: URL?) {
        let frame = FormattingFrame(
            id: nextFormattingID,
            tagName: tagName,
            link: link
        )
        formattingGenerations.append(frame.id)
        activeFormatting[frame.id] = frame
        if let tagStack = activeFormattingByTag[tagName] {
            tagStack.generations.append(frame.id)
        } else {
            activeFormattingByTag[tagName] = FormattingGenerationStack(frame.id)
        }
        nextFormattingID += 1
        activateFormatting(frame)
    }

    private mutating func removeFormatting(tagName: String) {
        guard let tagStack = activeFormattingByTag[tagName] else {
            return
        }

        while let id = tagStack.generations.popLast() {
            if deactivateFormatting(id: id) {
                break
            }
        }

        if tagStack.generations.isEmpty {
            activeFormattingByTag.removeValue(forKey: tagName)
        }
    }

    private mutating func restoreFormatting(to watermark: Int) {
        guard watermark < formattingGenerations.count else {
            return
        }

        while formattingGenerations.count > watermark {
            let id = formattingGenerations.removeLast()
            deactivateFormatting(id: id)
        }
    }

    private mutating func activateFormatting(_ frame: FormattingFrame) {
        switch frame.tagName {
        case "strong", "b":
            boldFormattingCount += 1
        case "em", "i":
            italicFormattingCount += 1
        case "del":
            strikethroughFormattingCount += 1
        case "a":
            activeLink = frame.link
        default:
            break
        }
        refreshCachedTextStyle()
    }

    @discardableResult
    private mutating func deactivateFormatting(id: Int) -> Bool {
        guard let frame = activeFormatting.removeValue(forKey: id) else {
            return false
        }

        switch frame.tagName {
        case "strong", "b":
            boldFormattingCount -= 1
        case "em", "i":
            italicFormattingCount -= 1
        case "del":
            strikethroughFormattingCount -= 1
        case "a":
            activeLink = nil
        default:
            break
        }
        refreshCachedTextStyle()
        return true
    }

    private mutating func refreshCachedTextStyle() {
        cachedTextStyle = HTMLTextStyle(
            isBold: boldFormattingCount > 0,
            isItalic: italicFormattingCount > 0,
            isStruckThrough: strikethroughFormattingCount > 0,
            validatedLink: activeLink
        )
    }

    private static let suppressedTagNames: Set<String> = [
        "script",
        "style",
        "template",
    ]
}

private struct InlineAccumulator {
    private var completedInlines: [HTMLInline] = []
    private var pendingText = ""
    private var pendingStyle: HTMLTextStyle?
    private var hasPendingParagraphBoundary = false

    var inlines: [HTMLInline] {
        guard let pendingStyle, !pendingText.isEmpty else {
            return completedInlines
        }

        var result = completedInlines
        result.append(.text(pendingText, style: pendingStyle))
        return result
    }

    var isEmpty: Bool {
        completedInlines.isEmpty && pendingText.isEmpty
    }

    mutating func append(_ rawText: String, style: HTMLTextStyle) {
        let hasNonWhitespace = containsNonWhitespace(rawText)
        if hasPendingParagraphBoundary, hasNonWhitespace {
            appendLineBreak()
        }

        var normalized = ""
        normalized.reserveCapacity(rawText.utf8.count)
        var isAtLineStart = atLineStart
        var previousWasWhitespace = endsInCollapsedWhitespace

        for scalar in rawText.unicodeScalars {
            if isHTMLASCIIWhitespace(scalar) {
                if !isAtLineStart, !previousWasWhitespace {
                    normalized.append(" ")
                    previousWasWhitespace = true
                }
            } else {
                normalized.unicodeScalars.append(scalar)
                isAtLineStart = false
                previousWasWhitespace = false
            }
        }

        appendRun(normalized, style: style)
    }

    mutating func appendLineBreak() {
        trimTrailingWhitespace()
        flushPendingText()
        completedInlines.append(.lineBreak)
        hasPendingParagraphBoundary = false
    }

    mutating func markParagraphBoundary() {
        trimTrailingWhitespace()
        if !isEmpty, !atLineStart {
            hasPendingParagraphBoundary = true
        }
    }

    mutating func finish() {
        trimTrailingWhitespace()
        flushPendingText()
        hasPendingParagraphBoundary = false
    }

    private var atLineStart: Bool {
        if !pendingText.isEmpty {
            return false
        }
        guard let last = completedInlines.last else {
            return true
        }
        if case .lineBreak = last {
            return true
        }
        return false
    }

    private var endsInCollapsedWhitespace: Bool {
        if let last = pendingText.last {
            return last == " "
        }
        guard case let .text(text, _) = completedInlines.last else {
            return false
        }
        return text.last == " "
    }

    private mutating func appendRun(_ text: String, style: HTMLTextStyle) {
        guard !text.isEmpty else {
            return
        }

        if pendingStyle == style {
            pendingText.append(contentsOf: text)
        } else {
            flushPendingText()
            pendingStyle = style
            pendingText = text
        }
    }

    private mutating func trimTrailingWhitespace() {
        if pendingText.last == " " {
            pendingText.removeLast()
            if pendingText.isEmpty {
                pendingStyle = nil
            }
        }

        while pendingText.isEmpty,
              case let .text(text, style) = completedInlines.last,
              text.last == " " {
            var trimmed = text
            trimmed.removeLast()
            if trimmed.isEmpty {
                completedInlines.removeLast()
            } else {
                completedInlines[completedInlines.count - 1] = .text(
                    trimmed,
                    style: style
                )
            }
        }
    }

    private mutating func flushPendingText() {
        guard let pendingStyle, !pendingText.isEmpty else {
            self.pendingStyle = nil
            return
        }

        completedInlines.append(.text(pendingText, style: pendingStyle))
        pendingText = ""
        self.pendingStyle = nil
    }
}

private func asciiLowercased(_ value: String) -> String {
    var result = ""
    result.reserveCapacity(value.utf8.count)

    for scalar in value.unicodeScalars {
        if (0x41...0x5A).contains(scalar.value) {
            result.unicodeScalars.append(
                Unicode.Scalar(scalar.value + 0x20)!
            )
        } else {
            result.unicodeScalars.append(scalar)
        }
    }

    return result
}

private func containsNonWhitespace(_ value: String) -> Bool {
    value.unicodeScalars.contains { !isHTMLASCIIWhitespace($0) }
}

private func isHTMLASCIIWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0C, 0x0D, 0x20:
        true
    default:
        false
    }
}
