import SwiftUI
import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

final class SpriteHelper {
    static func addNode(
        name: String,
        width: Double,
        height: Double,
        x: CGFloat,
        y: CGFloat,
        scene: SKScene?,
        zPosition: Int = 0,
        onComplete: @escaping (SKSpriteNode) -> Void
    ) {
        let node = SKSpriteNode(imageNamed: name)
        node.size = CGSize(width: width, height: height)
        node.position = CGPoint(x: x, y: y)
        node.zPosition = CGFloat(zPosition)
        node.name = name
        scene?.addChild(node)
        onComplete(node)
    }

    static func addNode(_ node: SKNode, to parent: SKNode, at position: CGPoint, zPosition: CGFloat) {
        node.position = position
        node.zPosition = zPosition
        parent.addChild(node)
    }

    static func addPhysics(node: SKSpriteNode, effectedByGravity: Bool = true, dynamic: Bool = true) {
        node.physicsBody = SKPhysicsBody(rectangleOf: node.size)
        node.physicsBody?.affectedByGravity = effectedByGravity
        node.physicsBody?.isDynamic = dynamic
        node.physicsBody?.contactTestBitMask = node.physicsBody?.collisionBitMask ?? 0
    }

    static func makeTextureAnimation(
        name: String,
        range: ClosedRange<Int>,
        node: SKSpriteNode,
        duration: TimeInterval
    ) {
        let textures = range.map {
            SKTexture(imageNamed: "\(name)\($0)")
        }
        let animation = SKAction.animate(with: textures, timePerFrame: duration)
        let animationRepeat = SKAction.repeatForever(animation)
        node.run(animationRepeat)
    }

    static func removeAction(node: SKSpriteNode, onSuccess: @escaping () -> Void) {
        let remove = SKAction.removeFromParent()
        node.run(remove) {
            onSuccess()
        }
    }

    static func spawnedRepeatedly(scene: SKScene?, run: @escaping () -> Void, duration: TimeInterval) {
        let spawnAction = SKAction.run {
            run()
        }
        let waitAction = SKAction.wait(forDuration: duration)
        let spawnAndWaitAction = SKAction.sequence([spawnAction, waitAction])
        scene?.run(SKAction.repeatForever(spawnAndWaitAction))
    }

    static func handleContact(
        contact: SKPhysicsContact,
        item1: SKSpriteNode,
        item2: SKSpriteNode,
        onContact: @escaping (SKNode, SKNode) -> Void
    ) {
        guard let nodeA = contact.bodyA.node else { return }
        guard let nodeB = contact.bodyB.node else { return }

        if nodeA.name == item1.name && nodeB.name == item2.name {
            onContact(nodeA, nodeB)
        }
    }

    static func moveVertical(
        node: SKSpriteNode,
        moveTo: CGFloat,
        duration: TimeInterval,
        onSuccess: @escaping () -> Void = doNothing
    ) {
        let move = SKAction.moveTo(y: moveTo, duration: duration)
        node.run(move) {
            onSuccess()
        }
    }

    static func moveVerticalAndRemove(
        node: SKSpriteNode,
        moveTo: CGFloat,
        duration: TimeInterval,
        onSuccess: @escaping () -> Void
    ) {
        let move = SKAction.moveTo(y: moveTo, duration: duration)
        let removeAction = SKAction.removeFromParent()
        let moveAndRemoveSequence = SKAction.sequence([move, removeAction])
        node.run(moveAndRemoveSequence) {
            onSuccess()
        }
    }

    static func moveHorizontal(
        node: SKSpriteNode,
        moveTo: CGFloat,
        duration: TimeInterval,
        onSuccess: @escaping () -> Void = doNothing
    ) {
        let move = SKAction.moveTo(x: moveTo, duration: duration)
        node.run(move) {
            onSuccess()
        }
    }

    static func moveHorizontalAndRemove(
        node: SKSpriteNode,
        moveTo: CGFloat,
        duration: TimeInterval,
        onSuccess: @escaping () -> Void
    ) {
        let move = SKAction.moveTo(x: moveTo, duration: duration)
        let removeAction = SKAction.removeFromParent()
        let moveAndRemoveSequence = SKAction.sequence([move, removeAction])
        node.run(moveAndRemoveSequence) {
            onSuccess()
        }
    }

    #if canImport(UIKit)
    static func handleTap(
        touches: Set<UITouch>,
        with event: UIEvent?,
        scene: SKScene?,
        node: SKSpriteNode,
        onTap: @escaping () -> Void
    ) {
        guard let scene else { return }

        for touch in touches {
            let location = touch.location(in: scene)
            let touchedNodes = scene.nodes(at: location)

            for touchedNode in touchedNodes {
                if touchedNode == node {
                    onTap()
                }
            }
        }
    }

    static func getTouchLocation(
        touches: Set<UITouch>,
        scene: SKScene?,
        onAction: @escaping (CGPoint) -> Void
    ) {
        guard let scene else { return }

        for touch in touches {
            let location = touch.location(in: scene)
            onAction(location)
        }
    }
    #endif

    nonisolated static func doNothing() { }
}
