import SwiftUI

/// Slim scrollbar down the right edge of the script. Drag it to scrub.
///
/// The thumb is sized by how much of the script fits on screen and positioned by how far
/// through it you are, so it doubles as a progress indicator for the whole read.
struct ScriptScrollBar: View {
    @ObservedObject var engine: TeleprompterEngine
    var width: CGFloat = 5

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.height
            let thumb = thumbHeight(track: track)
            let travel = max(1, track - thumb)

            ZStack(alignment: .top) {
                Capsule().fill(.white.opacity(0.10))
                Capsule()
                    .fill(.white.opacity(dragging ? 0.75 : 0.42))
                    .frame(height: thumb)
                    .offset(y: travel * progress)
            }
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance 0 so a plain click jumps straight to that point.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        // Centre the thumb on the cursor rather than its top edge, so the
                        // script lands where you are pointing.
                        engine.scrub(toProgress: (value.location.y - thumb / 2) / travel)
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(width: width)
    }

    private var progress: CGFloat {
        guard engine.maxOffset > 0 else { return 0 }
        return min(1, max(0, engine.offset / engine.maxOffset))
    }

    private func thumbHeight(track: CGFloat) -> CGFloat {
        guard engine.contentHeight > 0 else { return track }
        let visible = min(1, engine.viewportHeight / engine.contentHeight)
        return max(18, track * visible)
    }
}
