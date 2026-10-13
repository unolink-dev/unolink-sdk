// The bridge's declaration lives here, not in a public header: the pod also compiles Swift (the SDK), and Swift must
// never import React Native's C++ codegen headers through this pod's umbrella header.
#import <RNUnolinkSpec/RNUnolinkSpec.h>

/// React Native bridge to the Unolink iOS SDK (the Swift `Unolink` class, compiled into this pod).
@interface RNUnolink : NativeRNUnolinkSpecBase <NativeRNUnolinkSpec>
@end

// The Swift SDK compiled into this pod, through its generated Objective-C header.
#if __has_include(<UnolinkReactNative/UnolinkReactNative-Swift.h>)
#import <UnolinkReactNative/UnolinkReactNative-Swift.h>
#else
#import "UnolinkReactNative-Swift.h"
#endif

static UNLLogLevel UNLLogLevelFrom(NSString *name) {
  if ([name isEqualToString:@"none"]) return UNLLogLevelNone;
  if ([name isEqualToString:@"error"]) return UNLLogLevelError;
  if ([name isEqualToString:@"info"]) return UNLLogLevelInfo;
  if ([name isEqualToString:@"debug"]) return UNLLogLevelDebug;
  return UNLLogLevelWarn;
}

@implementation RNUnolink

RCT_EXPORT_MODULE(RNUnolink)

- (void)configure:(NSString *)apiKey
          baseUrl:(NSString *)baseUrl
         logLevel:(NSString *)logLevel
            debug:(BOOL)debug
       sdkVersion:(NSString *)sdkVersion
{
  UNLOptions *options = [[UNLOptions alloc] initWithBaseURL:(baseUrl.length > 0 ? baseUrl : UNLOptions.defaultBaseURL)
                                                   logLevel:UNLLogLevelFrom(logLevel)
                                                      debug:debug];
  [Unolink configureWithApiKey:apiKey options:options sdkName:@"react-native" sdkVersion:sdkVersion];
  __weak RNUnolink *weakSelf = self;
  [Unolink onDeferredDeepLink:^(UNLDeepLink *link) {
    [weakSelf emitOnDeferredDeepLink:@{
      @"deepLink": link.deepLink ?: [NSNull null],
      @"params": link.params ?: @{},
      @"linkSlug": link.linkSlug ?: [NSNull null],
      @"clickId": link.clickId,
    }];
  }];
}

- (void)track:(NSString *)name properties:(NSDictionary *)properties
{
  [Unolink track:name properties:properties];
}

- (void)purchase:(NSString *)amount currency:(NSString *)currency productId:(NSString *)productId properties:(NSDictionary *)properties
{
  NSDecimalNumber *value = [NSDecimalNumber decimalNumberWithString:amount locale:@{NSLocaleDecimalSeparator: @"."}];
  if ([value isEqualToNumber:[NSDecimalNumber notANumber]]) {
    NSLog(@"[Unolink] purchase(): amount \"%@\" is not a number. Not recorded.", amount);
    return;
  }
  [Unolink purchaseWithAmount:value currency:currency productId:productId properties:properties];
}

- (void)setUserId:(NSString *)userId
{
  [Unolink setUserId:userId];
}

- (void)flush
{
  [Unolink flush];
}

- (void)setEnabled:(BOOL)enabled
{
  [Unolink setEnabled:enabled];
}

- (NSString *)getInstallId
{
  return Unolink.installId;
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeRNUnolinkSpecJSI>(params);
}

@end
