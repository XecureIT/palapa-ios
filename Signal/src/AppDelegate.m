//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "ConversationListViewController.h"
#import "DebugLogger.h"
#import "MainAppContext.h"
#import "OWS2FASettingsViewController.h"
#import "OWSBackup.h"
#import "OWSOrphanDataCleaner.h"
#import "OWSScreenLockUI.h"
#import "Pastelog.h"
#import "PALAPA-Swift.h"
#import "SignalApp.h"
#import "ViewControllerUtils.h"
#import "YDBLegacyMigration.h"
#import <Intents/Intents.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/CallKitIdStore.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StickerInfo.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <UserNotifications/UserNotifications.h>
#import <WebRTC/WebRTC.h>

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
static NSString *const kURLSchemeSGNLKey                = @"palapa";
static NSString *const kURLHostVerifyPrefix             = @"verify";
static NSString *const kURLHostAddStickersPrefix = @"addstickers";

static NSTimeInterval launchStartedAt;

typedef NS_ENUM(NSUInteger, LaunchFailure) {
    LaunchFailure_None,
    LaunchFailure_CouldNotLoadDatabase,
    LaunchFailure_UnknownDatabaseVersion,
};

NSString *NSStringForLaunchFailure(LaunchFailure launchFailure)
{
    switch (launchFailure) {
        case LaunchFailure_None:
            return @"LaunchFailure_None";
        case LaunchFailure_CouldNotLoadDatabase:
            return @"LaunchFailure_CouldNotLoadDatabase";
        case LaunchFailure_UnknownDatabaseVersion:
            return @"LaunchFailure_UnknownDatabaseVersion";
    }
}

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@property (nonatomic) BOOL areVersionMigrationsComplete;
@property (nonatomic) BOOL didAppLaunchFail;

@end

#pragma mark -

@implementation AppDelegate

@synthesize window = _window;

#pragma mark - Dependencies

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

- (OWSReadReceiptManager *)readReceiptManager
{
    return [OWSReadReceiptManager sharedManager];
}

- (id<OWSUDManager>)udManager
{
    OWSAssertDebug(SSKEnvironment.shared.udManager);

    return SSKEnvironment.shared.udManager;
}

- (nullable OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
}

- (PushRegistrationManager *)pushRegistrationManager
{
    OWSAssertDebug(AppEnvironment.shared.pushRegistrationManager);

    return AppEnvironment.shared.pushRegistrationManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (OWSDisappearingMessagesJob *)disappearingMessagesJob
{
    OWSAssertDebug(SSKEnvironment.shared.disappearingMessagesJob);

    return SSKEnvironment.shared.disappearingMessagesJob;
}

- (TSSocketManager *)socketManager
{
    OWSAssertDebug(SSKEnvironment.shared.socketManager);

    return SSKEnvironment.shared.socketManager;
}

- (OWSMessageManager *)messageManager
{
    OWSAssertDebug(SSKEnvironment.shared.messageManager);

    return SSKEnvironment.shared.messageManager;
}

- (OWSWindowManager *)windowManager
{
    return Environment.shared.windowManager;
}

- (OWSBackup *)backup
{
    return AppEnvironment.shared.backup;
}

- (OWSNotificationPresenter *)notificationPresenter
{
    return AppEnvironment.shared.notificationPresenter;
}

- (OWSUserNotificationActionHandler *)userNotificationActionHandler
{
    return AppEnvironment.shared.userNotificationActionHandler;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (id<SyncManagerProtocol>)syncManager
{
    OWSAssertDebug(SSKEnvironment.shared.syncManager);

    return SSKEnvironment.shared.syncManager;
}

- (StorageCoordinator *)storageCoordinator
{
    return SSKEnvironment.shared.storageCoordinator;
}

- (LaunchJobs *)launchJobs
{
    return Environment.shared.launchJobs;
}

#pragma mark -

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidEnterBackground.");

    [DDLog flushLog];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillEnterForeground.");
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidReceiveMemoryWarning.");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillTerminate.");

    [DDLog flushLog];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // This should be the first thing we do.
    SetCurrentAppContext([MainAppContext new]);

    launchStartedAt = CACurrentMediaTime();

    BOOL isLoggingEnabled;
#ifdef DEBUG
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    isLoggingEnabled = TRUE;
    [DebugLogger.sharedLogger enableTTYLogging];
#elif RELEASE
    isLoggingEnabled = OWSPreferences.isLoggingEnabled;
#endif
    if (isLoggingEnabled) {
        [DebugLogger.sharedLogger enableFileLogging];
    }
    if (SSKFeatureFlags.audibleErrorLogging) {
        [DebugLogger.sharedLogger enableErrorReporting];
    }

    OWSLogWarn(@"application: didFinishLaunchingWithOptions.");
    [Cryptography seedRandom];

    // XXX - careful when moving this. It must happen before we load YDB and/or GRDB.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    // We need to do this _after_ we set up logging, when the keychain is unlocked,
    // but before we access YapDatabase, files on disk, or NSUserDefaults
    NSError *_Nullable launchError = nil;
    LaunchFailure launchFailure = LaunchFailure_None;

    BOOL isYdbNotReady = ![YDBLegacyMigration ensureIsYDBReadyForAppExtensions:&launchError];
    if (isYdbNotReady || launchError != nil) {
        launchFailure = LaunchFailure_CouldNotLoadDatabase;
    } else if (StorageCoordinator.hasInvalidDatabaseVersion) {
        // Prevent:
        // * Users who have used GRDB revert to using YDB.
        // * Users with an unknown GRDB schema revert to using an earlier GRDB schema.
        launchFailure = LaunchFailure_UnknownDatabaseVersion;
    }
    if (launchFailure != LaunchFailure_None) {
        OWSLogInfo(@"application: didFinishLaunchingWithOptions failed.");
        [self showUIForLaunchFailure:launchFailure];

        return YES;
    }

#if RELEASE
    // ensureIsYDBReadyForAppExtensions may change the state of the logging
    // preference (due to [NSUserDefaults migrateToSharedUserDefaults]), so honor
    // that change if necessary.
    if (isLoggingEnabled && !OWSPreferences.isLoggingEnabled) {
        [DebugLogger.sharedLogger disableFileLogging];
    }
#endif

    [AppVersion sharedInstance];

    [self startupLogging];

    // Prevent the device from sleeping during database view async registration
    // (e.g. long database upgrades).
    //
    // This block will be cleared in storageIsReady.
    [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }
    [AppSetup
        setupEnvironmentWithAppSpecificSingletonBlock:^{
            // Create AppEnvironment.
            [AppEnvironment.shared setup];
            [SignalApp.sharedApp setup];
        }
        migrationCompletion:^{
            OWSAssertIsOnMainThread();

            [self versionMigrationsDidComplete];
        }];

    [UIUtil setupSignalAppearence];

    UIWindow *mainWindow = [OWSWindow new];
    self.window = mainWindow;
    CurrentAppContext().mainWindow = mainWindow;
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    if (@available(iOS 10, *)) {
        // This must happen in appDidFinishLaunching or earlier to ensure we don't
        // miss notifications.
        // Setting the delegate also seems to prevent us from getting the legacy notification
        // notification callbacks upon launch e.g. 'didReceiveLocalNotification'
        UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    }

    // Accept push notification when app is not open
    NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotif) {
        OWSLogInfo(@"Application was launched by tapping a push notification.");
        [self application:application didReceiveRemoteNotification:remoteNotif];
    }

    [OWSScreenLockUI.sharedManager setupWithRootWindow:self.window];
    [[OWSWindowManager sharedManager] setupWithRootWindow:self.window
                                     screenBlockingWindow:OWSScreenLockUI.sharedManager.screenBlockingWindow];
    [OWSScreenLockUI.sharedManager startObserving];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storageIsReady)
                                                 name:StorageIsReadyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationLockDidChange:)
                                                 name:NSNotificationName_2FAStateDidChange
                                               object:nil];

    OWSLogInfo(@"application: didFinishLaunchingWithOptions completed.");

    OWSLogInfo(@"launchOptions: %@.", launchOptions);

    [OWSAnalytics appLaunchDidBegin];

    return YES;
}

/**
 *  The user must unlock the device once after reboot before the database encryption key can be accessed.
 */
- (void)verifyDBKeysAvailableBeforeBackgroundLaunch
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        return;
    }

    // someone currently using yap
    if (StorageCoordinator.hasYdbFile && !SSKPreferences.isYdbMigrated
        && OWSPrimaryStorage.isDatabasePasswordAccessible) {
        return;
    }

    // someone who migrated from yap to grdb needs the GRDB spec
    if (SSKPreferences.isYdbMigrated && GRDBDatabaseStorageAdapter.isKeyAccessible) {
        return;
    }

    // someone who never used yap needs the GRDB spec
    if (!StorageCoordinator.hasYdbFile && StorageCoordinator.hasGrdbFile
        && GRDBDatabaseStorageAdapter.isKeyAccessible) {
        return;
    }

    OWSLogInfo(@"exiting because we are in the background and the database password is not accessible.");

    UILocalNotification *notification = [UILocalNotification new];
    NSString *messageFormat = NSLocalizedString(@"NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
        @"Lock screen notification text presented after user powers on their device without unlocking. Embeds "
        @"{{device model}} (either 'iPad' or 'iPhone')");
    notification.alertBody = [NSString stringWithFormat:messageFormat, UIDevice.currentDevice.localizedModel];

    // Make sure we clear any existing notifications so that they don't start stacking up
    // if the user receives multiple pushes.
    [UIApplication.sharedApplication cancelAllLocalNotifications];
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:0];

    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:1];

    [DDLog flushLog];
    exit(0);
}

- (void)showUIForLaunchFailure:(LaunchFailure)launchFailure
{
    OWSLogInfo(@"launchFailure: %@", NSStringForLaunchFailure(launchFailure));

    // Disable normal functioning of app.
    self.didAppLaunchFail = YES;

    // We perform a subset of the [application:didFinishLaunchingWithOptions:].
    [AppVersion sharedInstance];
    [self startupLogging];

    self.window = [OWSWindow new];

    // Show the launch screen
    UIViewController *viewController = [[UIStoryboard storyboardWithName:@"Launch Screen"
                                                                  bundle:nil] instantiateInitialViewController];
    self.window.rootViewController = viewController;

    [self.window makeKeyAndVisible];

    NSString *alertTitle;
    NSString *alertMessage
        = NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_MESSAGE", @"Message for the 'app launch failed' alert.");
    switch (launchFailure) {
        case LaunchFailure_CouldNotLoadDatabase:
            alertTitle = NSLocalizedString(@"APP_LAUNCH_FAILURE_COULD_NOT_LOAD_DATABASE",
                @"Error indicating that the app could not launch because the database could not be loaded.");
            break;
        case LaunchFailure_UnknownDatabaseVersion:
            alertTitle = NSLocalizedString(@"APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_TITLE",
                @"Error indicating that the app could not launch without reverting unknown database migrations.");
            alertMessage = NSLocalizedString(@"APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_MESSAGE",
                @"Error indicating that the app could not launch without reverting unknown database migrations.");
            break;
        default:
            OWSFailDebug(@"Unknown launch failure.");
            alertTitle
                = NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_TITLE", @"Title for the 'app launch failed' alert.");
            break;
    }

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:alertTitle message:alertMessage];

    [actionSheet
        addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", nil)
                                                     style:ActionSheetActionStyleDefault
                                                   handler:^(ActionSheetAction *_Nonnull action) {
                                                       [Pastelog submitLogsWithCompletion:^{
                                                           OWSFail(@"exiting after sharing debug logs.");
                                                       }];
                                                   }]];
    [viewController presentActionSheet:actionSheet];
}

- (void)startupLogging
{
    OWSLogInfo(@"iOS Version: %@ (%@)",
        [UIDevice currentDevice].systemVersion,
        [NSString stringFromSysctlKey:@"kern.osversion"]);

    NSString *localeIdentifier = [NSLocale.currentLocale objectForKey:NSLocaleIdentifier];
    if (localeIdentifier.length > 0) {
        OWSLogInfo(@"Locale Identifier: %@", localeIdentifier);
    }
    NSString *countryCode = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
    if (countryCode.length > 0) {
        OWSLogInfo(@"Country Code: %@", countryCode);
    }
    NSString *languageCode = [NSLocale.currentLocale objectForKey:NSLocaleLanguageCode];
    if (languageCode.length > 0) {
        OWSLogInfo(@"Language Code: %@", languageCode);
    }

    OWSLogInfo(@"Device Model: %@ (%@)", UIDevice.currentDevice.model, [NSString stringFromSysctlKey:@"hw.machine"]);

    NSDictionary<NSString *, NSString *> *buildDetails =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BuildDetails"];
    OWSLogInfo(@"WebRTC Commit: %@", buildDetails[@"WebRTCCommit"]);
    OWSLogInfo(@"Build XCode Version: %@", buildDetails[@"XCodeVersion"]);
    OWSLogInfo(@"Build OS X Version: %@", buildDetails[@"OSXVersion"]);
    OWSLogInfo(@"Build Cocoapods Version: %@", buildDetails[@"CocoapodsVersion"]);
    OWSLogInfo(@"Build Date/Time: %@", buildDetails[@"DateTime"]);

    OWSLogInfo(@"Build Expires in: %ld days", (long)SSKAppExpiry.daysUntilBuildExpiry);
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogInfo(@"registered vanilla push token");
    [self.pushRegistrationManager didReceiveVanillaPushToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogError(@"failed to register vanilla push token with error: %@", error);
#ifdef DEBUG
    OWSLogWarn(@"We're in debug mode. Faking success for remote registration with a fake push identifier");
    [self.pushRegistrationManager didReceiveVanillaPushToken:[[NSMutableData dataWithLength:32] copy]];
#else
    OWSProdError([OWSAnalyticsEvents appDelegateErrorFailedToRegisterForRemoteNotifications]);
    [self.pushRegistrationManager didFailToReceiveVanillaPushTokenWithError:error];
#endif
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    OWSAssertIsOnMainThread();

    return [self tryToOpenUrl:url];
}

- (BOOL)tryToOpenUrl:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([StickerPackInfo isStickerPackShareUrl:url]) {
        StickerPackInfo *_Nullable stickerPackInfo = [StickerPackInfo parseStickerPackShareUrl:url];
        if (stickerPackInfo == nil) {
            OWSFailDebug(@"Could not parse sticker pack share URL: %@", url);
            return NO;
        }
        return [self tryToShowStickerPackView:stickerPackInfo];
    } else if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![self.tsAccountManager isRegistered]) {
            if (!AppReadiness.isAppReady) {
                OWSFailDebug(@"Ignoring URL; app is not ready.");
                return NO;
            }
            return [SignalApp.sharedApp receivedVerificationCode:[url.path substringFromIndex:1]];
        } else if ([url.host hasPrefix:kURLHostAddStickersPrefix] && [self.tsAccountManager isRegistered]) {
            if (!SSKFeatureFlags.stickerAutoEnable && !SSKFeatureFlags.stickerSend) {
                return NO;
            }
            StickerPackInfo *_Nullable stickerPackInfo = [self parseAddStickersUrl:url];
            if (stickerPackInfo == nil) {
                OWSFailDebug(@"Invalid URL: %@", url);
                return NO;
            }
            return [self tryToShowStickerPackView:stickerPackInfo];
        } else {
            OWSLogVerbose(@"Invalid URL: %@", url);
            OWSFailDebug(@"Unknown URL host: %@", url.host);
        }
    } else {
        OWSFailDebug(@"Unknown URL scheme: %@", url.scheme);
    }

    return NO;
}

- (nullable StickerPackInfo *)parseAddStickersUrl:(NSURL *)url
{
    NSString *_Nullable packIdHex;
    NSString *_Nullable packKeyHex;
    NSURLComponents *components = [NSURLComponents componentsWithString:url.absoluteString];
    for (NSURLQueryItem *queryItem in [components queryItems]) {
        if ([queryItem.name isEqualToString:@"pack_id"]) {
            OWSAssertDebug(packIdHex == nil);
            packIdHex = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"pack_key"]) {
            OWSAssertDebug(packKeyHex == nil);
            packKeyHex = queryItem.value;
        } else {
            OWSLogWarn(@"Unknown query item: %@", queryItem.name);
        }
    }

    return [StickerPackInfo parsePackIdHex:packIdHex packKeyHex:packKeyHex];
}

- (BOOL)tryToShowStickerPackView:(StickerPackInfo *)stickerPackInfo
{
    OWSAssertDebug(!self.didAppLaunchFail);

    if (!SSKFeatureFlags.stickerAutoEnable && !SSKFeatureFlags.stickerSend) {
        OWSFailDebug(@"Ignoring sticker pack URL; stickers not enabled.");
        return NO;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring sticker pack URL; not registered.");
            return;
        }

        StickerPackViewController *packView =
            [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];
        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [packView presentFrom:rootViewController animated:NO];
                                                   }];
        } else {
            [packView presentFrom:rootViewController animated:NO];
        }
    }];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogWarn(@"applicationDidBecomeActive.");
    if (CurrentAppContext().isRunningTests) {
        return;
    }

    [SignalApp.sharedApp ensureRootViewController:launchStartedAt];

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self handleActivation];
    }];

    // Clear all notifications whenever we become active.
    // When opening the app from a notification,
    // AppDelegate.didReceiveLocalNotification will always
    // be called _before_ we become active.
    [self clearAllNotificationsAndRestoreBadgeCount];

    // On every activation, clear old temp directories.
    ClearOldTemporaryDirectories();

    // Ensure that all windows have the correct frame.
    [self.windowManager updateWindowFrames];

    OWSLogInfo(@"applicationDidBecomeActive completed.");
}

- (void)enableBackgroundRefreshIfNecessary
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (OWS2FAManager.sharedManager.is2FAEnabled && [self.tsAccountManager isRegisteredAndReady]) {
            // Ping server once a day to keep-alive 2FA clients.
            const NSTimeInterval kBackgroundRefreshInterval = 24 * 60 * 60;
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:kBackgroundRefreshInterval];
        } else {
            [[UIApplication sharedApplication]
                setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        }
    }];
}

- (void)handleActivation
{
    OWSAssertIsOnMainThread();

    OWSLogWarn(@"handleActivation.");

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RTCInitializeSSL();

        if ([self.tsAccountManager isRegistered]) {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSLogInfo(@"running post launch block for registered user: %@", [self.tsAccountManager localAddress]);

                // Clean up any messages that expired since last launch immediately
                // and continue cleaning in the background.
                [self.disappearingMessagesJob startIfNecessary];

                [self enableBackgroundRefreshIfNecessary];

            });
        } else {
            OWSLogInfo(@"running post launch block for unregistered user.");

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [AppEnvironment.shared.notificationPresenter clearAllNotifications];

            [self.socketManager requestSocketOpen];
        }
    }); // end dispatchOnce for first time we become active

    // Every time we become active...
    if ([self.tsAccountManager isRegistered]) {
        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async block
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.socketManager requestSocketOpen];
            [Environment.shared.contactsManager fetchSystemContactsOnceIfAlreadyAuthorized];
            [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];

            if (![UIApplication sharedApplication].isRegisteredForRemoteNotifications) {
                OWSLogInfo(@"Retrying to register for remote notifications since user hasn't registered yet.");
                // Push tokens don't normally change while the app is launched, so checking once during launch is
                // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                // restart the app, so we check every activation for users who haven't yet registered.
                __unused AnyPromise *promise =
                    [OWSSyncPushTokensJob runWithAccountManager:AppEnvironment.shared.accountManager
                                                    preferences:Environment.shared.preferences];
            }

            // 2FA

            if ([OWS2FAManager sharedManager].hasPending2FASetup) {
                UIViewController *frontmostViewController = UIApplication.sharedApplication.frontmostViewController;
                OWSAssertDebug(frontmostViewController);

                if ([frontmostViewController isKindOfClass:[OWSPinSetupViewController class]]) {
                    // We're already presenting this
                    return;
                }

                OWSPinSetupViewController *setupVC = [[OWSPinSetupViewController alloc] initWithCompletionHandler:^{
                    [frontmostViewController dismissViewControllerAnimated:YES completion:nil];
                }];

                [frontmostViewController
                    presentFullScreenViewController:[[OWSNavigationController alloc] initWithRootViewController:setupVC]
                                           animated:YES
                                         completion:nil];
            } else if ([OWS2FAManager sharedManager].isDueForReminder) {
                UIViewController *frontmostViewController = UIApplication.sharedApplication.frontmostViewController;
                OWSAssertDebug(frontmostViewController);

                UIViewController *reminderVC;
                if (SSKFeatureFlags.pinsForEveryone) {
                    reminderVC = [OWSPinReminderViewController new];
                } else {
                    reminderVC = [OWS2FAReminderViewController wrappedInNavController];
                    reminderVC.modalPresentationStyle = UIModalPresentationFullScreen;
                }

                if ([frontmostViewController isKindOfClass:[reminderVC class]]) {
                    // We're already presenting this
                    return;
                }

                [frontmostViewController presentViewController:reminderVC animated:YES completion:nil];
            }
        });
    }

    OWSLogInfo(@"handleActivation completed.");
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogWarn(@"applicationWillResignActive.");

    [self clearAllNotificationsAndRestoreBadgeCount];

    [DDLog flushLog];
}

- (void)clearAllNotificationsAndRestoreBadgeCount
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        [OWSMessageUtils.sharedManager updateApplicationBadgeCount];
    }];
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        completionHandler(NO);
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (![self.tsAccountManager isRegisteredAndReady]) {
            ActionSheetController *controller = [[ActionSheetController alloc]
                initWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_WELCOME", nil)
                      message:NSLocalizedString(@"REGISTRATION_RESTRICTED_MESSAGE", nil)];

            [controller addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"OK", nil)
                                                                     style:ActionSheetActionStyleDefault
                                                                   handler:^(ActionSheetAction *_Nonnull action) {

                                                                   }]];
            UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
            [fromViewController presentViewController:controller
                                             animated:YES
                                           completion:^{
                                               completionHandler(NO);
                                           }];
            return;
        }

        [SignalApp.sharedApp showNewConversationView];

        completionHandler(YES);
    }];
}

/**
 * Among other things, this is used by "call back" callkit dialog and calling from native contacts app.
 *
 * We always return YES if we are going to try to handle the user activity since
 * we never want iOS to contact us again using a URL.
 *
 * From https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application?language=objc:
 *
 * If you do not implement this method or if your implementation returns NO, iOS tries to
 * create a document for your app to open using a URL.
 */
- (BOOL)application:(UIApplication *)application
    continueUserActivity:(nonnull NSUserActivity *)userActivity
      restorationHandler:(nonnull void (^)(NSArray *_Nullable))restorationHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([userActivity.activityType isEqualToString:@"INStartVideoCallIntent"]) {
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            OWSLogError(@"unexpectedly received INStartVideoCallIntent pre iOS10");
            return NO;
        }

        OWSLogInfo(@"got start video call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartVideoCallIntent class]]) {
            OWSLogError(@"unexpected class for start call video: %@", intent);
            return NO;
        }
        INStartVideoCallIntent *startCallIntent = (INStartVideoCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", startCallIntent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppDidBecomeReady:^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            if (!SSKFeatureFlags.calling) {
                OWSLogInfo(@"Ignoring unsupported activity.");
                return;
            }

            SignalServiceAddress *_Nullable address = [self addressForIntentHandle:handle];
            if (!address.isValid) {
                OWSLogWarn(@"ignoring attempt to initiate video call to unknown user.");
                return;
            }

            // This intent can be received from more than one user interaction.
            //
            // * It can be received if the user taps the "video" button in the CallKit UI for an
            //   an ongoing call.  If so, the correct response is to try to activate the local
            //   video for that call.
            // * It can be received if the user taps the "video" button for a contact in the
            //   contacts app.  If so, the correct response is to try to initiate a new call
            //   to that user - unless there already is another call in progress.
            if (AppEnvironment.shared.callService.currentCall != nil) {
                if ([address isEqualToAddress:AppEnvironment.shared.callService.currentCall.remoteAddress]) {
                    OWSLogWarn(@"trying to upgrade ongoing call to video.");
                    [AppEnvironment.shared.callService handleCallKitStartVideo];
                    return;
                } else {
                    OWSLogWarn(@"ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.");
                    return;
                }
            }

            OutboundCallInitiator *outboundCallInitiator = AppEnvironment.shared.outboundCallInitiator;
            OWSAssertDebug(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithAddress:address];
        }];
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartAudioCallIntent"]) {

        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
            OWSLogError(@"unexpectedly received INStartAudioCallIntent pre iOS10");
            return NO;
        }

        OWSLogInfo(@"got start audio call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartAudioCallIntent class]]) {
            OWSLogError(@"unexpected class for start call audio: %@", intent);
            return NO;
        }
        INStartAudioCallIntent *startCallIntent = (INStartAudioCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", startCallIntent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppDidBecomeReady:^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            if (!SSKFeatureFlags.calling) {
                OWSLogInfo(@"Ignoring unsupported activity.");
                return;
            }

            SignalServiceAddress *_Nullable address = [self addressForIntentHandle:handle];
            if (!address.isValid) {
                OWSLogWarn(@"ignoring attempt to initiate audio call to unknown user.");
                return;
            }

            if (AppEnvironment.shared.callService.currentCall != nil) {
                OWSLogWarn(@"ignoring INStartAudioCallIntent due to ongoing WebRTC call.");
                return;
            }

            OutboundCallInitiator *outboundCallInitiator = AppEnvironment.shared.outboundCallInitiator;
            OWSAssertDebug(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithAddress:address];
        }];
        return YES;

    // On iOS 13, all calls triggered from contacts use this intent
    } else if ([userActivity.activityType isEqualToString:@"INStartCallIntent"]) {
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(13, 0)) {
            OWSLogError(@"unexpectedly received INStartCallIntent pre iOS13");
            return NO;
        }

        OWSLogInfo(@"got start call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        // TODO: iOS 13 – when we're building with the iOS 13 SDK, we should
        // switch this to reference the new `INStartCallIntent` class.
        if (![intent isKindOfClass:NSClassFromString(@"INStartCallIntent")]) {
            OWSLogError(@"unexpected class for start call: %@", intent);
            return NO;
        }

        NSArray<INPerson *> *contacts = [intent performSelector:@selector(contacts)];
        NSString *_Nullable handle = contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", intent);
            return NO;
        }

        [AppReadiness runNowOrWhenAppDidBecomeReady:^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            if (!SSKFeatureFlags.calling) {
                OWSLogInfo(@"Ignoring unsupported activity.");
                return;
            }

            SignalServiceAddress *_Nullable address = [self addressForIntentHandle:handle];
            if (!address.isValid) {
                OWSLogWarn(@"ignoring attempt to initiate call to unknown user.");
                return;
            }

            if (AppEnvironment.shared.callService.currentCall != nil) {
                OWSLogWarn(@"ignoring INStartCallIntent due to ongoing WebRTC call.");
                return;
            }

            OutboundCallInitiator *outboundCallInitiator = AppEnvironment.shared.outboundCallInitiator;
            OWSAssertDebug(outboundCallInitiator);
            [outboundCallInitiator initiateCallWithAddress:address];
        }];
        return YES;
    } else if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        if (userActivity.webpageURL == nil) {
            OWSFailDebug(@"Missing webpageURL.");
            return NO;
        }
        return [self tryToOpenUrl:userActivity.webpageURL];
    } else {
        OWSLogWarn(@"userActivity: %@, but not yet supported.", userActivity.activityType);
    }

    // TODO Something like...
    // *phoneNumber = [[[[[[userActivity interaction] intent] contacts] firstObject] personHandle] value]
    // thread = blah
    // [callUIAdapter startCall:thread]
    //
    // Here's the Speakerbox Example for intent / NSUserActivity handling:
    //
    //    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
    //        guard let handle = userActivity.startCallHandle else {
    //            print("Could not determine start call handle from user activity: \(userActivity)")
    //            return false
    //        }
    //
    //        guard let video = userActivity.video else {
    //            print("Could not determine video from user activity: \(userActivity)")
    //            return false
    //        }
    //
    //        callManager.startCall(handle: handle, video: video)
    //        return true
    //    }

    return NO;
}

- (nullable SignalServiceAddress *)addressForIntentHandle:(NSString *)handle
{
    OWSAssertDebug(handle.length > 0);

    if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
        SignalServiceAddress *_Nullable address = [CallKitIdStore addressForCallKitId:handle];
        if (!address.isValid) {
            OWSLogWarn(@"ignoring attempt to initiate audio call to unknown anonymous signal user.");
            return nil;
        }
        return address;
    }

    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:handle
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {
        return [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber.toE164];
    }
    return nil;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window
{
    if (self.didAppLaunchFail) {
        return UIInterfaceOrientationMaskPortrait;
    }

    if (self.hasCall) {
        OWSLogInfo(@"has call");
        // The call-banner window is only suitable for portrait display on iPhone
        if (!UIDevice.currentDevice.isIPad) {
            return UIInterfaceOrientationMaskPortrait;
        }
    }

    UIViewController *_Nullable rootViewController = self.window.rootViewController;
    if (!rootViewController) {
        return UIDevice.currentDevice.defaultSupportedOrienations;
    }
    return rootViewController.supportedInterfaceOrientations;
}

- (BOOL)hasCall
{
    return self.windowManager.hasCall;
}

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }
    if (!(AppReadiness.isAppReady && [self.tsAccountManager isRegisteredAndReady])) {
        OWSLogInfo(@"Ignoring remote notification; app not ready.");
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];
    }];
}

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }
    if (!(AppReadiness.isAppReady && [self.tsAccountManager isRegisteredAndReady])) {
        OWSLogInfo(@"Ignoring remote notification; app not ready.");
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            completionHandler(UIBackgroundFetchResultNewData);
        });
    }];
}

- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    OWSLogInfo(@"performing background fetch");
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        __block AnyPromise *job = [AppEnvironment.shared.messageFetcherJob run].then(^{
            // HACK: Call completion handler after n seconds.
            //
            // We don't currently have a convenient API to know when message fetching is *done* when
            // working with the websocket.
            //
            // We *could* substantially rewrite the TSSocketManager to take advantage of the `empty` message
            // But once our REST endpoint is fixed to properly de-enqueue fallback notifications, we can easily
            // use the rest endpoint here rather than the websocket and circumvent making changes to critical code.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                completionHandler(UIBackgroundFetchResultNewData);
                job = nil;
            });
        });
        [job retainUntilComplete];
    }];
}

- (void)versionMigrationsDidComplete
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"versionMigrationsDidComplete");

    self.areVersionMigrationsComplete = YES;

    [self checkIfAppIsReady];
}

- (void)storageIsReady
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"storageIsReady");

    [self checkIfAppIsReady];
}

- (void)checkIfAppIsReady
{
    OWSAssertIsOnMainThread();

    // App isn't ready until storage is ready AND all version migrations are complete.
    if (!self.areVersionMigrationsComplete) {
        return;
    }
    if (![self.storageCoordinator isStorageReady]) {
        return;
    }
    if ([AppReadiness isAppReady]) {
        // Only mark the app as ready once.
        return;
    }
    BOOL launchJobsAreComplete = [self.launchJobs ensureLaunchJobsWithCompletion:^{
        // If launch jobs need to run, return and
        // call checkIfAppIsReady again when they're complete.
        [self checkIfAppIsReady];
    }];
    if (!launchJobsAreComplete) {
        // Wait for launch jobs to complete.
        return;
    }

    OWSLogInfo(@"checkIfAppIsReady");

    // Note that this does much more than set a flag;
    // it will also run all deferred blocks.
    [AppReadiness setAppIsReady];

    if (CurrentAppContext().isRunningTests) {
        OWSLogVerbose(@"Skipping post-launch logic in tests.");
        return;
    }

    if ([self.tsAccountManager isRegistered]) {
        OWSLogInfo(@"localAddress: %@", TSAccountManager.localAddress);

        // Fetch messages as soon as possible after launching. In particular, when
        // launching from the background, without this, we end up waiting some extra
        // seconds before receiving an actionable push notification.
        [[AppEnvironment.shared.messageFetcherJob run] retainUntilComplete];

        // This should happen at any launch, background or foreground.
        __unused AnyPromise *pushTokenpromise =
            [OWSSyncPushTokensJob runWithAccountManager:AppEnvironment.shared.accountManager
                                            preferences:Environment.shared.preferences];
    }

    [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:self];

    [AppVersion.sharedInstance mainAppLaunchDidComplete];

    [Environment.shared.audioSession setup];

    [SSKEnvironment.shared.reachabilityManager setup];

    if (!Environment.shared.preferences.hasGeneratedThumbnails) {
        [self.databaseStorage
            asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                [TSAttachment anyEnumerateWithTransaction:transaction
                                                  batched:YES
                                                    block:^(TSAttachment *attachment, BOOL *stop) {
                                                        // no-op. It's sufficient to initWithCoder: each object.
                                                    }];
            }
            completion:^{
                [Environment.shared.preferences setHasGeneratedThumbnails:YES];
            }];
    }

#ifdef DEBUG
    // A bug in orphan cleanup could be disastrous so let's only
    // run it in DEBUG builds for a few releases.
    //
    // TODO: Release to production once we have analytics.
    // TODO: Orphan cleanup is somewhat expensive - not least in doing a bunch
    //       of disk access.  We might want to only run it "once per version"
    //       or something like that in production.
    [OWSOrphanDataCleaner auditOnLaunchIfNecessary];
#endif

    [self.profileManager fetchAndUpdateLocalUsersProfile];
    [self.readReceiptManager prepareCachedValues];

    [SignalApp.sharedApp ensureRootViewController:launchStartedAt];

    [self.messageManager startObserving];

    [self.udManager setup];

    if (StorageCoordinator.dataStoreForUI == DataStoreYdb) {
        [self.primaryStorage touchDbAsync];
    }

    // Every time the user upgrades to a new version:
    //
    // * Update account attributes.
    // * Sync configuration to linked devices.
    if ([self.tsAccountManager isRegistered]) {
        AppVersion *appVersion = AppVersion.sharedInstance;
        if (appVersion.lastAppVersion.length > 0
            && ![appVersion.lastAppVersion isEqualToString:appVersion.currentAppVersion]) {
            [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];

            if (self.tsAccountManager.isRegisteredPrimaryDevice) {
                [self.syncManager sendConfigurationSyncMessage];
            }
        }
    }

    [ViewOnceMessages appDidBecomeReady];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"registrationStateDidChange");

    [self enableBackgroundRefreshIfNecessary];

    if ([self.tsAccountManager isRegistered]) {
        OWSLogInfo(@"localAddress: %@", [self.tsAccountManager localAddress]);

        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [ExperienceUpgradeFinder.sharedManager markAllAsSeenWithTransaction:transaction];
        }];

        // Start running the disappearing messages job in case the newly registered user
        // enables this feature
        [self.disappearingMessagesJob startIfNecessary];

        // TODO MULTIRING
        // Currently, we only build the CallUIAdapter for the primary device, which we can't determine
        // until *after* the user has registered. Once we create calling on all devices, we can
        // create the callUIAdapter unconditionally, on all devices, and get rid of this.
        [AppEnvironment.shared.callService createCallUIAdapter];
    }
}

- (void)registrationLockDidChange:(NSNotification *)notification
{
    [self enableBackgroundRefreshIfNecessary];
}

#pragma mark - status bar touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    CGPoint location = [[[event allTouches] anyObject] locationInView:[self window]];
    CGRect statusBarFrame = [UIApplication sharedApplication].statusBarFrame;
    if (CGRectContainsPoint(statusBarFrame, location)) {
        OWSLogDebug(@"touched status bar");
        [[NSNotificationCenter defaultCenter] postNotificationName:TappedStatusBarNotification object:nil];
    }
}

#pragma mark - UNUserNotificationsDelegate

// The method will be called on the delegate only if the application is in the foreground. If the method is not
// implemented or the handler is not called in a timely manner then the notification will not be presented. The
// application can choose to have the notification presented as a sound, badge, alert and/or in the notification list.
// This decision should be based on whether the information in the notification is otherwise visible to the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
    __IOS_AVAILABLE(10.0)__TVOS_AVAILABLE(10.0)__WATCHOS_AVAILABLE(3.0)__OSX_AVAILABLE(10.14)
{
    OWSLogInfo(@"");
    [AppReadiness runNowOrWhenAppDidBecomeReady:^() {
        // We need to respect the in-app notification sound preference. This method, which is called
        // for modern UNUserNotification users, could be a place to do that, but since we'd still
        // need to handle this behavior for legacy UINotification users anyway, we "allow" all
        // notification options here, and rely on the shared logic in NotificationPresenter to
        // honor notification sound preferences for both modern and legacy users.
        UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert
            | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound;
        completionHandler(options);
    }];
}

// The method will be called on the delegate when the user responded to the notification by opening the application,
// dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application
// returns from application:didFinishLaunchingWithOptions:.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler __IOS_AVAILABLE(10.0)__WATCHOS_AVAILABLE(3.0)
                                       __OSX_AVAILABLE(10.14)__TVOS_PROHIBITED
{
    OWSLogInfo(@"");
    [AppReadiness runNowOrWhenAppDidBecomeReady:^() {
        [self.userNotificationActionHandler handleNotificationResponse:response completionHandler:completionHandler];
    }];
}

// The method will be called on the delegate when the application is launched in response to the user's request to view
// in-app notification settings. Add UNAuthorizationOptionProvidesAppNotificationSettings as an option in
// requestAuthorizationWithOptions:completionHandler: to add a button to inline notification settings view and the
// notification settings view in Settings. The notification will be nil when opened from Settings.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    openSettingsForNotification:(nullable UNNotification *)notification __IOS_AVAILABLE(12.0)
                                    __OSX_AVAILABLE(10.14)__WATCHOS_PROHIBITED __TVOS_PROHIBITED
{
    OWSLogInfo(@"");
}

@end
