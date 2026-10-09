// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@preconcurrency import NativeDisc

public struct VerificationService: Sendable {
    public init() {}
    public func readText(deviceID: String) async throws -> String {
        let data = try await Task.detached { try CDNativeDisc.readText(forDevice: deviceID) }.value
        return String(decoding: data, as: UTF8.self)
    }
    public func verifyText(deviceID: String, expected: CDText) async throws {
        let expectedBytes = try NativeBurningService.validateText(expected)
        let readBytes = try await Task.detached { try CDNativeDisc.readText(forDevice: deviceID) }.value
        guard let expectedRows = try JSONSerialization.jsonObject(with: expectedBytes) as? [[String: String]],
              let actualRows = try JSONSerialization.jsonObject(with: readBytes) as? [[String: Any]],
              actualRows.count == expectedRows.count else { throw CDScribeError.message("CD-Text readback track count differs from the preview.") }
        for (index, row) in expectedRows.enumerated() {
            for (key, value) in row where (actualRows[index][key] as? String) != value {
                throw CDScribeError.message("On-disc CD-Text differs at disc/track \(index), field \(key). Expected “\(value)”.")
            }
        }
    }
}
