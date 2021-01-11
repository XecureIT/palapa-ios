//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ShareAppExtensionContext.h"
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSConstants.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShareAppExtensionContext ()

@property (nonatomic) UIViewController *rootViewController;

@property (atomic) UIApplicationState reportedApplicationState;

@end

#pragma mark -

@implementation ShareAppExtensionContext

@synthesize mainWindow = _mainWindow;
@synthesize appLaunchTime = _appLaunchTime;
@synthesize buildTime = _buildTime;

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(rootViewController);

    _rootViewController = rootViewController;

    self.reportedApplicationState = UIApplicationStateActive;

    _appLaunchTime = [NSDate new];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostDidBecomeActive:)
                                                 name:NSExtensionHostDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostWillResignActive:)
                                                 name:NSExtensionHostWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostDidEnterBackground:)
                                                 name:NSExtensionHostDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHostWillEnterForeground:)
                                                 name:NSExtensionHostWillEnterForegroundNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)extensionHostDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.reportedApplicationState = UIApplicationStateActive;

    [BenchManager benchWithTitle:@"Slow post DidBecomeActive"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationDidBecomeActiveNotification
                                                 object:nil];
                           }];
}

- (void)extensionHostWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    self.reportedApplicationState = UIApplicationStateInactive;

    OWSLogInfo(@"");
    [DDLog flushLog];

    [BenchManager benchWithTitle:@"Slow post WillResignActive"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationWillResignActiveNotification
                                                 object:nil];
                           }];
}

- (void)extensionHostDidEnterBackground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");
    [DDLog flushLog];

    self.reportedApplicationState = UIApplicationStateBackground;

    [BenchManager benchWithTitle:@"Slow post DidEnterBackground"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationDidEnterBackgroundNotification
                                                 object:nil];
                           }];
}

- (void)extensionHostWillEnterForeground:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    self.reportedApplicationState = UIApplicationStateInactive;

    [BenchManager benchWithTitle:@"Slow post WillEnterForeground"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               [NSNotificationCenter.defaultCenter
                                   postNotificationName:OWSApplicationWillEnterForegroundNotification
                                                 object:nil];
                           }];
}

#pragma mark -

- (BOOL)isMainApp
{
    return NO;
}

- (BOOL)isMainAppAndActive
{
    return NO;
}

- (UIApplicationState)mainApplicationStateOnLaunch
{
    OWSFailDebug(@"Not main app.");

    return UIApplicationStateInactive;
}

- (BOOL)isRTL
{
    static BOOL isRTL = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Borrowed from PureLayout's AppExtension compatible RTL support.
        // App Extensions may not access -[UIApplication sharedApplication]; fall back to checking the bundle's
        // preferred localization character direction
        isRTL = [NSLocale characterDirectionForLanguage:[[NSBundle mainBundle] preferredLocalizations][0]]
            == NSLocaleLanguageDirectionRightToLeft;
    });
    return isRTL;
}

- (void)setStatusBarHidden:(BOOL)isHidden animated:(BOOL)isAnimated
{
    OWSLogInfo(@"Ignoring request to show/hide status bar since we're in an app extension");
}

- (CGFloat)statusBarHeight
{
    return 20;
}

- (BOOL)isInBackground
{
    return self.reportedApplicationState == UIApplicationStateBackground;
}

- (BOOL)isAppForegroundAndActive
{
    return self.reportedApplicationState == UIApplicationStateActive;
}

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler
{
    return UIBackgroundTaskInvalid;
}

- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)backgroundTaskIdentifier
{
    OWSAssertDebug(backgroundTaskIdentifier == UIBackgroundTaskInvalid);
}

- (void)ensureSleepBlocking:(BOOL)shouldBeBlocking blockingObjectsDescription:(NSString *)blockingObjectsDescription
{
    OWSLogDebug(@"Ignoring request to block sleep.");
}

- (void)setMainAppBadgeNumber:(NSInteger)value
{
    OWSFailDebug(@"");
}

- (nullable UIViewController *)frontmostViewController
{
    OWSAssertDebug(self.rootViewController);

    return [self.rootViewController findFrontmostViewController:YES];
}

- (nullable ActionSheetAction *)openSystemSettingsActionWithCompletion:(void (^_Nullable)(void))completion
{
    return nil;
}

- (BOOL)isRunningTests
{
    // We don't need to distinguish this in the SAE.
    return NO;
}

- (NSDate *)buildTime
{
    if (!_buildTime) {
        NSInteger buildTimestamp = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BuildTimestamp"] integerValue];

        if (buildTimestamp == 0) {
            // Production builds should _always_ expire, ensure that here.
            OWSAssert(OWSIsDebugBuild());

            OWSLogDebug(@"No build timestamp, assuming app never expires.");
            _buildTime = [NSDate distantFuture];
        } else {
            _buildTime = [NSDate dateWithTimeIntervalSince1970:buildTimestamp];
        }
    }

    return _buildTime;
}

- (CGRect)frame
{
    return self.rootViewController.view.frame;
}

- (UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationPortrait;
}

- (void)setNetworkActivityIndicatorVisible:(BOOL)value
{
    OWSFailDebug(@"");
}

- (void)runNowOrWhenMainAppIsActive:(AppActiveBlock)block
{
    OWSFailDebug(@"cannot run main app active blocks in share extension.");
}

- (id<SSKKeychainStorage>)keychainStorage
{
    return [SSKDefaultKeychainStorage shared];
}

- (NSString *)appDocumentDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentDirectoryURL path];
}

- (NSString *)appSharedDataDirectoryPath
{
    NSURL *groupContainerDirectoryURL =
        [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SignalApplicationGroup];
    return [groupContainerDirectoryURL path];
}

- (NSString *)appDatabaseBaseDirectoryPath
{
    return self.appSharedDataDirectoryPath;
}

- (NSUserDefaults *)appUserDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:SignalApplicationGroup];
}

- (BOOL)canPresentNotifications
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
