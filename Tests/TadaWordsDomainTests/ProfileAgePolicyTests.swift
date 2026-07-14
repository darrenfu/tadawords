import TadaWordsDomain
import XCTest

final class ProfileAgePolicyTests: XCTestCase {
    func testNewProfileAgesMatchTheAuthoredPreKThroughGradeThreeRange() {
        XCTAssertEqual(ProfileAgePolicy.supportedAges, 3...8)
        XCTAssertFalse(ProfileAgePolicy.isSupported(2))
        XCTAssertTrue(ProfileAgePolicy.isSupported(3))
        XCTAssertTrue(ProfileAgePolicy.isSupported(8))
        XCTAssertFalse(ProfileAgePolicy.isSupported(9))

        XCTAssertEqual(ProfileAgePolicy.durableAges, 2...18)
        XCTAssertTrue(ProfileAgePolicy.isDurable(2))
        XCTAssertTrue(ProfileAgePolicy.isDurable(18))
    }

    func testSuggestedGradeFollowsEarlyElementaryAgeMilestones() {
        XCTAssertEqual(ProfileAgePolicy.suggestedSchoolGrade(for: 3), .preK)
        XCTAssertEqual(ProfileAgePolicy.suggestedSchoolGrade(for: 4), .preK)
        XCTAssertEqual(
            ProfileAgePolicy.suggestedSchoolGrade(for: 5),
            .kindergarten
        )
        XCTAssertEqual(ProfileAgePolicy.suggestedSchoolGrade(for: 6), .grade1)
        XCTAssertEqual(ProfileAgePolicy.suggestedSchoolGrade(for: 7), .grade2)
        XCTAssertEqual(ProfileAgePolicy.suggestedSchoolGrade(for: 8), .grade3)
        XCTAssertNil(ProfileAgePolicy.suggestedSchoolGrade(for: 9))
    }

    func testSuggestedAgeCoversEveryExplicitGradeWithoutChangingIt() {
        XCTAssertEqual(ProfileAgePolicy.suggestedAge(for: .preK), 4)
        XCTAssertEqual(ProfileAgePolicy.suggestedAge(for: .kindergarten), 5)
        XCTAssertEqual(ProfileAgePolicy.suggestedAge(for: .grade1), 6)
        XCTAssertEqual(ProfileAgePolicy.suggestedAge(for: .grade2), 7)
        XCTAssertEqual(ProfileAgePolicy.suggestedAge(for: .grade3), 8)
    }
}
