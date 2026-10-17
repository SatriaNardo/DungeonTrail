import SpriteKit
import SwiftUI
#if canImport(UIKit)
import UIKit
import AVFoundation

#endif
final class GameScene: SKScene {
    static let iPhone17PortraitSize = CGSize(width: 402, height: 874)
    /// Set by ContentView before the scene is presented.
    /// GameScene writes live values here; SwiftUI HUDView reads them.
    weak var gameHUD: GameHUD?
    private enum PhysicsCategory {
        static let none: UInt32 = 0
        static let player: UInt32 = 1 << 0
        static let trap: UInt32 = 1 << 1
        static let collectible: UInt32 = 1 << 2
        static let follower: UInt32 = 1 << 3
    }
    private enum AssetName {
        static let tile = "tile"
        static let trap = "trap"
        static let collectible = "Chest"
        static let player = "player"
        static let follower = "follower"
        static let detectorText = "detectorText"
    }
    private struct Tile {
        let row: Int
        let column: Int
        let hasTrap: Bool
    }
    private struct GridPosition: Hashable {
        let row: Int
        let column: Int
    }

    private enum TrapType {
        case spike
        case fire

        var texturePrefix: String {
            switch self {
            case .spike: return "SpikeTrap"
            case .fire: return "FireTrap"
            }
        }
    }
    private enum MarkType {
        case question
        case xMark
        var next: MarkType? {
            switch self {
            case .question: return .xMark
            case .xMark:    return nil
            }
        }
    }
    private enum TutorialStep {
        case moveUp       // Step 0: player must swipe up twice to reach row 5
        case nearbyTrap   // Step 1: explain the trap detector number
        case markTiles    // Step 2: player must tap 3 adjacent tiles with QMark
        case moveDown     // Step 3: player must swipe down once
        case moveSideways // Step 4: player must swipe left AND right at least once each
        case done         // Tutorial complete – free play
    }
    private enum TorchSide {
        case left
        case right
    }
    private struct TorchData {
        let side: TorchSide
        let isLit: Bool
    }
    // MARK: - ⚙️ Lighting & Torch Settings
    private let torchXOffsetMultiplier: CGFloat = 0.625   // Wall horizontal offset multiplier
    private let torchWidthRatio: CGFloat = 0.64           // Torch width relative to tile width
    private let torchHeightRatio: CGFloat = 1.5           // Torch height relative to tile height
    private let torchLightYOffsetRatio: CGFloat = 0.45    // Torch light Y position relative to torch height (lowered down)
    private let torchSpawnChancePerRow: Double = 0.12     // 12% spawn chance per eligible row
    private let torchMinRowSpacing: Int = 4               // Minimum row gap between torches
    private let torchLitProbability: Double = 0.75        // 75% lit (Torch1..8), 25% unlit (Torch0)
    private let torchLightFalloff: CGFloat = 2.0          // Light falloff (lower = brighter & larger light coverage)
    private let torchLightColor = SKColor(red: 1.0, green: 0.82, blue: 0.42, alpha: 1.0) // Brighter warm torch light
    private let torchFlickerSpeed: Double = 11.0          // Speed of flame light flicker animation
    private let torchFlickerAmount: CGFloat = 0.18        // Intensity of light falloff flicker variation
    private let playerLightFalloff: CGFloat = 1         // Player light falloff
    private let playerLightColor = SKColor(white: 0.95, alpha: 1.0)
    private let dungeonAmbientColor = SKColor(white: 0.12, alpha: 1.0) // Scene ambient darkness
    private let followerLightFalloff: CGFloat = 2.2       // Follower light falloff
    // MARK: - ⚙️ Player Size, Position, Shadow & Speed Settings
    private let playerWidthRatio: CGFloat = 1.4    // Player width relative to tile width (increase to make wider, e.g. 0.95 - 1.2)
    private let playerHeightRatio: CGFloat = 1.45  // Player height relative to tile height (increase to make taller/larger, e.g. 1.45 - 1.8)
    private let playerAnchorX: CGFloat = 0.50      // Player horizontal anchor (0.5 = centered)
    private let playerAnchorY: CGFloat = 0.25      // Player vertical anchor (0.25 = feet position relative to sprite)
    private let playerOffsetY: CGFloat = 0         // Extra vertical pixel offset (+ for up, - for down)
    private let playerShadowWidthRatio: CGFloat = 0.65   // Shadow width relative to tile width
    private let playerShadowHeightRatio: CGFloat = 0.22  // Shadow height relative to tile height
    private let playerShadowOffsetX: CGFloat = 0.0       // Shadow X offset relative to feet (+ for right, - for left)
    private let playerShadowOffsetY: CGFloat = 25       // Shadow Y offset relative to feet (+ for up, - for down)
    private let playerShadowOpacity: CGFloat = 0.40      // Shadow darkness opacity (0.0 to 1.0)
    private let playerStepAnimTimePerFrame: TimeInterval = 0.15  // Step/Walk frame speed (slower animation, e.g. 0.08 - 0.12s)
    private let playerIdleAnimTimePerFrame: TimeInterval = 0.16  // Idle frame speed
    private let followerWalkAnimTimePerFrame: TimeInterval = 0.13 // Follower walk frame speed (increase to slow down)
    private let playerMoveSlideDuration: TimeInterval = 0.275    // Physical step movement slide duration between tiles (higher = slower step movement)
    // MARK: - General Game Parameters
    private let columnCount = 5
    private let visibleColumnsWidth: CGFloat = 4.0
    private let visibleRows: CGFloat = 7.5
    private let storedRowCount = 30
    private let rowsBehindPlayer = 3
    private let defaultFollowerLag = 2
    private let catchUpCountdownTarget = 5
    private let trapChance = 0.18
    private let maxDefusePower = 3.0
    private let rowsPerDefuseRecharge = 10
    private let pointsPerNewHighestTile = 10
    private let collectiblePoints = 100
    private let isFollowerEnabled = false
    private let followerTrapPenalty = 50
    private let collectibleChancePerRow = 0.05
    private let longPressDuration: TimeInterval = 0.45
    private let holdFeedbackActionKey = "hold-feedback"
    private var tileSize = CGSize(width: 0, height: 0)
    private var mapOrigin = CGPoint.zero
    private var bottomVisibleRow = 0
    private var cameraLeftColumn: CGFloat = 0.5
    private var playerGrid = (row: 3, column: 2)
    private var followerGrid = (row: 1, column: 2)
    private var isFollowerLeftOut = false
    private var leftOutCountdown = 0
    private var lastPlayerHorizontalDirection = 0
    private var playerVisitedTiles: Set<GridPosition> = [GridPosition(row: 3, column: 2)]
    private var tilesByRow: [Int: [Tile]] = [:]
    private var trapTypesByPosition: [GridPosition: TrapType] = [:]
    private var tileTextureNames: [GridPosition: String] = [:]
    private let tileImageNames = ["Tiles1", "Tiles2", "Tiles3", "Tiles4", "Tiles5", "Tiles6", "Tiles7", "Tiles8"]
    // Deterministic torch state management per row
    private var torchesByRow: [Int: TorchData] = [:]
    private var lastTorchRow: Int = -10
    private var markedTiles: [GridPosition: MarkType] = [:]
    private var defusedTiles: Set<GridPosition> = []
    private var collectibleTiles: Set<GridPosition> = []
    private var collectedTiles: Set<GridPosition> = []
    private var swipeStartPoint: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var isGameStarted = false
    private var isPlayerMoving = false
    private var isGameLost = false
    private var highestTileReached = 3
    private var lastRechargeTileReached = 3
    private var movementScore = 0
    private var collectibleScore = 0
    private var followerPenaltyScore = 0
    private var defusePower = 3.0
    private var activeHoldFeedbackNode: SKNode?
    private var followerTriggeredTraps: Set<GridPosition> = []
    
    // MARK: - Score Multiplier

    private let scoreMultiplierStepInterval = 20
    private let startingScoreMultiplier = 1
    
    // MARK: - Tutorial State
    private var isTutorialActive = false
    private var tutorialStep: TutorialStep = .moveUp
    private var tutorialMarkedSet: Set<GridPosition> = []
    private var tutorialMovedLeft = false
    private var tutorialMovedRight = false
    // Follower Trap Dodge Tutorial State
    private var hasCompletedFollowerTrapTutorial = false
    private var isFollowerTutorialActive = false
    private var canSwapMarks = false
    // Defuse Tutorial State (Row 9)
    private var hasCompletedDefuseTutorial = false
    private var isDefuseTutorialActive = false
    private var defuseTutorialTargetTile: GridPosition?
    // Tutorial required mark positions (relative to player stop at row 4, col 2)
    private let tutorialMarkTargets: [GridPosition] = [
        GridPosition(row: 4, column: 1),  // Left of player
        GridPosition(row: 5, column: 2),  // Top of player (has trap)
        GridPosition(row: 4, column: 3)   // Right of player
    ]
    // MARK: - ⚙️ Tutorial UI & Animation Config (Easily Configurable)
    // You can adjust locations, offsets, sizes, and animation speeds for all tutorial UI here:
    // 1. Directional Slide Animations (SlideUp, SlideDown, SlideLeft, SlideRight)
    var tutorialSlideSpriteScale: CGFloat = 1.2             // Scale relative to tileSize
    var tutorialSlideAnimTimePerFrame: TimeInterval = 0.2   // Seconds per frame (Slide 1...3)
    var tutorialSlideUpOffset: CGPoint = CGPoint(x: 75, y: 60)      // Offset from player center
    var tutorialSlideDownOffset: CGPoint = CGPoint(x: 75, y: -60)   // Offset from player center
    var tutorialSlideLeftOffset: CGPoint = CGPoint(x: -90, y: 0)   // Offset from player center
    var tutorialSlideRightOffset: CGPoint = CGPoint(x: 90, y: 0)   // Offset from player center
    // 2. Tap Animation (Tap1...Tap3 on the surrounding tiles)
    var tutorialTapSpriteScale: CGFloat = 1               // Scale relative to tileSize
    var tutorialTapAnimTimePerFrame: TimeInterval = 0.2     // Seconds per frame (Tap 1...3)
    var tutorialTapSpriteOffset: CGPoint = CGPoint(x: 0, y: -4)    // Offset within tile
    var tutorialTapLabelOffset: CGPoint = CGPoint(x: 0, y: 16)     // "TAP" text offset within tile
    var tutorialTapLabelFontSizeRatio: CGFloat = 0.22        // Font size relative to tileSize.width
    // 3. Hold Animation (HoldUI1...HoldUI11 on the defuse trap tile)
    var tutorialHoldSpriteScale: CGFloat = 0.9             // Scale relative to tileSize
    var tutorialHoldAnimTimePerFrame: TimeInterval = 0.1    // Seconds per frame (Hold 1...11)
    var tutorialHoldSpriteOffset: CGPoint = CGPoint(x: 0, y: 0)    // Offset within tile
    var tutorialHoldLabelOffset: CGPoint = CGPoint(x: 0, y: -24)   // "HOLD" text offset within tile
    var tutorialHoldLabelFontSizeRatio: CGFloat = 0.22       // Font size relative to tileSize.width
    // 4. Tutorial Instruction Banner Position
    var tutorialBannerTopOffset: CGFloat = 160             // Distance from top of screen to tutorial instruction banner
    // Tutorial Animation Textures
    private var tutorialTapTextures: [SKTexture] = []
    private var tutorialSlideUpTextures: [SKTexture] = []
    private var tutorialSlideDownTextures: [SKTexture] = []
    private var tutorialSlideLeftTextures: [SKTexture] = []
    private var tutorialSlideRightTextures: [SKTexture] = []
    private var tutorialHoldTextures: [SKTexture] = []
    // MARK: - ⚙️ Follower & Player Idle Arrow Config (Easily Configurable)
    // 1. Follower Direction Arrow (points to where the follower will move next)
    var followerArrowOffset: CGPoint = CGPoint(x: 0, y: 90)         // Offset from follower sprite center
    var followerArrowScale: CGFloat = 1                         // Scale relative to tileSize
    var followerArrowBobbingDistance: CGFloat = 4.0                 // Bobbing distance up/down
    var followerArrowBobbingDuration: TimeInterval = 0.30           // Bobbing speed duration
    // 2. Player Idle 4-Way Arrows (shown when player is idle)
    var playerIdleArrowDistanceRatio: CGFloat = 0.80                // Distance from player center relative to tileSize
    var playerIdleArrowScale: CGFloat = 1                        // Scale relative to tileSize
    var playerIdleArrowPulseDistance: CGFloat = 6.0                 // Pulse distance outward
    var playerIdleArrowPulseDuration: TimeInterval = 0.35           // Pulse duration in/out
    // MARK: - ⚙️ HUD Layout Config (Easily Configurable)
    // All positions are in scene coordinates (origin = bottom-left).
    // size.height ≈ 874, size.width ≈ 402 on iPhone 17 portrait.
    // --- Master Y offset ---
    // Increase hudYOffset to move the ENTIRE HUD (and gradient) DOWN from the top edge.
    // e.g. 0 = flush with top, 40 = shifted 40pt downward.
    var hudYOffset: CGFloat = 25
    // --- Black gradient (top fade) ---
    var hudGradientHeight: CGFloat = 165                        // Height of the dark top-fade gradient
    // --- Coin icon (left side) ---
    var hudCoinSize: CGFloat = 26                               // Diameter of the gold coin icon
    var hudCoinX: CGFloat = 16                                  // Left edge X of coin
    var hudCoinFromTop: CGFloat = 57                            // Distance from top edge to coin center
    // --- Score number (right of coin) ---
    var hudScoreOffsetX: CGFloat = 6                            // Gap between coin right edge and score number
    var hudScoreFontSize: CGFloat = 22
    // --- Depth label (below coin row) ---
    var hudDepthFromTop: CGFloat = 82                           // Distance from top edge to depth label top
    var hudDepthX: CGFloat = 16
    var hudDepthFontSize: CGFloat = 18
    // --- Disarm trap icons (right side) ---
    var hudDisarmIconSize: CGFloat = 36                         // Width & height of each disarm icon
    var hudDisarmIconSpacing: CGFloat = 6                       // Gap between icons
    var hudDisarmIconRightEdge: CGFloat = 386                   // X of rightmost icon's right edge
    var hudDisarmIconFromTop: CGFloat = 57                      // Distance from top edge to icons center
    // --- Game Over animation ---
    var gameOverOverlayScale: CGFloat = 0.75
    var gameOverOverlayOffset = CGPoint.init(x: 0, y: 0)
    @AppStorage("highestScore") private var highestScore = 0
    @AppStorage("highestTileReachedBest") private var highestTileReachedBest = 3
    private let worldNode = SKNode()
    private let mapNode = SKNode()
    private let trapLayerNode = SKNode()
    private let collectibleLayerNode = SKNode()
    private let feedbackLayerNode = SKNode()
    private let playerLayerNode = SKNode()
    private let followerBubbleNode = SKNode()
    private let topGradientNode = SKSpriteNode()
    private let redOverlayNode = SKSpriteNode()
    private let playerNode = SKSpriteNode(texture: SKTexture(imageNamed: "OjokIdle1"), size: CGSize(width: 38, height: 52))
    private let playerShadowNode = SKShapeNode()
    private let followerNode = SKSpriteNode(texture: SKTexture(imageNamed: "Follower1"), size: CGSize(width: 34, height: 46))
    private let followerShadowNode = SKShapeNode()
    // Ojok Player Character Textures
    private var ojokIdleTextures: [SKTexture] = []
    private var ojokWalkTextures: [SKTexture] = []
    private var ojokRightStepTextures: [SKTexture] = []
    private var ojokLeftStepTextures: [SKTexture] = []
    private var ojokDeadTextures: [SKTexture] = []
    // Follower Character Textures
    private var followerIdleTextures: [SKTexture] = []
    private var followerWalkTextures: [SKTexture] = []
    private var followerDidMoveThisStep = false
    // Trap Detection Textures
    private var trapDetectTextures: [SKTexture] = []
    private var gameOverTextures: [SKTexture] = []
    // Lighting
    private let playerLightNode = SKLightNode()
    private let followerLightNode = SKLightNode()
    private let followerArrowNode = SKNode()
    private let trapNumberLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let trapWarningOverlayNode = SKNode()
    private let playerIdleOverlayNode = SKNode()
    private let playerIdleThreshold: TimeInterval = 3
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let coinIconNode = SKSpriteNode(imageNamed: "GoldCoin")
    private let heightLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var disarmIconNodes: [SKSpriteNode] = []   // Disarm trap icon sprites (enabled/disabled)
    private let feedbackLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let loseLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let loseSubtitleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let endScoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let endHeightLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let retryLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let gameOverCoinIconNode = SKSpriteNode(imageNamed: "GoldCoin")
    private let gameOverOverlayNode = SKSpriteNode()
    private let menuOverlay = GameMenuOverlay()
    // Tutorial FTUE Nodes
    private let tutorialArrowNode = SKNode()         // Child of playerNode – arrows follow player
    private let tutorialTileHighlightNode = SKNode() // Child of worldNode – scrolls with map
    private let tutorialInstructionBg = SKShapeNode()
    private var disarmingAudioNode: SKAudioNode?
    private let tutorialInstructionLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let followerTutorialHighlightNode = SKNode() // Child of worldNode – highlights follower trap
    private let defuseTutorialHighlightNode = SKNode()   // Child of worldNode – highlights tile to defuse
    
    // MARK: - Follower Bubble Chat

    private let followerChatMinimumDelay: TimeInterval = 5.0
    private let followerChatMaximumDelay: TimeInterval = 10.0
    private let followerChatChance: Double = 0.3

    private let followerChatDuration: TimeInterval = 2.2

    private var followerHasBeenHit = false

    private let followerNormalDialogue: [String] = [
        "Careful!",
        "Keep going!",
        "That was close!",
        "What's that?",
        "Don't step there!",
        "We're doing great!",
        "Are we there yet?",
        "Something feels wrong."
    ]

    private let followerHitDialogue: [String] = [
        "OW!",
        "Do your job!",
        "That hurt!",
        "I got hit!",
        "I'm okay... I think.",
        "Watch the traps!",
        "My foot!"
    ]
    
    // MARK: - Game Initialization
    override func didMove(to view: SKView) {
        size = Self.iPhone17PortraitSize
        scaleMode = .aspectFit
        backgroundColor = .black
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        addChild(worldNode)
        worldNode.addChild(mapNode)
        worldNode.addChild(trapLayerNode)
        worldNode.addChild(collectibleLayerNode)
        worldNode.addChild(feedbackLayerNode)
        worldNode.addChild(playerLayerNode)
        setupLights()
        buildInitialMap()
        layoutScene()
        renderVisibleTiles()
        placePlayer()
        updateFollowerEnabledState()
        updatePlayerTrapNumber()
        setupStatusLabels()
        updateScore()
        updatePower()
        showStartMenu()
    }
    private func setupLights() {
        playerLightNode.categoryBitMask = 1
        playerLightNode.falloff = playerLightFalloff
        playerLightNode.lightColor = playerLightColor
        playerLightNode.ambientColor = dungeonAmbientColor
        playerNode.addChild(playerLightNode)
        followerLightNode.categoryBitMask = 1
        followerLightNode.falloff = followerLightFalloff
        followerLightNode.lightColor = SKColor(red: 0.85, green: 0.70, blue: 1.0, alpha: 1.0)
        followerLightNode.ambientColor = .clear
        followerNode.addChild(followerLightNode)
    }
    override func didChangeSize(_ oldSize: CGSize) {
        layoutScene()
        renderVisibleTiles()
        placePlayer()
        updateFollowerEnabledState()
        layoutHUD()
        if !isGameStarted {
            showStartMenu()
        }
    }
    private func showStartMenu() {
        setHUDVisible(false)
        if menuOverlay.parent == nil {
            addChild(menuOverlay)
        }
        menuOverlay.configure(size: size) { [weak self] in
            self?.startGame()
        }
    }
    private func startGame() {
        isGameStarted = true
        
        AudioManager.shared.playBGM()
        
        scheduleFollowerBubbleChat()
        setHUDVisible(true)
        menuOverlay.removeFromParent()
        resetPlayerIdleTimer()
        setupTutorial()
    }
    private func setHUDVisible(_ isVisible: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.gameHUD?.isVisible = isVisible
        }
    }
    private func layoutScene() {
        let topInset: CGFloat = 60
        let bottomInset: CGFloat = 0
        let usableHeight = size.height - topInset - bottomInset
        let widthBasedTile = size.width / visibleColumnsWidth
        let heightBasedTile = usableHeight / visibleRows
        let side = min(widthBasedTile, heightBasedTile)
        tileSize = CGSize(width: side, height: side)
        mapOrigin = CGPoint(
            x: (size.width - side * visibleColumnsWidth) * 0.5,
            y: bottomInset
        )
    }
    // MARK: - Map Initialization
    private func buildInitialMap() {
        tilesByRow.removeAll()
        trapTypesByPosition.removeAll()
        tileTextureNames.removeAll()
        torchesByRow.removeAll()
        collectibleTiles.removeAll()
        lastTorchRow = -10
        generateThirtyRowWindow(startingAt: bottomVisibleRow)
        clearStartingSafeTiles()
        applyTutorialTrapLayout()
    }
    private func generateRow(_ row: Int) -> [Tile] {
        (0..<columnCount).map { column in
            let hasTrap = Double.random(in: 0...1) < trapChance
            let position = GridPosition(row: row, column: column)

            if hasTrap {
                trapTypesByPosition[position] = Bool.random() ? .spike : .fire
            }

            return Tile(row: row, column: column, hasTrap: hasTrap)
        }
    }
    private func randomTileTextureName(for gridPosition: GridPosition) -> String {
        if let existing = tileTextureNames[gridPosition] { return existing }
        let name = tileImageNames.randomElement() ?? "Tiles1"
        tileTextureNames[gridPosition] = name
        return name
    }
    private func renderVisibleTiles() {
        mapNode.removeAllChildren()
        trapLayerNode.removeAllChildren()
        collectibleLayerNode.removeAllChildren()
        for row in bottomVisibleRow..<(bottomVisibleRow + storedRowCount) {
            ensureRowExists(row)
            // ── Wall tiles rendered inside mapNode at columns -1 and columnCount ──
            let leftWall = SKSpriteNode(texture: SKTexture(imageNamed: "WallLeft"), size: tileSize)
            leftWall.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            leftWall.lightingBitMask = 1
            SpriteHelper.addNode(leftWall, to: mapNode, at: pointFor(row: row, column: -1), zPosition: 0)
            let rightWall = SKSpriteNode(texture: SKTexture(imageNamed: "WallRight"), size: tileSize)
            rightWall.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            rightWall.lightingBitMask = 1
            SpriteHelper.addNode(rightWall, to: mapNode, at: pointFor(row: row, column: columnCount), zPosition: 0)
            // ── Render Torch from Stored Row State ──
            if let torchData = torchesByRow[row] {
                let torchNode = createTorchNode(isLit: torchData.isLit)
                let wallPos = pointFor(row: row, column: torchData.side == .left ? -1 : columnCount)
                let xOffset = torchData.side == .left ? (tileSize.width * torchXOffsetMultiplier) : (-tileSize.width * torchXOffsetMultiplier)
                torchNode.position = CGPoint(x: wallPos.x + xOffset, y: wallPos.y)
                mapNode.addChild(torchNode)
            }
            for column in 0..<columnCount {
                let position = pointFor(row: row, column: column)
                let gridPosition = GridPosition(row: row, column: column)
                let textureName = randomTileTextureName(for: gridPosition)
                let tileSprite = SKSpriteNode(texture: SKTexture(imageNamed: textureName), size: tileSize)
                tileSprite.name = "\(AssetName.tile)-\(row)-\(column)"
                tileSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                tileSprite.lightingBitMask = 1
                if let markType = markedTiles[gridPosition] {
                    tileSprite.addChild(markNode(size: tileSize, type: markType))
                }
                SpriteHelper.addNode(tileSprite, to: mapNode, at: position, zPosition: 0)
                if hasActiveTrap(at: gridPosition) {
                    let trapSprite = trapNode(for: gridPosition)
                    trapSprite.name = "\(AssetName.trap)-\(row)-\(column)"
                    trapSprite.alpha = 0
                    configureTrapPhysics(for: trapSprite, at: gridPosition)
                    SpriteHelper.addNode(trapSprite, to: trapLayerNode, at: position, zPosition: 2)
                }
                if hasActiveCollectible(at: gridPosition) {
                    let collectibleSprite = collectibleNode()
                    collectibleSprite.name = "\(AssetName.collectible)-\(row)-\(column)"
                    configureCollectiblePhysics(for: collectibleSprite, at: gridPosition)
                    SpriteHelper.addNode(collectibleSprite, to: collectibleLayerNode, at: position, zPosition: 3)
                }
            }
        }
    }
    // MARK: - Torch Node Factory
    private func createTorchNode(isLit: Bool) -> SKNode {
        let torchContainer = SKNode()
        torchContainer.zPosition = 1
        let torchSize = CGSize(width: tileSize.width * torchWidthRatio, height: tileSize.height * torchHeightRatio)
        let initialTextureName = isLit ? "Torch1" : "Torch0"
        let torchSprite = SKSpriteNode(texture: SKTexture(imageNamed: initialTextureName), size: torchSize)
        torchSprite.anchorPoint = CGPoint(x: 0.5, y: 0.15)
        torchSprite.lightingBitMask = 1
        if isLit {
            // 8-frame flame animation (Torch1 to Torch8)
            let textures = (1...8).map { SKTexture(imageNamed: "Torch\($0)") }
            let animation = SKAction.animate(with: textures, timePerFrame: 0.09)
            torchSprite.run(SKAction.repeatForever(animation))
            // Torch light node placed at lowered Y offset
            let torchLight = SKLightNode()
            torchLight.categoryBitMask = 1
            torchLight.falloff = torchLightFalloff
            torchLight.lightColor = torchLightColor
            torchLight.ambientColor = .clear
            torchLight.position = CGPoint(x: 0, y: torchSize.height * torchLightYOffsetRatio)
            // Continuous time-based flickering using customAction
            let flickerSpeed = torchFlickerSpeed
            let baseFalloff = torchLightFalloff
            let flickerAmount = torchFlickerAmount
            let flickerAction = SKAction.repeatForever(
                SKAction.customAction(withDuration: 60.0) { node, elapsedTime in
                    guard let light = node as? SKLightNode else { return }
                    let time = Double(elapsedTime)
                    let noise = sin(time * flickerSpeed) * Double(flickerAmount) + cos(time * (flickerSpeed * 0.65)) * Double(flickerAmount * 0.75)
                    light.falloff = baseFalloff + CGFloat(noise)
                }
            )
            torchLight.run(flickerAction)
            torchSprite.addChild(torchLight)
        }
        torchContainer.addChild(torchSprite)
        return torchContainer
    }
    private func clearStartingSafeTiles() {
        let safeRows = 0...playerGrid.row
        for row in safeRows {
            tilesByRow[row] = tilesByRow[row]?.map { tile in
                Tile(row: tile.row, column: tile.column, hasTrap: false)
            }
            for column in 0..<columnCount {
                let safePosition = GridPosition(row: row, column: column)
                collectibleTiles.remove(safePosition)
                collectedTiles.remove(safePosition)
            }
        }
    }
    // MARK: - Player Movement
    func movePlayer(byColumn columnDelta: Int, byRow rowDelta: Int) {
        guard isGameStarted, !isPlayerMoving, !isGameLost, !isFollowerTutorialActive, !isDefuseTutorialActive else { return }
        // Tutorial movement constraints
        if isTutorialActive {
            switch tutorialStep {
            case .moveUp:
                guard rowDelta > 0, columnDelta == 0 else { return } // Only up
            case .nearbyTrap, .markTiles:
                return // No movement during marking step
            case .moveDown:
                guard rowDelta < 0, columnDelta == 0 else { return } // Only down
            case .moveSideways:
                guard columnDelta != 0, rowDelta == 0 else { return } // Only sideways
                if columnDelta < 0 { tutorialMovedLeft = true }
                if columnDelta > 0 { tutorialMovedRight = true }
            case .done:
                break
            }
        }
        resetPlayerIdleTimer()
        let nextColumn = max(0, min(columnCount - 1, playerGrid.column + columnDelta))
        let nextRow = limitedRowAfterMoving(by: rowDelta)
        guard nextColumn != playerGrid.column || nextRow != playerGrid.row else { return }
        
        
        playPlayerMovementAnimation(columnDelta: columnDelta, rowDelta: rowDelta)
        let isMovingStrictlyForward = rowDelta > 0 && nextRow > highestTileReached
        let forwardRowsClimbed = isMovingStrictlyForward ? (nextRow - highestTileReached) : 0
        if nextColumn != playerGrid.column {
            lastPlayerHorizontalDirection = nextColumn > playerGrid.column ? 1 : -1
        } else if nextRow != playerGrid.row {
            lastPlayerHorizontalDirection = 0
        }
        playerGrid = (row: nextRow, column: nextColumn)
        playerVisitedTiles.insert(GridPosition(row: nextRow, column: nextColumn))
        if isFollowerEnabled && isMovingStrictlyForward {
            advanceFollowerWithCatchUp(forwardRowsClimbed: forwardRowsClimbed)
        }
        updateHighestTileReached(nextRow)
        ensureRowExists(nextRow)
        let targetBottomRow = scrollTargetBottomRow()
        let targetLeftColumn = scrollTargetLeftColumn()
        // Hide the previous trap detector while the player is moving.
        // It will be recalculated once the player reaches the new tile.
        hideTrapWarningOverlay()

        slideCharactersToCurrentTiles { [weak self] in
            guard let self else { return }

            let playerPos = GridPosition(
                row: self.playerGrid.row,
                column: self.playerGrid.column
            )

            if self.hasActiveTrap(at: playerPos) {
                self.triggerTrapDeathSequence(at: playerPos)
                return
            }

            self.scrollWorldIfNeeded(
                toRow: targetBottomRow,
                toColumn: targetLeftColumn
            )

            // IMPORTANT:
            // Recalculate the detector only AFTER the player has stopped.
            self.updatePlayerTrapNumber()

            // Follower trap tutorial trigger
            if self.followerGrid == (row: 4, column: 2)
                && !self.hasCompletedFollowerTrapTutorial {

                let trapPos = GridPosition(row: 5, column: 2)

                if self.markedTiles[trapPos] != .xMark {
                    self.triggerFollowerTrapTutorial()
                    return
                }
            }

            // Defuse tutorial trigger
            if self.playerGrid.row == 9 && !self.hasCompletedDefuseTutorial {
                self.triggerDefuseTutorial()
                return
            }

            // Tutorial step advancement
            if self.isTutorialActive {
                switch self.tutorialStep {
                case .moveUp where self.playerGrid.row >= 4:
                    self.advanceTutorialStep()

                case .moveDown where self.playerGrid.row <= 3:
                    self.advanceTutorialStep()

                case .moveSideways where self.tutorialMovedLeft || self.tutorialMovedRight:
                    self.advanceTutorialStep()

                default:
                    self.updateTutorialOverlay()
                }
            }
        }
        updateScore()
        updateFollowerArrow()
    }
    private func updatePlayerTrapNumber() {
        let nearbyTrapCount = [
            (playerGrid.row + 1, playerGrid.column),
            (playerGrid.row - 1, playerGrid.column),
            (playerGrid.row, playerGrid.column - 1),
            (playerGrid.row, playerGrid.column + 1)
        ].filter { row, column in
            hasActiveTrap(at: GridPosition(row: row, column: column))
        }.count
        let detectorColor: SKColor
        switch nearbyTrapCount {
        case 0:
            detectorColor = SKColor(red: 73 / 255, green: 164 / 255, blue: 73 / 255, alpha: 1) // #49A449
        case 1:
            detectorColor = SKColor(red: 163 / 255, green: 148 / 255, blue: 73 / 255, alpha: 1) // #A39449
        case 2:
            detectorColor = SKColor(red: 164 / 255, green: 120 / 255, blue: 73 / 255, alpha: 1) // #A47849
        default:
            detectorColor = SKColor(red: 164 / 255, green: 87 / 255, blue: 73 / 255, alpha: 1) // #A45749
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: detectorColor,
            .strokeColor: SKColor.black,
            .strokeWidth: -5.0
        ]
        #if canImport(UIKit)
        attributes[.font] = UIFont(
            name: trapNumberLabel.fontName ?? "AvenirNext-Bold",
            size: trapNumberLabel.fontSize
        ) ?? UIFont.boldSystemFont(ofSize: trapNumberLabel.fontSize)
        #endif
        trapNumberLabel.attributedText = NSAttributedString(
            string: "\(nearbyTrapCount)",
            attributes: attributes
        )
        trapNumberLabel.fontColor = detectorColor
        if nearbyTrapCount > 0 {
            showTrapWarningOverlay(color: detectorColor)
        } else {
            hideTrapWarningOverlay()
        }
    }
    private func preloadTrapDetectTextures() {
        guard trapDetectTextures.isEmpty else { return }
        trapDetectTextures = (5...5).map { SKTexture(imageNamed: "TrapDetect\($0)") }
    }
    private func showTrapWarningOverlay(color: SKColor) {
        preloadTrapDetectTextures()
        if trapWarningOverlayNode.parent == nil {
            trapWarningOverlayNode.name = "trapWarningOverlay"
            trapWarningOverlayNode.zPosition = 6
            playerNode.addChild(trapWarningOverlayNode)
        }
        trapWarningOverlayNode.removeAllChildren()
        trapWarningOverlayNode.isHidden = false
        guard !trapDetectTextures.isEmpty else { return }
        // Light up the 4 surrounding adjacent tiles (Top, Bottom, Left, Right)
        let neighborOffsets: [(dr: Int, dc: Int)] = [
            (dr: 1, dc: 0),   // Top tile
            (dr: -1, dc: 0),  // Bottom tile
            (dr: 0, dc: -1),  // Left tile
            (dr: 0, dc: 1)    // Right tile
        ]
        let detectAnimAction = SKAction.repeatForever(
            SKAction.animate(with: trapDetectTextures, timePerFrame: 0.12)
        )
        for (dr, dc) in neighborOffsets {
            let targetCol = playerGrid.column + dc
            let targetRow = playerGrid.row + dr
            // Ensure adjacent tile is within valid grid bounds
            guard targetCol >= 0, targetCol < columnCount else { continue }
            guard targetRow >= bottomVisibleRow, targetRow < bottomVisibleRow + storedRowCount else { continue }
            let detectSprite = SKSpriteNode(texture: trapDetectTextures.first, size: tileSize)
            detectSprite.position = CGPoint(
                x: CGFloat(dc) * tileSize.width,
                y: CGFloat(dr) * tileSize.height
            )
            detectSprite.run(detectAnimAction)
            trapWarningOverlayNode.addChild(detectSprite)
        }
    }
    private func hideTrapWarningOverlay() {
        trapWarningOverlayNode.removeAllChildren()
        trapWarningOverlayNode.isHidden = true
    }
    // MARK: - Player Idle Arrow Overlay (Up, Down, Left, Right)
    private func resetPlayerIdleTimer() {
        removeAction(forKey: "playerIdleTimer")
        hidePlayerIdleOverlay()

        guard isGameStarted && !isGameLost else { return }

        let wait = SKAction.wait(forDuration: 3.0)

        let show = SKAction.run { [weak self] in
            guard let self else { return }
            self.showPlayerIdleOverlay()
        }

        run(
            SKAction.sequence([
                wait,
                show
            ]),
            withKey: "playerIdleTimer"
        )
    }
    private func hidePlayerIdleOverlay() {
        playerIdleOverlayNode.removeAllChildren()
        playerIdleOverlayNode.isHidden = true
    }
    private func showPlayerIdleOverlay() {
        guard isGameStarted, !isGameLost, !isPlayerMoving, !isTutorialActive else { return }
        if playerIdleOverlayNode.parent == nil {
            playerIdleOverlayNode.name = "playerIdleOverlay"
            playerIdleOverlayNode.zPosition = 4.5
            playerLayerNode.addChild(playerIdleOverlayNode)
        }
        playerIdleOverlayNode.position = playerNode.position
        playerIdleOverlayNode.removeAllChildren()
        playerIdleOverlayNode.isHidden = false
        playerIdleOverlayNode.alpha = 0.0
        let arrowSize = CGSize(
            width: tileSize.width * playerIdleArrowScale,
            height: tileSize.height * playerIdleArrowScale
        )
        let arrowTexture = SKTexture(imageNamed: "Arrow")
        // 4 Directional arrow configurations (dr, dc, angle, pulseX, pulseY)
        let directions: [(dr: Int, dc: Int, angle: CGFloat, pulseX: CGFloat, pulseY: CGFloat)] = [
            (dr: 1,  dc: 0,  angle: 0,         pulseX: 0,                             pulseY: playerIdleArrowPulseDistance),   // Top ↑
            (dr: -1, dc: 0,  angle: .pi,       pulseX: 0,                             pulseY: -playerIdleArrowPulseDistance),  // Bottom ↓
            (dr: 0,  dc: -1, angle: .pi * 0.5, pulseX: -playerIdleArrowPulseDistance, pulseY: 0),                              // Left ←
            (dr: 0,  dc: 1,  angle: -.pi * 0.5, pulseX: playerIdleArrowPulseDistance, pulseY: 0)                              // Right →
        ]
        for dir in directions {
            let targetCol = playerGrid.column + dir.dc
            let targetRow = playerGrid.row + dir.dr
            // Valid move bounds check
            guard targetCol >= 0, targetCol < columnCount else { continue }
            guard targetRow >= bottomVisibleRow else { continue }
            let arrowContainer = SKNode()
            arrowContainer.position = CGPoint(
                x: CGFloat(dir.dc) * tileSize.width * playerIdleArrowDistanceRatio,
                y: CGFloat(dir.dr) * tileSize.height * playerIdleArrowDistanceRatio
            )
            arrowContainer.zRotation = dir.angle
            let arrowSprite = SKSpriteNode(texture: arrowTexture, size: arrowSize)
            arrowSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Outward pulsing motion
            let moveOut = SKAction.moveBy(x: dir.pulseX, y: dir.pulseY, duration: playerIdleArrowPulseDuration)
            let moveIn = SKAction.moveBy(x: -dir.pulseX, y: -dir.pulseY, duration: playerIdleArrowPulseDuration)
            moveOut.timingMode = .easeOut
            moveIn.timingMode = .easeIn
            arrowContainer.run(SKAction.repeatForever(SKAction.sequence([moveOut, moveIn])))
            arrowContainer.addChild(arrowSprite)
            playerIdleOverlayNode.addChild(arrowContainer)
        }
        let show = SKAction.fadeIn(withDuration: 0.30)
        let hold = SKAction.wait(forDuration: 1.5)
        let hide = SKAction.fadeOut(withDuration: 0.30)

        let waitForNext = SKAction.run { [weak self] in
            guard let self else { return }
            self.resetPlayerIdleTimer()
        }

        playerIdleOverlayNode.run(
            SKAction.sequence([
                show,
                hold,
                hide,
                SKAction.run { [weak self] in
                    self?.hidePlayerIdleOverlay()
                },
                waitForNext
            ]),
            withKey: "idleArrowCycle"
        )
    }
    private func limitedRowAfterMoving(by rowDelta: Int) -> Int {
        max(bottomVisibleRow, playerGrid.row + rowDelta)
    }
    private func configurePlayerPhysics() {
        playerNode.physicsBody = SKPhysicsBody(rectangleOf: playerNode.size)
        playerNode.physicsBody?.affectedByGravity = false
        playerNode.physicsBody?.isDynamic = true
        playerNode.physicsBody?.categoryBitMask = PhysicsCategory.player
        playerNode.physicsBody?.collisionBitMask = PhysicsCategory.none
        playerNode.physicsBody?.contactTestBitMask = PhysicsCategory.collectible
    }
    // MARK: - Ojok Player Character Animations
    private func preloadPlayerTextures() {
        guard ojokIdleTextures.isEmpty else { return }
        ojokIdleTextures = (1...5).map { SKTexture(imageNamed: "OjokIdle\($0)") }
        ojokWalkTextures = (1...6).map { SKTexture(imageNamed: "OjokWalk\($0)") }
        ojokRightStepTextures = (1...6).map { SKTexture(imageNamed: "OjokRightStep\($0)") }
        ojokLeftStepTextures = (1...6).map { SKTexture(imageNamed: "OjokLeftStep\($0)") }
        ojokDeadTextures = (1...3).map { SKTexture(imageNamed: "OjokDead\($0)") }
    }
    private func startPlayerIdleAnimation() {
        preloadPlayerTextures()
        guard !ojokIdleTextures.isEmpty else { return }
        playerNode.removeAction(forKey: "playerAnimation")
        let idleAction = SKAction.animate(with: ojokIdleTextures, timePerFrame: playerIdleAnimTimePerFrame)
        playerNode.run(SKAction.repeatForever(idleAction), withKey: "playerAnimation")
    }
    private func playPlayerMovementAnimation(columnDelta: Int, rowDelta: Int) {
        preloadPlayerTextures()
        playerNode.removeAction(forKey: "playerAnimation")
        let textures: [SKTexture]
        if columnDelta > 0 {
            textures = ojokRightStepTextures
        } else if columnDelta < 0 {
            textures = ojokLeftStepTextures
        } else if rowDelta > 0 {
            textures = ojokWalkTextures
        } else {
            textures = ojokWalkTextures.reversed()
        }
        guard !textures.isEmpty else { return }
        let animAction = SKAction.animate(with: textures, timePerFrame: playerStepAnimTimePerFrame)
        playerNode.run(animAction, withKey: "playerAnimation")
    }
    // MARK: - Follower Character Animations
    private func startFollowerIdleAnimation() {
        if followerIdleTextures.isEmpty {
            followerIdleTextures = (1...5).map { SKTexture(imageNamed: "Follower\($0)") }
        }
        guard !followerIdleTextures.isEmpty else { return }
        followerNode.removeAction(forKey: "followerAnimation")
        let idleAction = SKAction.animate(with: followerIdleTextures, timePerFrame: playerIdleAnimTimePerFrame)
        followerNode.run(SKAction.repeatForever(idleAction), withKey: "followerAnimation")
    }
    private func startFollowerWalkAnimation() {
        if followerWalkTextures.isEmpty {
            followerWalkTextures = (1...6).map {
                SKTexture(imageNamed: "FollowerWalk\($0)")
            }
        }

        guard !followerWalkTextures.isEmpty else { return }

        followerNode.removeAction(forKey: "followerAnimation")

        let walkAction = SKAction.animate(
            with: followerWalkTextures,
            timePerFrame: followerWalkAnimTimePerFrame
        )

        followerNode.run(
            SKAction.repeatForever(walkAction),
            withKey: "followerAnimation"
        )
    }
    private func placePlayer() {
        playerNode.anchorPoint = CGPoint(x: playerAnchorX, y: playerAnchorY)
        playerNode.size = CGSize(width: tileSize.width * playerWidthRatio, height: tileSize.height * playerHeightRatio)
        // Configure player shadow under feet
        // In local sprite coords, the feet are at y = -(anchorY * spriteHeight)
        // so the shadow sits right at the foot base, and playerShadowOffsetY nudges it further
        let shadowW = tileSize.width * playerShadowWidthRatio
        let shadowH = tileSize.height * playerShadowHeightRatio
        let shadowRect = CGRect(x: -shadowW / 2, y: -shadowH / 2, width: shadowW, height: shadowH)
        playerShadowNode.path = CGPath(ellipseIn: shadowRect, transform: nil)
        playerShadowNode.fillColor = SKColor.black.withAlphaComponent(playerShadowOpacity)
        playerShadowNode.strokeColor = .clear
        playerShadowNode.zPosition = -1
        let feetLocalY = -(playerAnchorY * playerNode.size.height)
        playerShadowNode.position = CGPoint(x: playerShadowOffsetX, y: feetLocalY + playerShadowOffsetY)
        if playerShadowNode.parent == nil {
            playerNode.addChild(playerShadowNode)
        }
        if playerNode.parent == nil {
            playerNode.name = AssetName.player
            preloadPlayerTextures()
            startPlayerIdleAnimation()
            configurePlayerPhysics()
            trapNumberLabel.name = AssetName.detectorText
            trapNumberLabel.fontColor = .green
            trapNumberLabel.fontSize = 30
            trapNumberLabel.verticalAlignmentMode = .center
            trapNumberLabel.horizontalAlignmentMode = .center
            trapNumberLabel.position = CGPoint(x: 0, y: -playerNode.size.height * 0.225)
            playerNode.addChild(trapNumberLabel)
            SpriteHelper.addNode(playerNode, to: playerLayerNode, at: .zero, zPosition: 5)
        }
        var targetPos = pointFor(row: playerGrid.row, column: playerGrid.column)
        targetPos.y += playerOffsetY
        playerNode.position = targetPos
    }
    
    private func showFollowerBubble(from dialogueList: [String]) {
        guard isFollowerEnabled else {
            return
        }

        guard let message = dialogueList.randomElement() else {
            return
        }


        // Cancel and clear the previous bubble
        followerBubbleNode.removeAllActions()
        followerBubbleNode.removeAllChildren()
        followerBubbleNode.alpha = 1.0

        // Make sure the bubble container follows the follower
        if followerBubbleNode.parent == nil {
            followerNode.addChild(followerBubbleNode)
        }

        // Create BubbleChat asset
        let bubble = SKSpriteNode(
            imageNamed: "BubbleChat"
        )
        // ==============================
        // BUBBLE POSITION
        // ==============================
        // X = left / right
        // Y = up / down
        bubble.position = CGPoint(
            x: 70,
            y: followerNode.size.height * 0.7
        )

        bubble.zPosition = 50
        bubble.alpha = 0

        // ==============================
        // CHAT TEXT
        // ==============================
        let label = SKLabelNode(
            fontNamed: "AvenirNext-Bold"
        )

        label.text = message
        label.fontSize = 11
        label.fontColor = .black

        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center

        label.preferredMaxLayoutWidth = bubble.size.width - 30
        label.numberOfLines = 2

        bubble.addChild(label)
        followerBubbleNode.addChild(bubble)

        // ==============================
        // BUBBLE ANIMATION
        // ==============================
        let appear = SKAction.fadeIn(
            withDuration: 0.15
        )

        let hold = SKAction.wait(
            forDuration: followerChatDuration
        )

        let disappear = SKAction.fadeOut(
            withDuration: 0.20
        )

        let remove = SKAction.removeFromParent()

        bubble.run(
            SKAction.sequence([
                appear,
                hold,
                disappear,
                remove
            ]),
            withKey: "followerBubble"
        )
    }
    
    private func scheduleFollowerBubbleChat() {
        guard isFollowerEnabled else {
            return
        }

        guard isGameStarted, !isGameLost else {
            return
        }

        let randomDelay = TimeInterval.random(
            in: followerChatMinimumDelay...followerChatMaximumDelay
        )

        let wait = SKAction.wait(
            forDuration: randomDelay
        )

        let attemptChat = SKAction.run { [weak self] in
            guard let self else {
                return
            }

            guard self.isGameStarted, !self.isGameLost else {
                return
            }

            // If the follower was recently hit,
            // show ONE hit dialogue and immediately
            // return to normal dialogue afterwards.
            if self.followerHasBeenHit {
                self.showFollowerBubble(
                    from: self.followerHitDialogue
                )

                // Reset immediately so future bubbles
                // use the normal dialogue.
                self.followerHasBeenHit = false
            }
            else if Double.random(in: 0...1) <= self.followerChatChance {
                self.showFollowerBubble(
                    from: self.followerNormalDialogue
                )
            }

            // Schedule the next normal chat.
            self.scheduleFollowerBubbleChat()
        }

        run(
            SKAction.sequence([
                wait,
                attemptChat
            ]),
            withKey: "followerBubbleScheduler"
        )
    }
    
    // MARK: - Touch Controls
    #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isGameLost {
            retryGame()
            return
        }
        guard isGameStarted else { return }
        resetPlayerIdleTimer()
        guard let touch = touches.first else { return }
        if isTutorialActive && tutorialStep == .nearbyTrap {
            advanceTutorialStep()
            swipeStartPoint = nil
            return
        }
        swipeStartPoint = touch.location(in: self)
        touchStartTime = touch.timestamp
        scheduleHoldFeedback(atScenePoint: touch.location(in: self))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isGameStarted else { return }
        guard
            let startPoint = swipeStartPoint,
            let currentPoint = touches.first?.location(in: self)
        else { return }
        let delta = CGPoint(x: currentPoint.x - startPoint.x, y: currentPoint.y - startPoint.y)
        if max(abs(delta.x), abs(delta.y)) >= 24 { cancelHoldFeedback() }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isGameStarted else {
            menuOverlay.startGame()
            return
        }
        guard
            let startPoint = swipeStartPoint,
            let endPoint = touches.first?.location(in: self)
        else { return }
        cancelHoldFeedback()
        swipeStartPoint = nil
        let touchEndTime = touches.first?.timestamp ?? touchStartTime
        handleTouchEnd(from: startPoint, to: endPoint, duration: touchEndTime - touchStartTime)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelHoldFeedback()
        swipeStartPoint = nil
    }
    #endif
    private func handleTouchEnd(from startPoint: CGPoint, to endPoint: CGPoint, duration: TimeInterval) {
        guard isGameStarted else { return }
        if isGameLost { retryGame(); return }
        let delta = CGPoint(x: endPoint.x - startPoint.x, y: endPoint.y - startPoint.y)
        guard max(abs(delta.x), abs(delta.y)) >= 24 else {
            if duration >= longPressDuration {
                attemptDefuse(atScenePoint: endPoint)
            } else {
                toggleMark(atScenePoint: endPoint)
            }
            return
        }
        if abs(delta.x) > abs(delta.y) {
            movePlayer(byColumn: delta.x > 0 ? 1 : -1, byRow: 0)
        } else {
            movePlayer(byColumn: 0, byRow: delta.y > 0 ? 1 : -1)
        }
    }
    private func toggleMark(atScenePoint scenePoint: CGPoint) {
        guard !isPlayerMoving, !isGameLost else { return }
        // Tile marks unlock only when the marking lesson begins.
        guard !isTutorialActive || tutorialStep == .markTiles else { return }
        guard let gridPosition = gridPosition(atScenePoint: scenePoint) else { return }
        // Tutorial marking step: restrict to 3 required tiles, only QMark allowed
        if isTutorialActive && tutorialStep == .markTiles {
            let targetSet = Set(tutorialMarkTargets)
            guard targetSet.contains(gridPosition) else { return }
            // Toggle QMark only – no XMark cycle during tutorial
            if markedTiles[gridPosition] != nil {
                markedTiles.removeValue(forKey: gridPosition)
                tutorialMarkedSet.remove(gridPosition)
            } else {
                markedTiles[gridPosition] = .question
                AudioManager.shared.playSFX("QMarkSFX.wav", on: self)
                tutorialMarkedSet.insert(gridPosition)
            }
            renderVisibleTiles()
            updateFollowerArrow()
            updateTutorialOverlay()
            // Advance when all 3 required tiles are marked
            if tutorialMarkedSet.count >= 3 {
                let wait = SKAction.wait(forDuration: 0.5)
                let advance = SKAction.run { [weak self] in self?.advanceTutorialStep() }
                run(SKAction.sequence([wait, advance]))
            }
            return
        }
        // Follower trap tutorial: player swaps mark on (5, 2) to XMark
        if isFollowerTutorialActive {
            guard gridPosition == GridPosition(row: 5, column: 2) else { return }
            if markedTiles[gridPosition] == .question {
                markedTiles[gridPosition] = .xMark
                AudioManager.shared.playSFX("XMarkSFX.wav", on: self)
            } else if markedTiles[gridPosition] == .xMark {
                markedTiles[gridPosition] = .question
                AudioManager.shared.playSFX("QMarkSFX.wav", on: self)
            } else {
                markedTiles[gridPosition] = .xMark
                AudioManager.shared.playSFX("XMarkSFX.wav", on: self)
            }
            renderVisibleTiles()
            updateFollowerArrow()
            if markedTiles[gridPosition] == .xMark {
                completeFollowerTrapTutorial()
            }
            return
        }
        // During defuse tutorial: remind player to HOLD instead of tap
        if isDefuseTutorialActive {
            if gridPosition == defuseTutorialTargetTile {
                showFeedback("HOLD to disarm the trap (long press)")
            }
            return
        }
        // Normal marking behavior: if canSwapMarks, cycle Unmarked -> .question -> .xMark -> Unmarked!
        if canSwapMarks {
            if let current = markedTiles[gridPosition] {
                if let next = current.next {
                    markedTiles[gridPosition] = next
                    let sfx = (next == .xMark) ? "XMarkSFX.wav" : "QMarkSFX.wav"
                    AudioManager.shared.playSFX(sfx, on: self)
                } else {
                    markedTiles.removeValue(forKey: gridPosition)
                }
            } else {
                markedTiles[gridPosition] = .question
                AudioManager.shared.playSFX("QMarkSFX.wav", on: self)
            }
        } else {
            // Before follower tutorial: toggle QMark on/off
            if markedTiles[gridPosition] != nil {
                markedTiles.removeValue(forKey: gridPosition)
            } else {
                markedTiles[gridPosition] = .question
                AudioManager.shared.playSFX("QMarkSFX.wav", on: self)
            }
        }
        renderVisibleTiles()
        updateFollowerArrow()
    }
    private func gridPosition(atScenePoint scenePoint: CGPoint) -> GridPosition? {
        let worldPoint = convert(scenePoint, to: worldNode)
        let colFloat = (worldPoint.x - mapOrigin.x) / tileSize.width + cameraLeftColumn
        let visibleRow = Int(floor((worldPoint.y - mapOrigin.y) / tileSize.height))
        let column = Int(floor(colFloat))
        let row = bottomVisibleRow + visibleRow
        guard column >= 0, column < columnCount else { return nil }
        guard row >= bottomVisibleRow, row < bottomVisibleRow + storedRowCount else { return nil }
        return GridPosition(row: row, column: column)
    }
    // MARK: - Follower Movement
    private func advanceFollowerWithCatchUp(forwardRowsClimbed: Int) {
        guard isFollowerEnabled, forwardRowsClimbed > 0 else {
            followerDidMoveThisStep = false
            return
        }

        let startingRow = followerGrid.row
        let startingColumn = followerGrid.column

        let playerPreviousRow = playerGrid.row - forwardRowsClimbed
        let preMoveDistance = playerPreviousRow - followerGrid.row
        let wasAlreadyLeftOut = preMoveDistance > defaultFollowerLag

        if wasAlreadyLeftOut {
            isFollowerLeftOut = true
            leftOutCountdown += forwardRowsClimbed
        } else {
            isFollowerLeftOut = false
            leftOutCountdown = 0
        }

        let isCatchUpActive = isFollowerLeftOut && (leftOutCountdown >= catchUpCountdownTarget)
        let stepsToMove = isCatchUpActive ? 2 : 1

        if isCatchUpActive {
            leftOutCountdown = 0
        }

        for _ in 0..<stepsToMove {
            if followerGrid.row < playerGrid.row - 1 {

                // Follower trap tutorial
                if followerGrid == (row: 4, column: 2) && !hasCompletedFollowerTrapTutorial {
                    let trapPos = GridPosition(row: 5, column: 2)

                    if markedTiles[trapPos] != .xMark {
                        break
                    }
                }

                moveFollowerSingleStep()
            }
        }

        // Check whether follower actually changed position
        followerDidMoveThisStep =
            followerGrid.row != startingRow ||
            followerGrid.column != startingColumn

        let postMoveDistance = playerGrid.row - followerGrid.row

        if postMoveDistance <= defaultFollowerLag {
            isFollowerLeftOut = false
            leftOutCountdown = 0
        } else {
            isFollowerLeftOut = true
        }

        updateFollowerArrow()
    }
    private func moveFollowerSingleStep() {
        let straightAhead = GridPosition(row: followerGrid.row + 1, column: followerGrid.column)
        if !isMarkedDangerousOrUnsure(straightAhead) {
            followerGrid = (row: straightAhead.row, column: straightAhead.column)
            return
        }
        let nextPos = nextStepForFollowerAroundMarks()
        followerGrid = (row: nextPos.row, column: nextPos.column)
    }
    private func isMarkedDangerousOrUnsure(_ gridPosition: GridPosition) -> Bool {
        return markedTiles[gridPosition] == .xMark
    }
    private func nextStepForFollowerAroundMarks() -> GridPosition {
        let start = GridPosition(row: followerGrid.row, column: followerGrid.column)
        let target = GridPosition(row: playerGrid.row - 1, column: playerGrid.column)
        var queue: [(pos: GridPosition, firstStep: GridPosition)] = []
        var visited: Set<GridPosition> = [start]
        let towardPlayerCol = playerGrid.column >= followerGrid.column ? 1 : -1
        let primaryHoriz = towardPlayerCol
        let secondaryHoriz = -towardPlayerCol
        for dir in [(dr: 1, dc: primaryHoriz), (dr: 1, dc: secondaryHoriz), (dr: 0, dc: primaryHoriz), (dr: 0, dc: secondaryHoriz)] {
            let nextPos = GridPosition(row: start.row + dir.dr, column: start.column + dir.dc)
            if isUnmarkedTileForFollower(nextPos) {
                if nextPos == target { return nextPos }
                queue.append((pos: nextPos, firstStep: nextPos))
                visited.insert(nextPos)
            }
        }
        var closestStep: GridPosition?
        var minDistanceToTarget = Int.max
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let dist = abs(current.pos.row - target.row) + abs(current.pos.column - target.column)
            if dist < minDistanceToTarget { minDistanceToTarget = dist; closestStep = current.firstStep }
            if current.pos == target { return current.firstStep }
            if current.pos.row > start.row + 6 { continue }
            for dir in [(dr: 1, dc: 0), (dr: 1, dc: primaryHoriz), (dr: 1, dc: secondaryHoriz), (dr: 0, dc: primaryHoriz), (dr: 0, dc: secondaryHoriz)] {
                let nextPos = GridPosition(row: current.pos.row + dir.dr, column: current.pos.column + dir.dc)
                guard nextPos.row >= start.row, nextPos.row < playerGrid.row else { continue }
                if !visited.contains(nextPos) && isUnmarkedTileForFollower(nextPos) {
                    visited.insert(nextPos)
                    queue.append((pos: nextPos, firstStep: current.firstStep))
                }
            }
        }
        return closestStep ?? start
    }
    private func isUnmarkedTileForFollower(_ gridPosition: GridPosition) -> Bool {
        guard gridPosition.column >= 0, gridPosition.column < columnCount else { return false }
        guard gridPosition.row >= bottomVisibleRow && gridPosition.row < bottomVisibleRow + storedRowCount else { return false }
        guard gridPosition.row < playerGrid.row else { return false }
        return !isMarkedDangerousOrUnsure(gridPosition)
    }
    private func placeFollower() {
        guard isFollowerEnabled else { return }
        followerNode.anchorPoint = CGPoint(x: 0.5, y: 0.25)
        followerNode.size = CGSize(width: tileSize.width * playerWidthRatio, height: tileSize.height * playerHeightRatio)
        // Shadow under follower feet (mirrors player shadow logic)
        let shadowW = tileSize.width * playerShadowWidthRatio
        let shadowH = tileSize.height * playerShadowHeightRatio
        let shadowRect = CGRect(x: -shadowW / 2, y: -shadowH / 2, width: shadowW, height: shadowH)
        followerShadowNode.path = CGPath(ellipseIn: shadowRect, transform: nil)
        followerShadowNode.fillColor = SKColor.black.withAlphaComponent(playerShadowOpacity)
        followerShadowNode.strokeColor = .clear
        followerShadowNode.zPosition = -1
        let followerFeetLocalY = -(0.25 * followerNode.size.height)
        followerShadowNode.position = CGPoint(x: playerShadowOffsetX, y: followerFeetLocalY + playerShadowOffsetY)
        if followerShadowNode.parent == nil {
            followerNode.addChild(followerShadowNode)
        }
        if followerNode.parent == nil {
            followerNode.name = AssetName.follower
            startFollowerIdleAnimation()
            configureFollowerPhysics()
            SpriteHelper.addNode(followerNode, to: playerLayerNode, at: .zero, zPosition: 4)
        }
        followerNode.position = pointFor(row: followerGrid.row, column: followerGrid.column)
        updateFollowerArrow()
    }
    private func updateFollowerEnabledState() {
        if isFollowerEnabled {
            placeFollower()
        } else {
            followerNode.removeAllActions()
            followerNode.removeFromParent()
            followerArrowNode.removeFromParent()
        }
    }
    // MARK: - Follower Directional Arrow Indicator
    private func setupFollowerArrow() {
        if followerArrowNode.parent == nil {
            followerArrowNode.name = "followerArrow"
            followerArrowNode.position = followerArrowOffset
            followerArrowNode.zPosition = 10
            let arrowSize = CGSize(
                width: tileSize.width * followerArrowScale,
                height: tileSize.height * followerArrowScale
            )
            let arrowSprite = SKSpriteNode(texture: SKTexture(imageNamed: "Arrow"), size: arrowSize)
            arrowSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Floating bobbing motion
            let bobbing = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: followerArrowBobbingDistance, duration: followerArrowBobbingDuration),
                SKAction.moveBy(x: 0, y: -followerArrowBobbingDistance, duration: followerArrowBobbingDuration)
            ]))
            arrowSprite.run(bobbing)
            followerArrowNode.addChild(arrowSprite)
            followerNode.addChild(followerArrowNode)
        }
    }
    private func updateFollowerArrow() {
        guard isFollowerEnabled, followerNode.parent != nil else {
            followerArrowNode.isHidden = true
            return
        }
        setupFollowerArrow()
        followerArrowNode.position = followerArrowOffset
        guard followerGrid.row < playerGrid.row - 1 else {
            followerArrowNode.isHidden = true
            return
        }
        let nextStep = predictFollowerNextStep()
        let deltaRow = nextStep.row - followerGrid.row
        let deltaCol = nextStep.column - followerGrid.column
        guard deltaRow != 0 || deltaCol != 0 else {
            followerArrowNode.isHidden = true
            return
        }
        followerArrowNode.isHidden = false
        let targetAngle = -atan2(CGFloat(deltaCol), CGFloat(deltaRow))
        let rotateAction = SKAction.rotate(toAngle: targetAngle, duration: 0.12, shortestUnitArc: true)
        followerArrowNode.run(rotateAction)
    }
    private func predictFollowerNextStep() -> GridPosition {
        let straightAhead = GridPosition(row: followerGrid.row + 1, column: followerGrid.column)
        if !isMarkedDangerousOrUnsure(straightAhead) {
            return straightAhead
        }
        return nextStepForFollowerAroundMarks()
    }
    // MARK: - Animation & Camera Scrolling
    private func slideCharactersToCurrentTiles(onComplete: @escaping () -> Void = { }) {
        var destination = pointFor(row: playerGrid.row, column: playerGrid.column)
        destination.y += playerOffsetY

        let slide = SKAction.move(
            to: destination,
            duration: playerMoveSlideDuration
        )
        slide.timingMode = .easeOut

        isPlayerMoving = true
        playFootstepSFX()

        playerNode.removeAction(forKey: "playerSlide")

        if isFollowerEnabled {

            // Only walk if follower's grid position actually changed
            if followerDidMoveThisStep {
                startFollowerWalkAnimation()
            } else {
                startFollowerIdleAnimation()
            }

            let followerSlide = SKAction.move(
                to: pointFor(
                    row: followerGrid.row,
                    column: followerGrid.column
                ),
                duration: playerMoveSlideDuration
            )
            followerSlide.timingMode = .easeOut

            followerNode.removeAction(forKey: "followerSlide")
            followerNode.run(
                followerSlide,
                withKey: "followerSlide"
            )
        }

        let slideSequence = SKAction.sequence([
            slide,
            SKAction.run { [weak self] in
                guard let self else { return }

                self.isPlayerMoving = false
                self.startPlayerIdleAnimation()

                if self.isFollowerEnabled {
                    self.startFollowerIdleAnimation()
                    self.followerDidMoveThisStep = false
                }

                onComplete()
            }
        ])

        playerNode.run(
            slideSequence,
            withKey: "playerSlide"
        )
    }
    private func scrollTargetBottomRow() -> Int {
        max(bottomVisibleRow, playerGrid.row - rowsBehindPlayer)
    }
    private func scrollTargetLeftColumn() -> CGFloat {
        let halfTile: CGFloat = 0.5
        if lastPlayerHorizontalDirection < 0 { return cameraLeftColumn - halfTile }
        if lastPlayerHorizontalDirection > 0 { return cameraLeftColumn + halfTile }
        return cameraLeftColumn
    }
    private func scrollWorldIfNeeded(toRow targetBottomRow: Int, toColumn targetLeftColumn: CGFloat) {
        let rowsToScroll = max(0, targetBottomRow - bottomVisibleRow)
        let colsToScroll = targetLeftColumn - cameraLeftColumn
        guard rowsToScroll > 0 || abs(colsToScroll) > 0.001 else { return }
        let deltaX = -tileSize.width * colsToScroll
        let deltaY = -tileSize.height * CGFloat(rowsToScroll)
        let cameraFollow = SKAction.moveBy(x: deltaX, y: deltaY, duration: playerMoveSlideDuration)
        cameraFollow.timingMode = .easeOut
        isPlayerMoving = true
        worldNode.run(cameraFollow) { [weak self] in
            guard let self else { return }
            self.finishScrollingWorld(toRow: targetBottomRow, toColumn: targetLeftColumn)
            self.isPlayerMoving = false
        }
    }
    private func finishScrollingWorld(toRow targetBottomRow: Int, toColumn targetLeftColumn: CGFloat) {
        bottomVisibleRow = targetBottomRow
        cameraLeftColumn = targetLeftColumn
        worldNode.position = .zero
        generateThirtyRowWindow(startingAt: bottomVisibleRow)
        removeRowsBelow(bottomVisibleRow)
        removeRowsAbove(bottomVisibleRow + storedRowCount - 1)
        removeMarksOutsideActiveRows()
        removeDefusedTilesOutsideActiveRows()
        removeCollectiblesOutsideActiveRows()
        renderVisibleTiles()
        placePlayer()
        updateFollowerEnabledState()
        updateTutorialOverlay() // Recompute tutorial highlights after camera scroll
        updateSpecialTutorialHighlights() // Recompute follower & defuse tutorial highlights after camera scroll
        if isFollowerEnabled && followerGrid.row < bottomVisibleRow {
            loseGame(reason: "FOLLOWER LEFT BEHIND")
        }
    }
    // MARK: - 🎓 FTUE Tutorial System
    private enum TutorialArrowDirection {
        case up
        case down
        case sideways
    }
    private func preloadTutorialTextures() {
        guard tutorialTapTextures.isEmpty else { return }
        tutorialTapTextures = (1...3).map { SKTexture(imageNamed: "Tap\($0)") }
        tutorialSlideUpTextures = (1...3).map { SKTexture(imageNamed: "SlideUp\($0)") }
        tutorialSlideDownTextures = (1...3).map { SKTexture(imageNamed: "SlideDown\($0)") }
        tutorialSlideLeftTextures = (1...3).map { SKTexture(imageNamed: "SlideLeft\($0)") }
        tutorialSlideRightTextures = (1...3).map { SKTexture(imageNamed: "SlideRight\($0)") }
        tutorialHoldTextures = (1...11).compactMap { index in
            let uiTex = SKTexture(imageNamed: "HoldUI\(index)")
            if uiTex.size() == .zero {
                return SKTexture(imageNamed: "Hold\(index)")
            }
            return uiTex
        }
    }
    private func setupTutorial() {
        preloadTutorialTextures()
        isTutorialActive = true
        tutorialStep = .moveUp
        tutorialMarkedSet.removeAll()
        tutorialMovedLeft = false
        tutorialMovedRight = false
        applyTutorialTrapLayout()
        renderVisibleTiles()
        setupTutorialNodes()
        updateTutorialOverlay()
    }
    private func applyTutorialTrapLayout() {
        // Reserve rows 0...13: ensure safe path initially
        for r in 0...13 {
            tilesByRow[r] = (0..<columnCount).map { col in
                Tile(row: r, column: col, hasTrap: false)
            }
            for c in 0..<columnCount {
                let pos = GridPosition(row: r, column: c)
                collectibleTiles.remove(pos)
                collectedTiles.remove(pos)
            }
        }
        // Fixed trap layout matching tutorial diagrams:
        // Row 5: col 2 (first trap, follower dodge tutorial)
        // Row 9: cols 0, 4 (flanking traps)
        // Row 10: cols 1, 2, 3 (upper wall of traps, defuse tutorial)
        let tutorialTraps: [(row: Int, col: Int)] = [
            (5, 2),
            (9, 0), (9, 4),
            (10, 1), (10, 2), (10, 3)
        ]
        for trap in tutorialTraps {
            tilesByRow[trap.row] = tilesByRow[trap.row]?.map { tile in
                if tile.column == trap.col {
                    let position = GridPosition(row: trap.row, column: trap.col)
                    if trapTypesByPosition[position] == nil {
                        trapTypesByPosition[position] = Bool.random() ? .spike : .fire
                    }
                    return Tile(row: trap.row, column: trap.col, hasTrap: true)
                }
                return tile
            }
        }
    }
    private func setupTutorialNodes() {
        if tutorialArrowNode.parent == nil {
            tutorialArrowNode.zPosition = 15
            playerNode.addChild(tutorialArrowNode)
        }
        if tutorialTileHighlightNode.parent == nil {
            tutorialTileHighlightNode.zPosition = 5
            worldNode.addChild(tutorialTileHighlightNode)
        }
        if tutorialInstructionBg.parent == nil {
            tutorialInstructionBg.zPosition = 35
            addChild(tutorialInstructionBg)
        }
        if tutorialInstructionLabel.parent == nil {
            tutorialInstructionLabel.zPosition = 36
            addChild(tutorialInstructionLabel)
        }
        tutorialInstructionBg.isHidden = true
        tutorialInstructionLabel.isHidden = true
    }
    
    private func updateTutorialOverlay() {
        guard isTutorialActive else {
            tutorialArrowNode.removeAllChildren()
            tutorialTileHighlightNode.removeAllChildren()
            stopTrapDetectorBlinking()
            if !isFollowerTutorialActive && !isDefuseTutorialActive {
                hideTutorialBanner()
            }
            return
        }
        tutorialArrowNode.removeAllChildren()
        tutorialTileHighlightNode.removeAllChildren()
        switch tutorialStep {
        case .moveUp:
            stopTrapDetectorBlinking()
            setTutorialBanner("SWIPE UP TO MOVE")
            showTutorialDirectionalArrow(direction: .up)
        case .nearbyTrap:
            setTutorialBanner("IT SEEMS LIKE THERES 1 TRAP NEARBY, TAP TO CONTINUE")
            startTrapDetectorBlinking()
        case .markTiles:
            stopTrapDetectorBlinking()
            let remaining = 3 - tutorialMarkedSet.count
            setTutorialBanner("TAP SURROUNDING FLOORS TO MARK [\(remaining) LEFT]")
            showTutorialMarkHighlights()
        case .moveDown:
            stopTrapDetectorBlinking()
            setTutorialBanner("SWIPE DOWN TO RETREAT")
            showTutorialDirectionalArrow(direction: .down)
        case .moveSideways:
            stopTrapDetectorBlinking()
            setTutorialBanner("SWIPE LEFT OR RIGHT TO EVADE")
            showTutorialDirectionalArrow(direction: .sideways)
        case .done:
            stopTrapDetectorBlinking()
            setTutorialBanner("NOW CONTINUE GOING UP!", isSuccess: true)
        }
    }

    // MARK: - Trap Detector Blinking Animation
    private func setTrapDetectorNumberAttributed(color: SKColor, strokeColor: SKColor = .black) {
        let nearbyTrapCount = [
            (playerGrid.row + 1, playerGrid.column),
            (playerGrid.row - 1, playerGrid.column),
            (playerGrid.row, playerGrid.column - 1),
            (playerGrid.row, playerGrid.column + 1)
        ].filter { row, column in
            hasActiveTrap(at: GridPosition(row: row, column: column))
        }.count
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .strokeColor: strokeColor,
            .strokeWidth: -5.0
        ]
        #if canImport(UIKit)
        attributes[.font] = UIFont(
            name: trapNumberLabel.fontName ?? "AvenirNext-Bold",
            size: trapNumberLabel.fontSize
        ) ?? UIFont.boldSystemFont(ofSize: trapNumberLabel.fontSize)
        #endif
        trapNumberLabel.attributedText = NSAttributedString(
            string: "\(nearbyTrapCount)",
            attributes: attributes
        )
        trapNumberLabel.fontColor = color
    }

    private func startTrapDetectorBlinking() {
        trapNumberLabel.removeAction(forKey: "trapDetectorBlinking")
        trapNumberLabel.removeAllChildren()
        trapNumberLabel.alpha = 1.0
        trapNumberLabel.setScale(1.0)

        // Slower, smooth pulse animation on the number
        let scaleUp = SKAction.scale(to: 1.35, duration: 0.45)
        scaleUp.timingMode = .easeInEaseOut
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.45)
        scaleDown.timingMode = .easeInEaseOut

        let detectorColor = SKColor(red: 163 / 255, green: 148 / 255, blue: 73 / 255, alpha: 1.0)
        let flashBright = SKAction.run { [weak self] in
            self?.setTrapDetectorNumberAttributed(
                color: detectorColor,
                strokeColor: SKColor(red: 1.0, green: 0.95, blue: 0.1, alpha: 1.0)
            )
        }
        let flashNormal = SKAction.run { [weak self] in
            self?.setTrapDetectorNumberAttributed(
                color: detectorColor,
                strokeColor: .black
            )
        }

        let cycle = SKAction.sequence([
            flashBright,
            scaleUp,
            SKAction.wait(forDuration: 0.08),
            flashNormal,
            scaleDown,
            SKAction.wait(forDuration: 0.15)
        ])

        trapNumberLabel.run(SKAction.repeatForever(cycle), withKey: "trapDetectorBlinking")
    }

    private func stopTrapDetectorBlinking() {
        trapNumberLabel.removeAction(forKey: "trapDetectorBlinking")
        trapNumberLabel.removeAllChildren()
        trapNumberLabel.alpha = 1.0
        trapNumberLabel.setScale(1.0)
        updatePlayerTrapNumber()
    }
    private func showTutorialDirectionalArrow(direction: TutorialArrowDirection) {
        tutorialArrowNode.removeAllChildren()
        preloadTutorialTextures()
        let spriteSize = CGSize(
            width: tileSize.width * tutorialSlideSpriteScale,
            height: tileSize.height * tutorialSlideSpriteScale
        )
        switch direction {
        case .up:
            let sprite = SKSpriteNode(texture: tutorialSlideUpTextures.first, size: spriteSize)
            sprite.position = tutorialSlideUpOffset
            sprite.zPosition = 1
            if !tutorialSlideUpTextures.isEmpty {
                sprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialSlideUpTextures, timePerFrame: tutorialSlideAnimTimePerFrame)))
            }
            tutorialArrowNode.addChild(sprite)
        case .down:
            let sprite = SKSpriteNode(texture: tutorialSlideDownTextures.first, size: spriteSize)
            sprite.position = tutorialSlideDownOffset
            sprite.zPosition = 1
            if !tutorialSlideDownTextures.isEmpty {
                sprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialSlideDownTextures, timePerFrame: tutorialSlideAnimTimePerFrame)))
            }
            tutorialArrowNode.addChild(sprite)
        case .sideways:
            if !tutorialMovedLeft {
                let leftSprite = SKSpriteNode(texture: tutorialSlideLeftTextures.first, size: spriteSize)
                leftSprite.position = tutorialSlideLeftOffset
                leftSprite.zPosition = 1
                if !tutorialSlideLeftTextures.isEmpty {
                    leftSprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialSlideLeftTextures, timePerFrame: tutorialSlideAnimTimePerFrame)))
                }
                tutorialArrowNode.addChild(leftSprite)
            }
            if !tutorialMovedRight {
                let rightSprite = SKSpriteNode(texture: tutorialSlideRightTextures.first, size: spriteSize)
                rightSprite.position = tutorialSlideRightOffset
                rightSprite.zPosition = 1
                if !tutorialSlideRightTextures.isEmpty {
                    rightSprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialSlideRightTextures, timePerFrame: tutorialSlideAnimTimePerFrame)))
                }
                tutorialArrowNode.addChild(rightSprite)
            }
        }
    }
    private func showTutorialMarkHighlights() {
        tutorialTileHighlightNode.removeAllChildren()
        preloadTutorialTextures()
        let tapSize = CGSize(
            width: tileSize.width * tutorialTapSpriteScale,
            height: tileSize.height * tutorialTapSpriteScale
        )
        for targetPos in tutorialMarkTargets {
            guard !tutorialMarkedSet.contains(targetPos) else { continue }
            let pos = pointFor(row: targetPos.row, column: targetPos.column)
            let container = SKNode()
            container.position = pos
            // Animated Tap Sprite (Tap1...Tap3)
            let tapSprite = SKSpriteNode(texture: tutorialTapTextures.first, size: tapSize)
            tapSprite.position = tutorialTapSpriteOffset
            tapSprite.zPosition = 2
            if !tutorialTapTextures.isEmpty {
                tapSprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialTapTextures, timePerFrame: tutorialTapAnimTimePerFrame)))
            }
            container.addChild(tapSprite)
            tutorialTileHighlightNode.addChild(container)
        }
    }
    private func advanceTutorialStep() {
        switch tutorialStep {
        case .moveUp:
            tutorialStep = .nearbyTrap
            updateTutorialOverlay()
        case .nearbyTrap:
            tutorialStep = .markTiles
            tutorialMarkedSet.removeAll()
            updateTutorialOverlay()
        case .markTiles:
            // ENABLE XMARK CYCLING HERE IMMEDIATELY AFTER MARKING TUTORIAL
            canSwapMarks = true
            tutorialStep = .moveDown
            updateTutorialOverlay()
        case .moveDown:
            tutorialStep = .moveSideways
            tutorialMovedLeft = false
            tutorialMovedRight = false
            updateTutorialOverlay()
        case .moveSideways:
            completeTutorial()
        case .done:
            break
        }
    }
    private func completeTutorial() {
        tutorialStep = .done
        canSwapMarks = true // Ensure mark swapping remains unlocked
        updateTutorialOverlay()
        let wait = SKAction.wait(forDuration: 1.5)
        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            self.isTutorialActive = false
            self.hideTutorialOverlay()
        }
        run(SKAction.sequence([wait, finish]))
    }
    private func hideTutorialOverlay() {
        tutorialArrowNode.removeAllChildren()
        tutorialTileHighlightNode.removeAllChildren()
        stopTrapDetectorBlinking()
        if !isFollowerTutorialActive && !isDefuseTutorialActive {
            hideTutorialBanner()
        }
    }
    private func updateSpecialTutorialHighlights() {
        if isFollowerTutorialActive {
            followerTutorialHighlightNode.removeAllChildren()
            let trapPos = GridPosition(row: 5, column: 2)
            let trapPoint = pointFor(row: trapPos.row, column: trapPos.column)
            let tapSize = CGSize(
                width: tileSize.width * tutorialTapSpriteScale,
                height: tileSize.height * tutorialTapSpriteScale
            )
            let tapSprite = SKSpriteNode(texture: tutorialTapTextures.first, size: tapSize)
            tapSprite.position = CGPoint(x: trapPoint.x + tutorialTapSpriteOffset.x, y: trapPoint.y + tutorialTapSpriteOffset.y)
            tapSprite.zPosition = 2
            if !tutorialTapTextures.isEmpty {
                tapSprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialTapTextures, timePerFrame: tutorialTapAnimTimePerFrame)))
            }
            followerTutorialHighlightNode.addChild(tapSprite)
            setTutorialBanner("TAP THE MARKED TILE TO SWAP THE MARK SO THE FOLLOWER DODGES!")
        }

        if isDefuseTutorialActive, let target = defuseTutorialTargetTile {
            defuseTutorialHighlightNode.removeAllChildren()
            let tilePoint = pointFor(row: target.row, column: target.column)
            let holdSize = CGSize(
                width: tileSize.width * tutorialHoldSpriteScale,
                height: tileSize.height * tutorialHoldSpriteScale
            )
            let holdSprite = SKSpriteNode(texture: tutorialHoldTextures.first, size: holdSize)
            holdSprite.position = CGPoint(x: tilePoint.x + tutorialHoldSpriteOffset.x, y: tilePoint.y + tutorialHoldSpriteOffset.y)
            holdSprite.zPosition = 2
            if !tutorialHoldTextures.isEmpty {
                holdSprite.run(SKAction.repeatForever(SKAction.animate(with: tutorialHoldTextures, timePerFrame: tutorialHoldAnimTimePerFrame)))
            }
            defuseTutorialHighlightNode.addChild(holdSprite)
            setTutorialBanner("HOLD TO DISARM THE TRAP!")
        }
    }

    private func triggerFollowerTrapTutorial() {
        guard !hasCompletedFollowerTrapTutorial, !isFollowerTutorialActive else { return }
        isFollowerTutorialActive = true
        canSwapMarks = true
        preloadTutorialTextures()
        if followerTutorialHighlightNode.parent == nil {
            followerTutorialHighlightNode.zPosition = 10
            worldNode.addChild(followerTutorialHighlightNode)
        }
        updateSpecialTutorialHighlights()
        setTutorialBanner("TAP THE MARKED TILE TO SWAP THE MARK SO THE FOLLOWER DODGES!")
    }
    private func completeFollowerTrapTutorial() {
        hasCompletedFollowerTrapTutorial = true
        isFollowerTutorialActive = false
        canSwapMarks = true
        followerTutorialHighlightNode.removeAllChildren()
        // Banner confirmation: instruct player to move forward
        setTutorialBanner("NOW MOVE FORWARD TO LEAD THE FOLLOWER!", isSuccess: true)
        let wait = SKAction.wait(forDuration: 2.0)
        let fade = SKAction.run { [weak self] in
            self?.hideTutorialBanner()
        }
        run(SKAction.sequence([wait, fade]))
    }
    // MARK: - Defuse Tutorial (Row 9)
    private func triggerDefuseTutorial() {
        guard !hasCompletedDefuseTutorial, !isDefuseTutorialActive else { return }
        isDefuseTutorialActive = true
        preloadTutorialTextures()
        let target = GridPosition(row: playerGrid.row + 1, column: playerGrid.column)
        defuseTutorialTargetTile = target
        if defuseTutorialHighlightNode.parent == nil {
            defuseTutorialHighlightNode.zPosition = 10
            worldNode.addChild(defuseTutorialHighlightNode)
        }
        updateSpecialTutorialHighlights()
        setTutorialBanner("HOLD DISARM THE TRAP!")
    }
    private func completeDefuseTutorial() {
        hasCompletedDefuseTutorial = true
        isDefuseTutorialActive = false
        defuseTutorialTargetTile = nil
        defuseTutorialHighlightNode.removeAllChildren()
        // Banner confirmation
        setTutorialBanner("TRAP DISARMED! PATH IS CLEAR!", isSuccess: true)
        let wait = SKAction.wait(forDuration: 2.0)
        let fade = SKAction.run { [weak self] in
            self?.hideTutorialBanner()
        }
        run(SKAction.sequence([wait, fade]))
    }
    // MARK: - HUD & Gradient
    private func setupStatusLabels() {
        layoutHUD()
        
        topGradientNode.isHidden = true
        if topGradientNode.parent == nil { addChild(topGradientNode) }
        scoreLabel.isHidden = true
        coinIconNode.isHidden = true
        heightLabel.isHidden = true
        // Disarm trap icon nodes (hidden in SK, rendered in SwiftUI)
        disarmIconNodes.forEach { $0.removeFromParent() }
        disarmIconNodes = (0..<Int(maxDefusePower)).map { _ in
            let node = SKSpriteNode(imageNamed: "DisarmTrapEnable")
            node.zPosition = 20
            node.isHidden = true
            addChild(node)
            return node
        }
        feedbackLabel.fontSize = 24
        feedbackLabel.fontColor = .white
        feedbackLabel.horizontalAlignmentMode = .center
        feedbackLabel.verticalAlignmentMode = .top
        feedbackLabel.zPosition = 20
        addChild(feedbackLabel)
        loseLabel.fontSize = 26
        loseLabel.fontColor = .white
        loseLabel.horizontalAlignmentMode = .center
        loseLabel.verticalAlignmentMode = .center
        loseLabel.zPosition = 30
        loseLabel.isHidden = true
        addChild(loseLabel)
        loseSubtitleLabel.fontSize = 18
        loseSubtitleLabel.fontColor = .white
        loseSubtitleLabel.horizontalAlignmentMode = .center
        loseSubtitleLabel.verticalAlignmentMode = .center
        loseSubtitleLabel.zPosition = 30
        loseSubtitleLabel.isHidden = true
        addChild(loseSubtitleLabel)
        endScoreLabel.fontSize = 18
        endScoreLabel.fontColor = .white
        endScoreLabel.horizontalAlignmentMode = .center
        endScoreLabel.verticalAlignmentMode = .center
        endScoreLabel.zPosition = 30
        endScoreLabel.isHidden = true
        addChild(endScoreLabel)
        endHeightLabel.fontSize = 18
        endHeightLabel.fontColor = SKColor.white.withAlphaComponent(0.9)
        endHeightLabel.horizontalAlignmentMode = .center
        endHeightLabel.verticalAlignmentMode = .center
        endHeightLabel.zPosition = 30
        endHeightLabel.isHidden = true
        addChild(endHeightLabel)
        gameOverCoinIconNode.size = CGSize(width: 26, height: 26)
        gameOverCoinIconNode.zPosition = 30
        gameOverCoinIconNode.isHidden = true
        addChild(gameOverCoinIconNode)
        gameOverOverlayNode.zPosition = 25
        gameOverOverlayNode.isHidden = true
        addChild(gameOverOverlayNode)
        retryLabel.text = "Tap to Retry"
        retryLabel.fontSize = 20
        retryLabel.fontColor = .white
        retryLabel.horizontalAlignmentMode = .center
        retryLabel.verticalAlignmentMode = .center
        retryLabel.zPosition = 100
        redOverlayNode.color = .red
        redOverlayNode.size = size
        redOverlayNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        redOverlayNode.zPosition = 22 // Below HUD text/overlays, above map/player
        redOverlayNode.alpha = 0
        redOverlayNode.isHidden = true
        if redOverlayNode.parent == nil { addChild(redOverlayNode) }
        retryLabel.isHidden = true
        addChild(retryLabel)
        layoutHUD()
    }
    private func layoutHUD() {
        // Gradient — anchored to top, shifted down by hudYOffset
        topGradientNode.texture = createTopGradientTexture(width: max(1, size.width), height: hudGradientHeight)
        topGradientNode.size = CGSize(width: size.width, height: hudGradientHeight)
        topGradientNode.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        topGradientNode.position = CGPoint(x: size.width * 0.5, y: size.height - hudYOffset)
        topGradientNode.zPosition = 15
        // All HUD elements: Y = size.height - hudYOffset - fromTop
        let topY = size.height - hudYOffset
        // Coin + score (left side)
        let coinCenterY = topY - hudCoinFromTop
        coinIconNode.size = CGSize(width: hudCoinSize, height: hudCoinSize)
        coinIconNode.anchorPoint = CGPoint(x: 0, y: 0.5)
        coinIconNode.position = CGPoint(x: hudCoinX, y: coinCenterY)
        scoreLabel.fontSize = hudScoreFontSize
        scoreLabel.position = CGPoint(x: hudCoinX + hudCoinSize + hudScoreOffsetX, y: coinCenterY)
        // Depth label (left side, below coin row)
        heightLabel.fontSize = hudDepthFontSize
        heightLabel.position = CGPoint(x: hudDepthX, y: topY - hudDepthFromTop)
        // Disarm icons (right side, placed right-to-left)
        let iconCenterY = topY - hudDisarmIconFromTop
        let iconStep = hudDisarmIconSize + hudDisarmIconSpacing
        for (i, node) in disarmIconNodes.enumerated() {
            node.size = CGSize(width: hudDisarmIconSize, height: hudDisarmIconSize)
            let rightEdge = hudDisarmIconRightEdge - CGFloat(i) * iconStep
            node.position = CGPoint(x: rightEdge - hudDisarmIconSize * 0.5, y: iconCenterY)
        }
        feedbackLabel.position = CGPoint(x: size.width * 0.5, y: size.height - 270)
        layoutGameOverResults()
    }
    private func layoutGameOverResults() {
        let centerX = size.width * 0.5
        loseLabel.horizontalAlignmentMode = .center
        loseLabel.verticalAlignmentMode = .center
        loseSubtitleLabel.horizontalAlignmentMode = .center
        loseSubtitleLabel.verticalAlignmentMode = .center
        endScoreLabel.horizontalAlignmentMode = .center
        endScoreLabel.verticalAlignmentMode = .center
        endHeightLabel.horizontalAlignmentMode = .center
        endHeightLabel.verticalAlignmentMode = .center
        let scoreY = size.height * 0.55
        loseLabel.position = CGPoint(
            x: centerX + 18,
            y: scoreY
    )
        gameOverCoinIconNode.position = CGPoint(
            x: centerX - 38,
            y: scoreY
        )
        loseSubtitleLabel.position = CGPoint(
            x: centerX,
            y: size.height * 0.5
        )
        endScoreLabel.position = CGPoint(
            x: centerX,
            y: size.height * 0.45
        )
        endHeightLabel.position = CGPoint(
            x: centerX,
            y: size.height * 0.4
        )
        gameOverCoinIconNode.size = CGSize(
            width: 40,
            height: 40
        )
        retryLabel.position = CGPoint(
            x: size.width * 0.5,
            y: size.height * 0.10
        )
        loseLabel.zPosition = 100
        loseSubtitleLabel.zPosition = 100
        endScoreLabel.zPosition = 100
        endHeightLabel.zPosition = 100
        gameOverCoinIconNode.zPosition = 100
    }
    private func createTopGradientTexture(width: CGFloat, height: CGFloat) -> SKTexture {
        let w = Int(max(1, width))
        let h = Int(max(1, height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let colors = [
            SKColor.black.withAlphaComponent(0.92).cgColor,
            SKColor.black.withAlphaComponent(0.60).cgColor,
            SKColor.black.withAlphaComponent(0.0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.60, 1.0]
        if let ctx = context, let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])
            if let cgImage = ctx.makeImage() { return SKTexture(cgImage: cgImage) }
        }
        return SKTexture()
    }
    // MARK: - Scoring
    private func updateScore() {
        // Push to SwiftUI HUD
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.gameHUD?.score = self.totalScore()
            self.gameHUD?.depth = self.highestTileReached
        }
    }
    // MARK: - Tutorial Banner helpers
    /// Show the tutorial instruction banner in the SwiftUI HUD.
    private func setTutorialBanner(_ text: String, isSuccess: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.gameHUD?.tutorialText = text
            self?.gameHUD?.tutorialIsSuccess = isSuccess
        }
    }
    /// Hide the tutorial instruction banner.
    private func hideTutorialBanner() {
        DispatchQueue.main.async { [weak self] in
            self?.gameHUD?.tutorialText = nil
            self?.gameHUD?.tutorialIsSuccess = false
        }
    }
    private func currentScoreMultiplier() -> Int {

        // If follower has ever been hit, multiplier is permanently disabled
        // for the current run.
        guard !followerHasBeenHit else {
            return 1
        }

        let completedIntervals = highestTileReached / scoreMultiplierStepInterval

        return startingScoreMultiplier + completedIntervals
    }

    private func totalScore() -> Int {

        let followerPenalty = isFollowerEnabled ? followerPenaltyScore : 0

        let baseScore = movementScore + collectibleScore

        let multiplier = currentScoreMultiplier()

        return (baseScore * multiplier) - followerPenalty
    }
    private func saveHighestResultsIfNeeded() {
        highestScore = max(highestScore, totalScore())
        highestTileReachedBest = max(highestTileReachedBest, highestTileReached)
    }
    private func updateHighestTileReached(_ row: Int) {

        let previousHighestTile = highestTileReached

        highestTileReached = max(highestTileReached, row)

        guard highestTileReached > previousHighestTile else {
            return
        }

        movementScore +=
            (highestTileReached - previousHighestTile)
            * pointsPerNewHighestTile

        // Check for a new score multiplier.
        if !followerHasBeenHit {

            let oldMultiplier =
                startingScoreMultiplier
                + (previousHighestTile / scoreMultiplierStepInterval)

            let newMultiplier =
                currentScoreMultiplier()

            if newMultiplier > oldMultiplier {
                showFeedback("\(newMultiplier)x SCORE!")

                updateScore()
            }
        }

        rechargeDefusePowerFromProgress()
    }
    // MARK: - Defusing
    private func rechargeDefusePowerFromProgress() {
        let gainedRechargeCount = (highestTileReached - lastRechargeTileReached) / rowsPerDefuseRecharge
        guard gainedRechargeCount > 0 else { return }
        lastRechargeTileReached += gainedRechargeCount * rowsPerDefuseRecharge
        let oldDefusePower = defusePower
        defusePower = min(maxDefusePower, defusePower + Double(gainedRechargeCount))
        if defusePower > oldDefusePower {
            showFeedback("Disarm Tools +\(Int(defusePower - oldDefusePower))")
            updatePower()
        }
    }
    private func updatePower() {
        let charges = Int(defusePower.rounded(.down))
        // Update SK icon nodes (still used during tutorial if needed)
        for (i, node) in disarmIconNodes.enumerated() {
            let enabled = i < charges
            node.texture = SKTexture(imageNamed: enabled ? "DisarmTrapEnable" : "DisarmTrapDisable")
            node.alpha = enabled ? 1.0 : 0.5
        }
        // Push to SwiftUI HUD
        DispatchQueue.main.async { [weak self] in
            self?.gameHUD?.defuseCharges = charges
        }
    }
    private func scheduleHoldFeedback(atScenePoint scenePoint: CGPoint) {
        // Defuse is introduced by its tutorial; do not suggest it before then.
        guard isDefuseTutorialActive || hasCompletedDefuseTutorial else { return }
        guard !isPlayerMoving, !isGameLost else { return }
        guard let gridPosition = gridPosition(atScenePoint: scenePoint) else { return }
        removeAction(forKey: holdFeedbackActionKey)
        let wait = SKAction.wait(forDuration: longPressDuration)
        let showHold = SKAction.run { [weak self] in self?.showActiveHoldFeedback(at: gridPosition) }
        run(SKAction.sequence([wait, showHold]), withKey: holdFeedbackActionKey)
    }
    private func cancelHoldFeedback() {
        removeAction(forKey: holdFeedbackActionKey)
        activeHoldFeedbackNode?.removeFromParent()
        activeHoldFeedbackNode = nil
        stopDisarmingSFX()
    }
    
    private func attemptDefuse(atScenePoint scenePoint: CGPoint) {
        // Stop the disarming loop immediately upon touch release
        stopDisarmingSFX()

        guard isDefuseTutorialActive || hasCompletedDefuseTutorial else { return }
        guard !isPlayerMoving, !isGameLost else { return }
        guard let gridPosition = gridPosition(atScenePoint: scenePoint) else { return }
        
        guard defusePower > 0 else {
            AudioManager.shared.playSFX("DisarmFail.mp3", on: self)
            showFeedback("No defuse power")
            showTileHoldFeedback(at: gridPosition, color: .gray, isSuccess: false)
            return
        }
        
        defusePower = max(0, defusePower - 1)
        if hasActiveTrap(at: gridPosition) {
            defusedTiles.insert(gridPosition)
            markedTiles.removeValue(forKey: gridPosition)
            AudioManager.shared.playSFX("DisarmSuccess.mp3", on: self)
            showFeedback("Disarm Success -1")
            showTileHoldFeedback(at: gridPosition, color: .systemGreen, isSuccess: true)
            renderVisibleTiles()
            updatePlayerTrapNumber()
            if isDefuseTutorialActive && gridPosition == defuseTutorialTargetTile {
                completeDefuseTutorial()
            }
        } else {
            AudioManager.shared.playSFX("DisarmFail.mp3", on: self)
            showFeedback("Disarm Fail theres no trap here-1")
            showTileHoldFeedback(at: gridPosition, color: .systemRed, isSuccess: false)
        }
        updatePower()
        }
    
    private func showFeedback(_ message: String) {
        let maxLabelWidth = size.width * 0.85 // Constrain width so text stays within screen boundaries

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 4.0

        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: SKColor.white,
            .strokeColor: SKColor.black,
            .strokeWidth: -3.0,
            .paragraphStyle: paragraphStyle
        ]
        #if canImport(UIKit)
        attributes[.font] = UIFont(
            name: feedbackLabel.fontName ?? "AvenirNext-Bold",
            size: feedbackLabel.fontSize
        ) ?? UIFont.boldSystemFont(ofSize: feedbackLabel.fontSize)
        #endif

        feedbackLabel.numberOfLines = 0 // Enable multi-line rendering
        feedbackLabel.preferredMaxLayoutWidth = maxLabelWidth
        feedbackLabel.horizontalAlignmentMode = .center
        feedbackLabel.verticalAlignmentMode = .top
        feedbackLabel.attributedText = NSAttributedString(
            string: message,
            attributes: attributes
        )

        feedbackLabel.removeAllActions()
        feedbackLabel.alpha = 0
        feedbackLabel.setScale(0.65)

        let appear = SKAction.group([
            SKAction.fadeIn(withDuration: 0.14),
            SKAction.scale(to: 1.15, duration: 0.14)
        ])
        let settle = SKAction.scale(to: 1.0, duration: 0.12)
        let wait = SKAction.wait(forDuration: 0.8)
        let disappear = SKAction.group([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.scale(to: 0.85, duration: 0.2)
        ])
        let clear = SKAction.run { [weak feedbackLabel] in
            feedbackLabel?.attributedText = nil
            feedbackLabel?.setScale(1.0)
        }

        feedbackLabel.run(SKAction.sequence([appear, settle, wait, disappear, clear]))
    }
    
    private func stopDisarmingSFX() {
        disarmingAudioNode?.run(SKAction.stop())
        disarmingAudioNode?.removeFromParent()
        disarmingAudioNode = nil
    }
    
    private func showActiveHoldFeedback(at gridPosition: GridPosition) {
        activeHoldFeedbackNode?.removeFromParent()
        stopDisarmingSFX()

        // 1. Play looping disarming SFX and store reference
        let audioNode = SKAudioNode(fileNamed: "Disarming.mp3")
        audioNode.autoplayLooped = true
        addChild(audioNode)
        disarmingAudioNode = audioNode

        let holdNode = SKNode()
        holdNode.position = pointFor(row: gridPosition.row, column: gridPosition.column)
        holdNode.zPosition = 4
        
        let baseRadius = min(tileSize.width, tileSize.height) * 0.45
        let holdColor = SKColor.systemYellow

        // --------------------------------------------------
        // 1. INNER CIRCLE (Yellow Center Core)
        // --------------------------------------------------
        let innerCircle = SKShapeNode(circleOfRadius: baseRadius)
        innerCircle.position = .zero
        innerCircle.strokeColor = holdColor
        innerCircle.lineWidth = 4.5
        innerCircle.fillColor = holdColor.withAlphaComponent(0.18)

        let innerPulse = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.group([
                    SKAction.fadeAlpha(to: 0.40, duration: 0.28),
                    SKAction.scale(to: 1.10, duration: 0.28)
                ]),
                SKAction.group([
                    SKAction.fadeAlpha(to: 1.0, duration: 0.28),
                    SKAction.scale(to: 1.0, duration: 0.28)
                ])
            ])
        )
        innerCircle.run(innerPulse)
        holdNode.addChild(innerCircle)

        // --------------------------------------------------
        // 2. MIDDLE CIRCLE (Yellow Mid Ring)
        // --------------------------------------------------
        let middleCircle = SKShapeNode(circleOfRadius: baseRadius * 1.45)
        middleCircle.position = .zero
        middleCircle.strokeColor = holdColor.withAlphaComponent(0.75)
        middleCircle.lineWidth = 3.0
        middleCircle.fillColor = .clear

        let middlePulse = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.group([
                    SKAction.fadeAlpha(to: 0.20, duration: 0.32),
                    SKAction.scale(to: 1.14, duration: 0.32)
                ]),
                SKAction.group([
                    SKAction.fadeAlpha(to: 0.75, duration: 0.32),
                    SKAction.scale(to: 1.0, duration: 0.32)
                ])
            ])
        )
        middleCircle.run(middlePulse)
        holdNode.addChild(middleCircle)

        // --------------------------------------------------
        // 3. OUTER CIRCLE (Yellow Outer Ring)
        // --------------------------------------------------
        let outerCircle = SKShapeNode(circleOfRadius: baseRadius * 1.95)
        outerCircle.position = .zero
        outerCircle.strokeColor = holdColor.withAlphaComponent(0.50)
        outerCircle.lineWidth = 2.0
        outerCircle.fillColor = .clear

        let outerPulse = SKAction.repeatForever(
            SKAction.sequence([
                SKAction.group([
                    SKAction.fadeAlpha(to: 0.08, duration: 0.36),
                    SKAction.scale(to: 1.18, duration: 0.36)
                ]),
                SKAction.group([
                    SKAction.fadeAlpha(to: 0.50, duration: 0.36),
                    SKAction.scale(to: 1.0, duration: 0.36)
                ])
            ])
        )
        outerCircle.run(outerPulse)
        holdNode.addChild(outerCircle)

        activeHoldFeedbackNode = holdNode
        feedbackLayerNode.addChild(holdNode)
    }
    
    private func showTileHoldFeedback(at gridPosition: GridPosition, color: SKColor, isSuccess: Bool) {
        let feedbackNode = SKNode()
        feedbackNode.position = pointFor(row: gridPosition.row, column: gridPosition.column)
        feedbackNode.zPosition = 4

        let baseRadius = min(tileSize.width, tileSize.height) * 0.45

        // --------------------------------------------------
        // 1. INNER CIRCLE (Colored Core)
        // --------------------------------------------------
        let innerCircle = SKShapeNode(circleOfRadius: baseRadius)
        innerCircle.position = .zero
        innerCircle.strokeColor = color
        innerCircle.lineWidth = 4.5
        innerCircle.fillColor = color.withAlphaComponent(0.20)
        feedbackNode.addChild(innerCircle)

        // --------------------------------------------------
        // 2. MIDDLE CIRCLE (Colored Mid Ring)
        // --------------------------------------------------
        let middleCircle = SKShapeNode(circleOfRadius: baseRadius * 1.45)
        middleCircle.position = .zero
        middleCircle.strokeColor = color.withAlphaComponent(0.80)
        middleCircle.lineWidth = 3.0
        middleCircle.fillColor = .clear
        feedbackNode.addChild(middleCircle)

        // --------------------------------------------------
        // 3. OUTER CIRCLE (Colored Outer Ring)
        // --------------------------------------------------
        let outerCircle = SKShapeNode(circleOfRadius: baseRadius * 1.95)
        outerCircle.position = .zero
        outerCircle.strokeColor = color.withAlphaComponent(0.50)
        outerCircle.lineWidth = 2.0
        outerCircle.fillColor = .clear
        feedbackNode.addChild(outerCircle)

        feedbackLayerNode.addChild(feedbackNode)

        // --------------------------------------------------
        // EXPANSION & FADE OUT ANIMATION
        // --------------------------------------------------
        let expand = SKAction.scale(to: 1.15, duration: 0.10)
        expand.timingMode = .easeOut
        
        let fadeOut = SKAction.fadeOut(withDuration: 0.45)
        fadeOut.timingMode = .easeIn

        feedbackNode.run(SKAction.sequence([
            expand,
            fadeOut,
            SKAction.removeFromParent()
        ]))
    }
    // MARK: - Physics & Contact
    private func configureTrapPhysics(for trapNode: SKSpriteNode, at gridPosition: GridPosition) {
        trapNode.userData = ["row": gridPosition.row, "column": gridPosition.column]
        trapNode.physicsBody = SKPhysicsBody(rectangleOf: trapNode.size)
        trapNode.physicsBody?.affectedByGravity = false
        trapNode.physicsBody?.isDynamic = false
        trapNode.physicsBody?.categoryBitMask = PhysicsCategory.trap
        trapNode.physicsBody?.collisionBitMask = PhysicsCategory.none
        trapNode.physicsBody?.contactTestBitMask = isFollowerEnabled
            ? PhysicsCategory.player | PhysicsCategory.follower
            : PhysicsCategory.player
    }
    private func configureFollowerPhysics() {
        guard isFollowerEnabled else { return }
        followerNode.physicsBody = SKPhysicsBody(rectangleOf: followerNode.size)
        followerNode.physicsBody?.affectedByGravity = false
        followerNode.physicsBody?.isDynamic = true
        followerNode.physicsBody?.categoryBitMask = PhysicsCategory.follower
        followerNode.physicsBody?.collisionBitMask = PhysicsCategory.none
        followerNode.physicsBody?.contactTestBitMask = PhysicsCategory.trap
    }
    private func applyFollowerTrapPenalty(from trapNode: SKNode?) {

        guard isFollowerEnabled, let trapNode else {
            return
        }

        guard let gridPosition = gridPosition(from: trapNode) else {
            return
        }

        guard gridPosition == GridPosition(
            row: followerGrid.row,
            column: followerGrid.column
        ) else {
            return
        }

        guard !followerTriggeredTraps.contains(gridPosition) else {
            return
        }

        followerTriggeredTraps.insert(gridPosition)

        // The follower has now been hit.
        followerHasBeenHit = true

        followerPenaltyScore += followerTrapPenalty

        showFeedback(
            "Follower hit trap -\(followerTrapPenalty)"
        )

        activateTrapAnimation(at: gridPosition)

        showTileHoldFeedback(
            at: gridPosition,
            color: .systemPurple,
            isSuccess: false
        )

        // Immediately show ONE special reaction.
        showFollowerBubble(
            from: followerHitDialogue
        )

        // The hit reaction has been handled.
        // Future scheduled bubbles return to normal dialogue.
        followerHasBeenHit = false

        updateScore()
    }
    private func configureCollectiblePhysics(for collectibleNode: SKSpriteNode, at gridPosition: GridPosition) {
        collectibleNode.userData = ["row": gridPosition.row, "column": gridPosition.column]
        let collectionRadius = min(tileSize.width, tileSize.height) * 0.18
        collectibleNode.physicsBody = SKPhysicsBody(
            circleOfRadius: collectionRadius
        )
        collectibleNode.physicsBody?.affectedByGravity = false
        collectibleNode.physicsBody?.isDynamic = false
        collectibleNode.physicsBody?.categoryBitMask = PhysicsCategory.collectible
        collectibleNode.physicsBody?.collisionBitMask = PhysicsCategory.none
        collectibleNode.physicsBody?.contactTestBitMask = PhysicsCategory.player
    }
    private func collect(_ collectibleNode: SKNode) {
        guard let gridPosition = gridPosition(from: collectibleNode) else { return }
        guard hasActiveCollectible(at: gridPosition) else { return }
        collectedTiles.insert(gridPosition)
        collectibleScore += collectiblePoints
        showFeedback("+\(collectiblePoints)")
        updateScore()
        collectibleNode.removeFromParent()
    }
    // MARK: - Game Lifecycle & Reset
    private func triggerTrapDeathSequence(at position: GridPosition) {
        guard !isGameLost else { return }

        isPlayerMoving = true

        // Stop normal movement / idle animation
        playerNode.removeAction(forKey: "playerAnimation")
        preloadPlayerTextures()

        // Activate trap animation immediately
        activateTrapAnimation(at: position)

        // --------------------------------------------------
        // OJOK DEAD 1 (Initial initial hit reaction / pose)
        // --------------------------------------------------
        let playDead1 = SKAction.run { [weak self] in
            self?.playerNode.texture = self?.ojokDeadTextures[0]
        }

        let dead1Hold = SKAction.wait(forDuration: 0.25)

        // --------------------------------------------------
        // FIRST ZOOM
        // --------------------------------------------------
        let firstZoom = SKAction.run { [weak self] in
            self?.zoomWorldToPlayer(scale: 1.18, duration: 0.35)
        }

        // --------------------------------------------------
        // OJOK DEAD 2 (Sudden Red Flash, Haptic & SFX Trigger Here)
        // --------------------------------------------------
        let playDead2AndFlash = SKAction.run { [weak self] in
            guard let self else { return }

            // Switch texture to Dead2
            self.playerNode.texture = self.ojokDeadTextures[1]

            // Play Death SFX
            AudioManager.shared.playSFX("Dead.mp3", on: self)

            // Trigger heavy haptic feedback
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            #endif

            // Instant red tint on player sprite
            self.playerNode.colorBlendFactor = 1.0
            self.playerNode.color = .red

            // Sudden red overlay flash with reduced opacity (0.12)
            self.redOverlayNode.isHidden = false
            self.redOverlayNode.alpha = 0.12
        }

        // Brief flash hold duration
        let holdRedFlash = SKAction.wait(forDuration: 0.4)

        // Revert character sprite back to its natural texture colors
        let revertPlayerColor = SKAction.run { [weak self] in
            self?.playerNode.colorBlendFactor = 0.0
            self?.playerNode.color = .white
        }

        let dead2Hold = SKAction.wait(forDuration: 0.25)

        // --------------------------------------------------
        // SECOND ZOOM
        // --------------------------------------------------
        let secondZoom = SKAction.run { [weak self] in
            self?.zoomWorldToPlayer(scale: 1.42, duration: 0.4)
        }

        // --------------------------------------------------
        // OJOK DEAD 3
        // --------------------------------------------------
        let playDead3 = SKAction.run { [weak self] in
            guard let self else { return }
            self.playerNode.texture = self.ojokDeadTextures[2]
        }

        let dead3Hold = SKAction.wait(forDuration: 0.7)

        // --------------------------------------------------
        // GAME OVER
        // --------------------------------------------------
        let showGameOver = SKAction.run { [weak self] in
            self?.loseGame(reason: "YOU HIT A TRAP")
        }

        // --------------------------------------------------
        // COMPLETE SEQUENCE
        // --------------------------------------------------
        let deathSequence = SKAction.sequence([
            playDead1,
            dead1Hold,
            firstZoom,
            playDead2AndFlash,  // <--- Sudden flash & haptic at Dead2 frame
            holdRedFlash,
            revertPlayerColor,
            dead2Hold,
            secondZoom,
            playDead3,
            dead3Hold,
            showGameOver
        ])

        run(deathSequence, withKey: "trapDeathSequence")
    }
    
    private func zoomWorldToPlayer(
        scale: CGFloat,
        duration: TimeInterval
    ) {
        let playerPosition = playerNode.position

        // Screen center.
        let screenCenter = CGPoint(
            x: size.width * 0.5,
            y: size.height * 0.5
        )

        // Move the world so the player stays centered while
        // the entire world scales around that point.
        let targetWorldPosition = CGPoint(
            x: screenCenter.x - (playerPosition.x * scale),
            y: screenCenter.y - (playerPosition.y * scale)
        )

        let zoom = SKAction.group([
            SKAction.scale(
                to: scale,
                duration: duration
            ),

            SKAction.move(
                to: targetWorldPosition,
                duration: duration
            )
        ])

        zoom.timingMode = .easeInEaseOut

        worldNode.run(
            zoom,
            withKey: "trapDeathCameraZoom"
        )
    }
    private func loseGame(reason: String = "LOSE") {
        guard !isGameLost else { return }
        isGameLost = true
        isPlayerMoving = false
        removeAction(forKey: "playerIdleTimer")
        hidePlayerIdleOverlay()
        playerNode.removeAllActions()
        setHUDVisible(false)
        saveHighestResultsIfNeeded()
        updateScore()
        let currentScore = totalScore()
        let currentDepth = highestTileReached
        let bestScore = highestScore
        let bestDepth = highestTileReachedBest
        loseLabel.text = "\(currentScore)"
        loseSubtitleLabel.text = "Depth Reached: \(currentDepth)m"
        endScoreLabel.text = "Personal Best: \(bestScore) coins"
        endHeightLabel.text = "Farthest: \(bestDepth)m"
        retryLabel.isHidden = false
        retryLabel.alpha = 0
        loseLabel.isHidden = false
        loseSubtitleLabel.isHidden = false
        endScoreLabel.isHidden = false
        endHeightLabel.isHidden = false
        loseLabel.alpha = 0
        loseSubtitleLabel.alpha = 0
        endScoreLabel.alpha = 0
        endHeightLabel.alpha = 0
        gameOverCoinIconNode.isHidden = false
        gameOverCoinIconNode.alpha = 0
        layoutGameOverResults()
        playerNode.color = .systemRed
        showGameOverSequence()
    }
    private func showGameOverSequence() {
        preloadGameOverTextures()
        gameOverOverlayNode.removeAllActions()
        gameOverOverlayNode.isHidden = false
        gameOverOverlayNode.alpha = 1
        gameOverOverlayNode.position = CGPoint(
            x: size.width * 0.5 + gameOverOverlayOffset.x,
            y: size.height * 0.5 + gameOverOverlayOffset.y
        )
        guard let firstTexture = gameOverTextures.first,
              let finalTexture = gameOverTextures.last else {
            gameOverOverlayNode.isHidden = true
            revealGameOverText()
            return
        }
        gameOverOverlayNode.texture = firstTexture
        gameOverOverlayNode.size = CGSize(
            width: firstTexture.size().width * gameOverOverlayScale,
            height: firstTexture.size().height * gameOverOverlayScale
        )
        let animation = SKAction.animate(
            with: gameOverTextures,
            timePerFrame: 0.09
        )
        let holdFinalFrame = SKAction.run { [weak self] in
            self?.gameOverOverlayNode.texture = finalTexture
        }
        let revealText = SKAction.run { [weak self] in
            self?.revealGameOverText()
        }
        gameOverOverlayNode.run(
            SKAction.sequence([
                animation,
                holdFinalFrame,
                SKAction.wait(forDuration: 0.05),
                revealText
            ])
        )
    }
    private func preloadGameOverTextures() {
        guard gameOverTextures.isEmpty else { return }
        gameOverTextures = (1...6).map { SKTexture(imageNamed: "GameOver\($0)") }
    }
    private func revealGameOverText() {
        loseLabel.isHidden = false
        loseSubtitleLabel.isHidden = false
        endScoreLabel.isHidden = false
        endHeightLabel.isHidden = false
        gameOverCoinIconNode.isHidden = false
        loseLabel.run(SKAction.fadeIn(withDuration: 0.25))
        gameOverCoinIconNode.run(SKAction.fadeIn(withDuration: 0.25))
        loseSubtitleLabel.run(
            SKAction.sequence([
                SKAction.wait(forDuration: 0.10),
                SKAction.fadeIn(withDuration: 0.25)
            ])
        )
        endScoreLabel.run(
            SKAction.sequence([
                SKAction.wait(forDuration: 0.20),
                SKAction.fadeIn(withDuration: 0.25)
            ])
        )
        endHeightLabel.run(
            SKAction.sequence([
                SKAction.wait(forDuration: 0.30),
                SKAction.fadeIn(withDuration: 0.25)
            ])
        )
        retryLabel.isHidden = false
        retryLabel.run(
            SKAction.sequence([
                SKAction.wait(forDuration: 0.4),
                SKAction.fadeIn(withDuration: 0.25)
            ])
        )
    }
    private func retryGame() {

        bottomVisibleRow = 0
        cameraLeftColumn = 0.5

        playerGrid = (row: 3, column: 2)
        followerGrid = (row: 1, column: 2)

        isFollowerLeftOut = false
        leftOutCountdown = 0

        lastPlayerHorizontalDirection = 0

        playerVisitedTiles = [
            GridPosition(row: 3, column: 2)
        ]

        highestTileReached = 3
        lastRechargeTileReached = 3

        movementScore = 0
        collectibleScore = 0
        followerPenaltyScore = 0

        defusePower = maxDefusePower

        markedTiles.removeAll()
        defusedTiles.removeAll()
        collectibleTiles.removeAll()
        collectedTiles.removeAll()
        followerTriggeredTraps.removeAll()
        
        //BUBBLE
        
        followerHasBeenHit = false

        followerBubbleNode.removeAllActions()
        followerBubbleNode.removeAllChildren()

        removeAction(forKey: "followerBubbleScheduler")

        tileTextureNames.removeAll()
        trapTypesByPosition.removeAll()

        torchesByRow.removeAll()
        lastTorchRow = -10

        isGameStarted = false
        isGameLost = false
        isPlayerMoving = false

        // --------------------------------------------------
        // RESET SUSPENSE CAMERA
        // --------------------------------------------------

        worldNode.removeAction(forKey: "trapDeathCameraZoom")
        worldNode.removeAction(forKey: "trapDeathCameraZoom2")
        worldNode.removeAllActions()

        worldNode.position = .zero
        worldNode.setScale(1.0)

        // --------------------------------------------------
        // RESET FEEDBACK
        // --------------------------------------------------

        feedbackLayerNode.removeAllChildren()

        feedbackLabel.text = ""

        // --------------------------------------------------
        // RESET OJOK
        // --------------------------------------------------

        playerNode.removeAllActions()

        // Make sure the dead animation cannot remain
        // after restarting.
        playerNode.texture = SKTexture(imageNamed: "OjokIdle1")

        playerNode.color = .systemBlue
        playerNode.setScale(1.0)

        // --------------------------------------------------
        // RESET GAME OVER
        // --------------------------------------------------

        gameOverOverlayNode.removeAllActions()
        gameOverOverlayNode.isHidden = true
        gameOverOverlayNode.texture = nil

        gameOverCoinIconNode.removeAllActions()
        gameOverCoinIconNode.isHidden = true

        loseLabel.removeAllActions()
        loseLabel.isHidden = true
        loseLabel.alpha = 0

        loseSubtitleLabel.removeAllActions()
        loseSubtitleLabel.isHidden = true
        loseSubtitleLabel.alpha = 0

        endScoreLabel.removeAllActions()
        endScoreLabel.isHidden = true
        endScoreLabel.alpha = 0

        endHeightLabel.removeAllActions()
        endHeightLabel.isHidden = true
        endHeightLabel.alpha = 0

        // --------------------------------------------------
        // RESET TUTORIAL
        // --------------------------------------------------

        isTutorialActive = false
        tutorialStep = .moveUp

        tutorialMarkedSet = []

        tutorialMovedLeft = false
        tutorialMovedRight = false

        hasCompletedFollowerTrapTutorial = false
        isFollowerTutorialActive = false

        canSwapMarks = false

        hasCompletedDefuseTutorial = false
        isDefuseTutorialActive = false
        defuseTutorialTargetTile = nil

        tutorialArrowNode.removeAllChildren()
        tutorialTileHighlightNode.removeAllChildren()
        followerTutorialHighlightNode.removeAllChildren()
        defuseTutorialHighlightNode.removeAllChildren()

        tutorialInstructionBg.isHidden = true
        tutorialInstructionLabel.isHidden = true
        stopTrapDetectorBlinking()

        // --------------------------------------------------
        // RESET RETRY LABEL
        // --------------------------------------------------

        retryLabel.removeAllActions()
        retryLabel.alpha = 0
        retryLabel.isHidden = true

        // --------------------------------------------------
        // REBUILD MAP
        // --------------------------------------------------

        buildInitialMap()
        renderVisibleTiles()

        // --------------------------------------------------
        // RESTORE OJOK
        // --------------------------------------------------

        playerNode.texture = SKTexture(imageNamed: "OjokIdle1")
        playerNode.setScale(1.0)
        playerNode.color = .systemBlue

        placePlayer()

        // Restart normal idle animation.
        startPlayerIdleAnimation()

        // --------------------------------------------------
        // UPDATE UI / GAME STATE
        // --------------------------------------------------

        updateFollowerEnabledState()
        updatePlayerTrapNumber()
        updateScore()
        updatePower()
        resetPlayerIdleTimer()
        
        // -------------
        // Reset Red
        // -----------
        redOverlayNode.removeAllActions()
        redOverlayNode.alpha = 0
        redOverlayNode.isHidden = true

        playerNode.colorBlendFactor = 0.0
        playerNode.color = .white
    

    }
    private func ensureRowExists(_ row: Int) {
        guard tilesByRow[row] == nil else { return }
        tilesByRow[row] = generateRow(row)
        generateCollectibleForRowIfNeeded(row)
        // ── Deterministic Torch Generation (Rolled ONCE per row) ──
        if row > 4 && (row - lastTorchRow >= torchMinRowSpacing) {
            if Double.random(in: 0...1) < torchSpawnChancePerRow {
                let side: TorchSide = Bool.random() ? .left : .right
                let isLit = Double.random(in: 0...1) < torchLitProbability
                torchesByRow[row] = TorchData(side: side, isLit: isLit)
                lastTorchRow = row
            }
        }
    }
    private func generateThirtyRowWindow(startingAt firstRow: Int) {
        for row in firstRow..<(firstRow + storedRowCount) { ensureRowExists(row) }
    }
    private func generateCollectibleForRowIfNeeded(_ row: Int) {
        let rowAlreadyHasCollectible = collectibleTiles.contains { $0.row == row }
            || collectedTiles.contains { $0.row == row }
        guard !rowAlreadyHasCollectible else { return }
        guard Double.random(in: 0...1) < collectibleChancePerRow else { return }
        let candidates = collectibleCandidatesNearTraps(in: row)
        guard let collectiblePosition = candidates.randomElement() else { return }
        collectibleTiles.insert(collectiblePosition)
    }
    private func collectibleCandidatesNearTraps(in row: Int) -> [GridPosition] {
        let trapPositions = tilesByRow.values.flatMap { tiles in
            tiles.compactMap { tile -> GridPosition? in
                guard tile.hasTrap else { return nil }
                return GridPosition(row: tile.row, column: tile.column)
            }
        }
        let positionsNearTrap = Set(trapPositions.flatMap(adjacentPositions(to:)))
        return (0..<columnCount)
            .map { GridPosition(row: row, column: $0) }
            .filter { position in
                positionsNearTrap.contains(position)
                    && tileAt(row: position.row, column: position.column)?.hasTrap == false
                    && position != GridPosition(row: playerGrid.row, column: playerGrid.column)
                    && !collectibleTiles.contains(position)
                    && !collectedTiles.contains(position)
            }
    }
    private func adjacentPositions(to position: GridPosition) -> [GridPosition] {
        [
            GridPosition(row: position.row + 1, column: position.column),
            GridPosition(row: position.row - 1, column: position.column),
            GridPosition(row: position.row, column: position.column - 1),
            GridPosition(row: position.row, column: position.column + 1)
        ].filter {
            $0.column >= 0 && $0.column < columnCount
                && $0.row >= bottomVisibleRow
                && $0.row < bottomVisibleRow + storedRowCount
        }
    }
    private func removeRowsBelow(_ row: Int) {
        tilesByRow = tilesByRow.filter { $0.key >= row }
        tileTextureNames = tileTextureNames.filter { $0.key.row >= row }
        torchesByRow = torchesByRow.filter { $0.key >= row }
    }
    private func removeRowsAbove(_ row: Int) {
        tilesByRow = tilesByRow.filter { $0.key <= row }
        tileTextureNames = tileTextureNames.filter { $0.key.row <= row }
        torchesByRow = torchesByRow.filter { $0.key <= row }
    }
    private func removeMarksOutsideActiveRows() {
        markedTiles = markedTiles.filter { pos, _ in
            pos.row >= bottomVisibleRow && pos.row < bottomVisibleRow + storedRowCount
        }
    }
    private func removeDefusedTilesOutsideActiveRows() {
        defusedTiles = defusedTiles.filter {
            $0.row >= bottomVisibleRow && $0.row < bottomVisibleRow + storedRowCount
        }
    }
    private func removeCollectiblesOutsideActiveRows() {
        collectibleTiles = collectibleTiles.filter {
            $0.row >= bottomVisibleRow && $0.row < bottomVisibleRow + storedRowCount
        }
        collectedTiles = collectedTiles.filter {
            $0.row >= bottomVisibleRow && $0.row < bottomVisibleRow + storedRowCount
        }
        followerTriggeredTraps = followerTriggeredTraps.filter {
            $0.row >= bottomVisibleRow && $0.row < bottomVisibleRow + storedRowCount
        }
    }
    private func hasActiveTrap(at gridPosition: GridPosition) -> Bool {
        tileAt(row: gridPosition.row, column: gridPosition.column)?.hasTrap == true
            && !defusedTiles.contains(gridPosition)
    }
    private func hasActiveCollectible(at gridPosition: GridPosition) -> Bool {
        collectibleTiles.contains(gridPosition) && !collectedTiles.contains(gridPosition)
    }
    private func gridPosition(from node: SKNode) -> GridPosition? {
        guard
            let row = node.userData?["row"] as? Int,
            let column = node.userData?["column"] as? Int
        else { return nil }
        return GridPosition(row: row, column: column)
    }
    private func tileAt(row: Int, column: Int) -> Tile? {
        guard column >= 0, column < columnCount else { return nil }
        return tilesByRow[row]?.first { $0.column == column }
    }
    private func pointFor(row: Int, column: Int) -> CGPoint {
        let visibleRow = CGFloat(row - bottomVisibleRow)
        let visibleCol = CGFloat(column) - cameraLeftColumn
        return CGPoint(
            x: mapOrigin.x + tileSize.width * (visibleCol + 0.5),
            y: mapOrigin.y + tileSize.height * (visibleRow + 0.5)
        )
    }
    // MARK: - Node Assets
    private func slashNode(from start: CGPoint, to end: CGPoint, color: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: start); path.addLine(to: end)
        let slash = SKShapeNode(path: path)
        slash.strokeColor = color; slash.lineWidth = 5; slash.lineCap = .round
        return slash
    }
    private func markNode(size: CGSize, type: MarkType) -> SKNode {
        let imageName: String
        switch type {
        case .question:
            imageName = "QMark"
        case .xMark:
            imageName = "XMark"
        }
        let markSprite = SKSpriteNode(texture: SKTexture(imageNamed: imageName), size: size)
        markSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        markSprite.zPosition = 1
        return markSprite
    }
    private func trapNode(for gridPosition: GridPosition) -> SKSpriteNode {
        let trapType = trapTypesByPosition[gridPosition] ?? .spike
        let initialTexture = SKTexture(imageNamed: "\(trapType.texturePrefix)1")

        // Trap uses exactly the same size and center position as its tile.
        let sprite = SKSpriteNode(texture: initialTexture, size: tileSize)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.lightingBitMask = 1
        return sprite
    }

    private func activateTrapAnimation(at gridPosition: GridPosition) {

        let nodeName = "\(AssetName.trap)-\(gridPosition.row)-\(gridPosition.column)"

        guard let trapSprite = trapLayerNode.childNode(withName: nodeName) as? SKSpriteNode else {
            return
        }

        let trapType = trapTypesByPosition[gridPosition] ?? .spike

        let textures = (1...5).map { index in
            SKTexture(imageNamed: "\(trapType.texturePrefix)\(index)")
        }

        // Remove previous trap animation and fire light
        trapSprite.removeAction(forKey: "trapAnimation")
        trapSprite.childNode(withName: "fireTrapLight")?.removeFromParent()

        trapSprite.alpha = 1.0

        // Put the activated trap above the player
        trapSprite.zPosition = 10

        // Keep the trap affected by the dungeon ambient lighting
        trapSprite.lightingBitMask = 1

        switch trapType {

        case .spike:
            // Play Spike trap SFX
            AudioManager.shared.playSFX("Spike.mp3", on: self)

            // SpikeTrap1 -> 2 -> 3 -> 4 -> 5, then stay on frame 5.
            let animation = SKAction.animate(
                with: textures,
                timePerFrame: 0.05,
                resize: false,
                restore: false
            )

            trapSprite.run(
                animation,
                withKey: "trapAnimation"
            )

        case .fire:
            // Play Flame trap SFX
            AudioManager.shared.playSFX("Flame.mp3", on: self)

            // --------------------------------------------------
            // FIRE LIGHT
            // --------------------------------------------------

            let fireLight = SKLightNode()
            fireLight.name = "fireTrapLight"

            // Same lighting category as your dungeon lights
            fireLight.categoryBitMask = 1

            // Warm fire color
            fireLight.lightColor = SKColor(
                red: 1.0,
                green: 0.35,
                blue: 0.08,
                alpha: 1.0
            )

            // Don't replace the ambient darkness
            fireLight.ambientColor = .clear

            // Controls how quickly the light fades
            fireLight.falloff = 1.8

            // Put the light around the flame
            fireLight.position = CGPoint(
                x: 0,
                y: tileSize.height * 0.18
            )

            trapSprite.addChild(fireLight)

            // --------------------------------------------------
            // FIRE LIGHT FLICKER
            // --------------------------------------------------

            let flicker = SKAction.sequence([

                SKAction.customAction(withDuration: 0.07) { node, _ in
                    guard let light = node as? SKLightNode else {
                        return
                    }

                    light.falloff = CGFloat.random(in: 1.55...2.05)
                },

                SKAction.wait(forDuration: 0.04)
            ])

            fireLight.run(
                .repeatForever(flicker),
                withKey: "fireLightFlicker"
            )

            // --------------------------------------------------
            // FIRE ANIMATION
            // --------------------------------------------------

            // FireTrap1 -> 2 -> 3 -> 4 -> 5
            let activation = SKAction.animate(
                with: textures,
                timePerFrame: 0.10,
                resize: false,
                restore: false
            )

            // Then continuously loop FireTrap4 <-> FireTrap5
            let fireLoop = SKAction.repeatForever(
                SKAction.animate(
                    with: [textures[3], textures[4]],
                    timePerFrame: 0.10,
                    resize: false,
                    restore: false
                )
            )

            trapSprite.run(
                SKAction.sequence([
                    activation,
                    fireLoop
                ]),
                withKey: "trapAnimation"
            )
        }
    }

    private func collectibleNode() -> SKSpriteNode {
        let sprite = SKSpriteNode(
            imageNamed: AssetName.collectible,
            normalMapped: false
        )
        sprite.lightingBitMask = 1
        return sprite
    }
    private func playerBodyNode() -> SKNode {
        let body = SKNode()
        let head = SKShapeNode(circleOfRadius: 9)
        head.fillColor = .black; head.strokeColor = .black
        head.position = CGPoint(x: 0, y: 26); body.addChild(head)
        let torso = SKShapeNode(rectOf: CGSize(width: 22, height: 26), cornerRadius: 4)
        torso.fillColor = .white; torso.strokeColor = .black; torso.lineWidth = 2
        torso.position = CGPoint(x: 0, y: 6); body.addChild(torso)
        let leftLeg = SKShapeNode(rectOf: CGSize(width: 6, height: 13), cornerRadius: 2)
        leftLeg.fillColor = .white; leftLeg.strokeColor = .black; leftLeg.lineWidth = 2
        leftLeg.position = CGPoint(x: -6, y: -15); body.addChild(leftLeg)
        let rightLeg = SKShapeNode(rectOf: CGSize(width: 6, height: 13), cornerRadius: 2)
        rightLeg.fillColor = .white; rightLeg.strokeColor = .black; rightLeg.lineWidth = 2
        rightLeg.position = CGPoint(x: 6, y: -15); body.addChild(rightLeg)
        return body
    }
    private func followerBodyNode() -> SKNode {
        let body = SKNode()
        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor = .systemPurple; head.strokeColor = .black
        head.position = CGPoint(x: 0, y: 22); body.addChild(head)
        let torso = SKShapeNode(rectOf: CGSize(width: 20, height: 22), cornerRadius: 4)
        torso.fillColor = .white; torso.strokeColor = .systemPurple; torso.lineWidth = 3
        torso.position = CGPoint(x: 0, y: 4); body.addChild(torso)
        let leftLeg = SKShapeNode(rectOf: CGSize(width: 5, height: 11), cornerRadius: 2)
        leftLeg.fillColor = .white; leftLeg.strokeColor = .systemPurple; leftLeg.lineWidth = 2
        leftLeg.position = CGPoint(x: -5, y: -13); body.addChild(leftLeg)
        let rightLeg = SKShapeNode(rectOf: CGSize(width: 5, height: 11), cornerRadius: 2)
        rightLeg.fillColor = .white; rightLeg.strokeColor = .systemPurple; rightLeg.lineWidth = 2
        rightLeg.position = CGPoint(x: 5, y: -13); body.addChild(rightLeg)
        return body
    }
    
    // MARK: -  SFX

    private func playFootstepSFX() {
        // Increase volumeMultiplier (e.g., 1.5 or 2.0) to make footsteps stand out
        AudioManager.shared.playSFX("FootStep.wav", volumeMultiplier: 1.5)
    }
}
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let combinedMask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if combinedMask == (PhysicsCategory.follower | PhysicsCategory.trap) {
            let trapNode = contact.bodyA.categoryBitMask == PhysicsCategory.trap
                ? contact.bodyA.node : contact.bodyB.node
            applyFollowerTrapPenalty(from: trapNode)
            return
        }
        if combinedMask == (PhysicsCategory.player | PhysicsCategory.collectible) {
            let collectibleNode = contact.bodyA.categoryBitMask == PhysicsCategory.collectible
                ? contact.bodyA.node : contact.bodyB.node
            if let collectibleNode { collect(collectibleNode) }
        }
    }
}
