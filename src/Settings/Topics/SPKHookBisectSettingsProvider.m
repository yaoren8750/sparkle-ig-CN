#import "SPKHookBisectSettingsProvider.h"

#if SPK_DEV

#import <UIKit/UIKit.h>

#import "../../App/SPKHookBisect.h"
#import "../../App/SPKPerfMeter.h"
#import "../../Utils.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"

// The bulk buttons flip many switches at once, so the visible rows have to be
// re-read. Same shape as the settings-lock rows in SPKToolsSettingsProvider.
static void SPKHookBisectReloadVisibleSettings(void) {
    UIViewController *presenter = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (presenter.presentedViewController)
        presenter = presenter.presentedViewController;

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

static SPKSetting *SPKHookBisectInstallerRow(NSString *installerName) {
    BOOL essential = SPKHookBisectInstallerIsEssential(installerName);
    // ON = installed. Reading "turn the hook off" matches what the user is
    // doing; the underlying pref stores the inverse (skipped).
    SPKSetting *row = [SPKSetting switchCellWithTitle:SPKHookBisectDisplayName(installerName)
                                             subtitle:essential ? @"始终安装" : @""
                                          defaultsKey:@""];
    row.requiresRestart = YES;
    row.switchValueProvider = ^BOOL {
        return !SPKHookBisectInstallerIsSkipped(installerName);
    };
    row.switchChangeHandler = ^(BOOL isOn) {
        SPKHookBisectSetInstaller(installerName, !isOn);
    };
    if (essential) {
        row.enabledProvider = ^BOOL {
            return NO;
        };
    }
    return row;
}

// The meter is what makes a bisect round decidable: "feels smoother" is not a
// result, "180ms blocked instead of 4.2s" is.
static NSArray<SPKSetting *> *SPKPerfMeterRows(void) {
    SPKSetting *meter = [SPKSetting switchCellWithTitle:@"性能测量器" defaultsKey:@""];
    meter.switchValueProvider = ^BOOL {
        return SPKPerfMeterIsEnabled();
    };
    meter.switchChangeHandler = ^(BOOL isOn) {
        SPKPreferenceSetObject(@(isOn), kSPKPerfMeterEnabledKey);
        SPKPerfMeterSetEnabled(isOn);
        if (isOn && [SPKUtils getBoolPref:kSPKPerfMeterHUDKey])
            SPKPerfMeterSetHUDVisible(YES);
        SPKHookBisectReloadVisibleSettings();
    };

    SPKSetting *hud = [SPKSetting switchCellWithTitle:@"屏幕悬浮显示" defaultsKey:@""];
    hud.switchValueProvider = ^BOOL {
        return [SPKUtils getBoolPref:kSPKPerfMeterHUDKey];
    };
    hud.switchChangeHandler = ^(BOOL isOn) {
        SPKPreferenceSetObject(@(isOn), kSPKPerfMeterHUDKey);
        SPKPerfMeterSetHUDVisible(isOn && SPKPerfMeterIsEnabled());
    };
    hud.enabledProvider = ^BOOL {
        return SPKPerfMeterIsEnabled();
    };

    SPKSetting *summary = [SPKSetting buttonCellWithTitle:@"阻塞时间"
                                                 subtitle:@""
                                                     icon:nil
                                                   action:^{
                                                       SPKHookBisectReloadVisibleSettings();
                                                   }];
    summary.accessoryTextProvider = ^NSString * {
        return SPKPerfMeterSummary();
    };

    // The whole point of the scope timers: the answer is readable here, without
    // attaching a console.
    SPKSetting *worst = [SPKSetting buttonCellWithTitle:@"最耗时 Hook"
                                               subtitle:@""
                                                   icon:nil
                                                 action:^{
                                                     SPKPerfMeterLogSnapshot(@"worst hook");
                                                     SPKHookBisectReloadVisibleSettings();
                                                 }];
    worst.accessoryTextProvider = ^NSString * {
        return SPKPerfMeterWorstScopeSummary();
    };

    SPKSetting *reset = [SPKSetting buttonCellWithTitle:@"开始新的测量"
                                               subtitle:@""
                                                   icon:nil
                                                 action:^{
                                                     SPKPerfMeterLogSnapshot(@"before reset");
                                                     SPKPerfMeterReset();
                                                     SPKHookBisectReloadVisibleSettings();
                                                 }];
    reset.enabledProvider = ^BOOL {
        return SPKPerfMeterIsEnabled();
    };

    SPKSetting *log = [SPKSetting buttonCellWithTitle:@"记录快照"
                                             subtitle:@""
                                                 icon:nil
                                               action:^{
                                                   SPKPerfMeterLogSnapshot(@"manual");
                                               }];
    log.enabledProvider = ^BOOL {
        return SPKPerfMeterIsEnabled();
    };

    return @[ meter, hud, summary, worst, reset, log ];
}

@implementation SPKHookBisectSettingsProvider

+ (SPKSetting *)rootSetting {
    NSArray<NSDictionary *> *groups = SPKHookBisectRegisteredGroups();

    // Button rather than static: the live count comes from accessoryTextProvider,
    // which the table only honours for button and navigation cells. Tapping just
    // re-reads the counters.
    SPKSetting *status = [SPKSetting buttonCellWithTitle:@"已跳过的安装器"
                                                subtitle:@""
                                                    icon:nil
                                                  action:^{
                                                      SPKHookBisectReloadVisibleSettings();
                                                  }];
    status.accessoryTextProvider = ^NSString * {
        return [NSString stringWithFormat:@"%lu / %lu",
                                          (unsigned long)SPKHookBisectSkippedCount(),
                                          (unsigned long)SPKHookBisectRegisteredInstallerCount()];
    };

    SPKSetting *skipHalf = [SPKSetting buttonCellWithTitle:@"跳过剩余一半"
                                                  subtitle:@""
                                                      icon:nil
                                                    action:^{
                                                        NSUInteger skipped = SPKHookBisectSkipHalfOfRemaining();
                                                        SPKHookBisectReloadVisibleSettings();
                                                        if (skipped > 0)
                                                            [SPKUtils showRestartConfirmation];
                                                    }];

    SPKSetting *skipAll = [SPKSetting buttonCellWithTitle:@"全部跳过"
                                                 subtitle:@""
                                                     icon:nil
                                                   action:^{
                                                       SPKHookBisectSetAll(YES);
                                                       SPKHookBisectReloadVisibleSettings();
                                                       [SPKUtils showRestartConfirmation];
                                                   }];

    SPKSetting *restoreAll = [SPKSetting buttonCellWithTitle:@"全部恢复"
                                                    subtitle:@""
                                                        icon:nil
                                                      action:^{
                                                          SPKHookBisectSetAll(NO);
                                                          SPKHookBisectReloadVisibleSettings();
                                                          [SPKUtils showRestartConfirmation];
                                                      }];

    // Individual switches use switchChangeHandler, which returns before the
    // table's own requiresRestart prompt, and prompting per row would fight the
    // workflow (a bisect round flips many rows at once). One explicit relaunch.
    SPKSetting *relaunch = [SPKSetting buttonCellWithTitle:@"重新启动 Instagram"
                                                  subtitle:@""
                                                      icon:nil
                                                    action:^{
                                                        [SPKUtils showRestartConfirmation];
                                                    }];

    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:SPKTopicSection(@"测量",
                                        SPKPerfMeterRows(),
                                        @"测量主线程被阻塞的时间，也就是实际造成卡顿的原因，并统计当前窗口中存活的视图控制器、视图和手势识别器数量。\n\n"
                                                                            @"如果数字随着操作不断增加且不会恢复，说明存在泄漏：页面或手势识别器正在累积，并持续占用资源。每次测试前重新开始测量，以便比较不同测试结果。\n\n"
                                                                            @"每个在布局期间运行的 Sparkle Hook 都会被计时，“最耗时 Hook”会显示占用主线程最多的项目。开启测量后继续浏览，直到感觉卡顿，然后返回查看结果。完整排名每 15 秒记录到日志中。")];
    [sections addObject:SPKTopicSection(@"二分排查",
                                        @[ status, skipHalf, skipAll, restoreAll, relaunch ],
                                        @"禁用安装器后，下次启动时将不会安装对应 Hook。这不同于关闭功能：大多数安装器不会根据自身偏好决定是否运行，因此即使功能关闭，其 Hook（以及布局期间执行的任务）仍可能存在。\n\n"
                                                                            @"要定位回归问题：跳过剩余项目的一半，重新启动并测试。如果问题消失，原因就在被跳过的那一半中；恢复全部后，再跳过另一半。重复此过程，直到找到单个安装器。每次修改都需要重新启动。")];

    for (NSDictionary *group in groups) {
        NSArray<NSString *> *installers = group[@"installers"];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *installerName in installers) {
            [rows addObject:SPKHookBisectInstallerRow(installerName)];
        }
        if (rows.count > 0)
            [sections addObject:SPKTopicSection(group[@"surface"], rows, nil)];
    }

    if (groups.count == 0) {
        [sections addObject:SPKTopicSection(@"",
                                            @[ [SPKSetting staticCellWithTitle:@"暂无安装器记录"
                                                                      subtitle:@"启动后稍等片刻再打开此页面"
                                                                          icon:nil] ],
                                            nil)];
    }

    return [SPKSetting navigationCellWithTitle:@"Hook 二分排查"
                                      subtitle:@""
                                          icon:SPKSettingsIcon(@"beaker")
                                   navSections:sections];
}

@end

#endif // SPK_DEV
