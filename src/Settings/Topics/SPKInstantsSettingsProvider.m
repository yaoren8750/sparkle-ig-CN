#import "SPKInstantsSettingsProvider.h"
#include <UIKit/UIKit.h>

#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../../Utils.h"
#import "../SPKPreferenceAvailability.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKInstantsActionButtonEnabledKey = @"instants_action_btn";

static NSArray *SPKInstantsSettingsSections(void);

@interface SPKInstantsSettingsViewController : SPKSettingsViewController
@end

@implementation SPKInstantsSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"Instants" sections:SPKInstantsSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SPKInstantsSettingsSections()];
}
@end

static NSArray *SPKInstantsSettingsSections(void) {
    return @[
        SPKTopicSection(@"操作按钮", @[
            [SPKSetting switchCellWithTitle:@"Instants 操作按钮"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKInstantsActionButtonEnabledKey],
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceInstants),
            SPKActionButtonConfigurationNavigationSetting(
                SPKActionButtonSourceInstants,
                @"Instants",
                SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceInstants),
                SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceInstants)
            )
        ],
        @"选择点击操作按钮时执行的操作。长按可打开完整菜单。"),

        SPKTopicSection(@"隐私", @[
            [SPKSetting switchCellWithTitle:@"允许截屏"
                                       icon:SPKSettingsIcon(@"warning")
                                defaultsKey:@"instants_allow_screenshot"],
        ],
        @"绕过 Instants 查看器的截屏和屏幕录制检测。"),

        SPKTopicSection(@"创建", @[
            ({
                SPKSetting *s =
                    [SPKSetting switchCellWithTitle:@"禁用 Instants 创建"
                                               icon:SPKSettingsIcon(@"instants")
                                        defaultsKey:@"instants_disable_creation"];

                s.switchChangeHandler = ^(BOOL isOn) {
                    SPKPreferenceSetObject(@(isOn), @"instants_disable_creation");
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:@"SPKQuickSnapCreationPrefChangedNotification"
                                      object:nil];
                };

                s;
            }),

            [SPKSetting switchCellWithTitle:@"跳过 Instants 后的相机页面"
                                       icon:SPKSettingsIcon(@"camera")
                                defaultsKey:@"instants_skip_camera_after_viewing"],

            ({
                BOOL cameraControlAvailable =
                    SPKPrefIsAvailable(@"instants_disable_camera_control");

                SPKSetting *s =
                    [SPKSetting switchCellWithTitle:@"禁用相机控制"
                                           subtitle:cameraControlAvailable
                                                ? @""
                                                : @"需要支持相机控制的 iPhone"
                                               icon:SPKSettingsSystemIcon(
                                                   @"button.vertical.right.press",
                                                   SPKSettingsCellIconPointSize,
                                                   UIImageSymbolWeightSemibold)
                                        defaultsKey:@"instants_disable_camera_control"];

                s;
            }),
        ],
        @"1. 禁止拍摄 Instants（照片和视频），但不会禁用已接收的 Instants。快门按钮会变暗。\n"
         @"2. 查看最后一个 Instant 后，跳过 Instagram 自动打开的相机页面。\n"
         @"3. 禁止使用硬件相机控制按钮（iPhone 16/17）拍摄 Instant。"),

        SPKTopicSection(@"", @[
            // 与按钮本身使用相同的图标：全局“打开菜单图标”选项。
            [SPKSetting switchCellWithTitle:@"相机视图按钮"
                                       icon:SPKSettingsIcon(SPKActionButtonOpenMenuIconName())
                                defaultsKey:@"instants_camera_btn"],
        ],
        @"在 Instants 相机界面添加 Sparkle 按钮，可从照片、文件或图库上传照片，也可以浏览已保存的 Instants。"),

        SPKTopicSection(@"确认", @[
            ({
                SPKSetting *s =
                    [SPKSetting switchCellWithTitle:@"确认拍摄 Instant"
                                               icon:SPKSettingsIcon(@"instants_burst")
                                        defaultsKey:@"instants_confirm_capture"];

                s.enabledProvider = ^BOOL {
                    return NO;
                };

                s;
            }),

            [SPKSetting switchCellWithTitle:@"确认 Instant 互动"
                                       icon:SPKSettingsIcon(@"reactions")
                                defaultsKey:@"instants_confirm_reaction"],
        ],
        @"1. 发送拍摄的 Instant 时请求确认。暂时不可用。\n"
         @"2. 发送 Instant 互动前显示确认提示。"),
    ];
}


@implementation SPKInstantsSettingsProvider

+ (UIViewController *)makeSettingsViewController {
    return [[SPKInstantsSettingsViewController alloc] init];
}

+ (SPKSetting *)rootSetting {
    SPKSetting *setting =
        [SPKSetting navigationCellWithTitle:@"Instants"
                                     subtitle:@""
                                         icon:SPKSettingsIcon(@"instants")
                               viewController:[[SPKInstantsSettingsViewController alloc] init]];

    setting.searchSectionsProvider = ^NSArray * {
        return SPKInstantsSettingsSections();
    };

    return SPKSettingApplyIconTint(
        setting,
        [SPKUtils SPKColor_InstagramPrimaryText]
    );
}

@end
