// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface CDNativeDisc : NSObject
+ (NSData *)driveSnapshot;
// Pure status decoding helpers also used by regression tests; no hardware writes.
+ (NSData *)speedSnapshot:(NSData *)json;
+ (NSString *)mediaLabel:(NSString *)rawType;
+ (nullable NSNumber *)requestedSpeed:(double)speed statusJSON:(NSData *)json;
+ (nullable NSData *)validatedText:(NSData *)json error:(NSError **)error;
+ (BOOL)isUnsupportedPregapError:(NSNumber *)code;
+ (BOOL)validateAudioPaths:(NSArray<NSString *> *)paths sectors:(NSArray<NSNumber *> *)sectors gaps:(NSArray<NSNumber *> *)gaps error:(NSError **)error;
+ (nullable NSData *)readTextForDevice:(NSString *)identifier error:(NSError **)error;
- (BOOL)startDevice:(NSString *)identifier paths:(NSArray<NSString *> *)paths sectors:(NSArray<NSNumber *> *)sectors gaps:(NSArray<NSNumber *> *)gaps text:(NSData *)json speed:(double)speed verify:(BOOL)verify error:(NSError **)error;
- (NSData *)burnStatus;
- (void)abort;
@end
NS_ASSUME_NONNULL_END
