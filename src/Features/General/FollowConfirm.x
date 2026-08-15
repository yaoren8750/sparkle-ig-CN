#import "../../InstagramHeaders.h"
#import "../../Utils.h"

////////////////////////////////////////////////////////

%group SPKFollowConfirmHooks

// Follow button on profile page
%hook IGFollowController

- (void)_didPressFollowButton {
    // Get user follow status
    NSInteger UserFollowStatus = self.user.followStatus;

    // Only show confirmation when the user is not already following
    if (UserFollowStatus == 2) {
        if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

            SPKLog(@"General", @"[Sparkle] Confirm follow triggered");

            [SPKUtils
                showConfirmation:^{
                    %orig;
                }
                           title:@"确认关注"
                         message:@"确定要关注此账号吗？"];

        } else {
            %orig;
        }
    } else {
        %orig;
    }
}


// Unfollow from profile action sheet
- (void)_performUnfollow {
    if ([SPKUtils getBoolPref:@"profile_confirm_unfollow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认取消关注"
                     message:@"确定要取消关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

// Follow button on discover people page
%hook IGDiscoverPeopleButtonGroupView

- (void)_onFollowButtonTapped:(id)arg1 {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

- (void)_onFollowingButtonTapped:(id)arg1 {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

// Suggested for you (home feed & profile) follow button
%hook IGHScrollAYMFCell

- (void)_didTapAYMFActionButton {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

%hook IGHScrollAYMFActionButton

- (void)_didTapTextActionButton {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

// Follow button on reels
%hook IGUnifiedVideoFollowButton

- (void)_hackilyHandleOurOwnButtonTaps:(id)arg1 event:(id)arg2 {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

// Follow text on profile when collapsed into top bar
%hook IGProfileViewController

- (void)navigationItemsControllerDidTapHeaderFollowButton:(id)arg1 {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

// Follow button on suggested friends in story section
%hook IGStorySectionController

- (void)followButtonTapped:(id)arg1 cell:(id)arg2 {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                %orig;
            }
                       title:@"确认关注"
                     message:@"确定要关注此账号吗？"];

    } else {
        %orig;
    }
}

%end


////////////////////////////////////////////////////////

// Follow all button in group chats (3+ members) people view

static void (*orig_listSectionController)(id, SEL, id, id);

static void hooked_listSectionController(
    id self,
    SEL _cmd,
    id arg1,
    id arg2
) {
    if ([SPKUtils getBoolPref:@"profile_confirm_follow"]) {

        [SPKUtils
            showConfirmation:^{
                orig_listSectionController(
                    self,
                    _cmd,
                    arg1,
                    arg2
                );
            }
                       title:@"确认全部关注"
                     message:@"确定要关注此列表中的所有用户吗？"];

        return;
    }

    orig_listSectionController(
        self,
        _cmd,
        arg1,
        arg2
    );
}


////////////////////////////////////////////////////////

// Install group chat "Follow All" hook

static void SPKInstallFollowAllConfirmHook(void) {
    Class cls =
        objc_getClass(
            "IGDirectDetailMembersKit.IGDirectThreadDetailsMembersListViewController"
        );

    if (!cls)
        return;

    MSHookMessageEx(
        cls,
        @selector(
            listSectionController:didTapHeaderButtonWithViewModel:
        ),
        (IMP)hooked_listSectionController,
        (IMP *)&orig_listSectionController
    );
}


////////////////////////////////////////////////////////

// Entry point

void SPKInstallFollowConfirmHooksIfNeeded(void) {

    if (![SPKUtils getBoolPref:@"profile_confirm_follow"] &&
        ![SPKUtils getBoolPref:@"profile_confirm_unfollow"]) {
        return;
    }

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        %init(SPKFollowConfirmHooks);

        SPKInstallFollowAllConfirmHook();
    });
}
