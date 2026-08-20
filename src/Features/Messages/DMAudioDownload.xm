#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../AssetUtils.h"
#import "../../Shared/Audio/SPKAudioDMUploadCoordinator.h"
#import "../../Shared/Audio/SPKAudioDownloadCoordinator.h"
#import "../../Shared/Audio/SPKAudioItem.h"
#import "../../Shared/Gallery/SPKGallerySaveMetadata.h"
#import "../../Shared/MediaUpload/SPKMediaDMUploadCoordinator.h"
#import "../../Shared/UI/SPKIGAlertPresenter.h"
#import "../../Shared/UI/SPKNotificationCenter.h"
#import "../../Utils.h"

static __unsafe_unretained id sSPKDMComposerForOverflowMenu = nil;
static BOOL sSPKDMUploadItemInjectedForOverflowMenu = NO;
static BOOL sSPKDMAudioDownloadPrismMenuPending = NO;
static id sSPKDMAudioDownloadViewModel = nil;

static id (*orig_SPKDMAudioPrismMenuViewInit3)(id, SEL, NSArray *, id, BOOL);
static id (*orig_SPKDMAudioPrismMenuViewInit5)(id, SEL, NSArray *, id, BOOL, BOOL, BOOL);
static id (*orig_SPKDMPrismMenuInit3)(id, SEL, NSArray *, id, BOOL);

static id SPKDMAudioCandidateObject(UIView *view);

static id SPKDMAudioIvarValue(id object, const char *name) {
    if (!object || !name)
        return nil;
    @try {
        for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            Ivar ivar = class_getInstanceVariable(cls, name);
            if (ivar)
                return object_getIvar(object, ivar);
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static id SPKDMAudioCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector])
        return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SPKDMAudioKVCObject(id object, NSString *key) {
    if (!object || key.length == 0)
        return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *SPKDMAudioString(id value) {
    if ([value isKindOfClass:NSString.class])
        return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    return nil;
}

static BOOL SPKDMAudioUsernameLooksUsable(NSString *username) {
    if (username.length == 0)
        return NO;
    NSString *lower = username.lowercaseString;
    if ([lower isEqualToString:@"direct"] || [lower isEqualToString:@"audio"] || [lower isEqualToString:@"media"])
        return NO;
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"instagram://"])
        return NO;
    if ([username rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound)
        return NO;
    if (username.length > 30)
        return NO;
    return YES;
}

static NSString *SPKDMAudioStringForNames(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSString *string = SPKDMAudioString(SPKDMAudioCall(object, name));
        if (!string)
            string = SPKDMAudioString(SPKDMAudioKVCObject(object, name));
        if (SPKDMAudioUsernameLooksUsable(string))
            return string;
    }
    return nil;
}

static BOOL SPKDMAudioStringMatchesPK(NSString *string, NSString *pk) {
    if (string.length == 0 || pk.length == 0)
        return NO;
    return [string isEqualToString:pk];
}

static NSString *SPKDMAudioPKForNames(id object, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSString *string = SPKDMAudioString(SPKDMAudioCall(object, name));
        if (!string)
            string = SPKDMAudioString(SPKDMAudioKVCObject(object, name));
        if (string.length > 0)
            return string;
    }
    return nil;
}

static BOOL SPKDMAudioShouldTraverseForUsername(id object) {
    if (!object)
        return NO;
    if ([object isKindOfClass:NSString.class] ||
        [object isKindOfClass:NSNumber.class] ||
        [object isKindOfClass:NSDate.class] ||
        [object isKindOfClass:NSURL.class] ||
        [object isKindOfClass:NSData.class] ||
        [object isKindOfClass:UIImage.class] ||
        [object isKindOfClass:UIView.class] ||
        [object isKindOfClass:UIViewController.class]) {
        return NO;
    }
    NSString *name = NSStringFromClass([object class]);
    return [name containsString:@"Direct"] ||
           [name containsString:@"Message"] ||
           [name containsString:@"Sender"] ||
           [name containsString:@"User"] ||
           [name containsString:@"Participant"] ||
           [name containsString:@"GraphQL"] ||
           [name containsString:@"GQL"] ||
           [name containsString:@"Model"];
}

static NSString *SPKDMAudioSenderPKFromObject(id object, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object || depth > 5)
        return nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        NSString *direct = SPKDMAudioPKForNames(object, @[ @"senderPk", @"senderPK", @"senderId", @"senderID", @"messageSenderId", @"messageSenderID" ]);
        if (direct)
            return direct;
        for (NSString *key in @[ @"messageMetadata", @"metadata", @"messageCellViewModel", @"viewModel", @"message", @"item" ]) {
            NSString *pk = SPKDMAudioSenderPKFromObject([(NSDictionary *)object objectForKey:key], visited, depth + 1);
            if (pk)
                return pk;
        }
        return nil;
    }
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class])
        return nil;

    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity])
        return nil;
    [visited addObject:identity];

    NSString *direct = SPKDMAudioPKForNames(object, @[ @"senderPk", @"senderPK", @"senderId", @"senderID", @"messageSenderId", @"messageSenderID" ]);
    if (direct)
        return direct;

    for (NSString *name in @[ @"messageMetadata", @"metadata", @"messageCellViewModel", @"viewModel", @"message", @"item" ]) {
        id nested = SPKDMAudioCall(object, name) ?: SPKDMAudioKVCObject(object, name);
        if (nested && nested != object) {
            NSString *pk = SPKDMAudioSenderPKFromObject(nested, visited, depth + 1);
            if (pk)
                return pk;
        }
    }
    return nil;
}

static BOOL SPKDMAudioObjectMatchesPK(id object, NSString *pk) {
    NSString *objectPK = SPKDMAudioPKForNames(object, @[ @"pk", @"PK", @"userPk", @"userPK", @"userId", @"userID", @"id", @"identifier" ]);
    return SPKDMAudioStringMatchesPK(objectPK, pk);
}

static NSString *SPKDMAudioUsernameForPKFromObject(id object, NSString *pk, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object || pk.length == 0 || depth > 7)
        return nil;

    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)object;
        id keyedValue = [dict objectForKey:pk];
        NSString *username = SPKDMAudioUsernameForPKFromObject(keyedValue, pk, visited, depth + 1);
        if (username)
            return username;

        NSString *dictPK = SPKDMAudioPKForNames(dict, @[ @"pk", @"PK", @"userPk", @"userPK", @"userId", @"userID", @"id", @"identifier" ]);
        if (SPKDMAudioStringMatchesPK(dictPK, pk)) {
            NSString *direct = SPKDMAudioStringForNames(dict, @[ @"username", @"userName", @"profileUsername", @"displayUsername" ]);
            if (direct)
                return direct;
        }

        for (NSString *key in @[ @"sender", @"senderUser", @"user", @"author", @"owner", @"participant", @"profile", @"threadUsers", @"users", @"participants", @"userMap" ]) {
            username = SPKDMAudioUsernameForPKFromObject([dict objectForKey:key], pk, visited, depth + 1);
            if (username)
                return username;
        }
        for (id value in dict.allValues) {
            username = SPKDMAudioUsernameForPKFromObject(value, pk, visited, depth + 1);
            if (username)
                return username;
        }
        return nil;
    }

    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        for (id value in object) {
            NSString *username = SPKDMAudioUsernameForPKFromObject(value, pk, visited, depth + 1);
            if (username)
                return username;
        }
        return nil;
    }

    if ([object isKindOfClass:NSString.class] ||
        [object isKindOfClass:NSNumber.class] ||
        [object isKindOfClass:NSDate.class] ||
        [object isKindOfClass:NSURL.class] ||
        [object isKindOfClass:NSData.class] ||
        [object isKindOfClass:UIImage.class]) {
        return nil;
    }

    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity])
        return nil;
    [visited addObject:identity];

    if (SPKDMAudioObjectMatchesPK(object, pk)) {
        NSString *direct = SPKDMAudioStringForNames(object, @[ @"username", @"userName", @"profileUsername", @"displayUsername" ]);
        if (direct)
            return direct;
    }

    for (NSString *name in @[
             @"sender", @"senderUser", @"senderInfo", @"senderViewModel", @"messageSender",
             @"threadMessageSenderViewModel", @"messageSenderViewModel", @"user", @"author",
             @"owner", @"participant", @"profile", @"threadUsers", @"users", @"participants",
             @"userMap", @"message", @"messageMetadata", @"metadata", @"viewModel",
             @"messageViewModel", @"audioMessageViewModel", @"messageCellViewModel", @"model", @"item"
         ]) {
        id nested = SPKDMAudioCall(object, name) ?: SPKDMAudioKVCObject(object, name);
        if (nested && nested != object) {
            NSString *username = SPKDMAudioUsernameForPKFromObject(nested, pk, visited, depth + 1);
            if (username)
                return username;
        }
    }

    if (!SPKDMAudioShouldTraverseForUsername(object))
        return nil;
    for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@')
                continue;
            const char *name = ivar_getName(ivar);
            NSString *ivarName = name ? [NSString stringWithUTF8String:name] : @"";
            NSString *lower = ivarName.lowercaseString;
            BOOL priority = [lower containsString:@"sender"] || [lower containsString:@"user"] || [lower containsString:@"participant"] || [lower containsString:@"message"] || [lower containsString:@"metadata"];
            if (!priority && depth > 3)
                continue;
            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (__unused NSException *exception) {
                value = nil;
            }
            NSString *username = SPKDMAudioUsernameForPKFromObject(value, pk, visited, depth + 1);
            if (username) {
                free(ivars);
                return username;
            }
        }
        free(ivars);
    }
    return nil;
}

static NSString *SPKDMAudioUsernameFromObject(id object, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!object || depth > 6)
        return nil;
    if ([object isKindOfClass:NSDictionary.class]) {
        NSString *direct = SPKDMAudioStringForNames(object, @[ @"username", @"userName", @"senderUsername", @"senderUserName", @"sender_name" ]);
        if (direct)
            return direct;
        for (NSString *key in @[ @"sender", @"senderUser", @"user", @"author", @"owner", @"participant", @"profile", @"message", @"viewModel", @"messageMetadata" ]) {
            id nested = [(NSDictionary *)object objectForKey:key];
            NSString *username = SPKDMAudioUsernameFromObject(nested, visited, depth + 1);
            if (username)
                return username;
        }
        for (id value in [(NSDictionary *)object allValues]) {
            NSString *username = SPKDMAudioUsernameFromObject(value, visited, depth + 1);
            if (username)
                return username;
        }
        return nil;
    }
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        for (id value in object) {
            NSString *username = SPKDMAudioUsernameFromObject(value, visited, depth + 1);
            if (username)
                return username;
        }
        return nil;
    }

    NSValue *identity = [NSValue valueWithNonretainedObject:object];
    if ([visited containsObject:identity])
        return nil;
    [visited addObject:identity];

    NSString *direct = SPKDMAudioStringForNames(object, @[
        @"username", @"userName", @"senderUsername", @"senderUserName",
        @"senderName", @"senderDisplayName", @"displayUsername", @"profileUsername"
    ]);
    if (direct)
        return direct;

    for (NSString *name in @[
             @"sender", @"senderUser", @"senderInfo", @"senderViewModel", @"messageSender",
             @"threadMessageSenderViewModel", @"messageSenderViewModel", @"user", @"author",
             @"owner", @"participant", @"profile", @"message", @"messageMetadata", @"viewModel",
             @"messageViewModel", @"audioMessageViewModel", @"model", @"item"
         ]) {
        id nested = SPKDMAudioCall(object, name) ?: SPKDMAudioKVCObject(object, name);
        if (nested && nested != object) {
            NSString *username = SPKDMAudioUsernameFromObject(nested, visited, depth + 1);
            if (username)
                return username;
        }
    }

    if (!SPKDMAudioShouldTraverseForUsername(object))
        return nil;
    for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@')
                continue;
            const char *name = ivar_getName(ivar);
            NSString *ivarName = name ? [NSString stringWithUTF8String:name] : @"";
            NSString *lower = ivarName.lowercaseString;
            BOOL priority = [lower containsString:@"sender"] || [lower containsString:@"user"] || [lower containsString:@"participant"] || [lower containsString:@"message"];
            if (!priority && depth > 2)
                continue;
            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (__unused NSException *exception) {
                value = nil;
            }
            NSString *username = SPKDMAudioUsernameFromObject(value, visited, depth + 1);
            if (username) {
                free(ivars);
                return username;
            }
        }
        free(ivars);
    }
    return nil;
}

static NSString *SPKDMAudioResolvedUsername(id object) {
    NSString *username = SPKDMAudioUsernameFromObject(object, [NSMutableSet set], 0);
    if (username)
        return username;

    NSString *senderPK = SPKDMAudioSenderPKFromObject(object, [NSMutableSet set], 0);
    if (!senderPK)
        return nil;
    return SPKDMAudioUsernameForPKFromObject(object, senderPK, [NSMutableSet set], 0);
}

static NSString *SPKDMAudioResolvedUsernameNearView(UIView *view, id primaryObject) {
    NSString *username = SPKDMAudioResolvedUsername(primaryObject);
    if (username)
        return username;

    NSString *senderPK = SPKDMAudioSenderPKFromObject(primaryObject, [NSMutableSet set], 0);
    for (UIView *candidateView = view; candidateView && candidateView != candidateView.window; candidateView = candidateView.superview) {
        id candidateObject = SPKDMAudioCandidateObject(candidateView);
        username = SPKDMAudioResolvedUsername(candidateObject);
        if (username)
            return username;

        if (senderPK.length > 0) {
            username = SPKDMAudioUsernameForPKFromObject(candidateObject, senderPK, [NSMutableSet set], 0);
            if (username)
                return username;
        }
    }
    return nil;
}

static id SPKDMAudioCandidateObject(UIView *view) {
    NSArray<NSString *> *selectors = @[ @"viewModel", @"messageViewModel", @"audioMessageViewModel", @"model", @"message", @"item" ];
    for (NSString *selector in selectors) {
        id value = SPKDMAudioCall(view, selector);
        if (value)
            return value;
    }
    for (NSString *ivar in @[ @"_viewModel", @"_messageViewModel", @"_audioMessageViewModel", @"_model", @"_message", @"_item" ]) {
        id value = SPKDMAudioIvarValue(view, ivar.UTF8String);
        if (value)
            return value;
    }
    return view;
}

static SPKAudioItem *SPKDMAudioItemForView(UIView *view, SPKAudioSource source) {
    id object = SPKDMAudioCandidateObject(view);
    SPKAudioItem *item = [SPKAudioDownloadCoordinator audioItemFromMediaObject:object source:source];
    if (!item && view.superview) {
        item = [SPKAudioDownloadCoordinator audioItemFromMediaObject:SPKDMAudioCandidateObject(view.superview) source:source];
    }
    if (!item)
        return nil;
    NSString *username = SPKDMAudioResolvedUsernameNearView(view, object);
    if (username.length > 0) {
        item.artist = username;
    } else if (!item.artist.length) {
        item.artist = @"direct";
    }
    return item;
}

static void SPKDMPresentAudioActions(UIView *view, SPKAudioSource source) {
    SPKAudioItem *item = SPKDMAudioItemForView(view, source);
    if (!item) {
        SPKNotify(kSPKNotificationDownloadShare, @"Could not find audio URL", @"Refresh the thread and try again if the URL expired.", @"error_filled", SPKNotificationToneError);
        return;
    }

    SPKGallerySaveMetadata *metadata = [[SPKGallerySaveMetadata alloc] init];
    metadata.source = (int16_t)[item gallerySource];
    metadata.sourceUsername = item.artist.length > 0 ? item.artist : @"direct";
    metadata.sourceMediaPK = item.mediaIdentifier;
    metadata.sourceMediaURLString = item.sourceURLString ?: item.url.absoluteString;

    UIViewController *presenter = [SPKUtils viewControllerForAncestralView:view] ?: topMostController();
    [SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                     title:@"音频"
                                                   message:nil
                                                   actions:@[
    [SPKIGAlertAction actionWithTitle:@"将音频保存到文件"
                                 style:SPKIGAlertActionStyleDefault
                               handler:^{
                                   [SPKAudioDownloadCoordinator performAction:SPKAudioActionSaveToFiles item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSPKNotificationDownloadAudio];
                               }],
    [SPKIGAlertAction actionWithTitle:@"分享音频"
                                 style:SPKIGAlertActionStyleDefault
                               handler:^{
                                   [SPKAudioDownloadCoordinator performAction:SPKAudioActionConvertAndShare item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSPKNotificationDownloadAudioShare];
                               }],
    [SPKIGAlertAction actionWithTitle:@"将音频保存到相册"
                                 style:SPKIGAlertActionStyleDefault
                               handler:^{
                                   [SPKAudioDownloadCoordinator performAction:SPKAudioActionConvertAndSaveToGallery item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSPKNotificationDownloadAudioGallery];
                               }],
    [SPKIGAlertAction actionWithTitle:@"播放音频"
                                 style:SPKIGAlertActionStyleDefault
                               handler:^{
                                   [SPKAudioDownloadCoordinator performAction:SPKAudioActionPlay item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSPKNotificationPlayAudio];
                               }],
    [SPKIGAlertAction actionWithTitle:@"复制音频下载链接"
                                 style:SPKIGAlertActionStyleDefault
                               handler:^{
                                   [SPKAudioDownloadCoordinator performAction:SPKAudioActionCopyURL item:item presenter:presenter sourceView:view metadata:metadata notificationIdentifier:kSPKNotificationCopyAudioURL];
                               }],
    [SPKIGAlertAction actionWithTitle:@"取消"
                                 style:SPKIGAlertActionStyleCancel
                               handler:nil]
                                                      ]];
}

static id SPKDMComposerSenderTarget(id composer) {
    if ([composer respondsToSelector:@selector(buttonDelegate)]) {
        return ((id (*)(id, SEL))objc_msgSend)(composer, @selector(buttonDelegate));
    }
    // IG 435+: the overflow controller holds a delegate that may be a wrapper
    // around the composer rather than the composer itself.
    id innerComposer = SPKDMAudioCall(composer, @"composer");
    if ([innerComposer respondsToSelector:@selector(buttonDelegate)]) {
        return ((id (*)(id, SEL))objc_msgSend)(innerComposer, @selector(buttonDelegate));
    }
    return nil;
}

// The overflow controller's link back to the composer: `_composer` up to IG 434,
// `_delegate` from IG 435 (which is the composer, conforming to the new
// IGDirectComposerOverflowControllerDelegate protocol).
static id SPKDMComposerFromOverflowController(id overflowController) {
    return SPKDMAudioIvarValue(overflowController, "_composer")
               ?: SPKDMAudioIvarValue(overflowController, "_delegate");
}

static BOOL SPKDMUploadMenuEnabled(void) {
    return [SPKUtils getBoolPref:@"msgs_upload_audio_messages"] ||
           [SPKUtils getBoolPref:@"msgs_upload_gallery_media"];
}

static id SPKDMComposerFromView(id view) {
    if ([view isKindOfClass:%c(IGDirectComposer)])
        return view;
    if ([view isKindOfClass:UIView.class]) {
        for (UIView *candidate = (UIView *)view; candidate; candidate = candidate.superview) {
            if ([candidate isKindOfClass:%c(IGDirectComposer)])
                return candidate;
        }
    }
    return nil;
}

static id SPKDMMenuItem(NSString *title, UIImage *image, void (^handler)(id item)) {
    Class menuItemClass = NSClassFromString(@"IGDSMenuItem");
    SEL titleImageHandler = NSSelectorFromString(@"menuItemWithTitle:image:handler:");
    if (menuItemClass && [menuItemClass respondsToSelector:titleImageHandler]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)(menuItemClass, titleImageHandler, title, image, handler);
    }

    SEL initTitleImageHandler = NSSelectorFromString(@"initWithTitle:image:handler:");
    if (menuItemClass && [menuItemClass instancesRespondToSelector:initTitleImageHandler]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)([menuItemClass alloc], initTitleImageHandler, title, image, handler);
    }

    SEL initTitleImageStyleHandler = NSSelectorFromString(@"initWithTitle:image:style:handler:");
    if (menuItemClass && [menuItemClass instancesRespondToSelector:initTitleImageStyleHandler]) {
        return ((id (*)(id, SEL, id, id, NSInteger, id))objc_msgSend)([menuItemClass alloc], initTitleImageStyleHandler, title, image, 0, handler);
    }

    SEL itemTitleStyleBlock = NSSelectorFromString(@"itemWithTitle:style:block:");
    if (menuItemClass && [menuItemClass respondsToSelector:itemTitleStyleBlock]) {
        return ((id (*)(id, SEL, id, NSInteger, id))objc_msgSend)(menuItemClass, itemTitleStyleBlock, title, 0, handler);
    }
    return nil;
}

static id SPKDMUploadAudioMenuItemForComposer(id composer) {
    id senderTarget = SPKDMComposerSenderTarget(composer);
    BOOL supports = [SPKAudioDMUploadCoordinator senderTargetSupportsAudioUpload:senderTarget];
    if (!supports) {
        SPKWarnLog(@"AudioUpload", @"Missing direct audio sender on composer delegate: %@", senderTarget);
        return nil;
    }

    __weak id weakComposer = composer;
    return SPKDMMenuItem(@"上传音频", [SPKAssetUtils instagramIconNamed:@"audio_upload" pointSize:24.0], ^(__unused id item) {
        id strongComposer = weakComposer;
        if (!strongComposer)
            return;
        UIView *composerView = [strongComposer isKindOfClass:UIView.class] ? (UIView *)strongComposer : nil;
        UIViewController *presenter = (composerView ? [SPKUtils viewControllerForAncestralView:composerView] : nil) ?: topMostController();
        [SPKAudioDMUploadCoordinator presentUploadPickerForSenderTarget:senderTarget
                                                              presenter:presenter
                                                             sourceView:composerView];
    });
}

static id SPKDMUploadMediaMenuItemForComposer(id composer) {
    id senderTarget = SPKDMComposerSenderTarget(composer);
    BOOL supports = [SPKMediaDMUploadCoordinator senderTargetSupportsMediaUpload:senderTarget];
    if (!supports) {
        SPKWarnLog(@"MediaUpload", @"Missing direct media sender on composer delegate: %@", senderTarget);
        return nil;
    }

    __weak id weakComposer = composer;
    return SPKDMMenuItem(@"上传照片", [SPKAssetUtils instagramIconNamed:@"photo" pointSize:24.0], ^(__unused id item) {
        id strongComposer = weakComposer;
        if (!strongComposer)
            return;
        UIView *composerView = [strongComposer isKindOfClass:UIView.class] ? (UIView *)strongComposer : nil;
        UIViewController *presenter = (composerView ? [SPKUtils viewControllerForAncestralView:composerView] : nil) ?: topMostController();
        [SPKMediaDMUploadCoordinator presentGalleryUploadPickerForSenderTarget:senderTarget
                                                                     presenter:presenter
                                                                    sourceView:composerView];
    });
}

// Builds the Sparkle items appended to the composer overflow (+) menu, in order.
static NSArray *SPKDMComposerExtraMenuItems(id composer) {
    NSMutableArray *items = [NSMutableArray array];
    BOOL audioPref = [SPKUtils getBoolPref:@"msgs_upload_audio_messages"];
    BOOL mediaPref = [SPKUtils getBoolPref:@"msgs_upload_gallery_media"];
    if (audioPref) {
        id audioItem = SPKDMUploadAudioMenuItemForComposer(composer);
        if (audioItem)
            [items addObject:audioItem];
    }
    if (mediaPref) {
        id mediaItem = SPKDMUploadMediaMenuItemForComposer(composer);
        if (mediaItem)
            [items addObject:mediaItem];
    }
    return items;
}

static void SPKDMPresentDownloadAudioActionsForViewModel(id viewModel) {
    UIViewController *presenter = topMostController();
    UIView *sourceView = presenter.view;
    SPKAudioItem *audioItem = [SPKAudioDownloadCoordinator audioItemFromMediaObject:viewModel source:SPKAudioSourceDMs];
    if (!audioItem) {
        SPKNotify(kSPKNotificationDownloadShare,
                  @"找不到音频链接",
                  @"如果链接已过期，请刷新对话后重试。",
                  @"error_filled",
                  SPKNotificationToneError);
        return;
    }

    SPKGallerySaveMetadata *metadata = [[SPKGallerySaveMetadata alloc] init];
    NSString *username = SPKDMAudioResolvedUsername(viewModel);
    metadata.source = (int16_t)[audioItem gallerySource];
    metadata.sourceUsername = username.length > 0 ? username : (audioItem.artist.length > 0 ? audioItem.artist : @"direct");
    metadata.sourceMediaPK = audioItem.mediaIdentifier;
    metadata.sourceMediaURLString = audioItem.sourceURLString ?: audioItem.url.absoluteString;

    [SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                        title:@"音频"
                                                      message:nil
                                                      actions:@[
        [SPKIGAlertAction actionWithTitle:@"将音频保存到文件"
                                    style:SPKIGAlertActionStyleDefault
                                  handler:^{
                                      [SPKAudioDownloadCoordinator performAction:SPKAudioActionSaveToFiles item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSPKNotificationDownloadAudio];
                                  }],
        [SPKIGAlertAction actionWithTitle:@"分享音频"
                                    style:SPKIGAlertActionStyleDefault
                                  handler:^{
                                      [SPKAudioDownloadCoordinator performAction:SPKAudioActionConvertAndShare item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSPKNotificationDownloadAudioShare];
                                  }],
        [SPKIGAlertAction actionWithTitle:@"将音频保存到相册"
                                    style:SPKIGAlertActionStyleDefault
                                  handler:^{
                                      [SPKAudioDownloadCoordinator performAction:SPKAudioActionConvertAndSaveToGallery item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSPKNotificationDownloadAudioGallery];
                                  }],
        [SPKIGAlertAction actionWithTitle:@"播放音频"
                                    style:SPKIGAlertActionStyleDefault
                                  handler:^{
                                      [SPKAudioDownloadCoordinator performAction:SPKAudioActionPlay item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSPKNotificationPlayAudio];
                                  }],
        [SPKIGAlertAction actionWithTitle:@"复制音频下载链接"
                                    style:SPKIGAlertActionStyleDefault
                                  handler:^{
                                      [SPKAudioDownloadCoordinator performAction:SPKAudioActionCopyURL item:audioItem presenter:presenter sourceView:sourceView metadata:metadata notificationIdentifier:kSPKNotificationCopyAudioURL];
                                  }],
        [SPKIGAlertAction actionWithTitle:@"取消"
                                    style:SPKIGAlertActionStyleCancel
                                  handler:nil]
                                                      ]];
}

static id SPKDMDownloadAudioMenuItemForViewModel(id viewModel) {
    if (![SPKUtils getBoolPref:@"downloads_audio_enabled"])
        return nil;
    if (![SPKUtils getBoolPref:@"msgs_download_audio_messages"])
        return nil;
    if (![SPKAudioDownloadCoordinator bestAudioURLFromMediaObject:viewModel])
        return nil;

    __strong id capturedViewModel = viewModel;
    return SPKDMMenuItem(@"音频操作", [SPKAssetUtils instagramIconNamed:@"action" pointSize:24.0], ^(__unused id item) {
        SPKDMPresentDownloadAudioActionsForViewModel(capturedViewModel);
    });
}

static id SPKDMPrismAudioDownloadElement(id templateElement, id viewModel) {
    Class builderClass = NSClassFromString(@"IGDSPrismMenuItemBuilder");
    if (!builderClass || !templateElement || !viewModel)
        return nil;
    SEL initSelector = @selector(initWithTitle:);
    SEL imageSelector = @selector(withImage:);
    SEL handlerSelector = @selector(withHandler:);
    SEL buildSelector = @selector(build);
    if (![builderClass instancesRespondToSelector:initSelector] ||
        ![builderClass instancesRespondToSelector:imageSelector] ||
        ![builderClass instancesRespondToSelector:handlerSelector] ||
        ![builderClass instancesRespondToSelector:buildSelector]) {
        return nil;
    }

    __strong id capturedViewModel = viewModel;
    void (^handler)(void) = ^{
        SPKDMPresentDownloadAudioActionsForViewModel(capturedViewModel);
    };

    id builder = ((id (*)(id, SEL, id))objc_msgSend)([builderClass alloc], initSelector, @"音频操作");
    builder = ((id (*)(id, SEL, id))objc_msgSend)(builder, imageSelector, [SPKAssetUtils instagramIconNamed:@"action" pointSize:24.0]);
    builder = ((id (*)(id, SEL, id))objc_msgSend)(builder, handlerSelector, handler);
    id menuItem = ((id (*)(id, SEL))objc_msgSend)(builder, buildSelector);
    if (!menuItem)
        return nil;

    id element = [[templateElement class] new];
    Ivar subtypeIvar = class_getInstanceVariable([templateElement class], "_subtype");
    Ivar itemIvar = class_getInstanceVariable([templateElement class], "_item_menuItem");
    if (!element || !subtypeIvar || !itemIvar)
        return nil;

    ptrdiff_t subtypeOffset = ivar_getOffset(subtypeIvar);
    *(uint64_t *)((uint8_t *)(__bridge void *)element + subtypeOffset) =
        *(uint64_t *)((uint8_t *)(__bridge void *)templateElement + subtypeOffset);
    object_setIvar(element, itemIvar, menuItem);
    return element;
}

static id SPKDMPrismMenuElement(id templateElement, NSString *title, UIImage *image, void (^handler)(void)) {
    Class builderClass = NSClassFromString(@"IGDSPrismMenuItemBuilder");
    if (!builderClass || !templateElement || title.length == 0 || !handler)
        return nil;
    SEL initSelector = @selector(initWithTitle:);
    SEL imageSelector = @selector(withImage:);
    SEL handlerSelector = @selector(withHandler:);
    SEL buildSelector = @selector(build);
    if (![builderClass instancesRespondToSelector:initSelector] ||
        ![builderClass instancesRespondToSelector:imageSelector] ||
        ![builderClass instancesRespondToSelector:handlerSelector] ||
        ![builderClass instancesRespondToSelector:buildSelector]) {
        return nil;
    }

    id builder = ((id (*)(id, SEL, id))objc_msgSend)([builderClass alloc], initSelector, title);
    if (image)
        builder = ((id (*)(id, SEL, id))objc_msgSend)(builder, imageSelector, image);
    builder = ((id (*)(id, SEL, id))objc_msgSend)(builder, handlerSelector, handler);
    id menuItem = ((id (*)(id, SEL))objc_msgSend)(builder, buildSelector);
    if (!menuItem)
        return nil;

    id element = [[templateElement class] new];
    Ivar subtypeIvar = class_getInstanceVariable([templateElement class], "_subtype");
    Ivar itemIvar = class_getInstanceVariable([templateElement class], "_item_menuItem");
    if (!element || !subtypeIvar || !itemIvar)
        return nil;

    ptrdiff_t subtypeOffset = ivar_getOffset(subtypeIvar);
    *(uint64_t *)((uint8_t *)(__bridge void *)element + subtypeOffset) =
        *(uint64_t *)((uint8_t *)(__bridge void *)templateElement + subtypeOffset);
    object_setIvar(element, itemIvar, menuItem);
    return element;
}

static NSArray *SPKDMPrismUploadElementsForComposer(id composer, id templateElement) {
    if (!composer || !templateElement || sSPKDMUploadItemInjectedForOverflowMenu)
        return @[];

    id senderTarget = SPKDMComposerSenderTarget(composer);
    NSMutableArray *elements = [NSMutableArray array];

    if ([SPKUtils getBoolPref:@"msgs_upload_audio_messages"] &&
        [SPKAudioDMUploadCoordinator senderTargetSupportsAudioUpload:senderTarget]) {
        __weak id weakComposer = composer;
        id audioElement = SPKDMPrismMenuElement(templateElement,
                                                @"Upload Audio",
                                                [SPKAssetUtils instagramIconNamed:@"audio_upload"
                                                                        pointSize:24.0],
                                                ^{
                                                    id strongComposer = weakComposer;
                                                    if (!strongComposer)
                                                        return;
                                                    UIView *composerView = [strongComposer isKindOfClass:UIView.class] ? (UIView *)strongComposer : nil;
                                                    UIViewController *presenter = (composerView ? [SPKUtils viewControllerForAncestralView:composerView] : nil) ?: topMostController();
                                                    [SPKAudioDMUploadCoordinator presentUploadPickerForSenderTarget:senderTarget
                                                                                                          presenter:presenter
                                                                                                         sourceView:composerView];
                                                });
        if (audioElement)
            [elements addObject:audioElement];
    }

    if ([SPKUtils getBoolPref:@"msgs_upload_gallery_media"] &&
        [SPKMediaDMUploadCoordinator senderTargetSupportsMediaUpload:senderTarget]) {
        __weak id weakComposer = composer;
        id mediaElement = SPKDMPrismMenuElement(templateElement,
                                                @"Upload Photo",
                                                [SPKAssetUtils instagramIconNamed:@"photo"
                                                                        pointSize:24.0],
                                                ^{
                                                    id strongComposer = weakComposer;
                                                    if (!strongComposer)
                                                        return;
                                                    UIView *composerView = [strongComposer isKindOfClass:UIView.class] ? (UIView *)strongComposer : nil;
                                                    UIViewController *presenter = (composerView ? [SPKUtils viewControllerForAncestralView:composerView] : nil) ?: topMostController();
                                                    [SPKMediaDMUploadCoordinator presentGalleryUploadPickerForSenderTarget:senderTarget
                                                                                                                 presenter:presenter
                                                                                                                sourceView:composerView];
                                                });
        if (mediaElement)
            [elements addObject:mediaElement];
    }

    return elements;
}

static NSArray *SPKDMPrismMenuElementsWithAudioDownload(NSArray *elements) {
    if (!sSPKDMAudioDownloadPrismMenuPending)
        return elements;
    sSPKDMAudioDownloadPrismMenuPending = NO;

    id viewModel = sSPKDMAudioDownloadViewModel;
    sSPKDMAudioDownloadViewModel = nil;
    if (![SPKUtils getBoolPref:@"msgs_download_audio_messages"] || ![elements isKindOfClass:NSArray.class] || elements.count == 0) {
        return elements;
    }

    id newElement = SPKDMPrismAudioDownloadElement(elements.firstObject, viewModel);
    if (!newElement)
        return elements;

    NSMutableArray *updated = [NSMutableArray arrayWithObject:newElement];
    [updated addObjectsFromArray:elements];
    return [updated copy];
}

static NSArray *SPKDMPrismMenuElementsWithInjections(NSArray *elements) {
    NSArray *updated = SPKDMPrismMenuElementsWithAudioDownload(elements);
    if (!SPKDMUploadMenuEnabled() || !sSPKDMComposerForOverflowMenu || sSPKDMUploadItemInjectedForOverflowMenu ||
        ![updated isKindOfClass:NSArray.class] || updated.count == 0) {
        return updated;
    }

    NSArray *uploadElements = SPKDMPrismUploadElementsForComposer(sSPKDMComposerForOverflowMenu, updated.firstObject);
    if (uploadElements.count == 0)
        return updated;

    NSMutableArray *merged = [NSMutableArray arrayWithArray:updated];
    [merged addObjectsFromArray:uploadElements];
    sSPKDMUploadItemInjectedForOverflowMenu = YES;
    return [merged copy];
}

static id SPKDMPrismMenuViewInit3(id self, SEL _cmd, NSArray *elements, id headerText, BOOL edrEnabled) {
    return orig_SPKDMAudioPrismMenuViewInit3(self, _cmd, SPKDMPrismMenuElementsWithInjections(elements), headerText, edrEnabled);
}

static id SPKDMPrismMenuViewInit5(id self, SEL _cmd, NSArray *elements, id headerText, BOOL edrEnabled, BOOL allowScrollingItems, BOOL allowMixedTextAlignment) {
    return orig_SPKDMAudioPrismMenuViewInit5(self, _cmd, SPKDMPrismMenuElementsWithInjections(elements), headerText, edrEnabled, allowScrollingItems, allowMixedTextAlignment);
}

static id SPKDMPrismMenuInit3(id self, SEL _cmd, NSArray *elements, id headerText, BOOL edrEnabled) {
    return orig_SPKDMPrismMenuInit3(self, _cmd, SPKDMPrismMenuElementsWithInjections(elements), headerText, edrEnabled);
}

static void SPKDMSetUploadComposerContext(id composer) {
    sSPKDMComposerForOverflowMenu = composer;
    sSPKDMUploadItemInjectedForOverflowMenu = NO;
}

static void SPKDMClearUploadComposerContext(void) {
    sSPKDMComposerForOverflowMenu = nil;
    sSPKDMUploadItemInjectedForOverflowMenu = NO;
}

%group SPKDMAudioDownloadHooks

%hook IGDirectComposerOverflowController

- (id)_setupMenuItemGroup {
    id composer = SPKDMComposerFromOverflowController(self);
    if (!SPKDMUploadMenuEnabled() || !composer) {
        return %orig;
    }

    SPKDMSetUploadComposerContext(composer);
    id result = %orig;
    SPKDMClearUploadComposerContext();
    return result;
}

%end

%hook IGDirectComposer

- (void)menuDidDismiss {
    SPKDMClearUploadComposerContext();
    %orig;
}

- (void)_didTapRedesignOverflowButton:(id)button {
    if (!SPKDMUploadMenuEnabled()) {
        %orig;
        return;
    }
    SPKDMSetUploadComposerContext(self);
    %orig;
}

%end

%hook IGDirectThreadViewController

- (void)inputView:(id)view didTapMoreButton:(id)button {
    id composer = SPKDMComposerFromView(view);
    if (!SPKDMUploadMenuEnabled() || !composer) {
        %orig;
        return;
    }
    SPKDMSetUploadComposerContext(composer);
    %orig;
}

- (void)inputView:(id)view didTapPlusButton:(id)button isExpanded:(_Bool)expanded layoutSpec:(id)layoutSpec {
    id composer = SPKDMComposerFromView(view);
    if (!SPKDMUploadMenuEnabled() || !composer) {
        if (!expanded)
            SPKDMClearUploadComposerContext();
        %orig;
        return;
    }
    if (expanded) {
        SPKDMSetUploadComposerContext(composer);
        %orig;
        return;
    }
    %orig;
    SPKDMClearUploadComposerContext();
}

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)button {
    id composer = SPKDMComposerFromView(button);
    if (!composer && [button isKindOfClass:UIView.class]) {
        for (UIView *candidate = (UIView *)button; candidate; candidate = candidate.superview) {
            composer = SPKDMComposerFromView(candidate);
            if (composer)
                break;
        }
    }
    if (SPKDMUploadMenuEnabled() && composer) {
        SPKDMSetUploadComposerContext(composer);
    }
    %orig;
}

%end

static id SPKDMProcessMenuItems(id menuItems) {
    if (sSPKDMComposerForOverflowMenu && !sSPKDMUploadItemInjectedForOverflowMenu && [menuItems isKindOfClass:NSArray.class]) {
        NSArray *extraItems = SPKDMComposerExtraMenuItems(sSPKDMComposerForOverflowMenu);
        if (extraItems.count > 0) {
            NSMutableArray *mutableItems = [(NSArray *)menuItems mutableCopy];
            [mutableItems addObjectsFromArray:extraItems];
            sSPKDMUploadItemInjectedForOverflowMenu = YES;
            return [mutableItems copy];
        }
    }
    return menuItems;
}

%hook IGDSMenu

- (id)initWithMenuItems:(id)menuItems {
    return %orig(SPKDMProcessMenuItems(menuItems));
}

- (id)initWithMenuItems:(id)menuItems edr:(_Bool)edr {
    return %orig(SPKDMProcessMenuItems(menuItems), edr);
}

- (id)initWithMenuItems:(id)menuItems edr:(_Bool)edr headerLabelText:(id)headerLabelText {
    return %orig(SPKDMProcessMenuItems(menuItems), edr, headerLabelText);
}

- (id)initWithMenuItems:(id)menuItems edr:(_Bool)edr headerLabelText:(id)headerLabelText enableScrollToDismiss:(_Bool)enableScrollToDismiss {
    return %orig(SPKDMProcessMenuItems(menuItems), edr, headerLabelText, enableScrollToDismiss);
}

- (id)initWithMenuItemsWithoutUIWindow:(id)menuItems edr:(_Bool)edr headerLabelText:(id)headerLabelText {
    return %orig(SPKDMProcessMenuItems(menuItems), edr, headerLabelText);
}

%end

%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration

+ (id)menuConfigurationWithEligibleOptions:(id)options
                          messageViewModel:(id)viewModel
                               contentType:(id)contentType
                                 isSticker:(_Bool)isSticker
                            isMusicSticker:(_Bool)isMusicSticker
                          directNuxManager:(id)directNuxManager
                       sessionUserDefaults:(id)sessionUserDefaults
                               launcherSet:(id)launcherSet
                               userSession:(id)userSession
                                tapHandler:(id)tapHandler {
    id config = %orig(options, viewModel, contentType, isSticker, isMusicSticker, directNuxManager, sessionUserDefaults, launcherSet, userSession, tapHandler);
    if ([SPKUtils getBoolPref:@"downloads_audio_enabled"] &&
        [SPKUtils getBoolPref:@"msgs_download_audio_messages"] &&
        [SPKAudioDownloadCoordinator bestAudioURLFromMediaObject:viewModel]) {
        sSPKDMAudioDownloadPrismMenuPending = YES;
        sSPKDMAudioDownloadViewModel = viewModel;
    }
    return config;
}

%end

%end

extern "C" void SPKInstallDMAudioDownloadHooksIfNeeded(void) {
    // Audio download/upload features sit behind the audio-downloads master switch;
    // gallery photo upload is independent of it.
    BOOL audioFeatureEnabled = [SPKUtils getBoolPref:@"downloads_audio_enabled"] &&
                               ([SPKUtils getBoolPref:@"msgs_download_audio_messages"] ||
                                [SPKUtils getBoolPref:@"msgs_download_notes_audio"] ||
                                [SPKUtils getBoolPref:@"msgs_upload_audio_messages"]);
    BOOL mediaUploadEnabled = [SPKUtils getBoolPref:@"msgs_upload_gallery_media"];
    if (!audioFeatureEnabled && !mediaUploadEnabled)
        return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SPKDMAudioDownloadHooks);
        Class prismMenuViewClass = objc_getClass("IGDSPrismMenu.IGDSPrismMenuView");
        SEL init3 = @selector(initWithMenuElements:headerText:edrEnabled:);
        if (prismMenuViewClass && [prismMenuViewClass instancesRespondToSelector:init3]) {
            MSHookMessageEx(prismMenuViewClass,
                            init3,
                            (IMP)SPKDMPrismMenuViewInit3,
                            (IMP *)&orig_SPKDMAudioPrismMenuViewInit3);
        }
        SEL init5 = @selector(initWithMenuElements:headerText:edrEnabled:allowScrollingItems:allowMixedTextAlignment:);
        if (prismMenuViewClass && [prismMenuViewClass instancesRespondToSelector:init5]) {
            MSHookMessageEx(prismMenuViewClass,
                            init5,
                            (IMP)SPKDMPrismMenuViewInit5,
                            (IMP *)&orig_SPKDMAudioPrismMenuViewInit5);
        }
        Class prismMenuClass = objc_getClass("IGDSPrismMenu.IGDSPrismMenu");
        if (prismMenuClass && [prismMenuClass instancesRespondToSelector:init3]) {
            MSHookMessageEx(prismMenuClass,
                            init3,
                            (IMP)SPKDMPrismMenuInit3,
                            (IMP *)&orig_SPKDMPrismMenuInit3);
        }
    });
}
