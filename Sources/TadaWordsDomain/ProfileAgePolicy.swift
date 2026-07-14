public enum ProfileAgePolicy {
    /// Tada Words currently authors learning recommendations from Pre-K
    /// through Grade 3. New profiles stay inside that honest product range.
    public static let supportedAges = 3...8
    /// Older snapshots used a wider storage range. Keep decoding and editing
    /// compatibility separate from what new-profile screens offer.
    public static let durableAges = 2...18
    public static let defaultAge = 4

    public static func isSupported(_ ageYears: Int) -> Bool {
        supportedAges.contains(ageYears)
    }

    public static func isDurable(_ ageYears: Int) -> Bool {
        durableAges.contains(ageYears)
    }

    public static func suggestedAge(for grade: ProfileSchoolGrade) -> Int {
        switch grade {
        case .preK:
            4
        case .kindergarten:
            5
        case .grade1:
            6
        case .grade2:
            7
        case .grade3:
            8
        }
    }

    /// Kid-created profiles do not ask a child to understand grade labels.
    /// The parent can later choose a different grade explicitly.
    public static func suggestedSchoolGrade(
        for ageYears: Int
    ) -> ProfileSchoolGrade? {
        guard isSupported(ageYears) else { return nil }
        return switch ageYears {
        case ...4:
            .preK
        case 5:
            .kindergarten
        case 6:
            .grade1
        case 7:
            .grade2
        default:
            .grade3
        }
    }
}
