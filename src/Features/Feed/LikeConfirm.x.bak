#import "../../Utils.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

extern void SPKMarkStoryAsSeenForViewWithAdvancePref(UIView *view, NSString *advancePrefKey);
extern UIView *SPKActiveStoryOverlayForInteractions(void);

static inline BOOL SPKStoryMarkSeenOnLikeEnabled(void) {
    return [SPKUtils getBoolPref:@"stories_mark_seen_on_like"];
}

static inline BOOL SPKStoryMarkSeenOnReplyEnabled(void) {
    return [SPKUtils getBoolPref:@"stories_mark_seen_on_reply"];
}

static inline BOOL SPKStoryQuickReactionConfirmEnabled(void) {
    return [SPKUtils getBoolPref:@"stories_confirm_quick_reaction"];
}

static inline BOOL SPKStoryInteractionHooksNeeded(void) {
    return [SPKUtils getBoolPref:@"stories_confirm_like"] ||
           SPKStoryMarkSeenOnLikeEnabled() ||
           SPKStoryMarkSeenOnReplyEnabled() ||
           [SPKUtils getBoolPref:@"stories_advance_on_like_seen"] ||
           [SPKUtils getBoolPref:@"stories_advance_on_reply_seen"] ||
           SPKStoryQuickReactionConfirmEnabled();
}

static inline id SPKObjectForSelectorIfAvailable(id target, NSString *selectorName) {
    if (!target || !selectorName.length)
        return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector])
        return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static BOOL SPKBoolValueForSelector(id target, NSString *selectorName, BOOL *resolved) {
    if (resolved)
        *resolved = NO;
    if (!target || !selectorName.length)
        return NO;

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector])
        return NO;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    if (!returnType || !returnType[0])
        return NO;

    if (returnType[0] == '@') {
        id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
        if (!value)
            return NO;
        if ([value respondsToSelector:@selector(boolValue)]) {
            if (resolved)
                *resolved = YES;
            return ((BOOL (*)(id, SEL))objc_msgSend)(value, @selector(boolValue));
        }
        if ([value respondsToSelector:@selector(doubleValue)]) {
            if (resolved)
                *resolved = YES;
            return ((double (*)(id, SEL))objc_msgSend)(value, @selector(doubleValue)) != 0.0;
        }
        if ([value respondsToSelector:@selector(integerValue)]) {
            if (resolved)
                *resolved = YES;
            return ((NSInteger (*)(id, SEL))objc_msgSend)(value, @selector(integerValue)) != 0;
        }
        return NO;
    }

    NSNumber *number = [SPKUtils numericValueForObj:target selectorName:selectorName];
    if (!number)
        return NO;
    if (resolved)
        *resolved = YES;
    return [number boolValue];
}

static BOOL SPKLikeStateFromControl(id control, BOOL *resolved) {
    if (resolved)
        *resolved = NO;
    if (!control)
        return NO;
    if ([control isKindOfClass:[UIControl class]]) {
        if (resolved)
            *resolved = YES;
        return ((UIControl *)control).selected;
    }
    return NO;
}

static BOOL SPKLikeStateFromModel(id model, BOOL *resolved) {
    if (resolved)
        *resolved = NO;
    if (!model)
        return NO;

    for (NSString *selectorName in @[
             @"hasLiked",
             @"isLiked",
             @"isLikedByCurrentUser",
             @"viewerHasLiked",
             @"isLikedByViewer",
             @"liked"
         ]) {
        BOOL found = NO;
        BOOL liked = SPKBoolValueForSelector(model, selectorName, &found);
        if (found) {
            if (resolved)
                *resolved = YES;
            return liked;
        }
    }
    return NO;
}

static void SPKPresentLikeToggleConfirmation(BOOL isUnlike,
                                             NSString *likeTitle,
                                             NSString *likeMessage,
                                             NSString *unlikeTitle,
                                             NSString *unlikeMessage,
                                             void (^handler)(void)) {
    [SPKUtils showConfirmation:handler
                         title:(isUnlike ? unlikeTitle : likeTitle)
                         message:(isUnlike ? unlikeMessage : likeMessage)];
}

static id SPKLikeButtonFromContext(id context) {
    if (!context)
        return nil;
    id button = SPKObjectForSelectorIfAvailable(context, @"likeButton");
    if (button)
        return button;

    id ufiView = [SPKUtils getIvarForObj:context name:"_ufiButtonBarView"];
    if (!ufiView)
        ufiView = SPKObjectForSelectorIfAvailable(context, @"ufiButtonBarView");
    if (!ufiView)
        return nil;

    return SPKObjectForSelectorIfAvailable(ufiView, @"likeButton");
}

static id SPKMediaFromContext(id context) {
    if (!context)
        return nil;
    id media = [SPKUtils getIvarForObj:context name:"_media"];
    if (media)
        return media;

    media = SPKObjectForSelectorIfAvailable(context, @"media");
    if (media)
        return media;

    id viewModel = [SPKUtils getIvarForObj:context name:"_cellViewModel_DO_NOT_USE"];
    if (!viewModel)
        viewModel = SPKObjectForSelectorIfAvailable(context, @"cellViewModel");
    if (!viewModel)
        return nil;

    return SPKObjectForSelectorIfAvailable(viewModel, @"media");
}

static id SPKCommentFromContext(id context) {
    if (!context)
        return nil;
    id comment = [SPKUtils getIvarForObj:context name:"_commentModel"];
    if (comment)
        return comment;

    comment = [SPKUtils getIvarForObj:context name:"_comment"];
    if (comment)
        return comment;

    comment = SPKObjectForSelectorIfAvailable(context, @"commentModel");
    if (comment)
        return comment;

    return SPKObjectForSelectorIfAvailable(context, @"comment");
}

static BOOL SPKFeedLikeIsUnlike(id button, id context) {
    BOOL resolved = NO;
    BOOL liked = SPKLikeStateFromControl(button, &resolved);
    if (!resolved) {
        id likeButton = SPKLikeButtonFromContext(context);
        liked = SPKLikeStateFromControl(likeButton, &resolved);
    }
    if (!resolved) {
        id media = SPKMediaFromContext(context);
        liked = SPKLikeStateFromModel(media, &resolved);
    }
    return resolved && liked;
}

static BOOL SPKCommentLikeIsUnlike(id button, id context) {
    BOOL resolved = NO;
    BOOL liked = SPKLikeStateFromControl(button, &resolved);
    if (!resolved) {
        id likeButton = SPKLikeButtonFromContext(context);
        liked = SPKLikeStateFromControl(likeButton, &resolved);
    }
    if (!resolved) {
        id comment = SPKCommentFromContext(context);
        liked = SPKLikeStateFromModel(comment, &resolved);
    }
    return resolved && liked;
}

static void SPKStoryMarkSeenForInteractionView(UIView *view, NSString *advancePrefKey) {
    if (!view)
        return;
    SPKMarkStoryAsSeenForViewWithAdvancePref(view, advancePrefKey);
}

static void SPKStoryReplySideEffects(void) {
    if (!SPKStoryMarkSeenOnReplyEnabled())
        return;
    UIView *overlay = SPKActiveStoryOverlayForInteractions();
    if (!overlay)
        return;
    SPKStoryMarkSeenForInteractionView(overlay, @"stories_advance_on_reply_seen");
}

///////////////////////////////////////////////////////////

// Confirmation handlers

static BOOL SPKBypassFeedPostLikeConfirm = NO;

#define SPK_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig) \
    do {                                                 \
        SPKBypassFeedPostLikeConfirm = YES;              \
        @try {                                           \
            orig;                                        \
        } @finally {                                     \
            SPKBypassFeedPostLikeConfirm = NO;           \
        }                                                \
    } while (0)

// A single comment like tap fans out through a forwarding chain: the Swift
// IGCommentCell handler forwards to IGCommentCellController (and the combined
// like/dislike variants forward to the plain ones). Each link is hooked, so
// without a guard the confirmation is presented once per link — the user sees
// a second prompt after confirming the first. We wrap the confirmed %orig in a
// re-entrancy flag so the forwarded calls run through untouched.
static BOOL SPKBypassCommentLikeConfirm = NO;

#define SPK_RUN_WITH_COMMENT_LIKE_CONFIRM_BYPASS(orig) \
    do {                                               \
        SPKBypassCommentLikeConfirm = YES;             \
        @try {                                         \
            orig;                                      \
        } @finally {                                   \
            SPKBypassCommentLikeConfirm = NO;          \
        }                                              \
    } while (0)

// The confirm-like pref must never affect the dislike button. Its state update
// enum (dislikeUpdate) is unreliable across builds, so we key off the tapped
// button's accessibility identifier ("comment-dislike-button") / label instead.
static BOOL SPKCommentButtonIsDislike(id button) {
    if (![button isKindOfClass:[UIView class]])
        return NO;
    UIView *view = (UIView *)button;
    NSString *identifier = view.accessibilityIdentifier.lowercaseString;
    if ([identifier containsString:@"dislike"])
        return YES;
    NSString *label = view.accessibilityLabel.lowercaseString;
    if ([label containsString:@"dislike"])
        return YES;
    return NO;
}

#define SPKCONFIRMLIKE(prefKey, logText, titleText, messageText, orig) \
    if ([SPKUtils getBoolPref:prefKey]) {                              \
        SPKLog(@"General", @"[Sparkle] %@", logText);                  \
        [SPKUtils                                                      \
            showConfirmation:^(void) {                                 \
                orig;                                                  \
            }                                                          \
                       title:titleText                                 \
                     message:messageText];                             \
    } else {                                                           \
        return orig;                                                   \
    }

#define CONFIRMFEEDPOSTLIKE(context, button, orig)                                                       \
    if (SPKBypassFeedPostLikeConfirm) {                                                                  \
        return orig;                                                                                     \
    }                                                                                                    \
    if ([SPKUtils getBoolPref:@"feed_confirm_post_like"]) {                                              \
        BOOL isUnlike = SPKFeedLikeIsUnlike((button), (context));                                        \
        SPKLog(@"General", @"[Sparkle] Confirm feed post %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SPKPresentLikeToggleConfirmation(                                                                \
            isUnlike,                                                                                    \
            @"Confirm Post Like",                                                                        \
            @"Are you sure you want to like this post?",                                                 \
            @"Confirm Post Unlike",                                                                      \
            @"Are you sure you want to unlike this post?",                                               \
            ^{                                                                                           \
                SPK_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig);                                        \
            });                                                                                          \
    } else {                                                                                             \
        return orig;                                                                                     \
    }

#define CONFIRMFEEDDOUBLETAPLIKE(context, orig)                                                                \
    if ([SPKUtils getBoolPref:@"feed_confirm_double_tap_like"]) {                                              \
        BOOL isUnlike = SPKFeedLikeIsUnlike(nil, (context));                                                   \
        SPKLog(@"General", @"[Sparkle] Confirm feed double-tap %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SPKPresentLikeToggleConfirmation(                                                                      \
            isUnlike,                                                                                          \
            @"Confirm Post Like",                                                                              \
            @"Are you sure you want to like this post?",                                                       \
            @"Confirm Post Unlike",                                                                            \
            @"Are you sure you want to unlike this post?",                                                     \
            ^{                                                                                                 \
                SPK_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig);                                              \
            });                                                                                                \
    } else {                                                                                                   \
        SPK_RUN_WITH_FEED_POST_LIKE_CONFIRM_BYPASS(orig);                                                      \
    }

#define CONFIRMCOMMENTLIKE(context, button, orig)                                                      \
    if (SPKBypassCommentLikeConfirm || SPKCommentButtonIsDislike(button)) {                            \
        return orig;                                                                                   \
    }                                                                                                  \
    if ([SPKUtils getBoolPref:@"general_comments_confirm_like"]) {                                     \
        BOOL isUnlike = SPKCommentLikeIsUnlike((button), (context));                                   \
        SPKLog(@"General", @"[Sparkle] Confirm comment %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SPKPresentLikeToggleConfirmation(                                                              \
            isUnlike,                                                                                  \
            @"Confirm Comment Like",                                                                   \
            @"Are you sure you want to like this comment?",                                            \
            @"Confirm Comment Unlike",                                                                 \
            @"Are you sure you want to unlike this comment?",                                          \
            ^{                                                                                         \
                SPK_RUN_WITH_COMMENT_LIKE_CONFIRM_BYPASS(orig);                                        \
            });                                                                                        \
    } else {                                                                                           \
        return orig;                                                                                   \
    }

// The combined like/dislike handlers fire for BOTH the like and the dislike
// button. `dislikeUpdate` being nonzero is a secondary signal that the dislike
// button was tapped (the button-identifier check in CONFIRMCOMMENTLIKE is the
// primary one) — either way the confirm-like pref must not apply.
#define CONFIRMCOMMENTLIKEORDISLIKE(context, button, dislikeUpdate, orig) \
    if ((dislikeUpdate) != 0) {                                          \
        return orig;                                                     \
    }                                                                    \
    CONFIRMCOMMENTLIKE(context, button, orig)

#define CONFIRMREELSLIKE(context, button, orig)                                                      \
    if ([SPKUtils getBoolPref:@"reels_confirm_like"]) {                                              \
        BOOL isUnlike = SPKFeedLikeIsUnlike((button), (context));                                    \
        SPKLog(@"General", @"[Sparkle] Confirm reels %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SPKPresentLikeToggleConfirmation(                                                            \
            isUnlike,                                                                                \
            @"Confirm Reel Like",                                                                    \
            @"Are you sure you want to like this reel?",                                             \
            @"Confirm Reel Unlike",                                                                  \
            @"Are you sure you want to unlike this reel?",                                           \
            ^{                                                                                       \
                orig;                                                                                \
            });                                                                                      \
    } else {                                                                                         \
        return orig;                                                                                 \
    }

#define CONFIRMREELSDOUBLETAPLIKE(context, orig)                                                                \
    if ([SPKUtils getBoolPref:@"reels_confirm_double_tap_like"]) {                                              \
        BOOL isUnlike = SPKFeedLikeIsUnlike(nil, (context));                                                    \
        SPKLog(@"General", @"[Sparkle] Confirm reels double-tap %@ triggered", isUnlike ? @"unlike" : @"like"); \
        SPKPresentLikeToggleConfirmation(                                                                       \
            isUnlike,                                                                                           \
            @"Confirm Reel Like",                                                                               \
            @"Are you sure you want to like this reel?",                                                        \
            @"Confirm Reel Unlike",                                                                             \
            @"Are you sure you want to unlike this reel?",                                                      \
            ^{                                                                                                  \
                orig;                                                                                           \
            });                                                                                                 \
    } else {                                                                                                    \
        return orig;                                                                                            \
    }

///////////////////////////////////////////////////////////

// Liking posts
%group SPKLikeConfirmHooks

%hook IGUFIButtonBarView
- (void)_onLikeButtonPressed {
    CONFIRMFEEDPOSTLIKE(self, nil, %orig);
}
- (void)_onLikeButtonPressed:(id)arg1 {
    CONFIRMFEEDPOSTLIKE(self, arg1, %orig);
}
%end
%hook IGFeedItemUFICell
- (void)UFIButtonBarDidTapOnLike:(id)arg1 {
    CONFIRMFEEDPOSTLIKE(self, arg1, %orig);
}
%end
%hook IGFeedItemUFICellConfigurableDelegateImpl
- (void)feedItemUFICellDidTapLikeButton:(id)arg1 {
    CONFIRMFEEDPOSTLIKE(self, arg1, %orig);
}
- (void)_performSingleTapLikeToggle {
    CONFIRMFEEDPOSTLIKE(self, nil, %orig);
}
%end
%hook IGFeedPhotoView
- (void)_onDoubleTap {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
- (void)_onDoubleTap:(id)arg1 {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
%end
%hook IGVideoPlayerOverlayContainerView
- (void)_handleDoubleTapGesture:(id)arg1 {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
// IG 436+ : the Swift-rewritten IGModernFeedVideoOverlays.IGVideoPlayerOverlayContainerView
// dropped the leading underscore from this selector.
- (void)handleDoubleTapGesture:(id)arg1 {
    CONFIRMFEEDDOUBLETAPLIKE(self, %orig);
}
%end

// Liking reels
%hook IGSundialViewerVideoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)controlsOverlayControllerDidLongPressLikeButton:(id)arg1 gestureRecognizer:(id)arg2 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
%end
%hook IGSundialViewerPhotoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
- (void)swift_photoCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
%end
%hook IGSundialViewerCarouselCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(self, arg1, %orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
- (void)carouselCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    CONFIRMREELSDOUBLETAPLIKE(self, %orig);
}
%end

// Liking comments
%hook IGCommentCellController
- (void)commentCell:(id)arg1 didTapLikeButton:(id)arg2 {
    CONFIRMCOMMENTLIKE(arg1, arg2, %orig);
}
// IG 436+ (comment dislikes): like taps route through this combined handler.
- (void)commentCell:(id)arg1 didTapLikeOrDislikeButton:(id)arg2 likeButton:(id)arg3 dislikeUpdate:(long long)arg4 {
    // arg2 is the button that was actually tapped (like or dislike); check it so
    // the dislike button is filtered by identifier, not just by dislikeUpdate.
    CONFIRMCOMMENTLIKEORDISLIKE(arg1, arg2, arg4, %orig);
}
- (void)commentCell:(id)arg1 didTapLikedByButtonForUser:(id)arg2 {
    CONFIRMCOMMENTLIKE(nil, nil, %orig);
}
- (void)commentCellDidLongPressOnLikeButton:(id)arg1 {
    CONFIRMCOMMENTLIKE(nil, arg1, %orig);
}
- (void)commentCellDidEndLongPressOnLikeButton:(id)arg1 {
    CONFIRMCOMMENTLIKE(nil, arg1, %orig);
}
- (void)commentCellDidDoubleTap:(id)arg1 {
    CONFIRMCOMMENTLIKE(arg1, nil, %orig);
}
%end
%hook IGFeedItemPreviewCommentCell
- (void)_didTapLikeButton {
    CONFIRMCOMMENTLIKE(self, nil, %orig);
}
%end
// IG 436+ : in the comment thread/detail view the like (and like/dislike) tap
// lands on the Swift comment cell (IGCommentCells.IGCommentCell) before it
// forwards to its UFI delegate (IGCommentCellController). Both links are hooked
// so gating works whichever fires; the SPKBypassCommentLikeConfirm guard keeps
// the forwarded call from surfacing a second prompt after the first is confirmed.
%hook IGCommentCell
- (void)contentViewDidTapLike:(id)arg1 {
    CONFIRMCOMMENTLIKE(self, arg1, %orig);
}
// Combined like/dislike handler. Unlike the controller variant, this method has
// NO tapped-button parameter — it always receives both the dislike button (arg1)
// and the like button (arg2), whichever was tapped — and `dislikeUpdate` is
// unreliable across builds. So we can't tell here whether the user liked or
// disliked. Pass it straight through: a *like* tap fans out to the plain
// contentViewDidTapLike: above (which confirms with the unambiguous like button),
// while a *dislike* tap fans out to an unhooked dislike handler and never
// surfaces the like-confirm prompt.
- (void)contentViewDidTapLikeOrDislikeButtonWithDislikeButton:(id)arg1 likeButton:(id)arg2 dislikeUpdate:(long long)arg3 {
    return %orig;
}
%end

// Liking stories (newer Instagram builds)
static void (*orig_spkStoryLikeTap)(id, SEL, id);
static void new_spkStoryLikeTap(id self, SEL _cmd, id button) {
    if (![SPKUtils getBoolPref:@"stories_confirm_like"]) {
        orig_spkStoryLikeTap(self, _cmd, button);
        if (SPKStoryMarkSeenOnLikeEnabled() && [button isKindOfClass:[UIView class]]) {
            SPKStoryMarkSeenForInteractionView((UIView *)button, @"stories_advance_on_like_seen");
        }
        return;
    }

    BOOL isSelected = [button isKindOfClass:[UIButton class]] ? [(UIButton *)button isSelected] : NO;
    BOOL isUnlike = !isSelected;

    UIButton *btn = [button isKindOfClass:[UIButton class]] ? (UIButton *)button : nil;
    SEL setLikedSel = NSSelectorFromString(@"setIsLiked:animated:");

    [SPKUtils
        showConfirmation:^{
            if (btn) {
                [btn setSelected:isSelected];
                if ([btn respondsToSelector:setLikedSel]) {
                    ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(btn, setLikedSel, isSelected, YES);
                }
            }
            orig_spkStoryLikeTap(self, _cmd, button);
            if (!isUnlike && SPKStoryMarkSeenOnLikeEnabled() && [button isKindOfClass:[UIView class]]) {
                SPKStoryMarkSeenForInteractionView((UIView *)button, @"stories_advance_on_like_seen");
            }
        }
                   title:(isUnlike ? @"Confirm Story Unlike" : @"Confirm Story Like")
                   message:(isUnlike ? @"Are you sure you want to unlike this story?" : @"Are you sure you want to like this story?")];

    if (btn) {
        [UIView performWithoutAnimation:^{
            [btn setSelected:!isSelected];
            if ([btn respondsToSelector:setLikedSel]) {
                ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(btn, setLikedSel, !isSelected, NO);
            }
        }];
    }
}

static void SPKInstallStoryLikeConfirmHookIfNeeded(void) {
    if (!SPKStoryInteractionHooksNeeded()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"_TtC22IGStoryLikesController38IGStoryLikesInteractionControllingImpl");
        if (!cls)
            cls = NSClassFromString(@"IGStoryLikesInteractionControllingImpl");
        if (!cls)
            return;

        SEL sel = NSSelectorFromString(@"handleStoryLikeTapWith:");
        if (!class_getInstanceMethod(cls, sel)) {
            sel = NSSelectorFromString(@"handleStoryLikeTapWithButton:");
        }
        if (!class_getInstanceMethod(cls, sel))
            return;

        MSHookMessageEx(cls, sel, (IMP)new_spkStoryLikeTap, (IMP *)&orig_spkStoryLikeTap);
    });
}

%hook IGDirectComposer
- (void)_didTapSend {
    %orig;
    SPKStoryReplySideEffects();
}

- (void)_didTapSend:(id)arg {
    %orig;
    SPKStoryReplySideEffects();
}

- (void)_send {
    %orig;
    SPKStoryReplySideEffects();
}

- (void)_didTapEmojiQuickReactionButton:(id)button {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                %orig;
                if (SPKActiveStoryOverlayForInteractions())
                    SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (SPKActiveStoryOverlayForInteractions()) {
        %orig;
        SPKStoryReplySideEffects();
        return;
    }
    %orig;
}

- (void)_didTapEmojiReactionButton:(id)button {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                %orig;
                if (SPKActiveStoryOverlayForInteractions())
                    SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (SPKActiveStoryOverlayForInteractions()) {
        %orig;
        SPKStoryReplySideEffects();
        return;
    }
    %orig;
}
%end

static void (*orig_storyFooterEmojiQuick)(id, SEL, id, id);
static void SPKHookedStoryFooterEmojiQuick(id self, SEL _cmd, id inputView, id button) {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                if (orig_storyFooterEmojiQuick)
                    orig_storyFooterEmojiQuick(self, _cmd, inputView, button);
                SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (orig_storyFooterEmojiQuick)
        orig_storyFooterEmojiQuick(self, _cmd, inputView, button);
    SPKStoryReplySideEffects();
}

static void (*orig_storyFooterEmojiReaction)(id, SEL, id, id);
static void SPKHookedStoryFooterEmojiReaction(id self, SEL _cmd, id inputView, id button) {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                if (orig_storyFooterEmojiReaction)
                    orig_storyFooterEmojiReaction(self, _cmd, inputView, button);
                SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (orig_storyFooterEmojiReaction)
        orig_storyFooterEmojiReaction(self, _cmd, inputView, button);
    SPKStoryReplySideEffects();
}

static void (*orig_storyQuickReaction)(id, SEL, id, id, id);
static void SPKHookedStoryQuickReaction(id self, SEL _cmd, id view, id sourceButton, id emoji) {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                if (orig_storyQuickReaction)
                    orig_storyQuickReaction(self, _cmd, view, sourceButton, emoji);
                SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (orig_storyQuickReaction)
        orig_storyQuickReaction(self, _cmd, view, sourceButton, emoji);
    SPKStoryReplySideEffects();
}

static void (*orig_storyPrivateEmojiQuick)(id, SEL, id);
static void SPKHookedStoryPrivateEmojiQuick(id self, SEL _cmd, id button) {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                if (orig_storyPrivateEmojiQuick)
                    orig_storyPrivateEmojiQuick(self, _cmd, button);
                SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (orig_storyPrivateEmojiQuick)
        orig_storyPrivateEmojiQuick(self, _cmd, button);
    SPKStoryReplySideEffects();
}

static void (*orig_directReshareQuickReaction)(id, SEL, id);
static void SPKHookedDirectReshareQuickReaction(id self, SEL _cmd, id arg) {
    if (SPKStoryQuickReactionConfirmEnabled()) {
        [SPKUtils
            showConfirmation:^{
                if (orig_directReshareQuickReaction)
                    orig_directReshareQuickReaction(self, _cmd, arg);
                SPKStoryReplySideEffects();
            }
                       title:@"Confirm Quick Reaction"
                     message:@"Are you sure you want to send this emoji reaction?"];
        return;
    }
    if (orig_directReshareQuickReaction)
        orig_directReshareQuickReaction(self, _cmd, arg);
    SPKStoryReplySideEffects();
}

static Class SPKStoryReplyFooterClass(void) {
    for (NSString *className in @[
             @"IGStoryDefaultFooter.IGStoryFullscreenDefaultFooterView",
             @"IGStoryFullscreenDefaultFooterView"
         ]) {
        Class cls = NSClassFromString(className);
        if (cls)
            return cls;
    }
    return Nil;
}

static void SPKInstallStoryReplyHooksIfNeeded(void) {
    if (!SPKStoryInteractionHooksNeeded())
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class footerClass = SPKStoryReplyFooterClass();
        SEL quickSelector = NSSelectorFromString(@"inputView:didTapEmojiQuickReactionButton:");
        if (footerClass && class_getInstanceMethod(footerClass, quickSelector)) {
            MSHookMessageEx(footerClass, quickSelector, (IMP)SPKHookedStoryFooterEmojiQuick, (IMP *)&orig_storyFooterEmojiQuick);
        }

        SEL reactionSelector = NSSelectorFromString(@"inputView:didTapEmojiReactionButton:");
        if (footerClass && class_getInstanceMethod(footerClass, reactionSelector)) {
            MSHookMessageEx(footerClass, reactionSelector, (IMP)SPKHookedStoryFooterEmojiReaction, (IMP *)&orig_storyFooterEmojiReaction);
        }

        Class quickReactionClass = NSClassFromString(@"IGStoryQuickReactions.IGStoryQuickReactionsController");
        if (!quickReactionClass)
            quickReactionClass = NSClassFromString(@"IGStoryQuickReactionsController");
        SEL quickReactionSelector = NSSelectorFromString(@"quickReactionsView:sourceEmojiButton:didTapEmoji:");
        if (quickReactionClass && class_getInstanceMethod(quickReactionClass, quickReactionSelector)) {
            MSHookMessageEx(quickReactionClass, quickReactionSelector, (IMP)SPKHookedStoryQuickReaction, (IMP *)&orig_storyQuickReaction);
        }

        SEL privateQuickSelector = NSSelectorFromString(@"_didTapEmojiQuickReactionButton:");
        if (footerClass && class_getInstanceMethod(footerClass, privateQuickSelector)) {
            MSHookMessageEx(footerClass, privateQuickSelector, (IMP)SPKHookedStoryPrivateEmojiQuick, (IMP *)&orig_storyPrivateEmojiQuick);
        }

        Class quickReactionDelegateClass = NSClassFromString(@"_TtC29IGStoryQuickReactionsDelegate33IGStoryQuickReactionsDelegateImpl");
        if (!quickReactionDelegateClass)
            quickReactionDelegateClass = NSClassFromString(@"IGStoryQuickReactionsDelegateImpl");
        SEL directReshareSelector = NSSelectorFromString(@"directReshareMediaReplyFooterViewDidTapQuickReactionEmoji:");
        if (quickReactionDelegateClass && class_getInstanceMethod(quickReactionDelegateClass, directReshareSelector)) {
            MSHookMessageEx(quickReactionDelegateClass, directReshareSelector, (IMP)SPKHookedDirectReshareQuickReaction, (IMP *)&orig_directReshareQuickReaction);
        }
    });
}

// DM like button (seems to be hidden)
%hook IGDirectThreadViewController
- (void)_didTapLikeButton {
    %orig;
}
- (void)_didTapLikeButton:(id)arg1 {
    %orig;
}
%end

%end

static void (*orig_spkReelsLikeHandlerTap)(id, SEL, id, id, BOOL) = NULL;
static void spkReelsLikeHandlerTap(id self, SEL _cmd, id context, id likeButton, BOOL willAnimate) {
    if (![SPKUtils getBoolPref:@"reels_confirm_like"]) {
        if (orig_spkReelsLikeHandlerTap)
            orig_spkReelsLikeHandlerTap(self, _cmd, context, likeButton, willAnimate);
        return;
    }

    __strong id strongContext = context;
    __strong id strongButton = likeButton;
    BOOL isUnlike = SPKFeedLikeIsUnlike(strongButton, strongContext);
    SPKLog(@"General", @"[Sparkle] Confirm reels %@ triggered", isUnlike ? @"unlike" : @"like");
    SPKPresentLikeToggleConfirmation(
        isUnlike,
        @"Confirm Reel Like",
        @"Are you sure you want to like this reel?",
        @"Confirm Reel Unlike",
        @"Are you sure you want to unlike this reel?",
        ^{
            if (orig_spkReelsLikeHandlerTap)
                orig_spkReelsLikeHandlerTap(self, _cmd, strongContext, strongButton, willAnimate);
        });
}

static void (*orig_spkReelsLikeHandlerTapCompletion)(id, SEL, id, id, BOOL, id) = NULL;
static void spkReelsLikeHandlerTapCompletion(id self, SEL _cmd, id context, id likeButton, BOOL willAnimate, id completion) {
    if (![SPKUtils getBoolPref:@"reels_confirm_like"]) {
        if (orig_spkReelsLikeHandlerTapCompletion)
            orig_spkReelsLikeHandlerTapCompletion(self, _cmd, context, likeButton, willAnimate, completion);
        return;
    }

    __strong id strongContext = context;
    __strong id strongButton = likeButton;
    id strongCompletion = completion ? [completion copy] : nil;
    BOOL isUnlike = SPKFeedLikeIsUnlike(strongButton, strongContext);
    SPKLog(@"General", @"[Sparkle] Confirm reels %@ triggered", isUnlike ? @"unlike" : @"like");
    SPKPresentLikeToggleConfirmation(
        isUnlike,
        @"Confirm Reel Like",
        @"Are you sure you want to like this reel?",
        @"Confirm Reel Unlike",
        @"Are you sure you want to unlike this reel?",
        ^{
            if (orig_spkReelsLikeHandlerTapCompletion)
                orig_spkReelsLikeHandlerTapCompletion(self, _cmd, strongContext, strongButton, willAnimate, strongCompletion);
        });
}

static void SPKInstallReelsSwiftLikeConfirmHookIfNeeded(void) {
    if (![SPKUtils getBoolPref:@"reels_confirm_like"])
        return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"_TtC30IGSundialOverlayActionHandlers38IGSundialViewerLikeButtonActionHandler");
        if (!cls)
            cls = NSClassFromString(@"IGSundialViewerLikeButtonActionHandler");
        Class meta = cls ? object_getClass(cls) : Nil;
        if (!meta)
            return;

        SEL tapSel = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:");
        if (class_getClassMethod(cls, tapSel)) {
            MSHookMessageEx(meta, tapSel, (IMP)spkReelsLikeHandlerTap, (IMP *)&orig_spkReelsLikeHandlerTap);
        }

        SEL tapCompletionSel = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:completion:");
        if (class_getClassMethod(cls, tapCompletionSel)) {
            MSHookMessageEx(meta, tapCompletionSel, (IMP)spkReelsLikeHandlerTapCompletion, (IMP *)&orig_spkReelsLikeHandlerTapCompletion);
        }
    });
}

void SPKInstallLikeConfirmHooksIfNeeded(void) {
    if (![SPKUtils getBoolPref:@"feed_confirm_post_like"] &&
        ![SPKUtils getBoolPref:@"feed_confirm_double_tap_like"] &&
        ![SPKUtils getBoolPref:@"general_comments_confirm_like"] &&
        ![SPKUtils getBoolPref:@"reels_confirm_like"] &&
        ![SPKUtils getBoolPref:@"reels_confirm_double_tap_like"] &&
        !SPKStoryInteractionHooksNeeded()) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKLikeConfirmHooks,
                       IGVideoPlayerOverlayContainerView = SPKResolveIGClass(@"IGModernFeedVideoOverlays.IGVideoPlayerOverlayContainerView", @"IGVideoPlayerOverlayContainerView"),
                       IGCommentCell = SPKResolveIGClass(@"IGCommentCells.IGCommentCell", @"IGCommentCell"));
    });

    SPKInstallStoryLikeConfirmHookIfNeeded();
    SPKInstallStoryReplyHooksIfNeeded();
    SPKInstallReelsSwiftLikeConfirmHookIfNeeded();
}
