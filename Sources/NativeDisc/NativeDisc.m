// SPDX-License-Identifier: GPL-3.0-or-later
#import "NativeDisc.h"
#import <DiscRecording/DiscRecording.h>
#import <IOKit/storage/IOCDMediaBSDClient.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <math.h>

static BOOL CDFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"CDScribe.DiscRecording" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}
static NSData *CDJSON(id value) { return [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil]; }
static NSString *CDMediaLabel(NSString *type) {
    if ([type isEqual:DRDeviceMediaTypeCDR]) return @"CD-R";
    if ([type isEqual:DRDeviceMediaTypeCDRW]) return @"CD-RW";
    if ([type isEqual:DRDeviceMediaTypeCDROM]) return @"CD-ROM";
    return type ?: @"Unknown";
}
static NSArray<NSDictionary *> *CDSpeedEntries(NSDictionary *status) {
    // Current macOS places this list inside DRDeviceMediaInfoKey. Older layouts
    // may have it at the top level. An explicitly empty media list is authoritative.
    id media = status[DRDeviceMediaInfoKey];
    id reported = [media isKindOfClass:NSDictionary.class] ? media[DRDeviceBurnSpeedsKey] : nil;
    if (!reported) reported = status[DRDeviceBurnSpeedsKey];
    if (![reported isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *entries = [NSMutableArray array];
    for (id value in reported) {
        if (![value isKindOfClass:NSNumber.class]) continue;
        double rate = [value doubleValue];
        if (!isfinite(rate) || rate <= 0) continue;
        double multiplier = rate / DRDeviceBurnSpeedCD1x;
        double nominal = round(multiplier);
        // The device reports integer KB/s (e.g. 2822 instead of 2822.4 at 16x).
        // Normalize only within that 1 KB/s quantization; retain the exact device
        // rate for DRBurnRequestedSpeedKey rather than sending a reconstructed rate.
        if (nominal > 0 && fabs(rate - nominal * DRDeviceBurnSpeedCD1x) <= 1.0) multiplier = nominal;
        [entries addObject:@{@"multiplier": @(multiplier), @"rate": @(rate)}];
    }
    return entries;
}
static NSArray<NSNumber *> *CDSpeedOptions(NSDictionary *status) {
    NSMutableArray *speeds = [NSMutableArray array];
    for (NSDictionary *entry in CDSpeedEntries(status)) [speeds addObject:entry[@"multiplier"]];
    return speeds;
}
static NSNumber *CDRequestedSpeed(double speed, NSDictionary *status) {
    if (!isfinite(speed) || speed <= 0) return nil;
    for (NSDictionary *entry in CDSpeedEntries(status)) {
        if ([entry[@"multiplier"] doubleValue] == speed) return entry[@"rate"];
    }
    return nil;
}
static DRCDTextBlock *CDTextBlock(NSData *json, NSError **error) {
    NSDictionary *text = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    if (![text isKindOfClass:NSDictionary.class]) { CDFail(error, @"Invalid CD-Text description."); return nil; }
    NSStringEncoding encoding = [text[@"encoding"] isEqual:@"latin1"] ? NSISOLatin1StringEncoding : NSASCIIStringEncoding;
    DRCDTextBlock *block = [[DRCDTextBlock alloc] initWithLanguage:@"en" encoding:encoding];
    NSMutableArray *dictionaries = [NSMutableArray arrayWithObject:@{DRCDTextTitleKey: text[@"title"], DRCDTextPerformerKey: text[@"performer"]}];
    for (NSDictionary *track in text[@"tracks"]) {
        [dictionaries addObject:@{DRCDTextTitleKey: track[@"title"], DRCDTextPerformerKey: track[@"performer"]}];
    }
    [block setTrackDictionaries:dictionaries];
    if (![[block trackDictionaries] isEqual:dictionaries]) {
        CDFail(error, @"DiscRecording would alter the CD-Text characters. Choose ASCII/transliteration and review the preview."); return nil;
    }
    NSUInteger truncated = [block flatten];
    if (truncated != 0) { CDFail(error, [NSString stringWithFormat:@"CD-Text exceeds the on-disc block capacity by %lu bytes. Shorten the affected text before burning.", (unsigned long)truncated]); return nil; }
    return block;
}
static NSArray *CDTracks(NSArray<NSString *> *paths, NSArray<NSNumber *> *sectors, NSArray<NSNumber *> *gaps, NSArray *metadata, BOOL verify, NSError **error) {
    if (paths.count != sectors.count || (gaps && paths.count != gaps.count)) { CDFail(error, @"Native audio layout count mismatch."); return nil; }
    NSMutableArray *tracks = [NSMutableArray array];
    for (NSUInteger i = 0; i < paths.count; i++) {
        DRTrack *track = [DRTrack trackForAudioFile:paths[i]];
        if (!track || [track estimateLength] != [sectors[i] unsignedLongLongValue]) {
            CDFail(error, [NSString stringWithFormat:@"DiscRecording cannot read the prepared WAV or reports a different length for track %lu.", (unsigned long)i + 1]); return nil;
        }
        NSMutableDictionary *properties = [[track properties] mutableCopy];
        properties[DRPreGapLengthKey] = gaps ? gaps[i] : @0;
        properties[DRPreGapIsRequiredKey] = @YES;
        properties[DRVerificationTypeKey] = verify ? DRVerificationTypeProduceAgain : DRVerificationTypeNone;
        NSString *isrc = metadata ? metadata[i][@"isrc"] : @"";
        if (isrc.length) properties[DRTrackISRCKey] = [isrc dataUsingEncoding:NSASCIIStringEncoding];
        [track setProperties:properties];
        [tracks addObject:track];
    }
    return tracks;
}

@implementation CDNativeDisc {
    DRBurn *_burn;
    NSArray *_tracks;
    BOOL _sawVerification;
    BOOL _requestedVerification;
}
+ (NSData *)speedSnapshot:(NSData *)json {
    id status = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    return CDJSON(CDSpeedOptions([status isKindOfClass:NSDictionary.class] ? status : @{}));
}
+ (NSString *)mediaLabel:(NSString *)rawType { return CDMediaLabel(rawType); }
+ (NSNumber *)requestedSpeed:(double)speed statusJSON:(NSData *)json {
    id status = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    return CDRequestedSpeed(speed, [status isKindOfClass:NSDictionary.class] ? status : @{});
}
+ (NSData *)driveSnapshot {
    NSMutableArray *drives = [NSMutableArray array];
    for (DRDevice *device in [DRDevice devices]) {
        if (![device isValid] || ![device writesCD]) continue;
        NSDictionary *capabilities = [device info][DRDeviceWriteCapabilitiesKey] ?: @{};
        NSDictionary *status = [device status] ?: @{};
        BOOL present = [device mediaIsPresent];
        NSArray *speeds = present ? CDSpeedOptions(status) : @[];
        [drives addObject:@{
            @"id": [device ioRegistryEntryPath] ?: @"",
            @"name": [device displayName] ?: @"Optical writer",
            @"bsdName": [device bsdName] ?: @"",
            @"present": @(present), @"blank": @((BOOL)(present && [device mediaIsBlank])),
            @"busy": @((BOOL)([device mediaIsBusy] || [device mediaIsTransitioning])),
            @"mediaType": present ? CDMediaLabel([device mediaType]) : @"No media",
            @"capacity": present ? @([[device mediaSpaceFree] sectors]) : @0,
            @"cdText": @([capabilities[DRDeviceCanWriteCDTextKey] boolValue]),
            @"sao": @([capabilities[DRDeviceCanWriteCDSAOKey] boolValue]),
            @"speeds": speeds
        }];
    }
    return CDJSON(drives);
}
+ (NSData *)validatedText:(NSData *)json error:(NSError **)error {
    DRCDTextBlock *block = CDTextBlock(json, error);
    return block ? CDJSON([block trackDictionaries]) : nil;
}
+ (BOOL)validateAudioPaths:(NSArray<NSString *> *)paths sectors:(NSArray<NSNumber *> *)sectors error:(NSError **)error {
    return CDTracks(paths, sectors, nil, nil, NO, error) != nil;
}
+ (NSData *)readTextForDevice:(NSString *)identifier error:(NSError **)error {
    DRDevice *device = [DRDevice deviceForIORegistryEntryPath:identifier];
    NSString *bsd = [device bsdName];
    if (!device || ![device mediaIsPresent] || !bsd.length) { CDFail(error, @"No readable disc is available for CD-Text readback."); return nil; }
    NSString *path = [@"/dev/r" stringByAppendingString:bsd];
    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) { CDFail(error, [NSString stringWithFormat:@"Cannot open %@ for CD-Text readback: %s", path, strerror(errno)]); return nil; }
    uint8_t buffer[65535] = {0};
    dk_cd_read_toc_t request = {0};
    request.format = kCDTOCFormatTEXT; request.buffer = buffer; request.bufferLength = sizeof(buffer);
    int result = ioctl(fd, DKIOCCDREADTOC, &request); int savedError = errno; close(fd);
    if (result != 0) { CDFail(error, [NSString stringWithFormat:@"This drive could not read CD-Text: %s", strerror(savedError)]); return nil; }
    if (request.bufferLength < 4) { CDFail(error, @"The drive returned no CD-Text."); return nil; }
    NSUInteger length = ((NSUInteger)buffer[0] << 8 | buffer[1]) + 2;
    if (length > request.bufferLength || length <= 4 || (length - 4) % 18 != 0) { CDFail(error, @"The drive returned malformed or empty CD-Text packs."); return nil; }
    NSData *packs = [NSData dataWithBytes:buffer length:length];
    NSArray *blocks = [DRCDTextBlock arrayOfCDTextBlocksFromPacks:packs];
    if (!blocks.count) { CDFail(error, @"No CD-Text block could be decoded from the disc."); return nil; }
    return CDJSON([blocks[0] trackDictionaries]);
}
- (BOOL)startDevice:(NSString *)identifier paths:(NSArray<NSString *> *)paths sectors:(NSArray<NSNumber *> *)sectors gaps:(NSArray<NSNumber *> *)gaps text:(NSData *)json speed:(double)speed verify:(BOOL)verify error:(NSError **)error {
    if (_burn) { CDFail(error, @"A burn is already active."); return NO; }
    DRDevice *device = [DRDevice deviceForIORegistryEntryPath:identifier];
    if (!device || ![device isValid] || ![device writesCD]) return CDFail(error, @"The selected CD writer is no longer available.");
    NSDictionary *caps = [device info][DRDeviceWriteCapabilitiesKey];
    if (![caps[DRDeviceCanWriteCDTextKey] boolValue] || ![caps[DRDeviceCanWriteCDSAOKey] boolValue]) return CDFail(error, @"The drive does not advertise CD-Text and session-at-once writing. CDScribe will not silently omit CD-Text.");
    if (![device mediaIsPresent] || ![device mediaIsBlank] || [device mediaIsBusy] || [device mediaIsTransitioning]) return CDFail(error, @"Insert an idle blank CD-R or CD-RW into the selected writer.");
    if (![[device mediaType] isEqual:DRDeviceMediaTypeCDR] && ![[device mediaType] isEqual:DRDeviceMediaTypeCDRW]) return CDFail(error, @"Audio CDs require CD-R or CD-RW media.");
    uint64_t needed = 0;
    for (NSUInteger i = 0; i < sectors.count; i++) needed += [sectors[i] unsignedLongLongValue] + [gaps[i] unsignedLongLongValue];
    if (needed > [[device mediaSpaceFree] sectors]) return CDFail(error, @"The inserted disc has insufficient capacity. Nothing has been written.");
    DRCDTextBlock *block = CDTextBlock(json, error); if (!block) return NO;
    NSDictionary *text = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    _tracks = CDTracks(paths, sectors, gaps, text[@"tracks"], verify, error); if (!_tracks) return NO;
    // Re-read current media speeds immediately before starting the writer.
    NSNumber *requestedRate = CDRequestedSpeed(speed, [device status]);
    if (!requestedRate) return CDFail(error, @"The chosen speed is not supported by the current writer and disc. Refresh the writer status and select a reported speed. Nothing has been written.");
    _burn = [[DRBurn alloc] initWithDevice:device];
    NSMutableDictionary *properties = [[_burn properties] mutableCopy];
    properties[DRCDTextKey] = @[block]; properties[DRBurnAppendableKey] = @NO;
    properties[DRBurnOverwriteDiscKey] = @NO; properties[DRBurnVerifyDiscKey] = @(verify);
    properties[DRBurnUnderrunProtectionKey] = @YES;
    properties[DRBurnStrategyKey] = DRBurnStrategyCDSAO; properties[DRBurnStrategyIsRequiredKey] = @YES;
    properties[DRBurnCompletionActionKey] = DRBurnCompletionActionMount;
    properties[DRBurnFailureActionKey] = DRBurnFailureActionNone;
    properties[DRBurnRequestedSpeedKey] = requestedRate;
    [_burn setProperties:properties];
    _sawVerification = NO; _requestedVerification = verify;
    [_burn writeLayout:_tracks];
    return YES;
}
- (NSData *)burnStatus {
    NSDictionary *status = [_burn status] ?: @{};
    NSString *state = status[DRStatusStateKey] ?: @"None";
    if ([state isEqual:DRStatusStateVerifying]) _sawVerification = YES;
    NSString *phase = [state isEqual:DRStatusStateVerifying] ? @"Verifying" :
        (([state isEqual:DRStatusStateFinishing] || [state isEqual:DRStatusStateSessionClose] || [state isEqual:DRStatusStateTrackClose]) ? @"Finalizing" : @"Burning");
    NSDictionary *error = status[DRErrorStatusKey] ?: @{};
    NSString *message = error[DRErrorStatusErrorStringKey] ?: @"";
    NSString *info = error[DRErrorStatusErrorInfoStringKey] ?: @"";
    NSMutableDictionary *result = [@{
        @"state": state, @"phase": phase, @"done": @([state isEqual:DRStatusStateDone]), @"failed": @([state isEqual:DRStatusStateFailed]),
        @"verificationObserved": @(_sawVerification), @"verificationRequested": @(_requestedVerification),
        @"error": [NSString stringWithFormat:@"%@ %@", message, info]
    } mutableCopy];
    if (status[DRStatusPercentCompleteKey]) result[@"fraction"] = status[DRStatusPercentCompleteKey];
    return CDJSON(result);
}
- (void)abort { [_burn abort]; }
@end
