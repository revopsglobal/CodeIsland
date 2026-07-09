import SwiftUI

/// Sheldon - the RevOps Claude mascot.
///
/// CodeIsland mascots are character-first, so Sheldon renders as the turtle
/// itself instead of a tiny turtle walking through a scene.
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

    private var palette: SheldonPalette {
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
            ForEach(0..<3, id: \.self) { index in
                floatingZ(index: index)
            }
        }
    }

    private func floatingZ(index: Int) -> some View {
        let ci = Double(index)
        let cycle = 2.8 + ci * 0.3
        let delay = ci * 0.9
        let phase = max(0, positiveRemainder(t - delay, cycle) / cycle)
        let fontSize = max(6, size * CGFloat(0.18 + phase * 0.09))
        let baseOpacity = 0.72 - ci * 0.12
        let opacity = phase < 0.78 ? baseOpacity : (1.0 - phase) * 3.3 * baseOpacity
        let xOffset = size * CGFloat(0.03 + ci * 0.08 + sin(phase * Double.pi * 2) * 0.03)
        let yOffset = -size * CGFloat(0.22 + phase * 0.34)

        return Text("z")
            .font(.system(size: fontSize, weight: .black, design: .monospaced))
            .foregroundStyle(.white.opacity(max(0, opacity)))
            .offset(x: xOffset, y: yOffset)
    }

    private func drawTurtle(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        let pose = SheldonPose(status: status, t: t)
        let y = 25 + pose.yOffset
        let breathe = status == .idle ? MascotMotion.breathe(t, period: 4.7) : 0
        let shellLift = -breathe * 0.7

        drawShadow(ctx, g, yOffset: pose.shadowOffset)
        drawLegs(ctx, g, y: y, pose: pose)
        drawTail(ctx, g, y: y, pose: pose)
        drawHead(ctx, g, y: y, pose: pose)
        drawShell(ctx, g, y: y + shellLift, breathe: breathe, pose: pose)

        if status == .running {
            drawSparkles(ctx, g, y: y)
        }
        if status == .waitingApproval || status == .waitingQuestion {
            drawAlertMarker(ctx, g)
        }
    }

    private func drawShadow(_ ctx: GraphicsContext, _ g: SheldonGeometry, yOffset: CGFloat) {
        ctx.fill(
            Path(ellipseIn: g.rect(5, 38 + yOffset, 38, 5)),
            with: .color(.black.opacity(0.28))
        )
    }

    private func drawLegs(_ ctx: GraphicsContext, _ g: SheldonGeometry, y: CGFloat, pose: SheldonPose) {
        let leftLift = pose.step == 0 ? pose.walkLift : -pose.walkLift * 0.35
        let rightLift = pose.step == 0 ? -pose.walkLift * 0.35 : pose.walkLift

        if status == .idle {
            drawLeg(ctx, g, x: 12, y: y + 9)
            drawLeg(ctx, g, x: 28, y: y + 9)
        } else {
            drawLeg(ctx, g, x: 11, y: y + 9 - leftLift)
            drawLeg(ctx, g, x: 29, y: y + 9 - rightLift)
        }
    }

    private func drawLeg(_ ctx: GraphicsContext, _ g: SheldonGeometry, x: CGFloat, y: CGFloat) {
        ctx.fill(Path(g.rect(x, y, 6, 4)), with: .color(palette.skinDark))
        ctx.fill(Path(g.rect(x + 1, y - 1, 4, 2)), with: .color(palette.skin))
    }

    private func drawTail(_ ctx: GraphicsContext, _ g: SheldonGeometry, y: CGFloat, pose: SheldonPose) {
        let wag = status == .running ? CGFloat(sin(t * 12)) * 1.1 : 0
        ctx.fill(Path(g.rect(5, y + 5 + wag, 7, 3)), with: .color(palette.skinDark))
        ctx.fill(Path(g.rect(4, y + 6 + wag, 3, 2)), with: .color(palette.skin))
    }

    private func drawHead(_ ctx: GraphicsContext, _ g: SheldonGeometry, y: CGFloat, pose: SheldonPose) {
        let headX: CGFloat = 34 + pose.headLean
        let headY = y - 2 + pose.headBob
        let alerting = status == .waitingApproval || status == .waitingQuestion

        ctx.fill(Path(g.rect(headX, headY + 2, 7, 7)), with: .color(palette.skinDark))
        ctx.fill(Path(g.rect(headX + 2, headY, 10, 10)), with: .color(palette.skin))
        ctx.fill(Path(g.rect(headX + 10, headY + 4, 3, 3)), with: .color(palette.skinDark))

        if status == .idle {
            ctx.fill(Path(g.rect(headX + 6, headY + 4, 5, 1.4)), with: .color(.black.opacity(0.75)))
        } else {
            let blink = max(0.12, MascotMotion.blink(t, seed: 0x51E1))
            ctx.fill(Path(g.rect(headX + 7, headY + 3, 2, 3 * blink)), with: .color(.black))
            if alerting {
                ctx.fill(Path(g.rect(headX + 10, headY + 3, 1.6, 3 * blink)), with: .color(.black))
            }
        }
    }

    private func drawShell(_ ctx: GraphicsContext, _ g: SheldonGeometry, y: CGFloat, breathe: CGFloat, pose: SheldonPose) {
        let shellY = y - 6
        let shellHeight = 19 + breathe * 1.2

        ctx.fill(Path(g.rect(12, shellY + 3, 25, shellHeight - 2)), with: .color(palette.shellDark))
        ctx.fill(Path(g.rect(14, shellY, 21, shellHeight)), with: .color(palette.shell))
        ctx.fill(Path(g.rect(16, shellY + 1, 17, 3)), with: .color(palette.shellLight.opacity(0.88)))
        ctx.fill(Path(g.rect(16, shellY + 8, 17, 3)), with: .color(palette.shellLight.opacity(0.72)))

        ctx.fill(Path(g.rect(20, shellY + 2, 2, shellHeight - 3)), with: .color(palette.shellDark.opacity(0.55)))
        ctx.fill(Path(g.rect(27, shellY + 3, 2, shellHeight - 5)), with: .color(palette.shellDark.opacity(0.45)))

        if status == .waitingApproval || status == .waitingQuestion {
            let glow = 0.35 + 0.18 * sin(t * 7)
            ctx.fill(Path(g.rect(15, shellY + 5, 19, 6)), with: .color(palette.glow.opacity(glow)))
        }

        if status == .processing {
            let pulse = 0.45 + 0.25 * sin(t * 5)
            ctx.fill(Path(g.rect(17, shellY + 5, 15, 2)), with: .color(Color.white.opacity(pulse)))
        }

        if status == .running {
            let shineX = 17 + CGFloat(positiveRemainder(t * 12, 11))
            ctx.fill(Path(g.rect(shineX, shellY + 4, 2, 9)), with: .color(Color.white.opacity(0.38)))
        }
    }

    private func drawSparkles(_ ctx: GraphicsContext, _ g: SheldonGeometry, y: CGFloat) {
        for i in 0..<3 {
            let phase = positiveRemainder(t + Double(i) * 0.35, 1.2) / 1.2
            let sx = CGFloat(8 + i * 11)
            let sy = y - 15 - CGFloat(phase) * 5
            ctx.fill(Path(g.rect(sx, sy, 2, 2)), with: .color(Color.white.opacity(1 - phase)))
        }
    }

    private func drawAlertMarker(_ ctx: GraphicsContext, _ g: SheldonGeometry) {
        let text = status == .waitingQuestion ? "?" : "!"
        ctx.draw(
            Text(text)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(palette.glow),
            at: g.point(39.5, 12.5)
        )
    }

    private func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: divisor)
        return r >= 0 ? r : r + divisor
    }
}

private struct SheldonPose {
    let yOffset: CGFloat
    let shadowOffset: CGFloat
    let headLean: CGFloat
    let headBob: CGFloat
    let walkLift: CGFloat
    let step: Int

    init(status: MascotAgentStatus, t: Double) {
        step = Int((t * 7).rounded()) % 2

        switch status {
        case .idle:
            let breath = MascotMotion.breathe(t, period: 4.7)
            yOffset = 1 + breath * 0.8
            shadowOffset = 0
            headLean = -1
            headBob = breath * 0.4
            walkLift = 0
        case .processing:
            yOffset = CGFloat(sin(t * 3.2)) * 0.7
            shadowOffset = 0
            headLean = CGFloat(sin(t * 4.2)) * 0.6
            headBob = CGFloat(cos(t * 4.0)) * 0.5
            walkLift = 1.5
        case .running:
            let hop = CGFloat(abs(sin(t * 5.6))) * -2.5
            yOffset = hop
            shadowOffset = -hop * 0.35
            headLean = 1
            headBob = hop * 0.4
            walkLift = 2.2
        case .waitingApproval, .waitingQuestion:
            let pulse = t.truncatingRemainder(dividingBy: 1.1)
            let hop = pulse < 0.18 ? MascotMotion.easeOutBack(CGFloat(1 - pulse / 0.18)) * -3.8 : 0
            yOffset = hop
            shadowOffset = -hop * 0.3
            headLean = 1
            headBob = CGFloat(sin(t * 8)) * 0.45
            walkLift = 0
        }
    }
}

private struct SheldonGeometry {
    let scale: CGFloat
    let origin: CGPoint

    init(_ size: CGSize) {
        scale = min(size.width, size.height) / 48
        origin = CGPoint(x: (size.width - 48 * scale) / 2, y: (size.height - 48 * scale) / 2)
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
