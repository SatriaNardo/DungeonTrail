import SwiftUI

// SwiftUI overlay rendered on top of the SpriteKit game scene.
struct HUDView: View {

    @ObservedObject var hud: GameHUD

    private let gradientHeight: CGFloat = 230

    var body: some View {
        ZStack(alignment: .top) {
            if hud.isVisible {
                hudContent
                    .transition(.opacity)
            }
        }
        .animation(
            .easeInOut(duration: 0.35),
            value: hud.isVisible
        )
    }

    private var hudContent: some View {
        VStack(spacing: 0) {

            mainHUDRow
                .padding(.horizontal, hud.hudHorizontalPadding)
                .padding(.top, hud.hudTopPadding)

            if let text = hud.tutorialText {
                tutorialBanner(text: text)
                    .padding(.horizontal, hud.hudHorizontalPadding)
                    .padding(.top, hud.tutorialTopGap)
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }

            Spacer()
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(alignment: .top) {
            LinearGradient(
                colors: [
                    .black.opacity(hud.hudBackgroundOpacity),
                    .black.opacity(hud.hudBackgroundOpacity * 0.7),
                    .black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: gradientHeight)
            .ignoresSafeArea(edges: .top)
        }
        .animation(
            .easeInOut(duration: 0.25),
            value: hud.tutorialText
        )
    }

    private var mainHUDRow: some View {
        HStack(spacing: 0) {
            scoreDepthStack

            Spacer(minLength: 0)

            disarmIconRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var scoreDepthStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(hud.coinImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: hud.coinSize,
                        height: hud.coinSize
                    )

                Text("\(hud.score)")
                    .font(
                        .system(
                            size: hud.scoreFontSize,
                            weight: hud.scoreFontWeight
                        )
                    )
                    .foregroundColor(hud.scoreColor)
            }

            Text("\(hud.depthPrefix) : \(hud.depth)m")
                .font(
                    .system(
                        size: hud.depthFontSize,
                        weight: hud.depthFontWeight
                    )
                )
                .foregroundColor(hud.depthColor)
        }
    }

    private var disarmIconRow: some View {
        HStack(spacing: hud.disarmIconSpacing) {
            ForEach(0..<hud.maxDefuseCharges, id: \.self) { index in

                let enabled = index < hud.defuseCharges

                Image(
                    enabled
                    ? hud.disarmEnabledImageName
                    : hud.disarmDisabledImageName
                )
                .resizable()
                .scaledToFit()
                .frame(
                    width: hud.disarmIconSize,
                    height: hud.disarmIconSize
                )
                .opacity(
                    enabled
                    ? 1.0
                    : hud.disarmDisabledOpacity
                )
            }
        }
    }

    private func tutorialBanner(text: String) -> some View {
        Text(text)
            .font(
                .system(
                    size: hud.tutorialFontSize,
                    weight: hud.tutorialFontWeight
                )
            )
            .foregroundColor(
                hud.tutorialIsSuccess
                ? hud.tutorialSuccessColor
                : hud.tutorialNormalColor
            )
            .multilineTextAlignment(.center)
            .padding(.horizontal, hud.tutorialBannerPaddingH)
            .padding(.vertical, hud.tutorialBannerPaddingV)
            .background(
                RoundedRectangle(
                    cornerRadius: hud.tutorialBannerCornerRadius,
                    style: .continuous
                )
                .fill(
                    Color.black.opacity(
                        hud.tutorialBannerOpacity
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: hud.tutorialBannerCornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        hud.tutorialIsSuccess
                        ? hud.tutorialSuccessColor
                        : hud.tutorialNormalColor,
                        lineWidth: 1.2
                    )
                )
            )
    }
}
