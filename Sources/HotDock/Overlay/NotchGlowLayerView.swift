import AppKit
import QuartzCore

/// The "app is live" indicator: Siri-style colours travelling around the notch outline.
///
/// This is Core Animation rather than SwiftUI, deliberately. A `repeatForever` SwiftUI
/// animation re-runs the view's body and the layout engine every frame; measured here, four
/// different SwiftUI versions of this effect all cost about 4% of a core, continuously, for a
/// 222x49 indicator. A `CABasicAnimation` on a layer is handed to the window server once and
/// runs there, so the app itself does no per-frame work at all.
///
/// Only three sides are ever drawn. The path deliberately has no top edge: that edge would sit
/// inside the notch cut-out, where the display has no pixels.
final class NotchGlowLayerView: NSView {

    private let notchSize: CGSize
    private let pad: CGFloat
    private let padBottom: CGFloat
    private let dark: Bool

    private let haloLayer = CAShapeLayer()
    private let sweepContainer = CALayer()
    private let sweepGradient = CAGradientLayer()
    private let sweepMask = CAShapeLayer()

    private let cornerRadius: CGFloat = 11
    private let spinDuration: CFTimeInterval = 5.5

    /// Siri / Apple Intelligence palette. First and last stop match so the sweep is seamless
    /// as the gradient turns past 360°.
    private static let siriColors: [CGColor] = [
        NSColor(srgbRed: 0.16, green: 0.78, blue: 1.00, alpha: 1).cgColor,   // cyan
        NSColor(srgbRed: 0.33, green: 0.42, blue: 1.00, alpha: 1).cgColor,   // blue
        NSColor(srgbRed: 0.70, green: 0.30, blue: 1.00, alpha: 1).cgColor,   // violet
        NSColor(srgbRed: 1.00, green: 0.26, blue: 0.68, alpha: 1).cgColor,   // magenta
        NSColor(srgbRed: 1.00, green: 0.44, blue: 0.33, alpha: 1).cgColor,   // coral
        NSColor(srgbRed: 0.99, green: 0.74, blue: 0.26, alpha: 1).cgColor,   // amber
        NSColor(srgbRed: 0.16, green: 0.78, blue: 1.00, alpha: 1).cgColor,   // back to cyan
    ]

    init(notchSize: CGSize, pad: CGFloat, padBottom: CGFloat, dark: Bool) {
        self.notchSize = notchSize
        self.pad = pad
        self.padBottom = padBottom
        self.dark = dark
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(haloLayer)
        layer?.addSublayer(sweepContainer)
        sweepContainer.addSublayer(sweepGradient)
        sweepContainer.mask = sweepMask
        configureLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    // MARK: Appearance

    private func configureLayers() {
        haloLayer.fillColor = nil
        haloLayer.lineCap = .round

        if dark {
            // Near-black rather than transparent: it keeps the notch's shape crisp against a
            // bright video frame instead of letting the picture bleed up to the cut-out edge.
            haloLayer.strokeColor = NSColor.black.withAlphaComponent(0.92).cgColor
            haloLayer.lineWidth = 1.8
            haloLayer.shadowOpacity = 0
            sweepContainer.isHidden = true
            return
        }

        // Soft coloured spill around the outline. A layer shadow is drawn by the GPU and never
        // changes, so it costs nothing to keep on screen.
        haloLayer.strokeColor = NSColor(srgbRed: 0.55, green: 0.45, blue: 1.0, alpha: 0.5).cgColor
        haloLayer.lineWidth = 3
        haloLayer.shadowColor = NSColor(srgbRed: 0.5, green: 0.6, blue: 1.0, alpha: 1).cgColor
        haloLayer.shadowRadius = 6
        haloLayer.shadowOpacity = 0.85
        haloLayer.shadowOffset = .zero

        sweepGradient.type = .conic
        sweepGradient.colors = Self.siriColors
        sweepGradient.locations = (0...6).map { NSNumber(value: Double($0) / 6.0) }
        sweepGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        sweepGradient.endPoint = CGPoint(x: 0.5, y: 0)

        // The mask strokes the outline; the gradient spins inside it. Masking the *container*
        // rather than the gradient keeps the outline still while the colours move.
        sweepMask.fillColor = nil
        sweepMask.strokeColor = NSColor.white.cgColor
        sweepMask.lineWidth = 1.8
        sweepMask.lineCap = .round
    }

    private func updateGeometry() {
        let shapeWidth = notchSize.width + pad * 2
        let shapeHeight = notchSize.height + padBottom
        let rect = CGRect(x: (bounds.width - shapeWidth) / 2,
                          y: bounds.height - shapeHeight,
                          width: shapeWidth,
                          height: shapeHeight)
        let path = outlinePath(in: rect)

        // Geometry changes come from screen reconfiguration, not animation; applying them
        // inside a disabled action block avoids CA's implicit quarter-second cross-fade.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        haloLayer.frame = bounds
        haloLayer.path = path
        haloLayer.shadowPath = path

        sweepContainer.frame = bounds
        sweepMask.frame = bounds
        sweepMask.path = path

        // Square big enough that the spinning conic gradient still covers a wide, short outline
        // at every angle; otherwise the corners go transparent as it turns.
        let side = (rect.width * rect.width + rect.height * rect.height).squareRoot()
        sweepGradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        sweepGradient.position = CGPoint(x: rect.midX, y: rect.midY)

        CATransaction.commit()

        startSpinIfNeeded()
    }

    private func outlinePath(in rect: CGRect) -> CGPath {
        // Open path: down the left side, around the two bottom corners, up the right side.
        // No top edge — that would fall inside the notch, where nothing is visible.
        let r = min(cornerRadius, rect.height, rect.width / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    private func startSpinIfNeeded() {
        guard !dark, sweepGradient.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = spinDuration
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        sweepGradient.add(spin, forKey: "spin")
    }
}
