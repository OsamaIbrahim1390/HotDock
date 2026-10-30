import AppKit
import SwiftUI
import QuartzCore

/// Album art as a spinning record.
///
/// Core Animation rather than SwiftUI, for the same reason as the notch glow: a
/// `repeatForever` SwiftUI rotation re-runs the view body and the layout engine every frame,
/// which measured at several percent of a core. A `CABasicAnimation` is handed to the window
/// server once and costs the app nothing per frame.
///
/// Pausing uses CA's own clock (`speed = 0` plus `timeOffset`) rather than removing the
/// animation, so the record stops where it is and picks up from the same angle — like
/// lifting the needle rather than whipping the disc back to the start.
final class SpotifyDiscLayerView: NSView {

    private let disc = CALayer()
    private let art = CALayer()
    private let hole = CALayer()
    private let spindle = CALayer()

    private var spinning = false
    private let revolutionDuration: CFTimeInterval = 3.2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(disc)
        disc.addSublayer(art)
        disc.addSublayer(hole)
        disc.addSublayer(spindle)

        // The artwork is the whole record face, not a small label in the middle. Only the
        // spindle hole sits on top, which is what still reads as vinyl rather than a circular
        // avatar — and gives the eye something to track while it turns.
        disc.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
        disc.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
        disc.borderWidth = 0.5
        disc.masksToBounds = true

        art.masksToBounds = true
        art.contentsGravity = .resizeAspectFill
        art.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor

        hole.backgroundColor = NSColor(white: 0.04, alpha: 0.92).cgColor
        spindle.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        let rect = CGRect(x: (bounds.width - side) / 2,
                          y: (bounds.height - side) / 2,
                          width: side, height: side)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        disc.bounds = CGRect(origin: .zero, size: rect.size)
        disc.position = CGPoint(x: rect.midX, y: rect.midY)
        disc.cornerRadius = side / 2

        art.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        art.position = CGPoint(x: side / 2, y: side / 2)
        art.cornerRadius = side / 2

        let holeSide = max(2.5, side * 0.11)
        hole.bounds = CGRect(x: 0, y: 0, width: holeSide, height: holeSide)
        hole.position = CGPoint(x: side / 2, y: side / 2)
        hole.cornerRadius = holeSide / 2

        let pinSide = max(1.2, side * 0.045)
        spindle.bounds = CGRect(x: 0, y: 0, width: pinSide, height: pinSide)
        spindle.position = CGPoint(x: side / 2, y: side / 2)
        spindle.cornerRadius = pinSide / 2

        CATransaction.commit()
    }

    func update(image: NSImage?, spinning shouldSpin: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        art.contents = image
        CATransaction.commit()

        guard shouldSpin != spinning else { return }
        spinning = shouldSpin
        shouldSpin ? resume() : pause()
    }

    private func startIfNeeded() {
        guard disc.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = revolutionDuration
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        disc.add(spin, forKey: "spin")
    }

    private func pause() {
        startIfNeeded()
        let now = disc.convertTime(CACurrentMediaTime(), from: nil)
        disc.speed = 0
        disc.timeOffset = now
    }

    private func resume() {
        startIfNeeded()
        let paused = disc.timeOffset
        disc.speed = 1
        disc.timeOffset = 0
        disc.beginTime = 0
        disc.beginTime = disc.convertTime(CACurrentMediaTime(), from: nil) - paused
    }
}

struct SpotifyDisc: NSViewRepresentable {
    let image: NSImage?
    let spinning: Bool

    func makeNSView(context: Context) -> SpotifyDiscLayerView {
        let view = SpotifyDiscLayerView()
        view.update(image: image, spinning: spinning)
        return view
    }

    func updateNSView(_ view: SpotifyDiscLayerView, context: Context) {
        view.update(image: image, spinning: spinning)
    }
}
