import SwiftUI

/// One control that resizes the whole overlay, keeping its proportions.
///
/// A normal `Slider` cannot work here. The card is centred on the notch, so making it wider
/// moves its right-hand side — and therefore this control — out from under the cursor. A
/// position-based slider reads the cursor's offset *within itself*, so the control sliding away
/// changes the reading, which resizes the card again: a feedback loop that makes the size bolt
/// away as soon as you touch it.
///
/// This reads `DragGesture` translation in **global** coordinates instead. Translation is
/// measured from where the drag began on screen, so the control moving underneath has no
/// effect on the value and the drag stays under your control.
struct OverlaySizeSlider: View {
    @ObservedObject var settings: Settings
    @ObservedObject var overlay: OverlayController

    /// Points of overlay width per point of cursor travel.
    ///
    /// One-to-one. At two, the card widened twice as fast as the cursor moved, so its right
    /// edge — where this control lives — slid sideways at exactly the speed of the drag, and
    /// the control ran away under the finger holding it. The card now holds its right edge
    /// still while you drag (see `OverlayController.beginResize`), and 1.0 gives a steady
    /// feel: a short drag nudges, a long one still reaches either end.
    private let sensitivity: Double = 1.0

    private let widthRange: ClosedRange<Double> = 280...1200
    private let heightRange: ClosedRange<Double> = 70...600

    @State private var startWidth: Double?
    @State private var startHeight: Double?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 13)

            GeometryReader { geo in
                let fraction = (settings.overlayWidth - widthRange.lowerBound)
                    / (widthRange.upperBound - widthRange.lowerBound)
                let travel = max(1, geo.size.width - 10)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(height: 3)
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .offset(x: travel * CGFloat(min(1, max(0, fraction))))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if startWidth == nil {
                                startWidth = settings.overlayWidth
                                startHeight = settings.overlayHeight
                                overlay.beginResize()
                            }
                            apply(dragged: Double(value.translation.width))
                        }
                        .onEnded { _ in
                            startWidth = nil
                            startHeight = nil
                            overlay.endResize()
                        }
                )
            }
            .frame(height: 14)

            Text("\(Int(settings.overlayWidth))×\(Int(settings.overlayHeight))")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 52, alignment: .trailing)

            ControlButton(symbol: "arrow.counterclockwise", label: "Reset the overlay size",
                          size: 8) {
                settings.resetOverlaySize()
            }
        }
        .help("Overlay size — drag to scale the whole card")
    }

    /// Scales width and height together from the size the drag started at, so the card keeps
    /// its shape. If either edge of its range is reached, both stop, rather than the overlay
    /// quietly changing proportions.
    private func apply(dragged: Double) {
        guard let startWidth, let startHeight, startWidth > 0 else { return }
        let ratio = startHeight / startWidth

        var width = startWidth + dragged * sensitivity
        width = min(widthRange.upperBound, max(widthRange.lowerBound, width))

        var height = width * ratio
        if height > heightRange.upperBound {
            height = heightRange.upperBound
            width = height / ratio
        } else if height < heightRange.lowerBound {
            height = heightRange.lowerBound
            width = height / ratio
        }

        settings.overlayWidth = (width / 2).rounded() * 2
        settings.overlayHeight = (height / 2).rounded() * 2
    }
}
