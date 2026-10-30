import XCTest
@testable import ReefCore

final class MarkdownBlocksTests: XCTestCase {
    func testSplitsHeadingsListsAndParagraphs() {
        let text = """
        ## Refactor auth

        1. Extract `TokenStore` from `AuthService`
        2. Add retry with backoff

        Risk: the session cache key changes.
        """
        XCTAssertEqual(MarkdownBlocks.parse(text), [
            .heading(level: 2, text: "Refactor auth"),
            .numbered(number: 1, text: "Extract `TokenStore` from `AuthService`"),
            .numbered(number: 2, text: "Add retry with backoff"),
            .paragraph("Risk: the session cache key changes."),
        ])
    }

    func testBulletsKeepTheirIndent() {
        let text = "- top\n  - nested\n* star form"
        XCTAssertEqual(MarkdownBlocks.parse(text), [
            .bullet(text: "top", indent: 0),
            .bullet(text: "nested", indent: 1),
            .bullet(text: "star form", indent: 0),
        ])
    }

    func testConsecutiveProseLinesJoinIntoOneParagraph() {
        XCTAssertEqual(MarkdownBlocks.parse("one line\nand its continuation\n\nsecond para"), [
            .paragraph("one line and its continuation"),
            .paragraph("second para"),
        ])
    }

    func testFencedCodeIsKeptVerbatim() {
        XCTAssertEqual(MarkdownBlocks.parse("before\n```\nlet x = 1\nlet y = 2\n```\nafter"), [
            .paragraph("before"),
            .code("let x = 1\nlet y = 2"),
            .paragraph("after"),
        ])
    }

    func testEmptyAndWhitespaceOnlyProduceNothing() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("   \n\n  \n"), [])
    }

    func testPlainTextWithNoMarkupIsOneParagraph() {
        XCTAssertEqual(MarkdownBlocks.parse("Fixed the flaky retry test."), [.paragraph("Fixed the flaky retry test.")])
    }
}
