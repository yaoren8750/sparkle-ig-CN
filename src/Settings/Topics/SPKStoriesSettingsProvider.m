#import "SPKStoriesSettingsProvider.h"

#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../../Shared/Stories/SPKStoryContext.h"
#import "../../Utils.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"
static NSString *const kSPKStoriesActionButtonEnabledKey = @"stories_action_btn";

static NSDictionary *SPKStoriesSeenReceiptsSection(void);
static NSArray *SPKStoriesSettingsSections(void);

@interface SPKStoriesSettingsViewController : SPKSettingsViewController
@end

@implementation SPKStoriesSettingsViewController

- (instancetype)init {
    return [super initWithTitle:@"快拍" sections:SPKStoriesSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SPKStoriesSettingsSections()];
}

- (void)switchChanged:(UISwitch *)sender {
    SPKSetting *row = [self settingForSender:sender];
    [super switchChanged:sender];

    if ([row.defaultsKey isEqualToString:@"stories_manual_seen"]) {
        [self replaceSections:SPKStoriesSettingsSections()];
    }
}

@end


static NSDictionary *SPKStoriesSeenReceiptsSection(void) {
    BOOL manualSeen = [SPKUtils getBoolPref:@"stories_manual_seen"];

    NSString *footer = manualSeen
        ? @"1. 快拍不会自动标记为已看，排除名单中的用户除外。\n"
          @"2. 点赞快拍时将其标记为已看。\n"
          @"3. 回复快拍时将其标记为已看。\n"
          @"4. 排除名单中的用户仍使用 Instagram 默认的已看规则，无需使用眼睛按钮。"
        : @"1. 快拍使用 Instagram 默认的已看规则，加入名单的用户除外。\n"
          @"2. 点赞快拍时将其标记为已看。\n"
          @"3. 回复快拍时将其标记为已看。\n"
          @"4. 加入名单的用户需要使用眼睛按钮、点赞或回复来标记已看。";

    SPKSetting *manualSeenList =
        [SPKSetting navigationCellWithTitle:SPKStoryManualSeenListTitle(manualSeen)
                                    subtitle:@""
                                        icon:SPKSettingsIcon(@"users")
                              viewController:SPKStoryManualSeenListViewController()];

    manualSeenList.userInfo = @{
        @"accessoryText" :
            [NSString stringWithFormat:@"%lu",
             (unsigned long)SPKStoryManualSeenUserList(manualSeen).count]
    };

    // 自动标记已看功能仅在手动标记已看开启时生效。
    // 关闭后保留原有开关状态，但暂时不可用。
    SPKSetting *markSeenOnLike =
        [SPKSetting switchCellWithTitle:@"点赞后标记已看"
                                   icon:SPKSettingsIcon(@"heart")
                            defaultsKey:@"stories_mark_seen_on_like"];

    SPKSetting *markSeenOnReply =
        [SPKSetting switchCellWithTitle:@"回复后标记已看"
                                   icon:SPKSettingsIcon(@"reply")
                            defaultsKey:@"stories_mark_seen_on_reply"];

    markSeenOnLike.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"stories_manual_seen"];
    };

    markSeenOnReply.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"stories_manual_seen"];
    };

    return SPKTopicSection(@"已看状态", @[
        [SPKSetting switchCellWithTitle:@"手动标记已看"
                                   icon:SPKSettingsIcon(@"eye")
                            defaultsKey:@"stories_manual_seen"],

        markSeenOnLike,
        markSeenOnReply,
        manualSeenList,

    ], footer);
}


static NSArray *SPKStoriesSettingsSections(void) {
    return @[
        SPKTopicSection(@"操作按钮", @[
            [SPKSetting switchCellWithTitle:@"快拍操作按钮"
                                       icon:SPKSettingsIcon(@"action")
                                defaultsKey:kSPKStoriesActionButtonEnabledKey],

            SPKActionButtonDefaultActionNavigationSetting(
                SPKActionButtonSourceStories
            ),

            SPKActionButtonConfigurationNavigationSetting(
                SPKActionButtonSourceStories,
                @"快拍",
                SPKActionButtonSupportedActionsForSource(SPKActionButtonSourceStories),
                SPKActionButtonDefaultSectionsForSource(SPKActionButtonSourceStories)
            )

        ],
        @"1. 在底部快拍栏上方添加操作按钮。\n"
         @"2. 设置单击按钮时执行的操作，长按始终打开完整操作菜单。"),


        SPKStoriesSeenReceiptsSection(),


        SPKTopicSection(@"快拍浏览", @[
            [SPKSetting switchCellWithTitle:@"停止自动切换"
                                       icon:SPKSettingsIcon(@"autoscroll")
                                defaultsKey:@"stories_stop_auto_advance"],

            [SPKSetting switchCellWithTitle:@"点击眼睛按钮后切换"
                                       icon:SPKSettingsIcon(@"eye")
                                defaultsKey:@"stories_advance_on_manual_seen"],

            [SPKSetting switchCellWithTitle:@"点赞后切换"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"stories_advance_on_like_seen"],

            [SPKSetting switchCellWithTitle:@"回复后切换"
                                       icon:SPKSettingsIcon(@"reply")
                                defaultsKey:@"stories_advance_on_reply_seen"],

        ],
        @"1. 停止快拍自动切换到下一条。\n"
         @"2. 点击眼睛按钮标记已看后切换到下一条快拍。\n"
         @"3. 点赞后切换到下一条快拍。\n"
         @"4. 回复后切换到下一条快拍。"),


        SPKTopicSection(@"操作确认", @[
            [SPKSetting switchCellWithTitle:@"点赞前确认"
                                       icon:SPKSettingsIcon(@"heart")
                                defaultsKey:@"stories_confirm_like"],

            [SPKSetting switchCellWithTitle:@"快速表情回应前确认"
                                       icon:SPKSettingsIcon(@"reactions")
                                defaultsKey:@"stories_confirm_quick_reaction"],

            [SPKSetting switchCellWithTitle:@"贴纸互动前确认"
                                       icon:SPKSettingsIcon(@"sticker")
                                defaultsKey:@"stories_confirm_sticker"]

        ],
        @"1. 点赞快拍前显示确认提示。\n"
         @"2. 点击快速表情回应前显示确认提示。\n"
         @"3. 点击快拍中的贴纸互动前显示确认提示。"),


        SPKTopicSection(@"Instagram Plus", @[
            [SPKSetting switchCellWithTitle:@"解锁快拍预览"
                                       icon:SPKSettingsIcon(@"story_preview")
                                defaultsKey:@"stories_unlock_preview"],

            [SPKSetting switchCellWithTitle:@"隐藏 Instagram Plus 按钮"
                                       icon:SPKSettingsIcon(@"aura")
                                defaultsKey:@"stories_hide_ig_plus_button"]

        ],
        @"1. 解锁“快拍预览”：在快拍长按菜单中预览完整快拍，同时不会出现在查看者列表中。\n"
         @"2. 隐藏快拍查看者列表中的 Instagram Plus 按钮。"),


        SPKTopicSection(@"快拍创建", @[
            [SPKSetting switchCellWithTitle:@"照片贴纸支持视频"
                                       icon:SPKSettingsIcon(@"video")
                                defaultsKey:@"stories_allow_video_sticker"],

            [SPKSetting switchCellWithTitle:@"显示图库上传按钮"
                                       icon:SPKSettingsIcon(@"sparkle_gallery")
                                defaultsKey:@"stories_gallery_upload_sticker"],

            [SPKSetting switchCellWithTitle:@"使用精细取色器"
                                       icon:SPKSettingsIcon(@"eyedropper")
                                defaultsKey:@"stories_detailed_color_picker"]

        ],
        @"1. 允许在快拍的照片贴纸中选择视频。\n"
         @"2. 使用 Sparkle 图库中的媒体作为贴纸。\n"
         @"3. 长按取色器，可更精确地调整文字颜色。"),


        SPKTopicSection(@"其他", @[
            [SPKSetting switchCellWithTitle:@"搜索查看者"
                                       icon:SPKSettingsIcon(@"search")
                                defaultsKey:@"stories_search_viewer_list"],

            [SPKSetting switchCellWithTitle:@"隐藏“加入热门”"
                                       icon:SPKSettingsIcon(@"arrow_up_right")
                                defaultsKey:@"stories_hide_join_trending"],

            [SPKSetting switchCellWithTitle:@"显示快拍提及"
                                       icon:SPKSettingsIcon(@"mention")
                                defaultsKey:@"stories_mentions_btn"],

            [SPKSetting switchCellWithTitle:@"显示投票人数"
                                       icon:SPKSettingsIcon(@"poll")
                                defaultsKey:@"stories_poll_vote_counts"],

        ],
        @"1. 在快拍查看者列表中添加搜索按钮，可搜索和筛选查看过快拍的用户。\n"
         @"2. 隐藏快拍中的“加入热门 / Add Yours”推广卡片。\n"
         @"3. 在底部快拍栏上方显示按钮，用于查看所有被提及的用户。\n"
         @"4. 显示投票中每个选项的投票人数。")
    ];
}


@implementation SPKStoriesSettingsProvider

+ (SPKSetting *)rootSetting {

    SPKSetting *setting =
        [SPKSetting navigationCellWithTitle:@"快拍"
                                    subtitle:@""
                                        icon:SPKSettingsIcon(@"story")
                              viewController:
                                  [[SPKStoriesSettingsViewController alloc] init]];

    setting.searchSectionsProvider = ^NSArray * {
        return SPKStoriesSettingsSections();
    };

    return SPKSettingApplyIconTint(
        setting,
        [SPKUtils SPKColor_InstagramPrimaryText]
    );
}

@end
