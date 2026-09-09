import XCTest
@testable import Codenotch

final class OllamaLocalUsageTests: XCTestCase {
    private let activeModelJSON = """
    {
      "models": [
        {
          "name": "llama3.2:3b",
          "model": "llama3.2:3b",
          "size": 2019393189,
          "digest": "a80c4f17acd55704e6c1e309fb13f360ae31d3d6",
          "expires_at": "2026-09-08T18:06:07.541672-04:00",
          "size_vram": 2019393189,
          "details": {
            "parent_model": "",
            "format": "gguf",
            "family": "llama",
            "families": ["llama"],
            "parameter_size": "3.2B",
            "quantization_level": "Q4_K_M"
          }
        }
      ]
    }
    """

    private let multiModelJSON = """
    {
      "models": [
        {
          "name": "qwen2.5-coder:7b",
          "model": "qwen2.5-coder:7b",
          "size": 4700000000,
          "size_vram": 4700000000,
          "expires_at": "2026-09-08T19:00:00.000Z"
        },
        {
          "name": "deepseek-coder:6.7b",
          "model": "deepseek-coder:6.7b",
          "size": 3900000000,
          "size_vram": 3900000000,
          "expires_at": "2026-09-08T19:30:00.000Z"
        }
      ]
    }
    """

    private let idleJSON = """
    {
      "models": []
    }
    """

    func testActiveSingleModelDecodesCorrectly() throws {
        let data = activeModelJSON.data(using: .utf8)!
        let windows = try OllamaLocalUsage.windows(from: data)

        XCTAssertEqual(windows.count, 1)
        let primary = windows[0]
        XCTAssertEqual(primary.id, "ollama.primary")
        XCTAssertEqual(primary.label, "llama3.2:3b")
        XCTAssertEqual(primary.usedFraction, 1.0)
        XCTAssertEqual(primary.used, 1) // ~1.88 GB rounds to 1 GB int
        XCTAssertNotNil(primary.resetsAt)
    }

    func testMultiModelDecodesAllEntries() throws {
        let data = multiModelJSON.data(using: .utf8)!
        let windows = try OllamaLocalUsage.windows(from: data)

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].id, "ollama.primary")
        XCTAssertEqual(windows[0].label, "qwen2.5-coder:7b")
        XCTAssertEqual(windows[0].used, 4)

        XCTAssertEqual(windows[1].id, "ollama.deepseek-coder:6.7b")
        XCTAssertEqual(windows[1].label, "deepseek-coder:6.7b")
        XCTAssertEqual(windows[1].used, 3)
    }

    func testIdleStateReturnsIdleWindow() throws {
        let data = idleJSON.data(using: .utf8)!
        let windows = try OllamaLocalUsage.windows(from: data)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].id, "ollama.idle")
        XCTAssertEqual(windows[0].label, "Local Models")
        XCTAssertEqual(windows[0].usedFraction, 0.0)
        XCTAssertNil(windows[0].resetsAt)
    }

    func testVRAMFormatting() {
        XCTAssertEqual(OllamaLocalUsage.formatVRAM(8589934592), "8.0 GB VRAM")
        XCTAssertEqual(OllamaLocalUsage.formatVRAM(2147483648), "2.0 GB VRAM")
        XCTAssertEqual(OllamaLocalUsage.formatVRAM(524288000), "500 MB VRAM")
    }

    func testRAMFormatting() {
        XCTAssertEqual(OllamaLocalUsage.formatMemory(2561524365, isVram: false), "2.4 GB RAM")
        XCTAssertEqual(OllamaLocalUsage.formatMemory(524288000, isVram: false), "500 MB RAM")
    }

    func testCPURAMFallbackWhenVRAMZero() throws {
        let cpuJSON = """
        {
          "models": [
            {
              "name": "llama3.2:3b",
              "model": "llama3.2:3b",
              "size": 2561524365,
              "size_vram": 0,
              "expires_at": "2026-09-08T18:06:07.541672-04:00"
            }
          ]
        }
        """
        let data = cpuJSON.data(using: .utf8)!
        let windows = try OllamaLocalUsage.windows(from: data)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].label, "llama3.2:3b")
        XCTAssertEqual(windows[0].used, 2) // ~2.38 GB -> 2 GB
    }

    func testISO8601DateParsing() {
        let parsed = OllamaLocalUsage.parseISO8601("2026-09-08T18:06:07.541672-04:00")
        XCTAssertNotNil(parsed)

        let parsedZulu = OllamaLocalUsage.parseISO8601("2026-09-08T19:00:00Z")
        XCTAssertNotNil(parsedZulu)

        let invalid = OllamaLocalUsage.parseISO8601("not-a-date")
        XCTAssertNil(invalid)
    }
}
