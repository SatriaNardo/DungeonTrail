import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var hud = GameHUD()
    @State private var scene: GameScene? = nil

    var body: some View {
        ZStack(alignment: .top) {
            if let gameScene = scene {
                SpriteView(scene: gameScene)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            HUDView(hud: hud)
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            if scene == nil {
                let s = GameScene(size: GameScene.iPhone17PortraitSize)
                s.scaleMode = .aspectFit
                s.gameHUD = hud
                self.scene = s
            }
        }
    }
}
