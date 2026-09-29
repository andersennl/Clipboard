import AppKit
import XCTest
@testable import Clipboard

@MainActor
final class HistoryRowMouseInteractionViewTests: XCTestCase {
    func testSingleMouseDownSelectsImmediatelyWithoutConfirming() throws {
        let view = HistoryRowMouseInteractionView()
        var selectCount = 0
        var confirmCount = 0
        view.onMouseDown = {
            selectCount += 1
        }
        view.onDoubleClickMouseUp = {
            confirmCount += 1
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, clickCount: 1))

        XCTAssertEqual(selectCount, 1)
        XCTAssertEqual(confirmCount, 0)
    }

    func testSingleMouseUpDoesNotConfirm() throws {
        let view = HistoryRowMouseInteractionView()
        var confirmCount = 0
        view.onDoubleClickMouseUp = {
            confirmCount += 1
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, clickCount: 1))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, clickCount: 1))

        XCTAssertEqual(confirmCount, 0)
    }

    func testDoubleMouseUpConfirmsAfterSelection() throws {
        let view = HistoryRowMouseInteractionView()
        var events: [String] = []
        view.onMouseDown = {
            events.append("select")
        }
        view.onDoubleClickMouseUp = {
            events.append("confirm")
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, clickCount: 2))
        XCTAssertEqual(events, ["select"])

        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, clickCount: 2))

        XCTAssertEqual(events, ["select", "confirm"])
    }

    private func mouseEvent(type: NSEvent.EventType, clickCount: Int) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: clickCount,
                pressure: 1
            )
        )
    }
}
