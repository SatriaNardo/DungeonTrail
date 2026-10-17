import SpriteKit

final class GameMenuOverlay: SKNode {
    private var onStart: (() -> Void)?

    func configure(
        size: CGSize,
        lightPositionRatio: CGPoint = CGPoint(x: 0.45, y: 0.4), // Position relative to screen (0.0 to 1.0)
        lightRadius: CGFloat = 250,
        ambientOpacity: CGFloat = 0.3,
        lightColor: UIColor = UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 0.45), // Warm ambient light
        onStart: @escaping () -> Void
    ) {
        self.onStart = onStart
        removeAllChildren()
        zPosition = 100

        // 1. Full-screen black background layer
        let blackBackground = SKShapeNode(rectOf: size)
        blackBackground.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        blackBackground.fillColor = .black
        blackBackground.strokeColor = .clear
        blackBackground.zPosition = 0
        addChild(blackBackground)

        // 2. Preload animation textures (HomeScreen1 to HomeScreen4)
        let homeScreenTextures = (1...4).map { SKTexture(imageNamed: "HomeScreen\($0)") }
        guard let firstTexture = homeScreenTextures.first else { return }

        // 3. Create initial sprite with calculated aspect ratio fit
        let background = SKSpriteNode(texture: firstTexture)
        
        let imageWidth = firstTexture.size().width
        let imageHeight = firstTexture.size().height
        
        if imageWidth > 0 && imageHeight > 0 {
            let imageAspect = imageWidth / imageHeight
            let targetHeight = size.height
            let targetWidth = targetHeight * imageAspect
            background.size = CGSize(width: targetWidth, height: targetHeight)
        } else {
            background.size = size
        }
        
        background.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        background.zPosition = 1
        addChild(background)

        // 4. Run looping animation sequence
        let animateAction = SKAction.animate(
            with: homeScreenTextures,
            timePerFrame: 0.2,
            resize: false,
            restore: false
        )
        background.run(SKAction.repeatForever(animateAction), withKey: "homeScreenAnimation")

        // 5. Dark Ambient Base Layer (Vignette Tint)
        let darkAmbientNode = SKShapeNode(rectOf: size)
        darkAmbientNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        darkAmbientNode.fillColor = UIColor.black.withAlphaComponent(ambientOpacity)
        darkAmbientNode.strokeColor = .clear
        darkAmbientNode.zPosition = 2
        addChild(darkAmbientNode)

        // 6. Central Spotlight Node (Generated Radial Gradient Texture)
        let lightPos = CGPoint(
            x: size.width * lightPositionRatio.x,
            y: size.height * lightPositionRatio.y
        )
        
        if let lightTexture = createRadialGradientTexture(radius: lightRadius, color: lightColor) {
            let spotlightNode = SKSpriteNode(texture: lightTexture)
            spotlightNode.position = lightPos
            spotlightNode.blendMode = .add // Screen/Add blending for glowing effect
            spotlightNode.zPosition = 3
            addChild(spotlightNode)
        }
    }

    func startGame() {
        onStart?()
    }
    
    // Helper function to dynamically draw a smooth radial light texture
    private func createRadialGradientTexture(radius: CGFloat, color: UIColor) -> SKTexture? {
        let size = CGSize(width: radius * 2, height: radius * 2)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        let colors = [color.cgColor, color.withAlphaComponent(0.15).cgColor, UIColor.clear.cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let locations: [CGFloat] = [0.0, 0.5, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            let center = CGPoint(x: radius, y: radius)
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: .drawsAfterEndLocation
            )
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image != nil ? SKTexture(image: image!) : nil
    }
}
