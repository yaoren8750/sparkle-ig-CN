#import "SPKActionDescriptor.h"
#import "ActionButtonCore.h"

@implementation SPKActionDescriptor

+ (instancetype)descriptorWithIdentifier:(NSString *)identifier
                                   title:(NSString *)title
                                iconName:(NSString *)iconName {
    SPKActionDescriptor *descriptor = [[self alloc] init];
    descriptor.identifier = identifier;
    descriptor.title = title;
    descriptor.iconName = iconName;
    return descriptor;
}

+ (NSArray<SPKActionDescriptor *> *)descriptors {
    static NSArray<SPKActionDescriptor *> *descriptors = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        descriptors = @[
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadLibrary
                                                    title:@"保存到照片"
                                                 iconName:@"download"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadShare
                                                    title:@"分享"
                                                 iconName:@"share"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionCopyDownloadLink
                                                    title:@"复制下载链接"
                                                 iconName:@"link"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionCopyMedia
                                                    title:@"复制媒体"
                                                 iconName:@"copy"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadGallery
                                                    title:@"保存到图库"
                                                 iconName:@"sparkle_gallery"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionTrimSave
                                                    title:@"裁剪并保存"
                                                 iconName:@"trim"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionEditSave
                                                    title:@"编辑并保存"
                                                 iconName:@"crop"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAudio
                                                    title:@"将音频保存到文件"
                                                 iconName:@"audio_download"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAudioShare
                                                    title:@"分享音频"
                                                 iconName:@"share"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAudioGallery
                                                    title:@"将音频保存到图库"
                                                 iconName:@"sparkle_gallery"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionPlayAudio
                                                    title:@"播放音频"
                                                 iconName:@"play"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionCopyAudioURL
                                                    title:@"复制音频下载链接"
                                                 iconName:@"link"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAllLibrary
                                                    title:@"全部保存到照片"
                                                 iconName:@"download"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAllShare
                                                    title:@"全部分享"
                                                 iconName:@"share"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAllGallery
                                                    title:@"全部保存到图库"
                                                 iconName:@"sparkle_gallery"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAllClipboard
                                                    title:@"复制全部媒体"
                                                 iconName:@"copy"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAllLinks
                                                    title:@"复制下载链接"
                                                 iconName:@"link"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDownloadAll
                                                    title:@"全部下载"
                                                 iconName:@"more"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionExpand
                                                    title:@"展开"
                                                 iconName:@"expand"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionViewThumbnail
                                                    title:@"查看缩略图"
                                                 iconName:@"photo_gallery"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionCopyCaption
                                                    title:@"复制说明"
                                                 iconName:@"caption"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionOpenTopicSettings
                                                    title:@"设置"
                                                 iconName:@"settings"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionDeletedMessagesLog
                                                    title:@"已删除消息"
                                                 iconName:@"channels"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionRepost
                                                    title:@"转发"
                                                 iconName:@"repost"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionToggleStorySeenUserRule
                                                    title:@"切换快拍用户规则"
                                                 iconName:@"eye"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionToggleStoryAutoSaveUserRule
                                                    title:@"切换快拍自动保存"
                                                 iconName:@"download"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionToggleDirectAutoSaveThreadRule
                                                    title:@"切换聊天自动保存"
                                                 iconName:@"download"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionToggleProfileStorySeenUserRule
                                                    title:@"切换快拍已读状态"
                                                 iconName:@"eye"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionToggleProfileMessagesSeenUserRule
                                                    title:@"切换消息已读状态"
                                                 iconName:@"eye"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionStoryMentionsSheet
                                                    title:@"快拍提及"
                                                 iconName:@"mention"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionProfileCopyInfo
                                                    title:@"复制信息"
                                                 iconName:@"info"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionProfileCopyID
                                                    title:@"复制 ID"
                                                 iconName:@"key"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionProfileCopyUsername
                                                    title:@"复制用户名"
                                                 iconName:@"用户名"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionProfileCopyName
                                                    title:@"复制名称"
                                                 iconName:@"text"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionProfileCopyBio
                                                    title:@"复制简介"
                                                 iconName:@"caption"],
            [SPKActionDescriptor descriptorWithIdentifier:kSPKActionProfileCopyLink
                                                    title:@"复制个人资料链接"
                                                 iconName:@"link"],
            [SPKActionDescriptor descriptorWithIdentifier:@"more"
                                                    title:@"更多"
                                                 iconName:@"more"],
            [SPKActionDescriptor descriptorWithIdentifier:@"action"
                                                    title:@"操作"
                                                 iconName:@"action"]
        ];
    });
    return descriptors;
}

+ (nullable instancetype)descriptorForIdentifier:(NSString *)identifier {
    for (SPKActionDescriptor *descriptor in [self descriptors]) {
        if ([descriptor.identifier isEqualToString:identifier]) {
            return descriptor;
        }
    }
    return nil;
}

+ (NSArray<SPKActionDescriptor *> *)availableSectionIconDescriptors {
    return @[
        [SPKActionDescriptor descriptorWithIdentifier:@"action"
                                                title:@"操作"
                                             iconName:@"action"],
        [SPKActionDescriptor descriptorWithIdentifier:@"copy"
                                                title:@"复制"
                                             iconName:@"copy"],
        [SPKActionDescriptor descriptorWithIdentifier:@"key"
                                                title:@"键"
                                             iconName:@"key"],
        [SPKActionDescriptor descriptorWithIdentifier:@"caption"
                                                title:@"说明"
                                             iconName:@"caption"],
        [SPKActionDescriptor descriptorWithIdentifier:@"download"
                                                title:@"下载"
                                             iconName:@"download"],
        [SPKActionDescriptor descriptorWithIdentifier:@"share"
                                                title:@"分享"
                                             iconName:@"share"],
        [SPKActionDescriptor descriptorWithIdentifier:@"link"
                                                title:@"链接"
                                             iconName:@"link"],
        [SPKActionDescriptor descriptorWithIdentifier:@"media"
                                                title:@"图库"
                                             iconName:@"sparkle_gallery"],
        [SPKActionDescriptor descriptorWithIdentifier:@"expand"
                                                title:@"展开"
                                             iconName:@"expand"],
        [SPKActionDescriptor descriptorWithIdentifier:@"photo_gallery"
                                                title:@"缩略图"
                                             iconName:@"photo_gallery"],
        [SPKActionDescriptor descriptorWithIdentifier:@"repost"
                                                title:@"转发"
                                             iconName:@"repost"],
        [SPKActionDescriptor descriptorWithIdentifier:@"mention"
                                                title:@"提及"
                                             iconName:@"mention"],
        [SPKActionDescriptor descriptorWithIdentifier:@"feed"
                                                title:@"动态"
                                             iconName:@"feed"],
        [SPKActionDescriptor descriptorWithIdentifier:@"reels"
                                                title:@"Reels"
                                             iconName:@"reels"],
        [SPKActionDescriptor descriptorWithIdentifier:@"story"
                                                title:@"快拍"
                                             iconName:@"story"],
        [SPKActionDescriptor descriptorWithIdentifier:@"messages"
                                                title:@"消息"
                                             iconName:@"messages"],
        [SPKActionDescriptor descriptorWithIdentifier:@"profile"
                                                title:@"个人资料"
                                             iconName:@"user_circle"],
        [SPKActionDescriptor descriptorWithIdentifier:@"settings"
                                                title:@"设置"
                                             iconName:@"settings"],
        [SPKActionDescriptor descriptorWithIdentifier:@"more"
                                                title:@"更多"
                                             iconName:@"more"]
    ];
}

@end

NSString *SPKActionDescriptorDisplayTitle(NSString *identifier, NSString *topicTitle) {
    if ([identifier isEqualToString:kSPKActionOpenTopicSettings] && topicTitle.length > 0) {
        return [NSString stringWithFormat:@"%@ Settings", topicTitle];
    }
    SPKActionDescriptor *descriptor = [SPKActionDescriptor descriptorForIdentifier:identifier];
    return descriptor.title ?: @"Action";
}

NSString *SPKActionDescriptorIconName(NSString *identifier) {
    SPKActionDescriptor *descriptor = [SPKActionDescriptor descriptorForIdentifier:identifier];
    return descriptor.iconName ?: @"action";
}
