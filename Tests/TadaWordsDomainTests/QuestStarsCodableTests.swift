import Foundation
import TadaWordsDomain
import XCTest

final class QuestStarsCodableTests: XCTestCase {
    func testDecodesLegacyKeyedRepresentation() throws {
        let data = Data(
            #"{"earned":["personalPace","completion","accuracy"]}"#.utf8
        )

        let stars = try JSONDecoder().decode(QuestStars.self, from: data)

        XCTAssertEqual(
            stars,
            QuestStars(earned: [.completion, .accuracy, .personalPace])
        )
    }

    func testDecodesCanonicalSingleValueRepresentation() throws {
        let data = Data(#"["completion","accuracy"]"#.utf8)

        let stars = try JSONDecoder().decode(QuestStars.self, from: data)

        XCTAssertEqual(stars, QuestStars(earned: [.completion, .accuracy]))
    }

    func testLegacyKeyedRepresentationRequiresEarnedField() throws {
        let data = Data(#"{}"#.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode(QuestStars.self, from: data)
        ) { error in
            guard case DecodingError.keyNotFound = error else {
                return XCTFail("Expected keyNotFound, got \(error)")
            }
        }
    }

    func testEncodesOnlyCanonicalStableRepresentation() throws {
        let stars = QuestStars(
            earned: [.personalPace, .completion, .accuracy]
        )

        let data = try JSONEncoder().encode(stars)

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"["completion","accuracy","personalPace"]"#
        )
    }
}
