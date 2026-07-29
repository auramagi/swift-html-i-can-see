#if canImport(SwiftUI)
import SwiftUI

/// Presentation choices used by ``HTMLDocumentView``.
///
/// The style is intentionally separate from the persisted semantic document.
/// All dimensions use points and continue to participate in SwiftUI's normal
/// layout, Dynamic Type, accessibility, and right-to-left behavior.
public struct HTMLDocumentStyle: Hashable, Sendable {
    public var blockSpacing: CGFloat
    public var listItemSpacing: CGFloat
    public var nestedListSpacing: CGFloat
    public var listIndentation: CGFloat
    public var markerSpacing: CGFloat
    public var unorderedListMarker: String
    public var orderedListMarkerSuffix: String
    public var markerColor: Color
    public var linkColor: Color?
    public var underlinesLinks: Bool

    public init(
        blockSpacing: CGFloat = 12,
        listItemSpacing: CGFloat = 6,
        nestedListSpacing: CGFloat = 6,
        listIndentation: CGFloat = 20,
        markerSpacing: CGFloat = 8,
        unorderedListMarker: String = "•",
        orderedListMarkerSuffix: String = ".",
        markerColor: Color = .secondary,
        linkColor: Color? = nil,
        underlinesLinks: Bool = false
    ) {
        self.blockSpacing = blockSpacing
        self.listItemSpacing = listItemSpacing
        self.nestedListSpacing = nestedListSpacing
        self.listIndentation = listIndentation
        self.markerSpacing = markerSpacing
        self.unorderedListMarker = unorderedListMarker
        self.orderedListMarkerSuffix = orderedListMarkerSuffix
        self.markerColor = markerColor
        self.linkColor = linkColor
        self.underlinesLinks = underlinesLinks
    }

    public static let standard = HTMLDocumentStyle()
}

public extension EnvironmentValues {
    /// The presentation style inherited by HTML document views.
    @Entry var htmlDocumentStyle: HTMLDocumentStyle = .standard
}

public extension View {
    /// Sets the presentation style for HTML document views in this subtree.
    nonisolated func htmlDocumentStyle(_ style: HTMLDocumentStyle) -> some View {
        environment(\.htmlDocumentStyle, style)
    }
}
#endif
