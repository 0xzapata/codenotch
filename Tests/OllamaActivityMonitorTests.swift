import XCTest
@testable import Codenotch

final class OllamaActivityMonitorTests: XCTestCase {
    private let activeModelJSON = """
    {
      "models": [
        {
          "name": "llama3.2:3b",
          "model": "llama3.2:3b",
          "size": 2019393189,
          "size_vram": 2019393189,
          "expires_at": "2026-09-08T18:06:07.541672-04:00"
        }
      ]
    }
    """

    private let cpuModelJSON = """
    {
      "models": [
        {
          "name": "qwen2.5-coder:7b",
          "model": "qwen2.5-coder:7b",
          "size": 4700000000,
          "size_vram": 0,
          "expires_at": "2026-09-08T19:00:00.000Z"
        }
      ]
    }
    """

    private let emptyJSON = """
    {
      "models": []
    }
    """

    func testActiveModelCreatesBusySession() throws {
        let data = activeModelJSON.data(using: .utf8)!
        let parsed = try JSONDecoder().decode(OllamaActivityMonitor.PSResponse.self, from: data)
        let sessions = OllamaActivityMonitor.sessions(from: parsed)

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.id, "ollama.llama3.2:3b")
        XCTAssertEqual(session.name, "llama3.2:3b")
        XCTAssertEqual(session.detail, "1.9 GB VRAM")
        XCTAssertEqual(session.state, .busy)
        XCTAssertNil(session.waitingFor)
    }

    func testCPURAMFallbackFormatting() throws {
        let data = cpuModelJSON.data(using: .utf8)!
        let parsed = try JSONDecoder().decode(OllamaActivityMonitor.PSResponse.self, from: data)
        let sessions = OllamaActivityMonitor.sessions(from: parsed)

        XCTAssertEqual(sessions.count, 1)
        let session = sessions[0]
        XCTAssertEqual(session.id, "ollama.qwen2.5-coder:7b")
        XCTAssertEqual(session.name, "qwen2.5-coder:7b")
        XCTAssertEqual(session.detail, "4.4 GB RAM")
        XCTAssertEqual(session.state, .busy)
    }

    func testEmptyModelsReturnsNoSessions() throws {
        let data = emptyJSON.data(using: .utf8)!
        let parsed = try JSONDecoder().decode(OllamaActivityMonitor.PSResponse.self, from: data)
        let sessions = OllamaActivityMonitor.sessions(from: parsed)

        XCTAssertTrue(sessions.isEmpty)
    }

    func testMemoryFormatting() {
        XCTAssertEqual(OllamaActivityMonitor.formatMemory(8589934592, isVram: true), "8.0 GB VRAM")
        XCTAssertEqual(OllamaActivityMonitor.formatMemory(2147483648, isVram: false), "2.0 GB RAM")
        XCTAssertEqual(OllamaActivityMonitor.formatMemory(524288000, isVram: false), "500 MB RAM")
    }
}
