import XCTest
@testable import OnlyWhisper

final class TextTargetTests: XCTestCase {
    func testSettableSelectionAcceptsAnyRole() {
        XCTAssertTrue(TextTarget.canAcceptInsertion(role: "AXWebArea", selectedTextSettable: true))
        XCTAssertTrue(TextTarget.canAcceptInsertion(role: nil, selectedTextSettable: true))
    }

    func testTextRolesAcceptWithoutSettableSelection() {
        XCTAssertEqual(
            TextTarget.writableRoles,
            ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField"]
        )
        for role in TextTarget.writableRoles {
            XCTAssertTrue(TextTarget.canAcceptInsertion(role: role, selectedTextSettable: false), role)
        }
    }

    func testNonTextRolesReject() {
        let roles: [String?] = ["AXWebArea", "AXWindow", "AXButton", "AXList", "AXOutline", "AXGroup", "AXScrollArea", nil]
        for role in roles {
            XCTAssertFalse(TextTarget.canAcceptInsertion(role: role, selectedTextSettable: false))
        }
    }

    func testTextFieldIsTheInsertionTarget() {
        XCTAssertEqual(
            TextTarget.insertionIndex(in: [("AXTextField", false)]),
            0
        )
    }

    func testAncestorTextAreaIsTheInsertionTarget() {
        XCTAssertEqual(
            TextTarget.insertionIndex(in: [
                ("AXGroup", false),
                ("AXTextArea", false),
            ]),
            1
        )
    }

    func testEditableWebSelectionIsTheInsertionTarget() {
        XCTAssertEqual(
            TextTarget.insertionIndex(in: [("AXWebArea", true)]),
            0
        )
    }

    func testWindowIsNotAnInsertionTarget() {
        XCTAssertNil(TextTarget.insertionIndex(in: [("AXWindow", false)]))
        XCTAssertNil(
            TextTarget.insertionIndex(in: [
                ("AXGroup", false),
                ("AXWebArea", false),
                ("AXWindow", false),
            ])
        )
    }
}

final class DictationDeliveryTests: XCTestCase {
    func testEmptyTextIsNothingHeard() {
        XCTAssertEqual(DictationDelivery.decide(text: "  ", inserted: true), .nothingHeard)
        XCTAssertEqual(DictationDelivery.decide(text: "", inserted: false), .nothingHeard)
    }

    func testInsertedWhenTheFieldAcceptedText() {
        XCTAssertEqual(DictationDelivery.decide(text: "Hallo", inserted: true), .inserted)
    }

    func testHoldForCopyWhenNothingLanded() {
        XCTAssertEqual(DictationDelivery.decide(text: "Hallo", inserted: false), .holdForCopy)
    }
}
