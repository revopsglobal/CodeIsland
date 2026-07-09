import SwiftUI

/// Sheldon - the RevOps Claude mascot. A tiny turtle on a living grass island.
///
/// This keeps the richer CodeIsland source/session model intact and swaps only
/// the Claude/default mascot presentation layer.
struct SheldonView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27

    private var frameInterval: TimeInterval {
        status == .idle ? 0.12 : 0.05
    }

    var body: some View {
        MascotTimeline(interval: frameInterval) { t in
            SheldonFrame(status: status, size: size, t: t)
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

private struct SheldonFrame: View {
    let status: MascotAgentStatus
    let size: CGFloat
    let t: Double

    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 20 || hour < 6
    }

    private var isDawnDusk: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 6 && hour < 8) || (hour >= 18 && hour < 20)
    }

    private var turtleColor: SheldonPalette {
        switch status {
        case .idle:
            return .sleepy
        case .processing:
            return .curious
        case .running:
            return .happy
        case .waitingApproval:
            return .alert
        case .waitingQuestion:
            return .question
        }
    }

    var body: some View {
        ZStack {
            Canvas { ctx, canvasSize in
                let g = SheldonGeometry(canvasSize)
                drawSky(ctx, g)
                drawGround(ctx, g)
                drawAmbient(ctx, g)
                drawProps(ctx, g)
                drawTurtle(ctx, g)
            }

            if status == .idle {
                sleepingZs
            }
        }
        .frame(width: size, height: size)
    }

    private var sleepingZs: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                let cycle = 2.9 + Double(index) * 0.4
                let delay = Double(index) * 0.75
                let phase = positiveRemainder(t - delay, cycle) / cycle
                let opacity = phase < 0.75 ? 0.70 - Double(index) * 0.16 : (1.0 - phase) * 2.8
                Text("z")
                    .font(.system(size: max(6, size * (0.15 + CGFloat(phase) * 0.07)), weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(max(0, opacity)))
                    .offset(
                        x: size * (0.12 + CGFloat(index) * 0.08 + sin(CGFloat(phase) * .pi * 2) * 0.03),
                        y: -size * (0.18 + CGFloat(phase) * 0.36)
                    )
            }
        }
    }

    private func drawSky(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        let top: Color
        let bottom: Color
        if isNight {
            top = Color(red: 0.04, green: 0.06, blue: 0.16)
            bottom = Color(red: 0.08, green: 0.12, blue: 0.26)
        } else if isDawnDusk {
            top = Color(red: 0.45, green: 0.35, blue: 0.70)
            bottom = Color(red: 1.00, green: 0.55, blue: 0.30)
        } else {
            top = Color(red: 0.36, green: 0.68, blue: 0.94)
            bottom = Color(red: 0.58, green: 0.82, blue: 0.98)
        }

        ctx.fill(
            Path(g.rect(0, 0, 64, 64)),
            with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: g.point(32, 0),
                endPoint: g.point(32, 64)
            )
        )
    }

    private func drawGround(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        ctx.fill(Path(g.rect(0, 46, 64, 18)), with: .color(Color(red: 0.13, green: 0.38, blue: 0.17)))
        ctx.fill(Path(g.rect(0, 43, 64, 8)), with: .color(Color(red: 0.25, green: 0.58, blue: 0.22)))
        ctx.fill(Path(g.rect(0, 43, 64, 2)), with: .color(Color(red: 0.47, green: 0.78, blue: 0.28)))

        for i in 0..<9 {
            let x = CGFloat(i) * 8 + CGFloat(sin(t * 0.7 + Double(i))) * 1.2
            let h = CGFloat(2 + (i % 3))
            ctx.fill(Path(g.rect(x, 41 - h, 1, h)), with: .color(Color(red: 0.60, green: 0.86, blue: 0.35).opacity(0.75)))
        }
    }

    private func drawAmbient(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        if isNight {
            drawMoon(ctx, g)
            for i in 0..<7 {
                let x = CGFloat((i * 11 + 5) % 62)
                let y = CGFloat((i * 7 + 4) % 28)
                let pulse = 0.45 + 0.35 * sin(t * 1.4 + Double(i))
                ctx.fill(Path(g.rect(x, y, 1, 1)), with: .color(.white.opacity(pulse)))
            }
            for i in 0..<3 {
                let x = CGFloat(10 + i * 17) + CGFloat(sin(t * 0.9 + Double(i))) * 3
                let y = CGFloat(35 + i % 2 * 4) + CGFloat(cos(t * 1.1 + Double(i))) * 2
                ctx.fill(Path(ellipseIn: g.rect(x, y, 1.4, 1.4)), with: .color(Color(red: 0.8, green: 1.0, blue: 0.45).opacity(0.55)))
            }
        } else {
            drawSun(ctx, g)
            let cloudShift = CGFloat(t.truncatingRemainder(dividingBy: 18) / 18) * 18
            drawCloud(ctx, g, x: 7 + cloudShift, y: 9, scale: 1.0)
            drawCloud(ctx, g, x: 42 - cloudShift * 0.45, y: 15, scale: 0.72)

            if status == .running {
                drawButterfly(ctx, g, x: 50 + CGFloat(sin(t * 2.0)) * 3, y: 31 + CGFloat(cos(t * 1.5)) * 2)
            }
        }
    }

    private func drawProps(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        drawFlower(ctx, g)

        if status == .waitingApproval || status == .waitingQuestion {
            let glow = 0.2 + 0.12 * sin(t * 7)
            ctx.fill(Path(ellipseIn: g.rect(20, 22, 24, 24)), with: .color(turtleColor.glow.opacity(glow)))
            drawAlertMarker(ctx, g)
        }
    }

    private func drawFlower(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        let flowerX: CGFloat = 49
        let flowerY: CGFloat = 42
        let nearFlower = abs(currentTurtleX - flowerX) < 6 && (status == .processing || status == .running)
        let petalCount = nearFlower ? max(1, 4 - Int((t * 10).truncatingRemainder(dividingBy: 4))) : 4

        ctx.fill(Path(g.rect(flowerX + 1, flowerY - 8, 1, 8)), with: .color(Color(red: 0.28, green: 0.62, blue: 0.24)))
        for i in 0..<petalCount {
            let angle = CGFloat(i) * .pi / 2 + CGFloat(t) * 0.08
            let px = flowerX + 1 + cos(angle) * 2.4
            let py = flowerY - 9 + sin(angle) * 2.4
            ctx.fill(Path(ellipseIn: g.rect(px, py, 2.4, 2.4)), with: .color(Color(red: 1.0, green: 0.75, blue: 0.25)))
        }
        ctx.fill(Path(ellipseIn: g.rect(flowerX + 0.2, flowerY - 8.8, 2.2, 2.2)), with: .color(Color(red: 0.55, green: 0.29, blue: 0.08)))
    }

    private func drawTurtle(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        let x = currentTurtleX
        let y = currentTurtleY
        let facingRight = currentFacingRight
        let sleeping = status == .idle
        let alerting = status == .waitingApproval || status == .waitingQuestion
        let step = Int((t * 7).rounded()) % 2
        let breathe = MascotMotion.breathe(t, period: 4.7)

        ctx.fill(Path(ellipseIn: g.rect(x - 13, y + 9, 28, 4)), with: .color(.black.opacity(0.26)))

        if !sleeping {
            let legLift: CGFloat = step == 0 ? 0 : -1
            drawLeg(ctx, g, x: x - 7, y: y + 7 + legLift)
            drawLeg(ctx, g, x: x + 4, y: y + 7 - legLift)
        } else {
            drawLeg(ctx, g, x: x - 7, y: y + 8)
            drawLeg(ctx, g, x: x + 4, y: y + 8)
        }

        let shellLift = sleeping ? -breathe * 0.8 : 0
        ctx.fill(Path(g.rect(x - 9, y - 2 + shellLift, 19, 11 + breathe * 1.0)), with: .color(turtleColor.shellDark))
        ctx.fill(Path(g.rect(x - 7, y - 5 + shellLift, 15, 12 + breathe * 1.2)), with: .color(turtleColor.shell))
        ctx.fill(Path(g.rect(x - 3, y - 4 + shellLift, 2, 10)), with: .color(turtleColor.shellDark.opacity(0.55)))
        ctx.fill(Path(g.rect(x + 3, y - 3 + shellLift, 2, 9)), with: .color(turtleColor.shellDark.opacity(0.45)))
        ctx.fill(Path(g.rect(x - 6, y + 0 + shellLift, 14, 2)), with: .color(turtleColor.shellLight.opacity(0.8)))

        let headX = x + (facingRight ? 9 : -13)
        let eyeX = headX + (facingRight ? 4 : 1)
        ctx.fill(Path(g.rect(headX, y - 2, 7, 7)), with: .color(turtleColor.skin))
        ctx.fill(Path(g.rect(headX + (facingRight ? 6 : -2), y + 2, 2, 2)), with: .color(turtleColor.skinDark))

        if sleeping {
            ctx.fill(Path(g.rect(eyeX - 1, y + 1, 3, 1)), with: .color(.black.opacity(0.75)))
            drawNightcapIfNeeded(ctx, g, x: headX + 1, y: y - 7)
        } else {
            let blink = max(0.12, MascotMotion.blink(t, seed: 0x51E1))
            ctx.fill(Path(g.rect(eyeX, y, 1.6, 2.0 * blink)), with: .color(.black))
            if alerting {
                ctx.fill(Path(g.rect(eyeX + (facingRight ? 2 : -2), y, 1.3, 2.0 * blink)), with: .color(.black))
            }
        }

        let tailX = x + (facingRight ? -12 : 10)
        let tailW: CGFloat = 4
        ctx.fill(Path(g.rect(tailX, y + 2 + CGFloat(sin(t * 12)) * (status == .running ? 1.2 : 0), tailW, 2)), with: .color(turtleColor.skinDark))

        if status == .running {
            drawSparkles(ctx, g, x: x, y: y)
        }
    }

    private var currentTurtleX: CGFloat {
        switch status {
        case .idle:
            return 32
        case .processing, .running:
            let cycle = status == .running ? 5.5 : 7.0
            let phase = positiveRemainder(t, cycle) / cycle
            let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            return 16 + CGFloat(triangle) * 32
        case .waitingApproval, .waitingQuestion:
            return 32
        }
    }

    private var currentTurtleY: CGFloat {
        switch status {
        case .idle:
            return 34 + MascotMotion.breathe(t, period: 4.7) * 1.0
        case .processing:
            return 33 + CGFloat(sin(t * 2.8)) * 0.8
        case .running:
            return 32 + CGFloat(abs(sin(t * 5.4))) * -2.0
        case .waitingApproval, .waitingQuestion:
            let pulse = positiveRemainder(t, 1.1)
            return 33 - (pulse < 0.18 ? MascotMotion.easeOutBack(CGFloat(1 - pulse / 0.18)) * 5 : 0)
        }
    }

    private var currentFacingRight: Bool {
        switch status {
        case .processing, .running:
            let cycle = status == .running ? 5.5 : 7.0
            return positiveRemainder(t, cycle) / cycle < 0.5
        default:
            return true
        }
    }

    private func drawLeg(_ ctx: GraphicsContext, _ g: SheldonGeometry, x: CGFloat, y: CGFloat) {
        ctx.fill(Path(g.rect(x, y, 4, 3)), with: .color(turtleColor.skinDark))
    }

    private func drawSun(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        ctx.fill(Path(ellipseIn: g.rect(47, 7, 8, 8)), with: .color(Color(red: 1.0, green: 0.82, blue: 0.28).opacity(isDawnDusk ? 0.75 : 0.9)))
    }

    private func drawMoon(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        ctx.fill(Path(ellipseIn: g.rect(48, 7, 8, 8)), with: .color(Color(red: 0.94, green: 0.92, blue: 0.76).opacity(0.9)))
        ctx.fill(Path(ellipseIn: g.rect(45, 6, 8, 8)), with: .color(Color(red: 0.04, green: 0.06, blue: 0.16)))
    }

    private func drawCloud(_ ctx: GraphicsContext, _ g: SheldonGeometry, x: CGFloat, y: CGFloat, scale: CGFloat) {
        let color = Color.white.opacity(0.58)
        ctx.fill(Path(g.rect(x, y + 3 * scale, 11 * scale, 3 * scale)), with: .color(color))
        ctx.fill(Path(ellipseIn: g.rect(x + 1 * scale, y, 5 * scale, 5 * scale)), with: .color(color))
        ctx.fill(Path(ellipseIn: g.rect(x + 5 * scale, y + 1 * scale, 6 * scale, 5 * scale)), with: .color(color))
    }

    private func drawButterfly(_ ctx: GraphicsContext, _ g: SheldonGeometry, x: CGFloat, y: CGFloat) {
        let wing = Color(red: 1.0, green: 0.58, blue: 0.76).opacity(0.85)
        ctx.fill(Path(ellipseIn: g.rect(x - 2, y - 1, 3, 3)), with: .color(wing))
        ctx.fill(Path(ellipseIn: g.rect(x + 1, y - 1, 3, 3)), with: .color(wing))
        ctx.fill(Path(g.rect(x, y, 1, 4)), with: .color(.black.opacity(0.55)))
    }

    private func drawAlertMarker(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        let text = status == .waitingQuestion ? "?" : "!"
        ctx.draw(
            Text(text).font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(turtleColor.glow),
            at: g.point(47, 21)
        )
    }

    private func drawSparkles(_ ctx: GraphicsContext, _ g: SheldonGeometry, x: CGFloat, y: CGFloat) {
        for i in 0..<3 {
            let phase = positiveRemainder(t + Double(i) * 0.35, 1.2) / 1.2
            let sx = x - 12 + CGFloat(i) * 9
            let sy = y - 13 - CGFloat(phase) * 5
            ctx.fill(Path(g.rect(sx, sy, 1.4, 1.4)), with: .color(Color.white.opacity(1 - phase)))
        }
    }

    private func drawNightcapIfNeeded(_ ctx: GraphicsContext, _ g: SheldonGeometry, x: CGFloat, y: CGFloat) {
        guard isNight else { return }
        ctx.fill(Path(g.rect(x, y + 2, 7, 3)), with: .color(Color(red: 0.28, green: 0.36, blue: 0.92)))
        ctx.fill(Path(g.rect(x + 2, y, 4, 3)), with: .color(Color(red: 0.36, green: 0.46, blue: 1.0)))
        ctx.fill(Path(ellipseIn: g.rect(x + 5, y - 1, 2.3, 2.3)), with: .color(.white.opacity(0.9)))
    }

    private func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: divisor)
        return r >= 0 ? r : r + divisor
    }
}

private struct SheldonGeometry {
    let scale: CGFloat
    let origin: CGPoint

    init(_ size: CGSize) {
        scale = min(size.width, size.height) / 64
        origin = CGPoint(x: (size.width - 64 * scale) / 2, y: (size.height - 64 * scale) / 2)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + x * scale,
            y: origin.y + y * scale,
            width: w * scale,
            height: h * scale
        )
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }
}

private struct SheldonPalette {
    let shell: Color
    let shellLight: Color
    let shellDark: Color
    let skin: Color
    let skinDark: Color
    let glow: Color

    static let sleepy = SheldonPalette(
        shell: Color(red: 0.25, green: 0.55, blue: 0.30),
        shellLight: Color(red: 0.42, green: 0.72, blue: 0.36),
        shellDark: Color(red: 0.11, green: 0.30, blue: 0.17),
        skin: Color(red: 0.62, green: 0.79, blue: 0.36),
        skinDark: Color(red: 0.34, green: 0.54, blue: 0.24),
        glow: Color(red: 0.65, green: 0.85, blue: 0.45)
    )

    static let curious = SheldonPalette(
        shell: Color(red: 0.25, green: 0.62, blue: 0.44),
        shellLight: Color(red: 0.54, green: 0.86, blue: 0.50),
        shellDark: Color(red: 0.08, green: 0.35, blue: 0.22),
        skin: Color(red: 0.68, green: 0.86, blue: 0.38),
        skinDark: Color(red: 0.36, green: 0.58, blue: 0.24),
        glow: Color(red: 0.55, green: 0.95, blue: 0.78)
    )

    static let happy = SheldonPalette(
        shell: Color(red: 0.36, green: 0.72, blue: 0.25),
        shellLight: Color(red: 0.66, green: 0.95, blue: 0.35),
        shellDark: Color(red: 0.13, green: 0.39, blue: 0.12),
        skin: Color(red: 0.76, green: 0.91, blue: 0.36),
        skinDark: Color(red: 0.40, green: 0.62, blue: 0.18),
        glow: Color(red: 0.70, green: 1.00, blue: 0.38)
    )

    static let alert = SheldonPalette(
        shell: Color(red: 0.72, green: 0.56, blue: 0.24),
        shellLight: Color(red: 1.0, green: 0.78, blue: 0.30),
        shellDark: Color(red: 0.43, green: 0.26, blue: 0.08),
        skin: Color(red: 0.82, green: 0.77, blue: 0.34),
        skinDark: Color(red: 0.56, green: 0.42, blue: 0.16),
        glow: Color(red: 1.0, green: 0.64, blue: 0.16)
    )

    static let question = SheldonPalette(
        shell: Color(red: 0.36, green: 0.43, blue: 0.73),
        shellLight: Color(red: 0.58, green: 0.68, blue: 1.0),
        shellDark: Color(red: 0.16, green: 0.20, blue: 0.46),
        skin: Color(red: 0.66, green: 0.78, blue: 0.58),
        skinDark: Color(red: 0.34, green: 0.48, blue: 0.34),
        glow: Color(red: 0.55, green: 0.72, blue: 1.0)
    )
}
