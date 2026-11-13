import SwiftUI
import UIKit

/// The town map in the iPhone's own zooming scroll view: pinching follows your fingers
/// exactly and eases to a stop, like zooming a photo. The pixel art is drawn once and
/// scaled with nearest-neighbour filtering, so it stays crisp at every zoom level, and
/// when you let go it eases to the nearest size where every art pixel is a whole number
/// of screen pixels.
struct ZoomableWorld<Content: View>: UIViewRepresentable {
    /// The world's size at zoom 1.
    let contentSize: CGSize
    let minZoom: CGFloat
    let maxZoom: CGFloat
    /// Zoom levels that land exactly on whole screen pixels are multiples of this.
    let snapStep: CGFloat
    /// Space at the bottom covered by the drawer.
    let bottomInset: CGFloat
    /// When set, the map glides so this point (in world coordinates at zoom 1) sits in view.
    var focus: CGPoint? = nil
    /// Zoom to use with `focus`; nil keeps the current zoom.
    var focusZoom: CGFloat? = nil
    /// Reports the zoom and how far the map is scrolled.
    var onChange: (_ zoom: CGFloat, _ offset: CGPoint) -> Void
    var onBackgroundTap: () -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WorldScrollView {
        let scroll = WorldScrollView()
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bounces = false
        // No rubber-banding past the limits: the farthest zoom-out is a hard stop.
        scroll.bouncesZoom = false
        scroll.backgroundColor = .clear
        scroll.decelerationRate = .normal

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        host.safeAreaRegions = []
        // An empty stand-in takes the zoom; the town itself is re-laid out at the new size each frame,
        // so SwiftUI redraws it sharp instead of stretching a picture.
        let container = UIView(frame: CGRect(origin: .zero, size: contentSize))
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        scroll.addSubview(container)
        scroll.addSubview(host.view)
        context.coordinator.container = container
        scroll.contentSize = contentSize
        context.coordinator.host = host
        context.coordinator.scroll = scroll

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        scroll.addGestureRecognizer(tap)

        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.didLayout() }
        apply(to: scroll)
        return scroll
    }

    func updateUIView(_ scroll: WorldScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.resize(to: contentSize)
        // Pass along new inputs (like pausing while a screen covers the town). Same view type, so its state is kept.
        context.coordinator.host?.rootView = content()
        apply(to: scroll)
        context.coordinator.glide(to: focus, zoom: focusZoom)
    }

    private func apply(to scroll: UIScrollView) {
        scroll.minimumZoomScale = minZoom
        scroll.maximumZoomScale = maxZoom
    }

    final class WorldScrollView: UIScrollView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableWorld
        weak var scroll: UIScrollView?
        var host: UIHostingController<Content>?
        var container: UIView?
        private(set) var placed = false
        private var lastBounds: CGSize = .zero
        private var lastReport: (CGFloat, CGPoint) = (-1, CGPoint(x: -1, y: -1))
        private var lastFocus: CGPoint?
        private var appliedInitialFocus = false

        /// Smoothly scroll so a world point sits in the upper part of the screen, leaving room for a tooltip below.
        private var lastZoom: CGFloat?

        func glide(to point: CGPoint?, zoom: CGFloat?) {
            guard point != lastFocus || zoom != lastZoom else { return }
            let zoomChanged = zoom != lastZoom
            lastFocus = point
            lastZoom = zoom
            guard placed else { return }   // didLayout applies it once the map is in place
            applyFocus(animated: true, slow: zoomChanged)
        }

        private func target(for point: CGPoint, in scroll: UIScrollView) -> CGPoint {
            let z = scroll.zoomScale, b = scroll.bounds.size, inset = scroll.contentInset
            var x = point.x * z - b.width / 2
            var y = point.y * z - (b.height - parent.bottomInset) * 0.36
            x = min(max(x, -inset.left), scroll.contentSize.width + inset.right - b.width)
            y = min(max(y, -inset.top), scroll.contentSize.height + inset.bottom - b.height)
            return CGPoint(x: x, y: y)
        }

        private func applyFocus(animated: Bool, slow: Bool = false) {
            guard let point = lastFocus, let scroll else { return }
            let move = {
                if let z = self.lastZoom { scroll.zoomScale = min(max(z, scroll.minimumZoomScale), scroll.maximumZoomScale) }
                self.keepInside(scroll)
                scroll.contentOffset = self.target(for: point, in: scroll)
            }
            if animated && slow, let z1 = lastZoom {
                zoomInto(point, zoom: z1, in: scroll)
            } else if animated {
                UIView.animate(withDuration: 0.55, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    move()
                } completion: { [weak self] _ in
                    self?.report(scroll, force: true)
                }
            } else {
                move()
            }
            report(scroll, force: true)
        }

        // MARK: One continuous zoom straight into a point

        private var link: CADisplayLink?
        private var zoomStart: (time: CFTimeInterval, z0: CGFloat, z1: CGFloat, s0: CGPoint, s1: CGPoint, point: CGPoint)?

        /// Zooms and pans together so the point glides from where it is on screen to its final spot,
        /// growing the whole way: it reads as diving into that point, not zoom-then-slide.
        private func zoomInto(_ point: CGPoint, zoom target: CGFloat, in scroll: UIScrollView) {
            link?.invalidate()
            let z0 = scroll.zoomScale, o0 = scroll.contentOffset
            let s0 = CGPoint(x: point.x * z0 - o0.x, y: point.y * z0 - o0.y)
            // Work out the end position, then put everything back.
            let z1 = min(max(target, scroll.minimumZoomScale), scroll.maximumZoomScale)
            scroll.zoomScale = z1; keepInside(scroll)
            let o1 = self.target(for: point, in: scroll)
            let s1 = CGPoint(x: point.x * z1 - o1.x, y: point.y * z1 - o1.y)
            scroll.zoomScale = z0; keepInside(scroll); scroll.contentOffset = o0
            zoomStart = (CACurrentMediaTime(), z0, z1, s0, s1, point)
            beginLiveZoom()
            let l = CADisplayLink(target: self, selector: #selector(stepZoom))
            l.add(to: .main, forMode: .common)
            link = l
        }

        @objc private func stepZoom() {
            guard let a = zoomStart, let scroll else { link?.invalidate(); return }
            let duration = 1.3
            let k = min(1, (CACurrentMediaTime() - a.time) / duration)
            let e = CGFloat(k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2)   // ease in-out
            let z = a.z0 + (a.z1 - a.z0) * e
            let sx = a.s0.x + (a.s1.x - a.s0.x) * e, sy = a.s0.y + (a.s1.y - a.s0.y) * e
            scroll.zoomScale = z
            keepInside(scroll)
            let inset = scroll.contentInset, b = scroll.bounds.size
            let x = min(max(a.point.x * z - sx, -inset.left), scroll.contentSize.width + inset.right - b.width)
            let y = min(max(a.point.y * z - sy, -inset.top), scroll.contentSize.height + inset.bottom - b.height)
            scroll.contentOffset = CGPoint(x: x, y: y)
            if k >= 1 {
                link?.invalidate(); link = nil; zoomStart = nil
                endLiveZoom()
                report(scroll, force: true)
            }
        }

        init(_ parent: ZoomableWorld) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { container }

        /// The world got a new size (an iPad turned, or a window resized): resize it in place,
        /// keeping the same spot in the middle of the screen.
        func resize(to size: CGSize) {
            guard let scroll, let container, container.bounds.size != size, size.width > 0 else { return }
            let z = scroll.zoomScale
            let old = container.bounds.size
            let mid = CGPoint(x: (scroll.contentOffset.x + scroll.bounds.width / 2) / max(old.width * z, 1),
                              y: (scroll.contentOffset.y + scroll.bounds.height / 2) / max(old.height * z, 1))
            container.bounds = CGRect(origin: .zero, size: size)
            container.center = CGPoint(x: size.width * z / 2, y: size.height * z / 2)
            scroll.contentSize = CGSize(width: size.width * z, height: size.height * z)
            refreshVisible()
            keepInside(scroll)
            recentre(scroll, on: mid)
        }

        private func recentre(_ scroll: UIScrollView, on mid: CGPoint) {
            let cs = scroll.contentSize, b = scroll.bounds.size, inset = scroll.contentInset
            let x = min(max(mid.x * cs.width - b.width / 2, -inset.left), max(cs.width - b.width + inset.right, -inset.left))
            let y = min(max(mid.y * cs.height - b.height / 2, -inset.top), max(cs.height - b.height + inset.bottom, -inset.top))
            scroll.contentOffset = CGPoint(x: x, y: y)
        }

        func didLayout() {
            guard let scroll, scroll.bounds.width > 0 else { return }
            if placed && lastBounds != .zero && lastBounds != scroll.bounds.size, let c = container {
                // The screen itself changed shape: keep looking at the same part of town.
                let cs = scroll.contentSize
                let mid = CGPoint(x: (scroll.contentOffset.x + lastBounds.width / 2) / max(cs.width, 1),
                                  y: (scroll.contentOffset.y + lastBounds.height / 2) / max(cs.height, 1))
                _ = c
                lastBounds = scroll.bounds.size
                keepInside(scroll)
                recentre(scroll, on: mid)
            }
            lastBounds = scroll.bounds.size
            keepInside(scroll)
            refreshVisible()
            if !placed {
                placed = true
                // Start centred on the town.
                let cs = scroll.contentSize, b = scroll.bounds.size
                scroll.contentOffset = CGPoint(
                    x: max((cs.width - b.width) / 2, -scroll.contentInset.left),
                    y: max((cs.height + parent.bottomInset - b.height) / 2, -scroll.contentInset.top)
                )
            }
            if lastFocus != nil && !appliedInitialFocus {
                appliedInitialFocus = true
                applyFocus(animated: false)
            }
            report(scroll)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Hard stop: never further out (or in) than allowed, whatever asked for it.
            let z = scrollView.zoomScale
            let clamped = min(max(z, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            if abs(clamped - z) > 0.0001 { scrollView.zoomScale = clamped; return }
            keepInside(scrollView)
            refreshVisible()
            report(scrollView)
        }

        // MARK: Cheap live zoom
        // Laying the whole town out again at every step of a pinch meant redrawing thousands of pixels
        // 60–120 times a second. While fingers (or the tour's glide) are zooming, the last sharp picture
        // is just scaled; when the zoom settles, the town is laid out once at the new size.

        /// The zoom the town was last laid out at, while a live zoom is running.
        private var frozenZoom: CGFloat?

        private var liveZooming: Bool {
            guard let scroll else { return false }
            return scroll.isZooming || scroll.isZoomBouncing || zoomStart != nil || snapping
        }
        private var snapping = false

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            beginLiveZoom()
        }

        private func beginLiveZoom() {
            guard frozenZoom == nil, let scroll, host?.view != nil else { return }
            frozenZoom = scroll.zoomScale
        }

        private func endLiveZoom() {
            guard frozenZoom != nil, let v = host?.view, let c = container else { return }
            frozenZoom = nil
            v.transform = .identity
            v.frame = c.frame
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            refreshVisible()
            report(scrollView)
        }

        /// SwiftUI only draws what it thinks is on screen; make it look again after zooming or scrolling.
        private func refreshVisible() {
            guard let v = host?.view, let c = container else { return }
            if let z0 = frozenZoom, let scroll, liveZooming {
                // Keep the old layout, scaled to where the town is now.
                let k = scroll.zoomScale / max(z0, 0.0001)
                let size = CGSize(width: c.bounds.width * z0, height: c.bounds.height * z0)
                if v.bounds.size != size { v.transform = .identity; v.frame = CGRect(origin: .zero, size: size) }
                v.transform = CGAffineTransform(scaleX: k, y: k)
                v.center = c.center
                return
            }
            if frozenZoom != nil { endLiveZoom(); return }
            if v.frame != c.frame { v.frame = c.frame }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Ease to the nearest crisp size (every art pixel a whole number of screen pixels).
            let step = parent.snapStep
            let target = min(max((scale / step).rounded() * step, parent.minZoom), parent.maxZoom)
            guard abs(target - scale) > 0.001 else { endLiveZoom(); return }
            snapping = true
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                scrollView.zoomScale = target
            } completion: { [weak self] _ in
                self?.snapping = false
                self?.endLiveZoom()
            }
        }

        /// When the world is smaller than the screen, centre it sideways and sit it just above the drawer.
        private func keepInside(_ scroll: UIScrollView) {
            let cs = scroll.contentSize, b = scroll.bounds.size
            let side = max(0, (b.width - cs.width) / 2)
            let top = max(0, b.height - parent.bottomInset - cs.height)
            let insets = UIEdgeInsets(top: top, left: side, bottom: parent.bottomInset, right: side)
            if scroll.contentInset != insets { scroll.contentInset = insets }
        }

        private func report(_ scroll: UIScrollView, force: Bool = false) {
            let z = scroll.zoomScale, o = scroll.contentOffset
            guard force || abs(z - lastReport.0) > 0.0005 || abs(o.x - lastReport.1.x) > 0.25 || abs(o.y - lastReport.1.y) > 0.25 else { return }
            lastReport = (z, o)
            parent.onChange(z, o)
        }

        @objc func tapped() { parent.onBackgroundTap() }
    }
}
