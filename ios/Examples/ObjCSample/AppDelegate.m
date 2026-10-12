#import "AppDelegate.h"
@import Unolink;

/// Calls every public SDK method from Objective-C, so an Objective-C-unfriendly API change fails to compile.
@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UNLOptions *options = [[UNLOptions alloc] initWithBaseURL:@"https://api-uat.unolink.dev" logLevel:UNLLogLevelDebug debug:YES];
    [Unolink configureWithApiKey:@"ulk_REPLACE_WITH_YOUR_KEY_000000000000" options:options];
    [Unolink onDeferredDeepLink:^(UNLDeepLink *link) {
        NSLog(@"Deep link %@ %@ via %@ (%@)", link.deepLink, link.params, link.linkSlug, link.clickId);
    }];

    NSDictionary *properties = @{@"level": @3};
    [Unolink track:@"level_up" properties:properties];
    [Unolink track:@"level_up" properties:nil];
    [Unolink onboardingCompletedWithProperties:nil];
    [Unolink paywallViewedWithPlacement:@"onboarding" properties:nil];
    [Unolink paywallSkippedWithPlacement:nil properties:properties];
    [Unolink signUpWithMethod:@"apple" properties:nil];
    [Unolink trialStartedWithProductId:@"pro_yearly" properties:nil];
    [Unolink purchaseWithAmount:[NSDecimalNumber decimalNumberWithString:@"4.99"] currency:@"USD" productId:@"pro_monthly" properties:nil];
    [Unolink purchaseCancelledWithProductId:nil properties:nil];
    [Unolink purchaseFailedWithProductId:@"pro_monthly" reason:@"card_declined" properties:nil];
    [Unolink setUserId:@"objc-user"];
    [Unolink setUserId:nil];
    [Unolink flush];
    [Unolink setEnabled:YES];
    NSString *installId = Unolink.installId;
    NSString *version = Unolink.sdkVersion;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [UIViewController new];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(UIScreen.mainScreen.bounds, 24, 120)];
    label.numberOfLines = 0;
    label.text = [NSString stringWithFormat:@"Unolink %@\nInstall ID: %@", version, installId ?: @"…"];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    [root.view addSubview:label];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
