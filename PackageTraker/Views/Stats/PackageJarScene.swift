import SpriteKit
import CoreMotion
import SwiftUI

/// SpriteKit 物理場景：罐子裡的包裹球
final class PackageJarScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Physics Categories

    private struct Category {
        static let ball: UInt32 = 0x1 << 0
        static let wall: UInt32 = 0x1 << 1
    }

    // MARK: - Layout Constants

    private let jarInset: CGFloat = 16
    private let jarCornerRadius: CGFloat = 40
    private let lidHeight: CGFloat = 38
    private let neckHeight: CGFloat = 10
    private let wallThickness: CGFloat = 3.0

    // MARK: - Properties

    private let carriers: [Carrier]
    private var textureCache: [Carrier: SKTexture]
    private let motionManager = CMMotionManager()

    // Haptic
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private var lastHapticTime: TimeInterval = 0
    private var sceneStartTime: TimeInterval = 0
    private var hasRecordedStartTime = false

    // 防止重複 setup
    private var didSetup = false

    // MARK: - Ball Sizing

    static func ballDiameter(for count: Int) -> CGFloat {
        if count <= 8 { return 52 }
        if count <= 15 { return 46 }
        return max(34, 46 - CGFloat(count - 15) * 1.2)
    }

    // MARK: - Jar Interior Bounds (for ball placement)

    private var jarLeft: CGFloat { jarInset + wallThickness }
    private var jarRight: CGFloat { size.width - jarInset - wallThickness }
    private var jarBottom: CGFloat { jarInset + wallThickness }
    private var jarInnerTop: CGFloat { size.height - lidHeight - neckHeight }

    // MARK: - Init

    init(carriers: [Carrier], textureCache: [Carrier: SKTexture] = [:]) {
        self.carriers = carriers
        self.textureCache = textureCache
        super.init(size: .zero)
        scaleMode = .resizeFill
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

        lightHaptic.prepare()
        rebuildIfNeeded()
        startMotionUpdates()
    }

    override func willMove(from view: SKView) {
        motionManager.stopAccelerometerUpdates()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildIfNeeded()
    }

    private func rebuildIfNeeded() {
        guard size.width > 0, size.height > 0, view != nil else { return }
        // 只在尺寸真正改變時重建
        if didSetup {
            children.forEach { $0.removeFromParent() }
            physicsBody = nil
        }
        didSetup = true
        setupJar()
        spawnBallsAtRest()
    }

    // MARK: - Jar Visual Setup

    private func setupJar() {
        let left = jarInset
        let right = size.width - jarInset
        let bottom = jarInset
        let top = jarInnerTop
        let r = jarCornerRadius

        // === 物理邊界 ===
        let physicsTop = top + neckHeight
        let physicsPath = CGMutablePath()
        physicsPath.addRoundedRect(in: CGRect(x: left, y: bottom, width: right - left, height: physicsTop - bottom), cornerWidth: r, cornerHeight: r)
        physicsBody = SKPhysicsBody(edgeLoopFrom: physicsPath)
        physicsBody?.categoryBitMask = Category.wall
        physicsBody?.friction = 0.3
        physicsBody?.restitution = 0.3

        // === 玻璃瓶身 ===
        drawJarBody(left: left, right: right, bottom: bottom, top: top, cornerRadius: r)

        // === 瓶口 ===
        drawNeck(left: left, right: right, top: top)

        // === 蓋子 ===
        drawLid(left: left, right: right, top: top)

        // === 玻璃反光 ===
        drawGlassReflections(left: left, right: right, bottom: bottom, top: top, cornerRadius: r)
    }

    // MARK: - Jar Components

    /// 瓶身：半透明底 + 邊緣漸層模擬玻璃厚度
    private func drawJarBody(left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat, cornerRadius r: CGFloat) {
        let w = right - left
        let h = top - bottom
        let imgSize = CGSize(width: w, height: h)

        // 使用支援透明的 format
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: imgSize, format: format)
        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            let bezier = UIBezierPath(roundedRect: rect, cornerRadius: r)

            // 半透明底（讓背景透出來）
            gc.saveGState()
            bezier.addClip()
            UIColor.clear.setFill()
            gc.fill(rect)
            gc.restoreGState()

            // 左邊緣漸層（白→透明）
            let edgeWidth: CGFloat = 20
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            gc.saveGState()
            bezier.addClip()
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0.25).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                gc.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: edgeWidth, y: 0),
                    options: [])
            }
            gc.restoreGState()

            // 右邊緣漸層（透明→白）
            gc.saveGState()
            bezier.addClip()
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: 0.12).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                gc.drawLinearGradient(gradient,
                    start: CGPoint(x: w - edgeWidth, y: 0),
                    end: CGPoint(x: w, y: 0),
                    options: [])
            }
            gc.restoreGState()

            // 底部邊緣漸層
            gc.saveGState()
            bezier.addClip()
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0.15).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                gc.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: h),
                    end: CGPoint(x: 0, y: h - 15),
                    options: [])
            }
            gc.restoreGState()

            // 外框描邊
            gc.saveGState()
            UIColor(white: 1, alpha: 0.25).setStroke()
            bezier.lineWidth = 2
            bezier.stroke()
            gc.restoreGState()
        }

        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture, size: imgSize)
        sprite.position = CGPoint(x: left + w / 2, y: bottom + h / 2)
        sprite.zPosition = -1
        addChild(sprite)
    }

    /// 瓶口：純白窄帶（比蓋子短）
    private func drawNeck(left: CGFloat, right: CGFloat, top: CGFloat) {
        let neckInset: CGFloat = 10  // 比瓶身左右各縮 10pt
        let neckRect = CGRect(x: left + neckInset, y: top, width: right - left - neckInset * 2, height: neckHeight)
        let neck = SKShapeNode(rect: neckRect)
        neck.strokeColor = UIColor.white.withAlphaComponent(0.5)
        neck.lineWidth = 1.5
        neck.fillColor = UIColor.white.withAlphaComponent(0.85)
        neck.zPosition = 1
        addChild(neck)
    }

    /// 蓋子：金屬漸層紋理（無圓角）
    private func drawLid(left: CGFloat, right: CGFloat, top: CGFloat) {
        let lidInset: CGFloat = 1
        let lidLeft = left + lidInset
        let lidW = right - left - lidInset * 2
        let lidH = lidHeight
        let lidBottom = top + neckHeight

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: lidW, height: lidH), format: format)
        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: lidW, height: lidH)

            // 金屬漸層（微圓角）
            let bezier = UIBezierPath(roundedRect: rect, cornerRadius: 5)
            gc.saveGState()
            bezier.addClip()
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(red: 0.96, green: 0.88, blue: 0.62, alpha: 1).cgColor,  // 亮金
                    UIColor(red: 0.88, green: 0.76, blue: 0.48, alpha: 1).cgColor,  // 中金
                    UIColor(red: 0.72, green: 0.60, blue: 0.35, alpha: 1).cgColor,  // 暗金
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) {
                gc.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: lidH),
                    options: [])
            }
            gc.restoreGState()

            // 描邊
            gc.saveGState()
            UIColor(red: 0.55, green: 0.44, blue: 0.22, alpha: 0.6).setStroke()
            bezier.lineWidth = 1.5
            bezier.stroke()
            gc.restoreGState()
        }

        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: lidW, height: lidH))
        sprite.position = CGPoint(x: lidLeft + lidW / 2, y: lidBottom + lidH / 2)
        sprite.zPosition = 2
        addChild(sprite)
    }

    /// 玻璃反光：左側漸層弧帶
    private func drawGlassReflections(left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat, cornerRadius r: CGFloat) {
        let jarHeight = top - bottom

        // 左側反光帶（用漸層紋理畫一條寬弧）
        let stripW: CGFloat = 18
        let stripH = jarHeight - r
        let stripBottom = bottom + r * 0.6

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: stripW, height: stripH))
        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            // 水平漸層：左透明 → 中白 → 右透明
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: 0.18).cgColor,
                    UIColor(white: 1, alpha: 0.06).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor,
                ] as CFArray,
                locations: [0, 0.3, 0.6, 1]
            ) {
                gc.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: stripW, y: 0),
                    options: [])
            }

            // 垂直遮罩：上下漸淡
            gc.setBlendMode(.destinationIn)
            if let vGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: 1).cgColor,
                    UIColor(white: 1, alpha: 1).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor,
                ] as CFArray,
                locations: [0, 0.1, 0.85, 1]
            ) {
                gc.drawLinearGradient(vGradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: stripH),
                    options: [])
            }
        }

        let texture = SKTexture(image: image)
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: stripW, height: stripH))
        sprite.position = CGPoint(x: left + 16 + stripW / 2, y: stripBottom + stripH / 2)
        sprite.zPosition = 5
        addChild(sprite)

        // 右側微弱反光帶
        let rStripW: CGFloat = 10
        let rStripH = jarHeight * 0.4
        let rStripBottom = bottom + r + 20

        let rRenderer = UIGraphicsImageRenderer(size: CGSize(width: rStripW, height: rStripH))
        let rImage = rRenderer.image { ctx in
            let gc = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: 0.07).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor,
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) {
                gc.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: rStripW, y: 0),
                    options: [])
            }

            gc.setBlendMode(.destinationIn)
            if let vGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: 1).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor,
                ] as CFArray,
                locations: [0, 0.4, 1]
            ) {
                gc.drawLinearGradient(vGradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: rStripH),
                    options: [])
            }
        }

        let rTexture = SKTexture(image: rImage)
        let rSprite = SKSpriteNode(texture: rTexture, size: CGSize(width: rStripW, height: rStripH))
        rSprite.position = CGPoint(x: right - 16 - rStripW / 2, y: rStripBottom + rStripH / 2)
        rSprite.zPosition = 5
        addChild(rSprite)
    }

    // MARK: - Ball Spawning (at rest)

    /// 球直接排列在罐子底部，不會掉落
    private func spawnBallsAtRest() {
        let diameter = Self.ballDiameter(for: carriers.count)
        let radius = diameter / 2

        let innerLeft = jarLeft + radius + 2
        let innerRight = jarRight - radius - 2
        let innerWidth = innerRight - innerLeft
        let cols = max(1, Int(innerWidth / (diameter * 0.9)))
        let colSpacing = innerWidth / CGFloat(max(1, cols - 1))

        for (index, carrier) in carriers.enumerated() {
            let texture = textureCache[carrier] ?? makeFallbackTexture(for: carrier, diameter: diameter)
            let ball = SKSpriteNode(texture: texture, size: CGSize(width: diameter, height: diameter))

            // 由底部往上堆疊
            let row = index / cols
            let col = index % cols
            // 奇數行偏移半顆球（堆疊感）
            let xOffset: CGFloat = (row % 2 == 1) ? colSpacing * 0.5 : 0
            var x = innerLeft + CGFloat(col) * colSpacing + xOffset
            x = min(max(x, innerLeft), innerRight)
            let y = jarBottom + radius + 2 + CGFloat(row) * (diameter * 0.85)

            ball.position = CGPoint(x: x, y: y)

            let body = SKPhysicsBody(circleOfRadius: radius)
            body.restitution = 0.4
            body.friction = 0.3
            body.linearDamping = 0.4
            body.density = 1.0
            body.categoryBitMask = Category.ball
            body.contactTestBitMask = Category.ball | Category.wall
            body.collisionBitMask = Category.ball | Category.wall
            ball.physicsBody = body

            addChild(ball)
        }
    }

    private func makeFallbackTexture(for carrier: Carrier, diameter: CGFloat) -> SKTexture {
        let s = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: s)
        let image = renderer.image { ctx in
            UIColor(carrier.brandColor).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: s))
        }
        return SKTexture(image: image)
    }

    // MARK: - Motion Updates

    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable else {
            let sway = SKAction.customAction(withDuration: 6.0) { [weak self] _, elapsed in
                let dx = sin(elapsed * 1.2) * 1.5
                self?.physicsWorld.gravity = CGVector(dx: dx, dy: -9.8)
            }
            run(SKAction.repeatForever(sway))
            return
        }

        motionManager.accelerometerUpdateInterval = 1.0 / 50.0
        motionManager.startAccelerometerUpdates()
    }

    override func update(_ currentTime: TimeInterval) {
        if !hasRecordedStartTime {
            sceneStartTime = currentTime
            hasRecordedStartTime = true
        }

        guard let data = motionManager.accelerometerData else { return }
        physicsWorld.gravity = CGVector(
            dx: data.acceleration.x * 9.8,
            dy: data.acceleration.y * 9.8
        )
    }

    // MARK: - Pause / Resume

    func pause() {
        isPaused = true
        motionManager.stopAccelerometerUpdates()
    }

    func resume() {
        isPaused = false
        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates()
        }
        lightHaptic.prepare()
    }

    // MARK: - Contact Delegate (Haptics)

    func didBegin(_ contact: SKPhysicsContact) {
        guard !isPaused else { return }

        let isWallCollision =
            contact.bodyA.categoryBitMask == Category.wall ||
            contact.bodyB.categoryBitMask == Category.wall
        guard isWallCollision else { return }

        guard contact.collisionImpulse > 0.5 else { return }

        let now = CACurrentMediaTime()
        guard hasRecordedStartTime, now - sceneStartTime > 0.5 else { return }
        guard now - lastHapticTime > 0.2 else { return }
        lastHapticTime = now

        lightHaptic.impactOccurred()
    }
}
