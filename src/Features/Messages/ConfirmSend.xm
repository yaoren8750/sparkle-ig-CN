#import "../../Utils.h"
#import <objc/runtime.h>

static NSString *const kSPKConfirmSendPref = @"general_confirm_send";
static NSString *const kSPKBottomButtonsViewRuntimeClassName = @"IGShareSheet.IGSharesheetBottomButtonsView";

@interface IGTextButton : UIButton
@property (copy, nonatomic) NSString *text;
@end

static NSString *SPKGetShareTypeFromController(UIViewController *vc) {
    if (!vc)
        return nil;

    id recipientListVC = nil;
    id delegate = nil;

    // IGDirectShareSheetContainerViewController has recipientListViewController
    if ([vc respondsToSelector:@selector(recipientListViewController)]) {
        recipientListVC = [vc performSelector:@selector(recipientListViewController)];
    }
    if ([vc respondsToSelector:@selector(delegate)]) {
        delegate = [vc performSelector:@selector(delegate)];
    }

    // Try finding the delegate of the recipient list view controller if we don't have delegate yet
    if (!delegate && recipientListVC && [recipientListVC respondsToSelector:@selector(delegate)]) {
        delegate = [recipientListVC performSelector:@selector(delegate)];
    }

    // 1. Check Comment
    id commentIdObj = nil;
    if (delegate)
        commentIdObj = [SPKUtils getIvarForObj:delegate name:"_commentId"];
    if (!commentIdObj && recipientListVC)
        commentIdObj = [SPKUtils getIvarForObj:recipientListVC name:"_commentId"];
    if (commentIdObj && [commentIdObj isKindOfClass:[NSString class]] && [(NSString *)commentIdObj length] > 0) {
        return @"comment";
    }

    // 2. Check Story
    id storyItem = nil;
    if (delegate)
        storyItem = [SPKUtils getIvarForObj:delegate name:"_currentStoryItem"];
    if (!storyItem && recipientListVC)
        storyItem = [SPKUtils getIvarForObj:recipientListVC name:"_currentStoryItem"];
    if (storyItem) {
        return @"story";
    }

    // 3. Check Media
    id media = nil;
    if (recipientListVC && [recipientListVC respondsToSelector:@selector(media)]) {
        media = [recipientListVC performSelector:@selector(media)];
    }
    if (!media && delegate) {
        media = [SPKUtils getIvarForObj:delegate name:"_media"];
    }
    if (!media && recipientListVC) {
        media = [SPKUtils getIvarForObj:recipientListVC name:"_media"];
    }

    if (media) {
        if ([media respondsToSelector:@selector(isClipsMedia)] && [media isClipsMedia]) {
            return @"reel";
        }
        if ([media respondsToSelector:@selector(isIGTVMedia)] && [media isIGTVMedia]) {
            return @"IGTV video";
        }
        if ([media respondsToSelector:@selector(isFeedPost)] && [media isFeedPost]) {
            return @"post";
        }
        return @"post";
    }

    // 4. Check SelectedPost (KVC/ivar fallback)
    id selectedPost = nil;
    if (delegate)
        selectedPost = [SPKUtils getIvarForObj:delegate name:"_selectedPost"];
    if (!selectedPost && recipientListVC)
        selectedPost = [SPKUtils getIvarForObj:recipientListVC name:"_selectedPost"];
    if (selectedPost) {
        if ([selectedPost respondsToSelector:@selector(isClipsMedia)] && [selectedPost isClipsMedia]) {
            return @"reel";
        }
        return @"post";
    }

    // 5. Check other types
    id collection = nil;
    if (delegate)
        collection = [SPKUtils getIvarForObj:delegate name:"_collection"];
    if (!collection && recipientListVC)
        collection = [SPKUtils getIvarForObj:recipientListVC name:"_collection"];
    if (collection) {
        return @"collection";
    }

    id audioTrack = nil;
    if (delegate)
        audioTrack = [SPKUtils getIvarForObj:delegate name:"_musicTrack"];
    if (!audioTrack && recipientListVC)
        audioTrack = [SPKUtils getIvarForObj:recipientListVC name:"_musicTrack"];
    if (audioTrack) {
        return @"audio";
    }

    id location = nil;
    if (delegate)
        location = [SPKUtils getIvarForObj:delegate name:"_location"];
    if (!location && recipientListVC)
        location = [SPKUtils getIvarForObj:recipientListVC name:"_location"];
    if (location) {
        return @"location";
    }

    id broadcastOwner = nil;
    if (delegate)
        broadcastOwner = [SPKUtils getIvarForObj:delegate name:"_broadcastOwner"];
    if (!broadcastOwner && recipientListVC)
        broadcastOwner = [SPKUtils getIvarForObj:recipientListVC name:"_broadcastOwner"];
    if (broadcastOwner) {
        return @"broadcast channel";
    }

    return nil;
}

%group SPKConfirmSendHooks

%hook SPKBottomButtonsViewClass

- (void)primaryButtonTappedWithButton:(id)button {
    if (![SPKUtils getBoolPref:kSPKConfirmSendPref]) {
        %orig;
        return;
    }

    if (!button) {
        %orig;
        return;
    }

    // This hook is bound only to the share sheet's bottom-buttons view
    // (IGShareSheet.IGSharesheetBottomButtonsView), whose primary button IS the
    // Send button — so confirm on any primary tap. (The old send/share title sniff
    // was both redundant and localized, silently disabling confirm on non-English.)

    UIViewController *vc = [SPKUtils nearestViewControllerForView:(UIView *)self];
    NSString *contentType = SPKGetShareTypeFromController(vc);
    NSString *title = nil;
    NSString *message = nil;
    if (contentType) {
        title = [NSString stringWithFormat:@"确认发送 %@", [contentType capitalizedString]];
        message = [NSString stringWithFormat:@"确定要发送这个%@吗？", contentType];
    } else {
        title = @"确认发送";
        message = @"确定要发送这个内容吗？?";
    }

    [SPKUtils
        showConfirmation:^{
            %orig;
        }
                   title:title
                 message:message];
}

%end

%end // group SPKConfirmSendHooks

extern "C" void SPKInstallConfirmSendHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class bottomButtonsViewClass = objc_getClass(kSPKBottomButtonsViewRuntimeClassName.UTF8String);
        if (bottomButtonsViewClass) {
            %init(SPKConfirmSendHooks, SPKBottomButtonsViewClass = bottomButtonsViewClass);
        }
    });
}
