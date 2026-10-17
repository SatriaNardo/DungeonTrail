import SwiftUI
import Combine

final class GameHUD: ObservableObject {
    @Published var isVisible = false
    @Published var score = 0
    @Published var depth = 0
    @Published var defuseCharges = 3
    @Published var tutorialText: String?
    @Published var tutorialIsSuccess = false

    let maxDefuseCharges = 3
    let coinImageName = "GoldCoin"
    let disarmEnabledImageName = "DisarmTrapEnable"
    let disarmDisabledImageName = "DisarmTrapDisable"
    let depthPrefix = "Depth"

    let hudHorizontalPadding: CGFloat = 16
    let hudTopPadding: CGFloat = 12
    let hudBackgroundOpacity = 0.88
    let coinSize: CGFloat = 46
    let scoreFontSize: CGFloat = 22
    let scoreFontWeight: Font.Weight = .bold
    let scoreColor = Color.white
    let depthFontSize: CGFloat = 18
    let depthFontWeight: Font.Weight = .medium
    let depthColor = Color.white.opacity(0.8)
    let disarmIconSize: CGFloat = 60
    let disarmIconSpacing: CGFloat = 5
    let disarmDisabledOpacity = 0.4
    let tutorialTopGap: CGFloat = 180
    let tutorialFontSize: CGFloat = 15
    let tutorialFontWeight: Font.Weight = .bold
    let tutorialNormalColor = Color.yellow
    let tutorialSuccessColor = Color.green
    let tutorialBannerPaddingH: CGFloat = 16
    let tutorialBannerPaddingV: CGFloat = 10
    let tutorialBannerCornerRadius: CGFloat = 8
    let tutorialBannerOpacity = 0.8
}
