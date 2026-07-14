import Foundation
import TadaWordsContent
import TadaWordsDomain

struct GuardianPresetRollbackRequest: Equatable, Sendable {
    let profileID: ProfileID
    let learningMode: LearningMode
    let membershipIDs: [WordPoolEntryID]

    init(
        profileID: ProfileID,
        learningMode: LearningMode,
        membershipIDs: [WordPoolEntryID]
    ) {
        self.profileID = profileID
        self.learningMode = learningMode
        self.membershipIDs = Array(Set(membershipIDs)).sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
    }
}

struct GuardianPresetImportSummary: Equatable, Sendable {
    let addedMembershipCount: Int
    let reactivatedMembershipCount: Int
    let alreadyPresentMembershipCount: Int

    var message: String {
        let changedMessage: String?
        switch (addedMembershipCount, reactivatedMembershipCount) {
        case (0, 0):
            changedMessage = nil
        case (let added, 0):
            changedMessage = "Added \(entryCount(added))."
        case (0, let reactivated):
            changedMessage = "Restored \(entryCount(reactivated))."
        case (let added, let reactivated):
            changedMessage =
                "Added \(entryCount(added)) and restored \(entryCount(reactivated))."
        }

        guard alreadyPresentMembershipCount > 0 else {
            return changedMessage ?? "No pool entries changed."
        }
        let alreadyPresentMessage =
            "\(alreadyPresentMembershipCount) already \(alreadyPresentMembershipCount == 1 ? "exists" : "exist") in the selected pool or pools."
        guard let changedMessage else { return alreadyPresentMessage }
        return "\(changedMessage) \(alreadyPresentMessage)"
    }

    private func entryCount(_ count: Int) -> String {
        "\(count) pool \(count == 1 ? "entry" : "entries")"
    }
}

enum GuardianPresetImportFailure: Equatable, Sendable {
    case unchanged
    case rolledBack
    case rollbackFailed

    var message: String {
        switch self {
        case .unchanged:
            "The selected words could not be added. No pool was changed. Try again."
        case .rolledBack:
            "The selected words could not be added to every pool, so this Add was rolled back. Try again."
        case .rollbackFailed:
            "Some selected words may remain in one pool. Open Manage Words to review them before trying again."
        }
    }
}

enum GuardianPresetImportOutcome: Equatable, Sendable {
    case success(GuardianPresetImportSummary)
    case failure(GuardianPresetImportFailure)
}

/// Executes the already parent-approved plan. Each submitted batch is still
/// atomic in the repository. When `Both` needs two batches, a later failure
/// deactivates every membership changed by the earlier batch so the operation
/// remains retryable without leaving a hidden half-import.
@MainActor
struct GuardianPresetImportCoordinator {
    typealias Submit =
        @MainActor (ProfileID, GuardianWordImportRequest) async
        -> GuardianWordImportReport?
    typealias Rollback =
        @MainActor (GuardianPresetRollbackRequest) async -> Bool

    func execute(
        profileID: ProfileID,
        plan: PresetWordSelectionPlan,
        submit: Submit,
        rollback: Rollback
    ) async -> GuardianPresetImportOutcome {
        var appliedRequests: [GuardianPresetRollbackRequest] = []
        var addedMembershipCount = 0
        var reactivatedMembershipCount = 0
        var alreadyPresentMembershipCount = plan.alreadyPresentMembershipCount

        for addition in plan.additions {
            guard
                let report = await submit(
                    profileID,
                    GuardianWordImportRequest(
                        rawText: addition.words.joined(separator: "\n"),
                        learningMode: addition.learningMode
                    )
                )
            else {
                return await failure(
                    afterApplying: appliedRequests,
                    rollback: rollback
                )
            }

            let expected = normalizedSet(addition.words)
            let inserted = normalizedSet(
                report.insertedMemberships.map(\.normalizedText)
            )
            let reactivated = normalizedSet(
                report.reactivatedMemberships.map(\.normalizedText)
            )
            let alreadyActive = normalizedSet(
                report.alreadyActiveMemberships.map(\.normalizedText)
            )
            let reportMatchesScope =
                report.profileID == profileID
                && report.learningMode == addition.learningMode
            let changedMembershipIDs = report.changedMemberships.map(\.entryID)
            if reportMatchesScope, !changedMembershipIDs.isEmpty {
                appliedRequests.append(
                    GuardianPresetRollbackRequest(
                        profileID: profileID,
                        learningMode: addition.learningMode,
                        membershipIDs: changedMembershipIDs
                    )
                )
            }

            let reportIsComplete =
                reportMatchesScope
                && report.rejected.isEmpty
                && report.duplicateInputWords.isEmpty
                && inserted.isDisjoint(with: reactivated)
                && inserted.isDisjoint(with: alreadyActive)
                && reactivated.isDisjoint(with: alreadyActive)
                && inserted.union(reactivated).union(alreadyActive) == expected
                && Set(changedMembershipIDs).count == changedMembershipIDs.count
            guard reportIsComplete else {
                return await failure(
                    afterApplying: appliedRequests,
                    rollback: rollback
                )
            }

            addedMembershipCount += inserted.count
            reactivatedMembershipCount += reactivated.count
            alreadyPresentMembershipCount += alreadyActive.count
        }

        return .success(
            GuardianPresetImportSummary(
                addedMembershipCount: addedMembershipCount,
                reactivatedMembershipCount: reactivatedMembershipCount,
                alreadyPresentMembershipCount: alreadyPresentMembershipCount
            )
        )
    }

    private func failure(
        afterApplying appliedRequests: [GuardianPresetRollbackRequest],
        rollback: Rollback
    ) async -> GuardianPresetImportOutcome {
        guard !appliedRequests.isEmpty else { return .failure(.unchanged) }

        var didRollbackEveryRequest = true
        for request in appliedRequests.reversed() {
            if !(await rollback(request)) {
                didRollbackEveryRequest = false
            }
        }
        return .failure(didRollbackEveryRequest ? .rolledBack : .rollbackFailed)
    }

    private func normalizedSet(_ words: [String]) -> Set<String> {
        Set(words.compactMap { try? EnglishWordNormalizer.normalize($0) })
    }
}
