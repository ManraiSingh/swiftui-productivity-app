import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct Sprite {
    let rows: [[Character]]
    var palette: [Character: Color] { didSet { key = Self.makeKey(rows, palette) } }
    /// Identifies this drawing (shape and colours), so its picture can be made once and reused.
    private(set) var key: Int

    init(_ rows: [String], _ palette: [Character: Color]) {
        let r = rows.map { Array($0) }
        self.rows = r
        self.palette = palette
        self.key = Self.makeKey(r, palette)
    }

    /// The same drawing with some colors swapped, for extra villagers.
    func recolored(_ changes: [Character: Color]) -> Sprite {
        var copy = self
        copy.palette.merge(changes) { _, new in new }
        return copy
    }

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    private static func makeKey(_ rows: [[Character]], _ palette: [Character: Color]) -> Int {
        var h = Hasher()
        for row in rows { h.combine(String(row)) }
        for (k, v) in palette.sorted(by: { $0.key < $1.key }) { h.combine(k); h.combine(v) }
        return h.finalize()
    }
}

/// Sprites turned into tiny bitmaps (one pixel per art pixel), made once and then drawn as a single
/// picture instead of hundreds of separate squares every frame.
enum SpriteImages {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Int: CGImage] = [:]

    static func image(_ sprite: Sprite, flip: Bool, walkFrame: Int? = nil) -> CGImage? {
        var h = Hasher()
        h.combine(sprite.key); h.combine(flip); h.combine(walkFrame)
        let k = h.finalize()
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[k] { return hit }
        let made = render(sprite, flip: flip, walkFrame: walkFrame)
        if cache.count > 600 { cache.removeAll() }
        cache[k] = made
        return made
    }

    private static func render(_ sprite: Sprite, flip: Bool, walkFrame: Int?) -> CGImage? {
        let w = sprite.width, h = sprite.height
        guard w > 0, h > 0,
              let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let env = EnvironmentValues()
        var colors: [Character: CGColor] = [:]
        func color(_ ch: Character) -> CGColor? {
            if let c = colors[ch] { return c }
            guard let c = sprite.palette[ch]?.resolve(in: env).cgColor else { return nil }
            colors[ch] = c
            return c
        }
        func put(_ x: Int, _ y: Int, _ c: CGColor) {
            let px = flip ? w - 1 - x : x
            cg.setFillColor(c)
            cg.fill(CGRect(x: px, y: h - 1 - y, width: 1, height: 1))
        }
        let odd = (walkFrame ?? 0) % 2 == 1
        for (r, row) in sprite.rows.enumerated() where !odd || r < 14 {
            for (c, ch) in row.enumerated() where ch != "." {
                if let col = color(ch) { put(c, r, col) }
            }
        }
        if odd, sprite.rows.count > 14 {
            // Legs apart, mid-step (matches the old per-pixel walking drawing).
            let pantsKey = sprite.rows[14].count > 4 ? sprite.rows[14][4] : "p"
            let pants = color(pantsKey) ?? CGColor(gray: 0.5, alpha: 1)
            let ink = color("k") ?? CGColor(gray: 0, alpha: 1)
            for (r, row) in ["..kppk....kppk..", "..kkk......kkk.."].enumerated() {
                for (c, ch) in row.enumerated() where ch != "." { put(c, 14 + r, ch == "k" ? ink : pants) }
            }
        }
        return cg.makeImage()
    }
}

/// Collects squares of one colour drawn back to back and fills them as one shape.
/// The town draws thousands of art pixels a frame; one fill call each was the main cost.
final class PixelBatch {
    let ctx: GraphicsContext
    private var path = Path()
    private var color: Color?
    private var count = 0

    init(_ ctx: GraphicsContext) { self.ctx = ctx }

    func add(_ r: CGRect, _ c: Color) {
        if c != color { flush(); color = c }
        path.addRect(r)
        count += 1
    }

    func flush() {
        if count > 0, let color { ctx.fill(path, with: .color(color)) }
        path = Path(); count = 0; color = nil
    }
}

/// A small bitmap the art is drawn into, one frame at a time, at `k` image pixels per art pixel.
/// Filling a few thousand tiny squares in a bitmap is far cheaper than handing each one to SwiftUI.
final class PixelBitmap {
    let cg: CGContext
    let k: CGFloat
    let width: Int, height: Int

    init?(cols: Int, rows: Int, k: Int) {
        let w = max(1, cols * k), h = max(1, rows * k)
        guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Top-left origin, like SwiftUI.
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .none
        cg.setShouldAntialias(false)
        self.cg = cg; self.k = CGFloat(k); width = w; height = h
    }

    // Colours and glows are worked out once and reused.
    nonisolated(unsafe) private static var colors: [Color: CGColor] = [:]
    nonisolated(unsafe) private static var gradients: [Color: CGGradient] = [:]
    private static let env = EnvironmentValues()
    private var lastFill: Color?

    static func cgColor(_ c: Color) -> CGColor {
        if let hit = colors[c] { return hit }
        let made = c.resolve(in: env).cgColor
        if colors.count > 4000 { colors.removeAll() }
        colors[c] = made
        return made
    }

    func fill(_ r: CGRect, _ c: Color) {
        if c != lastFill { cg.setFillColor(Self.cgColor(c)); lastFill = c }
        cg.fill(r)
    }

    func fillUnion(_ rects: [CGRect], _ c: Color) {
        cg.setFillColor(Self.cgColor(c)); lastFill = c
        cg.addRects(rects)
        cg.fillPath(using: .winding)
    }

    /// Draws a picture right way up into a top-left-origin rect.
    func draw(_ img: CGImage, in r: CGRect) {
        cg.saveGState()
        cg.translateBy(x: r.minX, y: r.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(img, in: CGRect(origin: .zero, size: r.size))
        cg.restoreGState()
    }

    func glow(center: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        let key = color.opacity(alpha)
        let g: CGGradient
        if let hit = Self.gradients[key] { g = hit } else {
            let c = Self.cgColor(key)
            let clear = c.copy(alpha: 0) ?? c
            g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c, clear] as CFArray, locations: [0, 1])!
            if Self.gradients.count > 1000 { Self.gradients.removeAll() }
            Self.gradients[key] = g
        }
        cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    func image() -> CGImage? { cg.makeImage() }

    func clear() {
        cg.clear(CGRect(x: 0, y: 0, width: width, height: height))
        lastFill = nil
    }
}

/// Draws on a low-resolution pixel grid, scaled up: either onto a SwiftUI canvas or into a `PixelBitmap`.
struct Painter {
    private let gc: GraphicsContext?
    private let bitmap: PixelBitmap?
    let s: CGFloat
    /// When set, fills are gathered and drawn in runs (see `PixelBatch`); `ox`/`oy` is how far this
    /// painter is shifted from the canvas origin.
    var batch: PixelBatch? = nil
    var ox: CGFloat = 0
    var oy: CGFloat = 0

    init(ctx: GraphicsContext, s: CGFloat, batch: PixelBatch? = nil, ox: CGFloat = 0, oy: CGFloat = 0) {
        gc = ctx; bitmap = nil; self.s = s; self.batch = batch; self.ox = ox; self.oy = oy
    }

    init(bitmap: PixelBitmap, ox: CGFloat = 0, oy: CGFloat = 0) {
        gc = nil; self.bitmap = bitmap; s = bitmap.k; self.ox = ox; self.oy = oy
    }

    /// The SwiftUI canvas, for the few drawings that need it directly (only when drawing onto one).
    var ctx: GraphicsContext { gc! }
    var isBitmap: Bool { bitmap != nil }

    /// Draws with batching on, then makes sure everything gathered reaches the canvas.
    static func batched(_ ctx: GraphicsContext, s: CGFloat, _ draw: (Painter) -> Void) {
        let b = PixelBatch(ctx)
        draw(Painter(ctx: ctx, s: s, batch: b))
        b.flush()
    }

    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
        guard w > 0, h > 0 else { return }
        if let bitmap {
            bitmap.fill(CGRect(x: CGFloat(x) * s + ox, y: CGFloat(y) * s + oy, width: CGFloat(w) * s, height: CGFloat(h) * s), color)
            return
        }
        let r = CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s + 0.5, height: CGFloat(h) * s + 0.5)
        if let batch {
            batch.add(r.offsetBy(dx: ox, dy: oy), color)
        } else {
            ctx.fill(Path(r), with: .color(color))
        }
    }

    /// Many rects filled as one shape, so a see-through colour never doubles up where they overlap.
    func rects(_ list: [(Int, Int, Int, Int)], _ color: Color) {
        if let bitmap {
            bitmap.fillUnion(list.filter { $0.2 > 0 && $0.3 > 0 }.map {
                CGRect(x: CGFloat($0.0) * s + ox, y: CGFloat($0.1) * s + oy, width: CGFloat($0.2) * s, height: CGFloat($0.3) * s)
            }, color)
            return
        }
        flush()
        var path = Path()
        for (x, y, w, h) in list where w > 0 && h > 0 {
            path.addRect(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s + 0.5, height: CGFloat(h) * s + 0.5))
        }
        ctx.fill(path, with: .color(color))
    }

    /// Sends any gathered squares to the canvas, before drawing something straight onto it.
    func flush() { batch?.flush() }

    /// The same painter, nudged up or down by some rows.
    func shifted(dy: Int) -> Painter { shifted(dx: 0, dy: dy) }

    func shifted(dx: Int, dy: Int) -> Painter {
        if let bitmap {
            return Painter(bitmap: bitmap, ox: ox + CGFloat(dx) * s, oy: oy + CGFloat(dy) * s)
        }
        var moved = ctx
        moved.translateBy(x: CGFloat(dx) * s, y: CGFloat(dy) * s)
        return Painter(ctx: moved, s: s, batch: batch, ox: ox + CGFloat(dx) * s, oy: oy + CGFloat(dy) * s)
    }

    func dot(_ x: Int, _ y: Int, _ color: Color) {
        rect(x, y, 1, 1, color)
    }

    func sprite(_ sprite: Sprite, x: Int, y: Int, flip: Bool = false) {
        guard let img = SpriteImages.image(sprite, flip: flip) else { return }
        place(img, x: x, y: y)
    }

    /// Draws a sprite mid-step: same body, legs apart on odd frames.
    func walking(_ sprite: Sprite, x: Int, y: Int, flip: Bool, frame: Int) {
        guard let img = SpriteImages.image(sprite, flip: flip, walkFrame: frame % 2) else { return }
        place(img, x: x, y: y)
    }

    private func place(_ img: CGImage, x: Int, y: Int) {
        picture(img, x: x, y: y, w: img.width, h: img.height)
    }

    /// A finished picture stretched over an area of art pixels (nearest-neighbour, so it stays crisp).
    func picture(_ img: CGImage, x: Int, y: Int, w: Int, h: Int) {
        if let bitmap {
            bitmap.draw(img, in: CGRect(x: CGFloat(x) * s + ox, y: CGFloat(y) * s + oy, width: CGFloat(w) * s, height: CGFloat(h) * s))
            return
        }
        flush()
        ctx.draw(Image(decorative: img, scale: 1).interpolation(.none),
                 in: CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s, height: CGFloat(h) * s))
    }

    func glow(_ x: Double, _ y: Double, radius: Double, _ color: Color, _ alpha: Double) {
        if let bitmap {
            bitmap.glow(center: CGPoint(x: x * s + ox, y: y * s + oy), radius: radius * s, color: color, alpha: alpha)
            return
        }
        flush()
        let center = CGPoint(x: x * s, y: y * s)
        let r = radius * s
        let gradient = Gradient(colors: [color.opacity(alpha), color.opacity(0)])
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r)
        )
    }

    /// Draws `body` as its own layer, then washes `tints` over only what it drew
    /// (so a figure can be shaded to match the evening without tinting the background twice).
    func tintedLayer(width: Int, height: Int, tints: [Color], _ body: (Painter) -> Void) {
        if let bitmap {
            let cg = bitmap.cg
            cg.saveGState()
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            body(self)
            cg.setBlendMode(.sourceAtop)
            let r = CGRect(x: ox, y: oy, width: CGFloat(width) * s, height: CGFloat(height) * s)
            for t in tints { cg.setFillColor(PixelBitmap.cgColor(t)); cg.fill(r) }
            cg.endTransparencyLayer()
            cg.restoreGState()
            return
        }
        flush()
        ctx.drawLayer { layer in
            let q = Painter(ctx: layer, s: s)
            body(q)
            layer.blendMode = .sourceAtop
            for t in tints {
                layer.fill(Path(CGRect(x: 0, y: 0, width: CGFloat(width) * s, height: CGFloat(height) * s)), with: .color(t))
            }
        }
    }

    /// Only lets drawing inside the given art area through.
    func clipped(x: Int, y: Int, w: Int, h: Int, _ body: (Painter) -> Void) {
        if let bitmap {
            bitmap.cg.saveGState()
            bitmap.cg.clip(to: CGRect(x: CGFloat(x) * s + ox, y: CGFloat(y) * s + oy, width: CGFloat(w) * s, height: CGFloat(h) * s))
            body(self)
            bitmap.cg.restoreGState()
            return
        }
        flush()
        var c = ctx
        c.clip(to: Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s, height: CGFloat(h) * s)))
        body(Painter(ctx: c, s: s))
    }
}

/// Pixel art drawn a frame at a time into one small bitmap, then shown as a single crisp picture.
/// The drawing happens on a background thread, so the main thread stays free for touches and
/// scrolling; the newest finished frame is shown as soon as it's ready.
/// `cols`×`rows` art pixels, each `s` points on screen; `k` image pixels per art pixel (2 keeps glows soft).
/// `frame` should change whenever there's something new to draw (usually the timeline's time).
/// The draw closure runs off the main thread: it must only use values, never the store or other live objects.
struct PixelCanvas: View {
    let cols: Int
    let rows: Int
    let s: CGFloat
    var k: Int = 2
    var frame: Double = 0
    let draw: (Painter) -> Void

    @State private var job = PixelRenderJob()

    var body: some View {
        let _ = job.submit(frame: frame, cols: cols, rows: rows, k: k, draw: draw)
        Color.clear
            .overlay(alignment: .topLeading) {
                if let img = job.image {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: CGFloat(cols) * s, height: CGFloat(rows) * s)
                }
            }
            .clipped()
    }
}

/// Renders one `PixelCanvas`'s frames in the background, never more than one at a time,
/// always skipping ahead to the newest frame asked for.
@Observable
final class PixelRenderJob {
    private(set) var image: CGImage?

    /// Every pixel canvas shares this one queue, so the drawing code never runs twice at once.
    static let queue = DispatchQueue(label: "workdoro.pixels", qos: .userInteractive)

    @ObservationIgnored private var lastFrame = Double.nan
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var pending: (() -> CGImage?)?

    func submit(frame: Double, cols: Int, rows: Int, k: Int, draw: @escaping (Painter) -> Void) {
        guard frame != lastFrame else { return }
        lastFrame = frame
        let work: () -> CGImage? = {
            guard let bitmap = PixelBitmaps.shared.bitmap(cols: cols, rows: rows, k: k) else { return nil }
            bitmap.clear()
            draw(Painter(bitmap: bitmap))
            return bitmap.image()
        }
        if image == nil && !busy {
            // The very first frame gets a moment to finish, so a screen rarely opens blank, but it
            // never holds up the main thread for long (the first town frame builds a lot of caches).
            busy = true
            let done = DispatchSemaphore(value: 0)
            let box = ImageBox()
            Self.queue.async {
                box.image = work()
                done.signal()
                DispatchQueue.main.async {
                    if self.image == nil || box.late { self.image = box.image }
                    self.busy = false
                    if let next = self.pending { self.pending = nil; self.run(next) }
                }
            }
            if done.wait(timeout: .now() + 0.012) == .success {
                image = box.image
            } else {
                box.late = true
            }
            return
        }
        if busy { pending = work; return }
        run(work)
    }

    private func run(_ work: @escaping () -> CGImage?) {
        busy = true
        Self.queue.async {
            let img = work()
            DispatchQueue.main.async {
                self.image = img
                self.busy = false
                if let next = self.pending {
                    self.pending = nil
                    self.run(next)
                }
            }
        }
    }
}

/// Hands a frame from the drawing queue back to the main thread.
private final class ImageBox: @unchecked Sendable {
    var image: CGImage?
    var late = false
}

/// Reuses bitmaps of the same size between frames instead of making a new one each time.
/// Only ever used on `PixelRenderJob.queue`.
final class PixelBitmaps {
    static let shared = PixelBitmaps()
    private var pool: [String: PixelBitmap] = [:]

    func bitmap(cols: Int, rows: Int, k: Int) -> PixelBitmap? {
        let key = "\(cols)x\(rows)@\(k)"
        if let hit = pool[key] { return hit }
        guard let b = PixelBitmap(cols: cols, rows: rows, k: k) else { return nil }
        if pool.count > 8 { pool.removeAll() }
        pool[key] = b
        return b
    }
}

struct SpriteView: View {
    let sprite: Sprite
    var pixel: CGFloat = 4
    var flip = false

    var body: some View {
        Canvas { ctx, _ in
            Painter(ctx: ctx, s: pixel).sprite(sprite, x: 0, y: 0, flip: flip)
        }
        .frame(width: CGFloat(sprite.width) * pixel, height: CGFloat(sprite.height) * pixel)
        .accessibilityHidden(true)
    }
}

/// A villager that gently bobs, for headers and dialogue.
struct BobbingSprite: View {
    let sprite: Sprite
    var pixel: CGFloat = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let up = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            SpriteView(sprite: sprite, pixel: pixel)
                .offset(y: up ? -pixel : 0)
        }
        .frame(width: CGFloat(sprite.width) * pixel, height: CGFloat(sprite.height + 1) * pixel, alignment: .bottom)
    }
}

/// Deterministic noise for scattering grass, flowers and stars.
func noise(_ x: Int, _ y: Int) -> Int {
    var v = UInt32(truncatingIfNeeded: x) &* 374_761_393 &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
    v = (v ^ (v >> 13)) &* 1_274_126_177
    return Int((v ^ (v >> 16)) & 0xFFFF)
}

enum Sprites {
    private static let ink = Color(hex: 0x2B2233)
    private static let skin = Color(hex: 0xF6CFA8)
    private static let blush = Color(hex: 0xF0A090)
    private static let mouth = Color(hex: 0xC0605A)

    static let pip = Sprite([
        "................",
        ".....kkkkkk.....",
        "....kcccccck....",
        "...kcccccccck...",
        "..kyyyyyyyyyyk..",
        "..khsssssssshk..",
        "..kssksssskssk..",
        "..ksbssssssbsk..",
        "..kssssmmssssk..",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kccnccccck...",
        "..kccccnncccck..",
        "..ksccccnnncsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "c": Color(hex: 0x4A6FA5), "y": Color(hex: 0xF2C14E), "h": Color(hex: 0x6B4A2E),
        "s": skin, "b": blush, "m": mouth, "n": Color(hex: 0x8A5A3B), "p": Color(hex: 0x3D3F63)
    ])

    static let mo = Sprite([
        "......kkkk......",
        ".....khhhhk.....",
        "....kkhhhhkk....",
        "...khhhhhhhhk...",
        "..khhhhhhhhhhk..",
        "..khhsssssshhk..",
        "..khgkgssgkghk..",
        "..khsbssssbshk..",
        "..khsssmmssshk..",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kcccwwccck...",
        "..kccccwwcccck..",
        "..ksccooooccsk..",
        "...kdddkkdddk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "h": Color(hex: 0x5B3A6B), "s": skin, "g": Color(hex: 0xB08D57), "b": blush,
        "m": mouth, "w": Color(hex: 0xFFF6E5), "c": Color(hex: 0x6E8B5E), "o": Color(hex: 0xC65F4A),
        "d": Color(hex: 0x4A3F5C)
    ])

    static let bea = Sprite([
        "......kk........",
        ".....kook.......",
        "....kkookkk.....",
        "...kooooooook...",
        "..kooooooooook..",
        "..koosssssssok..",
        "..kosksssskssok.",
        "..kosbssssbssok.",
        "..koosssmmsssok.",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kgwwwwwwgk...",
        "..kggwwwwwwggk..",
        "..ksgwwccwwgsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "o": Color(hex: 0xD9824A), "s": skin, "b": blush, "m": mouth,
        "g": Color(hex: 0x7FB069), "w": Color(hex: 0xFFF6E5), "c": Color(hex: 0x8A5A3B),
        "p": Color(hex: 0x5A4A6B)
    ])

    static let you = Sprite([
        "................",
        ".....kkkkkk.....",
        "....krrrrrrk....",
        "...krrwrrwrrk...",
        "..krrrrrrrrrrk..",
        "..khsssssssshk..",
        "..kssksssskssk..",
        "..ksbssssssbsk..",
        "..kssssmmssssk..",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kggggggggk...",
        "..kggggwwggggk..",
        "..ksggggggggsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "r": Color(hex: 0xE07A5F), "w": Color(hex: 0xFFF6E5), "h": Color(hex: 0x6B4A2E),
        "s": skin, "b": blush, "m": mouth, "g": Color(hex: 0x81B29A), "p": Color(hex: 0x3D3F63)
    ])

    static let fern = mo.recolored(["h": Color(hex: 0x3E6B48), "c": Color(hex: 0xE0A458), "o": Color(hex: 0x4A6FA5)])
    static let olli = pip.recolored(["c": Color(hex: 0x8E5A8A), "y": Color(hex: 0xFFF6E5), "h": Color(hex: 0x2B2233), "n": Color(hex: 0xC65F4A)])

    static let juniper = mo.recolored([
        "h": Color(hex: 0x6B4A2E), "c": Color(hex: 0x6E8B5E), "o": Color(hex: 0xF2C14E),
        "w": Color(hex: 0xC9A27A), "g": Color(hex: 0xF6CFA8), "d": Color(hex: 0x5A4A3B)
    ])

    static let rosie = bea.recolored([
        "o": Color(hex: 0xFFF6E5), "g": Color(hex: 0xC2577A), "c": Color(hex: 0xE8A0B0), "p": Color(hex: 0x6B4A5E)
    ])

    static let farmer = you.recolored([
        "r": Color(hex: 0xE8C46A), "w": Color(hex: 0xC9A050), "g": Color(hex: 0x5B7FB0), "h": Color(hex: 0x8A5A3B)
    ])

    // Café customers.
    static let customers: [Sprite] = [
        you.recolored(["r": Color(hex: 0x4A6FA5), "g": Color(hex: 0xC65F4A)]),
        mo.recolored(["h": Color(hex: 0x2B2233), "c": Color(hex: 0x4A6FA5), "o": Color(hex: 0xF2C14E), "s": Color(hex: 0x8D5A3B)]),
        pip.recolored(["c": Color(hex: 0x6E8B5E), "y": Color(hex: 0xF2C14E)]),
        bea.recolored(["o": Color(hex: 0x3A2A20), "g": Color(hex: 0x8E5A8A), "w": Color(hex: 0xE9D6F0), "s": Color(hex: 0xC68B5E)]),
        you.recolored(["r": Color(hex: 0x2B2233), "g": Color(hex: 0xF2C14E), "s": Color(hex: 0xC68B5E)]),
        mo.recolored(["h": Color(hex: 0xC9773F), "c": Color(hex: 0x6B5F73), "o": Color(hex: 0xE8A0B0)])
    ]

    /// A sleeping tabby, curled into a loaf.
    static let sleepyCat = Sprite([
        "..k....k......",
        ".kok..kok.....",
        ".kooookoook...",
        "koooooooooook.",
        "kokkoooookkok.",
        "koowwnnwwoook.",
        ".koooooooookkk",
        ".ksoosoosookok",
        "..kkkkkkkkkkk."
    ], ["k": ink, "o": Color(hex: 0xE8A25A), "s": Color(hex: 0xC47A35), "w": Color(hex: 0xFFF6E5), "n": Color(hex: 0xF49AC1)])

    /// A trailing pothos in a terracotta pot.
    static let pottedPlant = Sprite([
        "......gg......",
        ".....gGGg.....",
        "..gg.gGGg.gg..",
        ".gGGg.gg.gGGg.",
        ".gGGgg..ggGGg.",
        "..gg.gGGg.gg..",
        "....ggGGgg....",
        ".gg..gGGg..gg.",
        "gGGg..gg..gGGg",
        ".gg..kkkk..gg.",
        "..kkkrrrrkkk..",
        "..krrrrrrrrk..",
        "...krRrrrrk...",
        "...krrrrrrk..g",
        "....kkkkkk..gG"
    ], ["k": ink, "g": Color(hex: 0x78B86A), "G": Color(hex: 0x4C8648), "r": Color(hex: 0xC9774A), "R": Color(hex: 0xE09468)])

    /// You, facing out, at a desk.
    /// You exactly as in town, without the blush, for zoomed-in widget scenes.
    static let plainYou = you.recolored(["b": skin])

    static let deskYou = Sprite([
        "........kkkkkkkk........",
        "......kkrrrrrrrrkk......",
        ".....krrwrrrrrrwrrk.....",
        "....krrrrrrwwrrrrrrk....",
        "....krrrrrrrrrrrrrrk....",
        "...kRRRRRRRRRRRRRRRRk...",
        "...khhsssssssssssshhk...",
        "...khsssssssssssssshk...",
        "...ksssseesssseessssk...",
        "...kssssewsssswessssk...",
        "...ksbbssssssssssbbsk...",
        "...ksssssssmmsssssssk...",
        "....kssssssssssssssk....",
        ".....kkkkkkkkkkkkkk.....",
        "....kgggwggggggwgggk....",
        "...kggggwggggggwggggk...",
        "..kggggggggggggggggggk..",
        ".kggggggggggggggggggggk.",
        ".kggggggggggggggggggggk.",
        ".kggggggggggggggggggggk.",
        ".kkkkkkkkkkkkkkkkkkkkkk."
    ], [
        "k": ink, "r": Color(hex: 0xE07A5F), "R": Color(hex: 0xC4614A), "w": Color(hex: 0xFFF6E5),
        "h": Color(hex: 0x6B4A2E), "s": skin, "b": blush, "m": mouth, "e": ink, "g": Color(hex: 0x81B29A)
    ])

    static let flame = Sprite([
        "...k...",
        "..kok..",
        "..koyk.",
        ".koyyok",
        "koyyyok",
        "koywyok",
        "koywyok",
        ".kooyk.",
        "..kkk.."
    ], ["k": ink, "o": Color(hex: 0xE8543A), "y": Color(hex: 0xF7A43C), "w": Color(hex: 0xFFE38A)])

    static let cupIcon = Sprite([
        "kkkkkkk..",
        "kcccccckk",
        "kwwwwwk.k",
        "kwwwwwkkk",
        "kwwwwwk..",
        ".kwwwk...",
        "..kkk...."
    ], ["k": ink, "c": Color(hex: 0x6B4226), "w": Color(hex: 0xFFFDF6)])

    static let leafIcon = Sprite([
        "....kkk",
        "..kkggk",
        ".kgglgk",
        "kgglggk",
        "kglggk.",
        "kkggk..",
        "k.kk..."
    ], ["k": ink, "g": Color(hex: 0x6FB25E), "l": Color(hex: 0x3E6E3A)])

    static let cat = Sprite([
        "k...k...",
        "kokok...",
        "koooo...",
        "kokok..k",
        ".kooookk",
        ".koooook",
        ".kkkkkk."
    ], ["k": ink, "o": Color(hex: 0xE8A25A)])

    static let duck = Sprite([
        "...kk...",
        "..kwwk..",
        "..kwkwo.",
        "kkwwwk..",
        "kwwwwwk.",
        ".kkkkk.."
    ], ["k": ink, "w": Color(hex: 0xF8F4EA), "o": Color(hex: 0xE8964A)])

    static let envelope = Sprite([
        "kkkkkkkkkk",
        "kwkwwwwkwk",
        "kwwkwwkwwk",
        "kwwwkkwwwk",
        "kwwwwwwwwk",
        "kwwwwwwrrk",
        "kkkkkkkkkk"
    ], ["k": ink, "w": Color(hex: 0xFFFDF6), "r": Color(hex: 0xC65F4A)])

    static let page = Sprite([
        "kkkkkkk.",
        "kwwwwwkk",
        "kwllllwk",
        "kwwwwwwk",
        "kwllllwk",
        "kwwwwwwk",
        "kwlllwwk",
        "kkkkkkkk"
    ], ["k": ink, "w": Color(hex: 0xFFFDF6), "l": Color(hex: 0xB9A9C9)])
}
