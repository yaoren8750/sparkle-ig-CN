#import "SPKMessagesSettingsProvider.h"

#import "../../Features/Messages/DeletedMessagesLog/SPKDeletedMessagesViewController.h"
#import "../../Shared/ActionButton/SPKActionButtonConfiguration.h"
#import "../../Shared/Messages/SPKDirectSeenContext.h"
#import "../../Utils.h"
#import "../SPKSettingsViewController.h"
#import "../SPKTopicSettingsSupport.h"

static NSString *const kSPKMessagesActionButtonEnabledKey = @"msgs_action_btn";
static NSString *const kSPKMessagesActionButtonChatMediaKey = @"msgs_action_btn_chat_media";
static NSString *const kSPKMessagesAudioCallConfirmKey = @"msgs_confirm_audio_call";
static NSString *const kSPKMessagesVideoCallConfirmKey = @"msgs_confirm_video_call";

static NSArray *SPKMessagesSettingsSections(void);

// A switch cell that stays visible but is disabled while the "Audio Downloads"
// master toggle is off (keeping its stored value).
static SPKSetting *SPKAudioGatedSwitch(NSString *title, UIImage *icon, NSString *defaultsKey) {
    SPKSetting *setting = [SPKSetting switchCellWithTitle:title icon:icon defaultsKey:defaultsKey];
    setting.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"downloads_audio_enabled"];
    };
    return setting;
}

@interface SPKMessagesSettingsViewController : SPKSettingsViewController
@end

@implementation SPKMessagesSettingsViewController
- (instancetype)init {
    return [super initWithTitle:@"消息" sections:SPKMessagesSettingsSections() reduceMargin:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self replaceSections:SPKMessagesSettingsSections()];
}

- (void)switchChanged:(UISwitch *)sender {
    SPKSetting *row = [self settingForSender:sender];
    [super switchChanged:sender];
    if ([row.defaultsKey isEqualToString:@"msgs_manual_seen"] ||
        [row.defaultsKey isEqualToString:@"msgs_manual_visual_seen"]) {
        [self replaceSections:SPKMessagesSettingsSections()];
    }
}
@end

static NSArray *SPKMessagesSettingsSections(void) {
    BOOL manualSeen = [SPKUtils getBoolPref:@"msgs_manual_seen"];

    SPKSetting *manualSeenList =
        [SPKSetting navigationCellWithTitle:SPKDirectManualSeenListTitle(manualSeen)
                                   subtitle:@""
                                       icon:SPKSettingsIcon(@"users")
                             viewController:SPKDirectManualSeenListViewController()];

    manualSeenList.userInfo = @{
        @"accessoryText" :
            [NSString stringWithFormat:@"%lu",
             (unsigned long)SPKDirectManualSeenThreadCount(manualSeen)]
    };

    // Auto-seen triggers only act while manual seen is on.
    // Keep their stored value but lock the cells when manual seen is off.
    SPKSetting *seenOnSend =
        [SPKSetting switchCellWithTitle:@"发送消息后标记已读"
                                   icon:SPKSettingsIcon(@"messages")
                            defaultsKey:@"msgs_seen_on_send"];

    SPKSetting *seenOnReply =
        [SPKSetting switchCellWithTitle:@"回复消息后标记已读"
                                   icon:SPKSettingsIcon(@"reply")
                            defaultsKey:@"msgs_seen_on_reply"];

    SPKSetting *seenOnReaction =
        [SPKSetting switchCellWithTitle:@"添加互动后标记已读"
                                   icon:SPKSettingsIcon(@"reactions")
                            defaultsKey:@"msgs_seen_on_reaction"];

    SPKSetting *seenOnTyping =
        [SPKSetting switchCellWithTitle:@"开始输入时标记已读"
                                   icon:SPKSettingsIcon(@"keyboard")
                            defaultsKey:@"msgs_seen_on_typing"];

    seenOnSend.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };

    seenOnReply.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };

    seenOnReaction.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };

    seenOnTyping.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };

    // Chooses where the manual-seen eye button lives.
    SPKSetting *seenButtonPosition =
        SPKSettingApplySelectedMenuIcon(
            [SPKSetting menuCellWithTitle:@"已读按钮位置"
                                     icon:SPKSettingsIcon(@"arrow_up")
                                      menu:SPKSeenButtonPositionMenu()],
            SPKSettingsIcon(@"arrow_up")
        );

    seenButtonPosition.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_seen"];
    };

    // Advancing after a manual seen only applies while visual manual seen is on.
    SPKSetting *advanceVisual =
        [SPKSetting switchCellWithTitle:@"手动标记已读后继续"
                                   icon:SPKSettingsIcon(@"autoscroll")
                            defaultsKey:@"msgs_advance_visual_on_seen"];

    advanceVisual.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:@"msgs_manual_visual_seen"];
    };

    // Tri-state control for chat-header last-active presence label.
    SPKSetting *lastActiveFormat =
        SPKSettingApplySelectedMenuIcon(
            [SPKSetting menuCellWithTitle:@"最后活跃时间"
                                     icon:SPKSettingsIcon(@"clock")
                                      menu:SPKLastActiveFormatMenu()],
            SPKSettingsIcon(@"clock")
        );

    // Extends the action button to the full-screen viewer for chat media.
    SPKSetting *chatMediaActionButton =
        [SPKSetting switchCellWithTitle:@"同时显示在聊天媒体中"
                                   icon:SPKSettingsIcon(@"photo")
                            defaultsKey:kSPKMessagesActionButtonChatMediaKey];

    chatMediaActionButton.enabledProvider = ^BOOL {
        return [SPKUtils getBoolPref:kSPKMessagesActionButtonEnabledKey];
    };

    return @[
        SPKTopicSection(
            @"操作按钮",
            @[
                [SPKSetting switchCellWithTitle:@"消息操作按钮"
                                           icon:SPKSettingsIcon(@"action")
                                    defaultsKey:kSPKMessagesActionButtonEnabledKey],

                chatMediaActionButton,

                SPKActionButtonDefaultActionNavigationSetting(
                    SPKActionButtonSourceDirect
                ),

                SPKActionButtonConfigurationNavigationSetting(
                    SPKActionButtonSourceDirect,
                    @"消息",
                    SPKActionButtonSupportedActionsForSource(
                        SPKActionButtonSourceDirect
                    ),
                    SPKActionButtonDefaultSectionsForSource(
                        SPKActionButtonSourceDirect
                    )
                )
            ],
            @"选择点击操作按钮时执行的操作。长按可打开完整菜单。\n"
             @"“同时显示在聊天媒体中”会将按钮添加到聊天中打开的相机胶卷照片和视频。"
        ),

        SPKTopicSection(
            @"消息",
            @[
                [SPKSetting switchCellWithTitle:@"解锁消息预览"
                                           icon:SPKSettingsIcon(@"story_preview")
                                    defaultsKey:@"msgs_unlock_preview"],

                [SPKSetting switchCellWithTitle:@"手动标记已读"
                                           icon:SPKSettingsIcon(@"eye")
                                    defaultsKey:@"msgs_manual_seen"],

                seenButtonPosition,
                seenOnSend,
                seenOnReply,
                seenOnReaction,
                seenOnTyping,
                manualSeenList,
            ],

            manualSeen
                ? @"1. 解锁“消息预览”：长按聊天菜单即可查看实际消息预览，同时不会将消息标记为已读。\n"
                  @"2. 阻止自动发送已读回执，并添加眼睛按钮以手动标记聊天为已读。\n"
                  @"3. 将已读按钮放置在顶部导航栏，或显示为位于输入框上方、方便拇指操作的可拖动气泡（滚动页面可将其吸附回原位）。\n"
                  @"4. 发送消息时将聊天标记为已读。\n"
                  @"5. 回复消息时将聊天标记为已读。\n"
                  @"6. 添加互动时将聊天标记为已读。\n"
                  @"7. 开始输入回复时将聊天标记为已读。\n\n"
                  @"排除的聊天仍保持 Instagram 默认的已读行为。可通过眼睛按钮、长按收件箱或上方列表进行管理。"
                : @"1. 解锁“消息预览”：长按聊天菜单即可查看实际消息预览，同时不会将消息标记为已读。\n"
                  @"2. 阻止自动发送已读回执，并添加眼睛按钮以手动标记聊天为已读。\n"
                  @"3. 将已读按钮放置在顶部导航栏，或显示为位于输入框上方、方便拇指操作的可拖动气泡（滚动页面可将其吸附回原位）。\n"
                  @"4. 发送消息时将聊天标记为已读。\n"
                  @"5. 回复消息时将聊天标记为已读。\n"
                  @"6. 添加互动时将聊天标记为已读。\n"
                  @"7. 开始输入回复时将聊天标记为已读。\n\n"
                  @"包含的聊天需要通过眼睛按钮或上述自动标记已读触发条件进行处理。可通过眼睛按钮、长按收件箱或上方列表进行管理。"
        ),

        SPKTopicSection(
            @"已删除消息",
            @[
                [SPKSetting switchCellWithTitle:@"保留已删除消息"
                                           icon:SPKSettingsIcon(@"undo_circle")
                                    defaultsKey:@"msgs_keep_deleted"],

                [SPKSetting switchCellWithTitle:@"确认刷新收件箱"
                                           icon:SPKSettingsIcon(@"arrow_cw")
                                    defaultsKey:@"msgs_confirm_refresh"],

                [SPKSetting switchCellWithTitle:@"记录已删除消息"
                                           icon:SPKSettingsIcon(@"logs")
                                    defaultsKey:@"msgs_deleted_log"],

                [SPKSetting switchCellWithTitle:@"记录已删除互动"
                                           icon:SPKSettingsIcon(@"reactions")
                                    defaultsKey:@"msgs_deleted_log_reactions"],

                [SPKSetting switchCellWithTitle:@"遵循已读聊天列表"
                                           icon:SPKSettingsIcon(@"eye")
                                    defaultsKey:@"msgs_deleted_log_respect_seen_list"],

                [SPKSetting navigationCellWithTitle:@"查看已删除消息"
                                           subtitle:@""
                                               icon:SPKSettingsIcon(@"channels")
                                     viewController:[SPKDeletedMessagesViewController new]],
            ],

            @"1. 保留聊天中已从服务器撤回的消息，并使用撤回图标进行标记。\n"
             @"2. 刷新收件箱前进行确认，因为刷新会重新加载聊天并清除已保留的消息。\n"
             @"3. 在消息被删除前记录消息内容，并在清除前保留仅查看一次/查看两次的媒体。\n"
             @"4. 同时记录被删除的互动。\n"
             @"5. 对于手动标记已读的包含/排除列表中的聊天，不记录消息内容，也不发送未发送消息通知。\n"
             @"6. 打开已记录的已删除消息。"
        ),

        SPKTopicSection(
            @"界面",
            @[
                lastActiveFormat,

                [SPKSetting switchCellWithTitle:@"隐藏正在输入状态"
                                           icon:SPKSettingsIcon(@"keyboard")
                                    defaultsKey:@"msgs_disable_typing"],

                [SPKSetting switchCellWithTitle:@"隐藏 Reels Blend 按钮"
                                           icon:SPKSettingsIcon(@"blend")
                                    defaultsKey:@"msgs_hide_reels_blend"],

                [SPKSetting switchCellWithTitle:@"隐藏语音通话按钮"
                                           icon:SPKSettingsIcon(@"call")
                                    defaultsKey:@"msgs_hide_audio_call_btn"],

                [SPKSetting switchCellWithTitle:@"隐藏视频通话按钮"
                                           icon:SPKSettingsIcon(@"video")
                                    defaultsKey:@"msgs_hide_video_call_btn"],

                [SPKSetting switchCellWithTitle:@"隐藏举报按钮"
                                           icon:SPKSettingsIcon(@"flag")
                                    defaultsKey:@"msgs_hide_flag_btn"],

                [SPKSetting switchCellWithTitle:@"不显示推荐聊天"
                                           icon:SPKSettingsIcon(@"question")
                                    defaultsKey:@"msgs_hide_suggested_chats"],
            ],

            @"1. 在聊天顶部显示对方最后活跃的准确时间（“活跃于凌晨 1:15”），而不是相对时间（“2 小时前活跃”）。"
             @"“智能”模式当天仅显示时间，较早日期则同时显示日期；“日期与时间”始终同时显示两者。仅重新格式化 Instagram 已经显示的在线状态。\n"
             @"2. 停止向其他人发送你的正在输入状态。\n"
             @"3. 从收件箱中移除 Reels Blend 按钮。\n"
             @"4. 隐藏聊天顶部的语音通话按钮。\n"
             @"5. 隐藏聊天顶部的视频通话按钮。\n"
             @"6. 隐藏聊天顶部的举报按钮。\n"
             @"7. 从收件箱中移除推荐聊天。"
        ),

        SPKTopicSection(
            @"视觉消息",
            @[
                [SPKSetting switchCellWithTitle:@"手动标记已读"
                                           icon:SPKSettingsIcon(@"eye")
                                    defaultsKey:@"msgs_manual_visual_seen"],

                advanceVisual,

                [SPKSetting switchCellWithTitle:@"停止自动切换"
                                           icon:SPKSettingsIcon(@"autoscroll")
                                    defaultsKey:@"msgs_stop_visual_auto_advance"],

                [SPKSetting switchCellWithTitle:@"禁用仅查看一次限制"
                                           icon:SPKSettingsIcon(@"view_once")
                                    defaultsKey:@"msgs_disable_view_once"],

                [SPKSetting switchCellWithTitle:@"禁用截屏检测"
                                           icon:SPKSettingsIcon(@"warning")
                                    defaultsKey:@"msgs_disable_screenshot_detection"]
            ],

            @"1. 阻止自动发送已读回执，并添加按钮以手动将聊天标记为已读。\n"
             @"2. 如果有下一条视觉消息，则自动切换到下一条，否则关闭当前消息。\n"
             @"3. 视觉消息结束后保持当前消息显示，不自动切换。\n"
             @"4. 仅查看一次的消息将按照普通视觉消息处理。\n"
             @"5. 允许截取视觉消息的屏幕内容。"
        ),

        SPKTopicSection(
            @"消失模式",
            @[
                [SPKSetting switchCellWithTitle:@"禁用上滑手势"
                                           icon:SPKSettingsIcon(@"arrow_up")
                                    defaultsKey:@"msgs_disable_vanish_swipe_up"],

                [SPKSetting switchCellWithTitle:@"禁用截屏检测"
                                           icon:SPKSettingsIcon(@"warning")
                                    defaultsKey:@"msgs_hide_vanish_screenshot"],
            ],

            @"1. 禁用启用消失模式的上滑手势。\n"
             @"2. 消失模式开启时允许截取屏幕内容。"
        ),

        SPKTopicSection(
            @"笔记",
            @[
                [SPKSetting switchCellWithTitle:@"隐藏笔记栏"
                                           icon:SPKSettingsIcon(@"notes")
                                    defaultsKey:@"msgs_hide_notes_tray"],

                [SPKSetting switchCellWithTitle:@"隐藏好友地图"
                                           icon:SPKSettingsIcon(@"map")
                                    defaultsKey:@"msgs_hide_friends_map"],

                SPKAudioGatedSwitch(
                    @"下载笔记音频",
                    SPKSettingsIcon(@"audio"),
                    @"msgs_download_notes_audio"
                ),

                [SPKSetting switchCellWithTitle:@"复制笔记文字"
                                           icon:SPKSettingsIcon(@"copy")
                                    defaultsKey:@"msgs_copy_note_text"]
            ],

            @"长按笔记栏中的笔记即可下载音频或复制文字。只有当笔记包含相应内容时，相关操作才会显示。"
        ),

        SPKTopicSection(
            @"音频",
            @[
                SPKAudioGatedSwitch(
                    @"下载语音消息",
                    SPKSettingsIcon(@"audio_download"),
                    @"msgs_download_audio_messages"
                ),

                [SPKSetting switchCellWithTitle:@"上传音频"
                                           icon:SPKSettingsIcon(@"audio_upload")
                                    defaultsKey:@"msgs_upload_audio_messages"],

                [SPKSetting switchCellWithTitle:@"发送前裁剪"
                                           icon:SPKSettingsIcon(@"trim")
                                    defaultsKey:@"msgs_audio_upload_trim"]
            ],

            @"1. 在支持的语音/音频消息界面添加音频操作。\n"
             @"2. 在输入框的加号（+）菜单中添加选项，可将选中的音频或视频作为语音消息发送。\n"
             @"3. 上传音频时，可选择在发送前裁剪音频。"
        ),

        SPKTopicSection(
            @"媒体",
            @[
                [SPKSetting switchCellWithTitle:@"从图库上传照片"
                                           icon:SPKSettingsIcon(@"photo")
                                    defaultsKey:@"msgs_upload_gallery_media"]
            ],

            @"在输入框的加号（+）菜单中添加选项，可将 Sparkle 图库中的照片发送到聊天中。"
        ),

        SPKTopicSection(
            @"确认",
            @[
                [SPKSetting switchCellWithTitle:@"确认语音通话"
                                           icon:SPKSettingsIcon(@"call")
                                    defaultsKey:kSPKMessagesAudioCallConfirmKey],

                [SPKSetting switchCellWithTitle:@"确认视频通话"
                                           icon:SPKSettingsIcon(@"video")
                                    defaultsKey:kSPKMessagesVideoCallConfirmKey],

                [SPKSetting switchCellWithTitle:@"确认双击"
                                           icon:SPKSettingsIcon(@"heart")
                                    defaultsKey:@"msgs_confirm_double_tap"],

                [SPKSetting switchCellWithTitle:@"确认互动"
                                           icon:SPKSettingsIcon(@"reactions")
                                    defaultsKey:@"msgs_confirm_reaction"],

                [SPKSetting switchCellWithTitle:@"确认语音消息"
                                           icon:SPKSettingsIcon(@"voice")
                                    defaultsKey:@"msgs_confirm_voice_msg"],

                [SPKSetting switchCellWithTitle:@"确认关注请求"
                                           icon:SPKSettingsIcon(@"user_request")
                                    defaultsKey:@"msgs_confirm_follow_request"],

                [SPKSetting switchCellWithTitle:@"确认消失模式"
                                           icon:SPKSettingsIcon(@"vanish")
                                    defaultsKey:@"msgs_confirm_vanish_mode"],

                [SPKSetting switchCellWithTitle:@"确认更改主题"
                                           icon:SPKSettingsIcon(@"palette")
                                    defaultsKey:@"msgs_confirm_theme_change"]
            ],

            @"在发送所选消息操作之前显示确认提示。"
        )
    ];
}


@implementation SPKMessagesSettingsProvider

+ (SPKSetting *)rootSetting {
    SPKSetting *setting =
        [SPKSetting navigationCellWithTitle:@"消息"
                                    subtitle:@""
                                        icon:SPKSettingsIcon(@"messages")
                              viewController:[[SPKMessagesSettingsViewController alloc] init]];

    setting.searchSectionsProvider = ^NSArray * {
        return SPKMessagesSettingsSections();
    };

    return SPKSettingApplyIconTint(
        setting,
        [SPKUtils SPKColor_InstagramPrimaryText]
    );
}

@end
