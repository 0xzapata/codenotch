import Foundation

/// Parses the `/api/ps` payload from a local Ollama daemon (`http://127.0.0.1:11434/api/ps`),
/// representing models currently loaded into memory or VRAM.
enum OllamaLocalUsage {
    struct PSResponse: Decodable {
        let models: [LoadedModel]?
    }

    struct LoadedModel: Decodable {
        let name: String
        let model: String
        let size: Int64?
        let digest: String?
        let expiresAt: String?
        let sizeVram: Int64?
        let details: ModelDetails?

        enum CodingKeys: String, CodingKey {
            case name, model, size, digest, details
            case expiresAt = "expires_at"
            case sizeVram = "size_vram"
        }
    }

    struct ModelDetails: Decodable {
        let parentModel: String?
        let format: String?
        let family: String?
        let families: [String]?
        let parameterSize: String?
        let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case parentModel = "parent_model"
            case format, family, families
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    /// Converts the `/api/ps` payload into Codenotch limit windows.
    static func windows(from data: Data) throws -> [LimitWindow] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(PSResponse.self, from: data)
        guard let models = response.models, !models.isEmpty else {
            // Idle state: Ollama daemon is active, but no model is currently in memory
            return [
                LimitWindow(
                    id: "ollama.idle",
                    label: "Local Models",
                    usedFraction: 0,
                    remaining: nil,
                    used: nil,
                    resetsAt: nil
                )
            ]
        }

        var windows: [LimitWindow] = []
        for (index, m) in models.enumerated() {
            let expirationDate = m.expiresAt.flatMap(parseISO8601)
            let memBytes = memoryBytes(for: m)
            let memGB = Int(memBytes / (1024 * 1024 * 1024))
            let id = index == 0 ? "ollama.primary" : "ollama.\(m.name)"

            windows.append(LimitWindow(
                id: id,
                label: m.name,
                usedFraction: 1.0, // Active in memory
                remaining: nil,
                used: memGB > 0 ? memGB : 1,
                resetsAt: expirationDate
            ))
        }
        return windows
    }

    /// Resolves memory bytes, preferring VRAM when > 0, falling back to model size in system RAM.
    static func memoryBytes(for model: LoadedModel) -> Int64 {
        if let vram = model.sizeVram, vram > 0 {
            return vram
        }
        return model.size ?? 0
    }

    /// Formats bytes into a human-readable VRAM or memory size string.
    static func formatMemory(_ bytes: Int64, isVram: Bool = true) -> String {
        let label = isVram ? "VRAM" : "RAM"
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB %@", locale: Locale(identifier: "en_US_POSIX"), gb, label)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB %@", locale: Locale(identifier: "en_US_POSIX"), mb, label)
    }

    /// Formats bytes into a human-readable VRAM string (convenience helper).
    static func formatVRAM(_ bytes: Int64) -> String {
        formatMemory(bytes, isVram: true)
    }

    /// Parses an ISO8601 string, handling fractional seconds or timezone offsets.
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
