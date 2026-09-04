import XCTest
import SwiftUI
@testable import PokeTokenBar

final class ShopPaperworkTests: XCTestCase {
    func testStartsAtFirstFormWithoutFilingAnything() {
        let desk = ShopPaperwork()
        XCTAssertEqual(desk.form, .roundness)
        XCTAssertEqual(desk.stage, .intake)
        XCTAssertEqual(desk.stage.action, "Request review")
    }

    func testThreeExplicitActionsProduceOnlyAFictionalCertificate() {
        var desk = ShopPaperwork()
        desk.advance()
        XCTAssertEqual(desk.stage, .review)
        desk.advance()
        XCTAssertEqual(desk.stage, .escalation)
        desk.advance()
        XCTAssertEqual(desk.stage, .filed)
        XCTAssertEqual(desk.form.stamp, "OFFICIALLY ROUND")
        desk.advance()
        XCTAssertEqual(desk.form, .lessPaperwork)
        XCTAssertEqual(desk.stage, .intake)
    }

    func testEveryStoryBeatIsDistinctAndCycleReturnsToStart() {
        var desk = ShopPaperwork()
        var lines = Set<String>()
        for _ in 0..<(ShopPaperwork.Form.allCases.count * ShopPaperwork.Stage.allCases.count) {
            XCTAssertTrue(lines.insert(desk.line).inserted)
            XCTAssertFalse(desk.form.title.isEmpty)
            XCTAssertFalse(desk.stage.action.isEmpty)
            desk.advance()
        }
        XCTAssertEqual(desk, ShopPaperwork())
    }

    func testRepeatedClicksStayBoundedAndDeterministic() {
        var first = ShopPaperwork()
        var second = ShopPaperwork()
        for _ in 0..<10_000 {
            first.advance()
            second.advance()
            XCTAssertEqual(first, second)
            XCTAssertLessThanOrEqual(first.line.count, 160)
        }
        // Nothing is persisted: a newly constructed desk starts a fresh story.
        XCTAssertEqual(ShopPaperwork().stage, .intake)
    }
}

@MainActor
final class ShopPaperworkLayoutTests: XCTestCase {
    private func size(expanded: Bool, paperwork: ShopPaperwork = ShopPaperwork(), width: CGFloat) -> CGSize {
        NSHostingController(rootView: ShopPaperworkView(initiallyExpanded: expanded, initialPaperwork: paperwork))
            .sizeThatFits(in: CGSize(width: width, height: 1000))
    }

    func testClosedDeskIsOneCompactRowAtProductionWidth() {
        let measured = size(expanded: false, width: PopoverMetrics.contentWidth)
        XCTAssertLessThanOrEqual(measured.width, PopoverMetrics.contentWidth)
        XCTAssertGreaterThanOrEqual(measured.height, 44)
        XCTAssertLessThanOrEqual(measured.height, 48)
    }

    func testEveryExpandedStoryFitsProductionAndPreviewWidths() {
        for width in [PopoverMetrics.contentWidth, CGFloat(388)] {
            for form in ShopPaperwork.Form.allCases {
                for stage in ShopPaperwork.Stage.allCases {
                    let measured = size(expanded: true, paperwork: ShopPaperwork(form: form, stage: stage), width: width)
                    XCTAssertLessThanOrEqual(measured.width, width, "\(form) \(stage)")
                    XCTAssertLessThanOrEqual(measured.height, 340, "\(form) \(stage)")
                    XCTAssertGreaterThan(measured.height, 44)
                }
            }
        }
    }
}
