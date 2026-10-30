import SwiftUI

/// The scrolling script.
///
/// This is a clipped container with the text offset inside it, not a `ScrollView`: a scroll
/// view would bring its own momentum, bounce and scrollbar, all of which fight a teleprompter.
/// Offsetting a plain stack means the only thing moving the text is the engine.
struct TeleprompterView: View {
    @ObservedObject var engine: TeleprompterEngine
    @ObservedObject var settings: Settings

    /// Named space so each heading can report its position relative to the top of the script,
    /// independent of how far we have scrolled.
    private static let contentSpace = "hotdock.script"

    var body: some View {
        GeometryReader { viewport in
            content(width: viewport.size.width)
                .frame(width: viewport.size.width, alignment: .leading)
                .offset(y: -engine.offset)
                .frame(maxHeight: .infinity, alignment: .top)
                .onAppear { engine.setViewportHeight(viewport.size.height) }
                .onChange(of: viewport.size.height) { _, height in engine.setViewportHeight(height) }
        }
        .clipped()
        .contentShape(Rectangle())
        // Pausing on hover is scoped to the text itself. Covering the whole card would mean
        // that clicking Play — with the cursor necessarily on the button — instantly paused
        // again, which looks exactly like the button not working.
        .onHover { engine.isPausedByHover = $0 }
        .onPreferenceChange(ContentHeightKey.self) { height in
            engine.setContentHeight(height)
        }
        .onPreferenceChange(SectionOffsetKey.self) { offsets in
            engine.updateSectionOffsets(offsets)
        }

    }

    private func content(width: CGFloat) -> some View {
        // `.equatable()` is the point of splitting this out. The parent re-renders on every
        // frame because `engine.offset` is published, and without this SwiftUI would rebuild
        // every Text in the script 120 times a second. ScriptContent's inputs do not change
        // while scrolling, so SwiftUI can skip its body entirely and just move the result.
        ScriptContent(width: width,
                      blocks: engine.document.blocks,
                      fontSize: settings.fontSize,
                      fontDesign: settings.scriptFont,
                      lineSpacing: settings.lineSpacing,
                      trailingRoom: max(0, engine.viewportHeight * 0.5),
                      coordinateSpace: Self.contentSpace)
            .equatable()
    }
}

/// The script itself. Deliberately holds plain values rather than the engine, so equality is
/// cheap to check and scrolling cannot invalidate it.
private struct ScriptContent: View, Equatable {
    /// The width of the script area, and part of this view's equality.
    ///
    /// Both halves matter. `.equatable()` below tells SwiftUI it may skip re-running this
    /// body, and without the width in `==` it did exactly that: the text kept the layout from
    /// whatever width it first saw, so long lines ended in an ellipsis instead of rewrapping.
    /// Measured, loading one long line and resizing the card from 900 to 320 points:
    ///
    ///     without width in ==   97, 97, 97, 97, 97   (frozen)
    ///     with it               97, 81, 97, 97, 113  (rewraps)
    let width: CGFloat
    let blocks: [ScriptBlock]
    let fontSize: Double
    let fontDesign: ScriptFont
    let lineSpacing: Double
    let trailingRoom: CGFloat
    let coordinateSpace: String

    static func == (lhs: ScriptContent, rhs: ScriptContent) -> Bool {
        lhs.width == rhs.width
            && lhs.fontSize == rhs.fontSize
            && lhs.fontDesign == rhs.fontDesign
            && lhs.lineSpacing == rhs.lineSpacing
            && lhs.trailingRoom == rhs.trailingRoom
            && lhs.blocks == rhs.blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(blocks) { block in
                blockView(block)
            }
            // Trailing room so the final line can rise clear of the bottom edge instead of
            // stopping flush against it.
            Color.clear.frame(height: trailingRoom)
        }
        .coordinateSpace(name: coordinateSpace)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            }
        )
    }

    @ViewBuilder
    private func blockView(_ block: ScriptBlock) -> some View {
        if block.isBlank {
            Color.clear.frame(height: fontSize * 0.45)
        } else if block.isHeading {
            Text(block.text)
                .font(.system(size: fontSize * 1.08, weight: .bold, design: fontDesign.design))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SectionOffsetKey.self,
                            value: [block.id: geo.frame(in: .named(coordinateSpace)).minY])
                    }
                )
        } else {
            Text(block.text)
                .font(.system(size: fontSize, weight: .medium, design: fontDesign.design))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SectionOffsetKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
