import CoreGraphics
import XCTest

@testable import TadaWordsDesignSystem

final class TadaWorldSceneDecorationPolicyTests: XCTestCase {
    func testPrincessDecorationsStayInLandscapeSideBands() {
        let landscapeCanvases = [
            CGSize(width: 874, height: 402),
            CGSize(width: 1_194, height: 834),
        ]

        for canvas in landscapeCanvases {
            let layout = MoonpetalSceneDecorationLayout(canvasSize: canvas)
            let rainbowFrame = CGRect(
                x: layout.rainbowCenter.x - layout.rainbowSize.width * 0.5,
                y: layout.rainbowCenter.y - layout.rainbowSize.height * 0.5,
                width: layout.rainbowSize.width,
                height: layout.rainbowSize.height
            )
            let unicornFrame = CGRect(
                x: layout.unicornCenter.x - layout.unicornSize.width * 0.5,
                y: layout.unicornCenter.y - layout.unicornSize.height * 0.5,
                width: layout.unicornSize.width,
                height: layout.unicornSize.height
            )

            XCTAssertLessThanOrEqual(rainbowFrame.maxX, canvas.width * 0.25)
            XCTAssertGreaterThanOrEqual(unicornFrame.minX, canvas.width * 0.75)
            XCTAssertLessThanOrEqual(unicornFrame.maxX, canvas.width)
            XCTAssertGreaterThan(rainbowFrame.width, 0)
            XCTAssertGreaterThan(unicornFrame.height, 0)

            let verticalOffset = TadaWorldStoryArtLayoutPolicy.verticalOffset(
                canvasHeight: canvas.height
            )
            XCTAssertGreaterThan(verticalOffset, 0)
            XCTAssertLessThanOrEqual(
                unicornFrame.maxY + verticalOffset
                    + TadaWorldStoryArtLayoutPolicy.moonpetalUnicornAdditionalOffset
                    + TadaWorldStoryArtLayoutPolicy.moonpetalMaximumDownwardMotion,
                canvas.height
            )
            XCTAssertLessThanOrEqual(
                canvas.height
                    * (0.80
                        + TadaWorldStoryArtLayoutPolicy.moonpetalCastleHeightRatio * 0.5)
                    + verticalOffset,
                canvas.height
            )
        }
    }

    func testReduceMotionAndQuestStyleDisableAmbientDrift() {
        XCTAssertTrue(
            TadaWorldSceneMotionPolicy.shouldAnimate(
                style: .lobby,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            TadaWorldSceneMotionPolicy.shouldAnimate(
                style: .lobby,
                reduceMotion: true
            )
        )
        XCTAssertFalse(
            TadaWorldSceneMotionPolicy.shouldAnimate(
                style: .quest,
                reduceMotion: false
            )
        )
    }

    func testExpansionWorldsKeepMajorStoryArtOutOfCenterLearningBand() {
        let landscapeCanvases = [
            CGSize(width: 874, height: 402),
            CGSize(width: 1_194, height: 834),
            CGSize(width: 1_366, height: 1_024),
        ]

        for canvas in landscapeCanvases {
            let layout = TadaExpandedWorldSceneLayout(canvasSize: canvas)

            XCTAssertGreaterThanOrEqual(
                TadaExpandedWorldSceneLayout.minimumDownwardMotion,
                0
            )
            XCTAssertGreaterThanOrEqual(layout.leftStoryFrame.minX, 0)
            XCTAssertLessThanOrEqual(layout.leftStoryFrame.maxX, canvas.width * 0.25)
            XCTAssertGreaterThanOrEqual(layout.rightStoryFrame.minX, canvas.width * 0.75)
            XCTAssertLessThanOrEqual(layout.rightStoryFrame.maxX, canvas.width)
            XCTAssertGreaterThan(layout.leftStoryFrame.width, 0)
            XCTAssertGreaterThan(layout.rightStoryFrame.height, 0)
            XCTAssertLessThanOrEqual(layout.groundHeight, canvas.height * 0.14)
            XCTAssertEqual(
                layout.storyVerticalOffset,
                TadaWorldStoryArtLayoutPolicy.verticalOffset(canvasHeight: canvas.height),
                accuracy: 0.001
            )
            XCTAssertLessThanOrEqual(
                layout.leftStoryFrame.maxY + layout.storyVerticalOffset
                    + TadaExpandedWorldSceneLayout.maximumDownwardMotion,
                canvas.height
            )
            XCTAssertLessThanOrEqual(
                layout.rightStoryFrame.maxY + layout.storyVerticalOffset
                    + TadaExpandedWorldSceneLayout.maximumDownwardMotion,
                canvas.height
            )
        }
    }

    func testStoryArtVerticalOffsetIsSmallAndCapped() {
        XCTAssertGreaterThanOrEqual(
            TadaWorldStoryArtLayoutPolicy.moonpetalMinimumDownwardMotion,
            0
        )
        XCTAssertGreaterThanOrEqual(
            TadaWorldStoryArtLayoutPolicy.moonpetalMaximumDownwardMotion,
            TadaWorldStoryArtLayoutPolicy.moonpetalMinimumDownwardMotion
        )
        XCTAssertEqual(
            TadaWorldStoryArtLayoutPolicy.verticalOffset(canvasHeight: 400),
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TadaWorldStoryArtLayoutPolicy.verticalOffset(canvasHeight: 1_024),
            32,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TadaWorldStoryArtLayoutPolicy.verticalOffset(canvasHeight: -100),
            0,
            accuracy: 0.001
        )
    }

    func testEveryMascotPoseHasARecognizableFriendlyExpression() {
        let personalities: [TadaMascotPersonality] = [
            .storybook, .vehicle, .woodland, .dinosaur,
            .helper, .builder, .snow, .adventurer,
        ]

        for personality in personalities {
            XCTAssertEqual(
                TadaMascotExpressionPolicy.expression(
                    for: .resting,
                    personality: personality
                ).mouth,
                .friendlySmile
            )
            XCTAssertEqual(
                TadaMascotExpressionPolicy.expression(
                    for: .cheering,
                    personality: personality
                ),
                TadaMascotExpression(
                    eyes: .happyArcs,
                    mouth: .openCheer,
                    showsBlush: true
                )
            )
            XCTAssertEqual(
                TadaMascotExpressionPolicy.expression(
                    for: .encouraging,
                    personality: personality
                ).eyes,
                .gentleWink
            )
            XCTAssertEqual(
                TadaMascotExpressionPolicy.expression(
                    for: .rescue,
                    personality: personality
                ),
                TadaMascotExpression(
                    eyes: .focused,
                    mouth: .readySmile,
                    showsBlush: false
                )
            )
        }
    }
}
