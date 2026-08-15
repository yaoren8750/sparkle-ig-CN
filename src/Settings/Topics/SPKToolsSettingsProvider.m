#import "SPKToolsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../../App/SPKFlexLoader.h"
#import "../../App/SPKStabilityGuard.h"
#import "../../AssetUtils.h"
#import "../../Shared/Gallery/SPKGalleryLockViewController.h"
#import "../../Shared/Settings/SPKSettingsLockManager.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Utils.h"
#import "../SPKOnboardingViewController.h"
#import "../SPKWhatsNewViewController.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"
#if SPK_DEV
#import "SPKHookBisectSettingsProvider.h"
#endif
#import "SPKInterfaceSettingsProvider.h"

static UIViewController *SPKSettingsLockPresenter(void) {
    UIViewController *presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController)
        presenter = presenter.presentedViewController;
    return presenter;
}

static void SPKSettingsLockReloadPresenter(UIViewController *presenter) {
    // `presenter` is the topmost presented VC, which is usually the navigation
    // controller wrapping the settings page rather than the page itself. Reload
    // whichever SPKSettingsViewController is actually on screen so the Change
    // Passcode row greys/ungreys with the lock toggle.
    SPKSettingsViewController *settingsVC = nil;
    if ([presenter isKindOfClass:SPKSettingsViewController.class]) {
        settingsVC = (SPKSettingsViewController *)presenter;
    } else if ([presenter isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)presenter).topViewController;
        if ([top isKindOfClass:SPKSettingsViewController.class])
            settingsVC = (SPKSettingsViewController *)top;
    }
    [settingsVC.tableView reloadData];
}

static NSDictionary *SPKSettingsLockSection(void) {
    SPKSetting *lockSwitch = [SPKSetting switchCellWithTitle:@"设置密码锁"
                                                       icon:SPKSettingsIcon(@"lock")
                                                defaultsKey:@""];
    lockSwitch.switchValueProvider = ^BOOL {
        return [SPKSettingsLockManager sharedManager].isLockEnabled;
    };

    lockSwitch.switchChangeHandler = ^(BOOL enabled) {
        SPKSettingsLockManager *currentManager = [SPKSettingsLockManager sharedManager];
        UIViewController *presenter = SPKSettingsLockPresenter();

        if (enabled && !currentManager.isLockEnabled) {
            [SPKGalleryLockViewController presentMode:SPKGalleryLockModeSetPasscode
                                           forManager:currentManager
                                     fromViewController:presenter
                                            completion:^(__unused BOOL success) {
                SPKSettingsLockReloadPresenter(presenter);
            }];
            return;
        }

        if (!enabled && currentManager.isLockEnabled) {
            [SPKIGAlertPresenter presentAlertFromViewController:presenter
                                                          title:@"关闭设置密码锁"
                                                        message:@"打开 Sparkle 设置时将不再需要身份验证。"
                                                        actions:@[
                [SPKIGAlertAction actionWithTitle:@"取消"
                                             style:SPKIGAlertActionStyleCancel
                                           handler:^{
                    SPKSettingsLockReloadPresenter(presenter);
                }],
                [SPKIGAlertAction actionWithTitle:@"关闭"
                                             style:SPKIGAlertActionStyleDestructive
                                           handler:^{
                    [currentManager removePasscode];
                    SPKSettingsLockReloadPresenter(presenter);
                }],
            ]];
        }
    };

    SPKSetting *changePasscode =
        [SPKSetting buttonCellWithTitle:@"修改设置密码"
                                subtitle:nil
                                    icon:SPKSettingsIcon(@"key")
                                  action:^{
        [SPKGalleryLockViewController presentMode:SPKGalleryLockModeChangePasscode
                                       forManager:[SPKSettingsLockManager sharedManager]
                                 fromViewController:SPKSettingsLockPresenter()
                                        completion:^(__unused BOOL success) {
        }];
    }];

    changePasscode.enabledProvider = ^BOOL {
        return [SPKSettingsLockManager sharedManager].isLockEnabled;
    };

    return SPKTopicSection(
        @"设置锁",
        @[ lockSwitch, changePasscode ],
        @"打开 Sparkle 设置（包括各个设置页面）时，需要输入独立的设置密码或进行生物识别验证。"
    );
}


@implementation SPKToolsSettingsProvider

+ (SPKSetting *)rootSetting {
    BOOL flexInstalled = SPKFlexIsBundled();

    NSString *flexFooter = flexInstalled
        ? @"FLEX 在每次会话中首次打开时，可能需要一些时间进行初始化。"
        : @"未安装 FLEX。请使用 \"--flex\" 参数重新编译，或安装 \"libFLEX.dylib\" 以启用这些选项。";

    SPKSetting *flexGesture =
        [SPKSetting switchCellWithTitle:@"三指长按"
                            defaultsKey:@"tools_flex_instagram"];

    SPKSetting *flexLaunch =
        [SPKSetting switchCellWithTitle:@"启动 App 时打开"
                            defaultsKey:@"tools_flex_app_launch"];

    SPKSetting *flexFocus =
        [SPKSetting switchCellWithTitle:@"进入 App 时打开"
                            defaultsKey:@"tools_flex_app_start"];

    SPKSetting *flexOpen =
        [SPKSetting buttonCellWithTitle:@"立即打开 FLEX"
                                subtitle:@""
                                    icon:nil
                                  action:^(void) {
        SPKFlexShowExplorer(@"settings");
    }];

    if (!flexInstalled) {
        flexGesture.userInfo = @{@"enabled" : @NO};
        flexLaunch.userInfo = @{@"enabled" : @NO};
        flexFocus.userInfo = @{@"enabled" : @NO};
        flexOpen.userInfo = @{@"enabled" : @NO};
    }

    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[

        SPKTopicSection(
            @"FLEX",
            @[ flexOpen, flexGesture, flexLaunch, flexFocus ],
            flexFooter
        ),

        SPKTopicSection(
            @"插件",
            @[
                [SPKSetting switchCellWithTitle:@"快速访问设置"
                                    defaultsKey:@"tools_settings_shortcut"
                                requiresRestart:YES],

                [SPKSetting switchCellWithTitle:@"快捷方式触感反馈"
                                    defaultsKey:@"tools_shortcut_haptics"],

                [SPKSetting switchCellWithTitle:@"启动 App 时显示设置"
                                    defaultsKey:@"tools_open_settings_on_launch"],

                [SPKSetting switchCellWithTitle:@"禁用所有设置"
                                    defaultsKey:@"tools_disable_all"
                                requiresRestart:YES],

                [SPKSetting buttonCellWithTitle:@"显示引导"
                                        subtitle:@""
                                            icon:nil
                                          action:^(void) {
                    [SPKOnboardingViewController presentFromViewController:nil
                                                                   onFinish:nil];
                }],

                [SPKSetting buttonCellWithTitle:@"显示更新内容"
                                        subtitle:@""
                                            icon:nil
                                          action:^(void) {
                    [SPKWhatsNewViewController presentFromViewController:nil
                                                                  onFinish:nil];
                }],
            ],
            @"1. 长按主页标签即可打开设置；如果主页标签被隐藏，则长按下一个可见标签。\n"
             "2. 触发设置快捷手势时提供触感反馈。\n"
             "3. 每次启动 Instagram 时自动打开 Sparkle 设置。\n"
             "4. 禁用所有 Sparkle 功能 Hook，仅保留进入此页面的快捷方式。用于排查崩溃问题。"
        ),

        SPKTopicSection(
            @"",
            @[
                [SPKSetting buttonCellWithTitle:@"重置安全启动模式"
                                        subtitle:@""
                                            icon:nil
                                          action:^(void) {
                    SPKStabilityGuardReset();
                    [SPKUtils showRestartConfirmation];
                }],

#if SPK_DEV

                // Dev builds only: wipe the intro-sheet state so the onboarding /
                // What's New gating fires from scratch on the next launch.
                [SPKSetting buttonCellWithTitle:@"[开发版] 重置引导状态"
                                        subtitle:@""
                                            icon:nil
                                          action:^(void) {
                    NSUserDefaults *defaults =
                        [NSUserDefaults standardUserDefaults];

                    [defaults removeObjectForKey:@"app_first_run"];
                    [defaults removeObjectForKey:@"app_last_whatsnew_version"];

                    [SPKUtils showRestartConfirmation];
                }],

#endif
            ],
            @"清除启动失败计数和临时 Hook 禁用状态。如果功能看起来没有生效，请点击此按钮。"
        ),

#if SPK_DEV

        SPKTopicSection(
            @"诊断",
            @[ [SPKHookBisectSettingsProvider rootSetting] ],
            @"启动时跳过指定功能的 Hook 安装器，用于定位导致崩溃或性能下降的具体功能。"
        ),

#endif

        SPKSettingsLockSection(),
    ]];

    // The TestFlight/Beta popup suppression is always active on release builds.
    // On dev builds, we keep a toggle to allow disabling it for testing.

    NSMutableArray *instagramCells = [NSMutableArray array];

#if SPK_DEV

    [instagramCells addObject:
        [SPKSetting switchCellWithTitle:@"[开发版] 隐藏 TestFlight 弹窗"
                            defaultsKey:@"tools_hide_testflight_popup"
                        requiresRestart:YES]];

#endif

    [instagramCells addObject:
        [SPKSetting switchCellWithTitle:@"修复重复通知"
                            defaultsKey:@"tools_fix_duplicate_notifications"]];

    [instagramCells addObject:
        [SPKSetting switchCellWithTitle:@"禁用安全模式"
                            defaultsKey:@"tools_disable_safe_mode"]];


#if SPK_DEV

    NSString *instagramFooter =
        @"1. 隐藏 Instagram Beta 更新弹窗。\n"
        @"2. 当通知扩展已经发送相同推送时，隐藏 Instagram 内重复显示的应用内横幅。仅在 App 处于前台时生效。\n"
        @"3. 防止 Instagram 在连续崩溃后重置设置。请谨慎使用。";

#else

    NSString *instagramFooter =
        @"1. 当通知扩展已经发送相同推送时，隐藏 Instagram 内重复显示的应用内横幅。仅在 App 处于前台时生效。\n"
        @"2. 防止 Instagram 在连续崩溃后重置设置。请谨慎使用。";

#endif

    [sections addObject:
        SPKTopicSection(
            @"Instagram",
            instagramCells,
            instagramFooter
        )
    ];

    return SPKTopicNavigationSetting(
        @"工具",
        @"toolbox",
        24.0,
        sections
    );
}

@end
