import XCTest
@testable import GameTranslator

final class TranslationCacheTests: XCTestCase {
    func testStoresAndReturnsTranslation() async {
        let cache = TranslationCache()
        await cache.set("Hello", translation: "สวัสดี", provider: "test")

        let value = await cache.get("Hello")
        let contains = await cache.contains("Hello")
        XCTAssertEqual(value, "สวัสดี")
        XCTAssertTrue(contains)
    }

    func testMissingKeyReturnsNil() async {
        let cache = TranslationCache()
        let value = await cache.get("missing")
        XCTAssertNil(value)
    }

    func testEvictsLeastRecentlyUsed() async {
        let cache = TranslationCache(maxEntries: 2)
        await cache.set("a", translation: "A", provider: "test")
        await cache.set("b", translation: "B", provider: "test")
        _ = await cache.get("a")            // "b" is now least recently used
        await cache.set("c", translation: "C", provider: "test")

        let a = await cache.get("a")
        let b = await cache.get("b")
        let c = await cache.get("c")
        let count = await cache.count
        XCTAssertEqual(a, "A")
        XCTAssertNil(b)
        XCTAssertEqual(c, "C")
        XCTAssertEqual(count, 2)
    }

    func testOverwritingDoesNotGrowCache() async {
        let cache = TranslationCache(maxEntries: 2)
        await cache.set("a", translation: "1", provider: "test")
        await cache.set("a", translation: "2", provider: "test")

        let value = await cache.get("a")
        let count = await cache.count
        XCTAssertEqual(value, "2")
        XCTAssertEqual(count, 1)
    }

    func testClear() async {
        let cache = TranslationCache()
        await cache.set("a", translation: "A", provider: "test")
        await cache.clear()

        let count = await cache.count
        let stats = await cache.stats
        XCTAssertEqual(count, 0)
        XCTAssertNil(stats.oldestAge)
    }
}
