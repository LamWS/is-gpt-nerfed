import Foundation
import XCTest
@testable import IsGPTNerfed

final class LocalizationTests: XCTestCase {
    func testChineseTranslationsAndFormatArguments() {
        XCTAssertEqual(L10n.tr("Match", language: "zh-Hans"), "匹配")
        XCTAssertEqual(L10n.tr("%@ of %@ answers", language: "zh-Hans", arguments: ["2", "3"]), "可用回答 2 / 3")
        XCTAssertEqual(L10n.tr("declared %@", language: "zh-Hans", arguments: ["91%"]), "所选模型 91%")
    }

    func testEnglishFallbackForUnsupportedLanguageAndUnknownKey() {
        XCTAssertEqual(L10n.tr("Match", language: "fr"), "Match")
        XCTAssertEqual(L10n.tr("Unknown future label", language: "fr"), "Unknown future label")
    }

    func testDynamicStatusCountsAndUnknownStatusFallback() {
        XCTAssertEqual(
            L10n.statusMessage("2 downgraded · 1 suspicious · 3 probes running", language: "zh-Hans"),
            "2 个会话降配 · 1 个可疑 · 3 个正在检测"
        )
        XCTAssertEqual(L10n.statusMessage("1 probe running", language: "zh-Hans"), "1 个正在检测")
        XCTAssertEqual(L10n.statusMessage("all clear", language: "fr"), "All clear")
        XCTAssertEqual(L10n.statusMessage("2 downgraded · future state", language: "zh-Hans"), "2 downgraded · future state")
    }

    func testDynamicAgoAndRawEvidenceBoundary() {
        XCTAssertEqual(L10n.localizedAgo("59s ago", language: "zh-Hans"), "59 秒前")
        XCTAssertEqual(L10n.localizedAgo("12m ago", language: "zh-Hans"), "12 分钟前")
        XCTAssertEqual(L10n.localizedAgo("3h ago", language: "zh-Hans"), "3 小时前")
        XCTAssertEqual(L10n.localizedAgo("2d ago", language: "zh-Hans"), "2 天前")
        XCTAssertEqual(L10n.localizedAgo("waiting for a new state", language: "zh-Hans"), "waiting for a new state")

        let evidence = "Silent model change: gpt-6-astra → gpt-reserve"
        XCTAssertEqual(
            L10n.evidenceText(evidence, ago: "2m ago", active: false, language: "zh-Hans"),
            "\(evidence) · 2 分钟前 · 已还原"
        )
    }
}
