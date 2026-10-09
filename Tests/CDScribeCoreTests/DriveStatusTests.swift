// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
import NativeDisc
@testable import CDScribeCore

@Suite("Native drive status") struct DriveStatusTests {
    func status(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    func speeds(_ object: [String: Any]) throws -> [Double] {
        try JSONDecoder().decode([Double].self, from: CDNativeDisc.speedSnapshot(status(object)))
    }
    @Test func insertedSuperDriveMediaReportsNestedSpeeds() throws {
        let json = try status(["DRDeviceMediaInfoKey": ["DRDeviceBurnSpeedsKey": [1764, 2822, 4233]]])
        #expect(try JSONDecoder().decode([Double].self, from: CDNativeDisc.speedSnapshot(json)) == [10, 16, 24])
        #expect(CDNativeDisc.requestedSpeed(10, statusJSON: json)?.doubleValue == 1764)
        #expect(CDNativeDisc.requestedSpeed(16, statusJSON: json)?.doubleValue == 2822)
        #expect(CDNativeDisc.requestedSpeed(24, statusJSON: json)?.doubleValue == 4233)
        for unknown in [0.0, 4, 8, 32, .infinity, .nan] { #expect(CDNativeDisc.requestedSpeed(unknown, statusJSON: json) == nil) }
    }
    @Test func emptyMediaSpeedsOverrideOlderTopLevelData() throws {
        #expect(try speeds(["DRDeviceMediaInfoKey": ["DRDeviceBurnSpeedsKey": []], "DRDeviceBurnSpeedsKey": [1764]]) == [])
        #expect(try speeds(["DRDeviceBurnSpeedsKey": [1764, 2822]]) == [10, 16])
        #expect(try speeds([:]) == [])
        #expect(try speeds(["DRDeviceMediaInfoKey": ["DRDeviceBurnSpeedsKey": "not an array"]]) == [])
    }
    @Test func onlyActualPositiveReportedRatesAreUsed() throws {
        #expect(try speeds(["DRDeviceMediaInfoKey": ["DRDeviceBurnSpeedsKey": [0, -1, "4233", 1764]]]) == [10])
        let reported = try speeds(["DRDeviceBurnSpeedsKey": [2000]])
        #expect(reported.count == 1)
        #expect(abs(reported[0] - 2000 / 176.4) < 0.00001)
        #expect(reported[0] != 11)
    }
    @Test func mediaConstantsBecomeUsableCDTypesAndReadyState() throws {
        #expect(CDNativeDisc.mediaLabel("DRDeviceMediaTypeCDR") == "CD-R")
        #expect(CDNativeDisc.mediaLabel("DRDeviceMediaTypeCDRW") == "CD-RW")
        #expect(CDNativeDisc.mediaLabel("DRDeviceMediaTypeCDROM") == "CD-ROM")
        let json = try status(["id": "writer", "name": "SuperDrive", "bsdName": "disk8", "present": true, "blank": true, "busy": false, "mediaType": CDNativeDisc.mediaLabel("DRDeviceMediaTypeCDR"), "capacity": 359844, "cdText": true, "sao": true, "speeds": [10,16,24]])
        var drive = try JSONDecoder().decode(DiscDrive.self, from: json)
        #expect(drive.ready)
        drive.blank = false; #expect(!drive.ready)
        drive.blank = true; drive.mediaType = "DVD-R"; #expect(!drive.ready)
    }
}
