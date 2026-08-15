#import "SPKProfileSettingsProvider.h"

#import "../../AssetUtils.h"
#import "../../Features/Profile/FollowIndicator.h"
#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../../Utils.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKProfileActionNone = @"none";
static NSString *const kSPKProfileActionCopyInfo = @"copy_info";
static NSString *const kSPKProfileActionViewPicture = @"view_picture";
static NSString *const kSPKProfileActionSharePicture = @"share_picture";
static NSString *const kSPKProfileActionSavePictureToGallery = @"save_picture_gallery";
static NSString *const kSPKProfileActionOpenSettings = @"profile_settings";
static NSString *const kSPKProfileDefaultCopyInfoKey = @"profile_action_btn_default_copy_info_action";
static NSString *const kSPKProfileCopyInfoID = @"id";
static NSString *const kSPKProfileCopyInfoUsername = @"用户名";
static NSString *const kSPKProfileCopyInfoName = @"name";
static NSString *const kSPKProfileCopyInfoBio = @"bio";
static NSString *const kSPKProfileCopyInfoLink = @"link";
static CGFloat const kSPKProfileSettingsMenuIconPointSize = 22.0;

static UIImage *SPKProfileSettingsMenuIcon(NSString *resourceName) {
    return [SPKAssetUtils instagramIconNamed:resourceName pointSize:kSPKProfileSettingsMenuIconPointSize];
}

static UICommand *SPKProfileActionDefaultCommand(NSString *title, NSString *resourceName, NSString *value) {
    UIImage *image = SPKProfileSettingsMenuIcon(resourceName);
    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:@{
                              @"defaultsKey" : @"profile_action_btn_default_action",
                              @"value" : value,
                              @"iconName" : resourceName
                          }];
}

static UIMenu *SPKProfileActionDefaultMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKProfileActionDefaultCommand(@"打开菜单", @"action", kSPKProfileActionNone),
        SPKProfileActionDefaultCommand(@"复制资料", @"copy", kSPKProfileActionCopyInfo),
        SPKProfileActionDefaultCommand(@"查看头像", @"photo", kSPKProfileActionViewPicture),
        SPKProfileActionDefaultCommand(@"分享头像", @"share", kSPKProfileActionSharePicture),
        SPKProfileActionDefaultCommand(@"保存到图库", @"sparkle_gallery", kSPKProfileActionSavePictureToGallery),
        SPKProfileActionDefaultCommand(@"个人资料设置", @"settings", kSPKProfileActionOpenSettings)
    ]];
}

static UICommand *SPKProfileDefaultCopyInfoCommand(NSString *title, NSString *resourceName, NSString *value) {
    UIImage *image = SPKProfileSettingsMenuIcon(resourceName);
    return [UICommand commandWithTitle:title
                                 image:image
                                action:@selector(menuChanged:)
                          propertyList:@{
                              @"defaultsKey" : kSPKProfileDefaultCopyInfoKey,
                              @"value" : value,
                              @"iconName" : resourceName
                          }];
}

static UIMenu *SPKProfileDefaultCopyInfoMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKProfileDefaultCopyInfoCommand(@"用户 ID", @"key", kSPKProfileCopyInfoID),
        SPKProfileDefaultCopyInfoCommand(@"用户名", @"用户名", kSPKProfileCopyInfoUsername),
        SPKProfileDefaultCopyInfoCommand(@"姓名", @"text", kSPKProfileCopyInfoName),
        SPKProfileDefaultCopyInfoCommand(@"个人简介", @"caption", kSPKProfileCopyInfoBio),
        SPKProfileDefaultCopyInfoCommand(@"个人主页链接", @"link", kSPKProfileCopyInfoLink)
    ]];
}

static NSString *const kSPKFollowIndicatorModeKey = @"profile_follow_indicator_mode";
static NSString *const kSPKFollowIndicatorModeOff = @"off";
static NSString *const kSPKFollowIndicatorModeText = @"text";
static NSString *const kSPKFollowIndicatorModeIcon = @"icon";
static NSString *const kSPKFollowIndicatorModeIconText = @"icontext";

// Mirrors FollowIndicator.x: no default is registered for the mode key, so an
// empty value means "use the legacy on/off bool" for pre-mode-menu users.
static NSString *SPKFollowIndicatorEffectiveMode(void) {
    NSString *mode = [SPKUtils getStringPref:kSPKFollowIndicatorModeKey];
    if (mode.length > 0)
        return mode;
    return [SPKUtils getBoolPref:@"profile_follow_indicator"] ? kSPKFollowIndicatorModeText
                                                              : kSPKFollowIndicatorModeOff;
}

static NSString *const kSPKFollowIndicatorColorfulKey = @"profile_follow_indicator_colorful";

// Mirrors FollowIndicator.x: no default is registered, so a never-set value
// falls back to the legacy bool (pre-menu enabled users keep colored).
static BOOL SPKFollowIndicatorColorfulEnabled(void) {
    id value = SPKPreferenceObjectForKey(kSPKFollowIndicatorColorfulKey);
    if (value == nil)
        return [SPKUtils getBoolPref:@"profile_follow_indicator"];
    return [value boolValue];
}

// No per-item icons: the menu is a plain title list. The cell keeps a static
// leading icon instead of reflecting the selection.
static UICommand *SPKFollowIndicatorModeCommand(NSString *title, NSString *value) {
    return [UICommand commandWithTitle:title
                                 image:nil
                                action:@selector(menuChanged:)
                          propertyList:@{
                              @"defaultsKey" : kSPKFollowIndicatorModeKey,
                              @"value" : value
                          }];
}

static UIMenu *SPKFollowIndicatorModeMenu(void) {
    return [UIMenu menuWithChildren:@[
        SPKFollowIndicatorModeCommand(@"关闭", kSPKFollowIndicatorModeOff),
        SPKFollowIndicatorModeCommand(@"仅图标", kSPKFollowIndicatorModeIcon),
        SPKFollowIndicatorModeCommand(@"仅文字", kSPKFollowIndicatorModeText),
        SPKFollowIndicatorModeCommand(@"图标与文字", kSPKFollowIndicatorModeIconText)
    ]];
}

@implementation SPKProfileSettingsProvider

+ (SPKSetting *)rootSetting {
    return SPKTopicNavigationSetting(@"个人资料", @"user_circle", 24.0, @[
        SPKTopicSection(@"操作按钮", @[
            [SPKSetting switchCellWithTitle:@"个人资料操作按钮"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:@"profile_action_btn"],
            SPKActionButtonDefaultActionNavigationSetting(SPKActionButtonSourceProfile),
            SPKActionButtonConfigurationNavigationSetting(
                SPKActionButtonSourceProfile,
                @"个人资料",
                SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceProfile),
                SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceProfile)
            ),
            SPKSettingApplySelectedMenuIcon(
                [SPKSetting menuCellWithTitle:@"默认复制资料"
                                         icon:SPKSettingsIcon(@"copy")
                                         menu:SPKProfileDefaultCopyInfoMenu()],
                SPKSettingsIcon(@"copy")
            )
        ],
        @"设置点击操作按钮时执行的操作。若默认操作为“复制资料”，可在这里选择要复制的资料内容。"),

        SPKTopicSection(@"头像", @[
            [SPKSetting switchCellWithTitle:@"长按放大头像"
                                       icon:SPKSettingsIcon(@"expand")
                                defaultsKey:@"profile_photo_zoom"]
        ],
        @"长按个人资料头像可放大查看。"),

        SPKTopicSection(@"关注状态", @[
            ({
                SPKSetting *mode = [SPKSetting menuCellWithTitle:@"关注状态提示"
                                                            icon:SPKSettingsIcon(@"user_check")
                                                            menu:SPKFollowIndicatorModeMenu()];
                mode.accessoryTextProvider = ^NSString * {
                    NSString *value = SPKFollowIndicatorEffectiveMode();

                    if ([value isEqualToString:kSPKFollowIndicatorModeText])
                        return @"仅文字";

                    if ([value isEqualToString:kSPKFollowIndicatorModeIcon])
                        return @"仅图标";

                    if ([value isEqualToString:kSPKFollowIndicatorModeIconText])
                        return @"图标与文字";

                    return @"关闭";
                };
                mode;
            }),

            ({
                // 关闭时使用 Instagram 原生灰色样式；
                // 开启后使用绿色/红色区分关注状态。
                SPKSetting *colorful =
                    [SPKSetting switchCellWithTitle:@"彩色关注状态"
                                               icon:SPKSettingsIcon(@"palette")
                                        defaultsKey:kSPKFollowIndicatorColorfulKey];

                colorful.switchValueProvider = ^BOOL {
                    return SPKFollowIndicatorColorfulEnabled();
                };

                colorful.switchChangeHandler = ^(BOOL isOn) {
                    SPKPreferenceSetObject(@(isOn), kSPKFollowIndicatorColorfulKey);

                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:SPKFollowIndicatorDidChangeNotification
                                      object:nil];
                };

                colorful.hiddenProvider = ^BOOL {
                    return [SPKFollowIndicatorEffectiveMode()
                        isEqualToString:kSPKFollowIndicatorModeOff];
                };

                colorful;
            }),

            [SPKSetting switchCellWithTitle:@"隐藏 Notes 气泡"
                                       icon:SPKSettingsIcon(@"notes")
                                defaultsKey:@"profile_hide_notes_bubble"],

            [SPKSetting switchCellWithTitle:@"隐藏 Threads 按钮"
                                       icon:SPKSettingsIcon(@"threads")
                                defaultsKey:@"profile_hide_threads_btn"]
        ],
        @"关注状态提示会显示在对方个人资料的统计信息下方，用于表示对方是否关注你。可选择仅显示图标、文字或两者，并可开启彩色样式以使用绿色/红色区分状态。"),

        SPKTopicSection(@"操作确认", @[
            [SPKSetting switchCellWithTitle:@"关注前确认"
                                       icon:SPKSettingsIcon(@"user_follow")
                                defaultsKey:@"profile_confirm_follow"],

            [SPKSetting switchCellWithTitle:@"取消关注前确认"
                                       icon:SPKSettingsIcon(@"user_unfollow")
                                defaultsKey:@"profile_confirm_unfollow"]
        ],
        @"开启后，在关注或取消关注前会显示确认提示。")
    ]);
}

@end
