import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsAppShell

final class FamilySyncBackgroundResultPolicyTests: XCTestCase {
    func testNewDataRequiresAChangedDurableReceiptToken() {
        assertResult(
            .newData,
            status: .synced(at: Date(timeIntervalSince1970: 1)),
            before: "before",
            after: "after"
        )
        assertResult(
            .noData,
            status: .synced(at: Date(timeIntervalSince1970: 1)),
            before: "same",
            after: "same"
        )
        assertResult(
            .noData,
            status: .synced(at: Date(timeIntervalSince1970: 1)),
            before: nil,
            after: "after"
        )
    }

    func testFailureDominatesAChangedReceiptToken() {
        assertResult(
            .failed,
            status: .failed(message: "safe", pendingCount: 1),
            before: "before",
            after: "after"
        )
    }

    private func assertResult(
        _ expected: FamilySyncBackgroundFetchResult,
        status: FamilySyncStatus,
        before: String?,
        after: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = FamilySyncBackgroundResultPolicy.result(
            status: status,
            receiptTokenBefore: before,
            receiptTokenAfter: after
        )
        switch (expected, actual) {
        case (.newData, .newData), (.noData, .noData), (.failed, .failed):
            break
        default:
            XCTFail("Unexpected background result", file: file, line: line)
        }
    }
}
