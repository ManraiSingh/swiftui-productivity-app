import SwiftUI

/// The Together House on the south lane, where real people from anywhere hang out and work.
extension VillageRenderer {
    static let studyHallCenter = (x: 196, base: 224)

    static func studyHall(_ p: Painter, t: Double, state: SceneState) {
        let style = HouseStyle(
            wall: Color(hex: 0xE9DCC6), wallDark: Color(hex: 0xD6C6AA),
            roof: Color(hex: 0x5B6E8C), roofDark: Color(hex: 0x485A78), roofLight: Color(hex: 0x7C90AE)
        )
        let cx = studyHallCenter.x, base = studyHallCenter.base
        let wallTop = base - 20

        // A little bell cupola on the ridge.
        box(p, cx - 3, wallTop - 20, 6, 6, Color(hex: 0xE9DCC6))
        p.rect(cx - 2, wallTop - 19, 4, 4, Color(hex: 0x3D3F63))
        let swing = Int(t * 1.5) % 4 == 0 ? 1 : 0
        p.rect(cx - 1 + swing, wallTop - 18, 2, 2, Theme.gold)
        // Little slate cap with a ball on top.
        p.dot(cx - 1, wallTop - 25, Theme.gold); p.dot(cx, wallTop - 25, Theme.gold)
        for r in 0..<3 {
            let half = 1 + r * 2
            p.rect(cx - half - 1, wallTop - 24 + r, half * 2 + 2, 1, ink)
            p.rect(cx - half, wallTop - 24 + r, half * 2, 1, r == 0 ? Color(hex: 0x7C90AE) : Color(hex: 0x5B6E8C))
        }

        house(p, cx: cx, base: base, w: 36, wallH: 20, roofRows: 13, style: style)
        carvedSign(p, "TOGETHER", cx: cx, top: wallTop - 10)

        // Tall arched windows, always lit: someone somewhere is working.
        let glass = Color(hex: 0xFFE2A8)
        for wx in [cx - 16, cx + 10] {
            box(p, wx, wallTop + 4, 6, 11, glass)
            p.dot(wx, wallTop + 4, ink)
            p.dot(wx + 5, wallTop + 4, ink)
            p.rect(wx + 3, wallTop + 4, 1, 11, Color(hex: 0x8E6B4A))
            p.rect(wx, wallTop + 9, 6, 1, Color(hex: 0x8E6B4A))
            p.dot(wx + 1, wallTop + 6, Color.white.opacity(0.6))
            // A desk lamp and a reader in each window.
            p.rect(wx + 1, wallTop + 12, 2, 2, Color(hex: 0x6B4A5E))
            p.dot(wx + 4, wallTop + 11, Color(hex: 0xC65F4A))
            box(p, wx - 1, wallTop + 16, 8, 1, Color(hex: 0x8A6A4A))
        }

        // A round window with the globe in it.
        circle(p, cx: cx, cy: wallTop + 4, r: 3, ink)
        circle(p, cx: cx, cy: wallTop + 4, r: 2, Color(hex: 0x6FB7DA))
        p.rect(cx - 1, wallTop + 3, 2, 1, Color(hex: 0x78B86A))
        p.dot(cx + 1, wallTop + 5, Color(hex: 0x78B86A))

        // Double doors under a stone arch.
        p.rect(cx - 5, base - 12, 10, 1, ink)
        door(p, x: cx - 4, y: base - 11, w: 8, h: 11, color: Color(hex: 0x4A6FA5))
        p.rect(cx - 6, base, 12, 1, stone)
        if weather == .snow { p.rect(cx - 18, wallTop - 1, 36, 1, Color(hex: 0xF4F7FB)) }
    }

    static func studyHallLights(_ p: Painter, strength: Double) {
        let cx = Double(studyHallCenter.x), base = Double(studyHallCenter.base)
        p.glow(cx - 13, base - 10, radius: 9, warm, 0.5 * strength)
        p.glow(cx + 13, base - 10, radius: 9, warm, 0.5 * strength)
        porchLantern(p, x: studyHallCenter.x - 8, y: studyHallCenter.base - 12, t: 0, strength: strength)
    }
}
