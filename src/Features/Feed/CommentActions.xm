#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../AssetUtils.h"
#import "../../Shared/Downloads/SPKDownloadHelpers.h"
#import "../../Shared/Gallery/SPKGalleryFile.h"
#import "../../Shared/Gallery/SPKGalleryOriginController.h"
#import "../../Shared/Gallery/SPKGallerySaveMetadata.h"
#import "../../Shared/UI/SPKNotificationCenter.h"
#import "../../Utils.h"

static NSString *const kSPKCommentCopyTextPref = @"general_comments_copy_text";
static NSString *const kSPKCommentMediaActionsPref = @"general_comments_media_actions";

static id SPKCommentObjectForSelector(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0)
        return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector])
        return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL SPKCommentBoolForSelector(id object, NSString *selectorName) {
    if (!object || selectorName.length == 0)
        return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector])
        return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static id SPKCommentObjectForIvar(id object, NSString *ivarName) {
    if (!object || ivarName.length == 0)
        return nil;
    Ivar ivar = class_getInstanceVariable([object class], ivarName.UTF8String);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static NSString *SPKCommentStringValue(id value) {
    if ([value isKindOfClass:NSString.class])
        return value;
    if ([value isKindOfClass:NSURL.class])
        return [(NSURL *)value absoluteString];
    if ([value respondsToSelector:@selector(stringValue)])
        return [value stringValue];
    return nil;
}

static NSString *SPKCommentStringForSelector(id object, NSString *selectorName) {
    return SPKCommentStringValue(SPKCommentObjectForSelector(object, selectorName));
}

static UIImage *SPKCommentIcon(NSString *name) {
    // menuIconNamed: avoids the UIGraphicsImageRenderer downscale that iOS 16's
    // UIMenu renders blank for vector-backed (.svg) glyphs. See SPKAssetUtils.
    return [SPKAssetUtils menuIconNamed:name];
}

static id SPKCommentLongPressedComment(id controller) {
    return SPKCommentObjectForIvar(controller, @"_longPressedComment");
}

static NSString *SPKCommentAttachmentURLString(id comment) {
    id attachment = SPKCommentObjectForSelector(comment, @"commentAttachment");
    if (!attachment)
        attachment = SPKCommentObjectForIvar(comment, @"_commentAttachment");
    if (!attachment)
        return nil;

    NSString *urlString = SPKCommentStringForSelector(attachment, @"imageURL");
    if (urlString.length == 0) {
        urlString = SPKCommentStringValue(SPKCommentObjectForIvar(attachment, @"_image_imageURL"));
    }
    return urlString;
}

static NSString *SPKCommentPhotoURLString(id comment) {
    id apiCommentDict = SPKCommentObjectForSelector(comment, @"apiCommentDict");
    id mediaCommentInfo = SPKCommentObjectForSelector(apiCommentDict, @"mediaCommentInfo");
    id media = SPKCommentObjectForSelector(mediaCommentInfo, @"media");
    if (media) {
        NSURL *url = [SPKUtils getPhotoUrlForMedia:media];
        if (!url) {
            id photoObject = SPKCommentObjectForSelector(media, @"photo");
            if (photoObject)
                url = [SPKUtils getPhotoUrl:photoObject];
        }
        if (!url) {
            id imageSpecifier = SPKCommentObjectForSelector(media, @"imageSpecifier");
            NSString *specURLString = SPKCommentStringForSelector(imageSpecifier, @"url");
            if (specURLString.length > 0)
                url = [NSURL URLWithString:specURLString];
        }
        if (url)
            return url.absoluteString;
    }

    return SPKCommentAttachmentURLString(comment);
}

static UIImage *SPKCommentUserUploadedImage(id comment) {
    id image = SPKCommentObjectForSelector(comment, @"userUploadedImage");
    return [image isKindOfClass:[UIImage class]] ? (UIImage *)image : nil;
}

static SPKGallerySaveMetadata *SPKCommentMediaMetadata(id comment, NSString *mediaID, NSString *mediaURLString) {
    SPKGallerySaveMetadata *metadata = [[SPKGallerySaveMetadata alloc] init];
    metadata.source = (int16_t)SPKGallerySourceComments;
    metadata.sourceMediaPK = mediaID;
    metadata.sourceMediaURLString = mediaURLString;

    id user = SPKCommentObjectForSelector(comment, @"user");
    NSString *username = SPKCommentStringForSelector(user, @"username");
    [SPKGalleryOriginController populateProfileMetadata:metadata username:username user:user];
    return metadata;
}

static void SPKCommentDownloadMediaURL(NSURL *url, NSString *extension, SPKGallerySaveMetadata *metadata, SPKDownloadDestination destination) {
    if (!url)
        return;
    [SPKDownloadHelpers downloadURL:url
                          extension:extension
                        destination:destination
                           metadata:metadata
                     notificationID:kSPKNotificationDownloadGallery
                          presenter:nil
                      sourceSurface:SPKDownloadSourceSurfaceComments];
}

static void SPKCommentDownloadLocalImage(UIImage *image, SPKGallerySaveMetadata *metadata, SPKDownloadDestination destination) {
    if (!image)
        return;
    NSString *stagedPath = [SPKDownloadHelpers stageImageForDownload:image];
    if (!stagedPath)
        return;
    [SPKDownloadHelpers submitLocalFileURL:[NSURL fileURLWithPath:stagedPath]
                                 extension:@"png"
                               destination:destination
                                  metadata:metadata
                            notificationID:kSPKNotificationDownloadGallery
                                 presenter:nil
                                anchorView:nil
                             sourceSurface:SPKDownloadSourceSurfaceComments];
}

static UIAction *SPKCommentAction(NSString *title, NSString *iconName, void (^handler)(void)) {
    return [UIAction actionWithTitle:title
                               image:SPKCommentIcon(iconName)
                          identifier:nil
                             handler:^(__unused UIAction *action) {
                                 if (handler)
                                     handler();
                             }];
}

static NSArray<UIMenuElement *> *SPKCommentMediaActionItems(id comment, NSURL *url, NSString *extension, UIImage *localImage, NSString *mediaID, NSString *copyLinkTitle, NSString *linkURLString, NSString *copyLinkToastMessage) {
    SPKGallerySaveMetadata *metadata = SPKCommentMediaMetadata(comment, mediaID, url.absoluteString);
    void (^performDownload)(SPKDownloadDestination) = ^(SPKDownloadDestination destination) {
        if (url) {
            SPKCommentDownloadMediaURL(url, extension, metadata, destination);
        } else if (localImage) {
            SPKCommentDownloadLocalImage(localImage, metadata, destination);
        }
    };

    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    [actions addObject:SPKCommentAction(@"保存到照片", @"download", ^{
                 performDownload(SPKDownloadDestinationPhotos);
             })];
    [actions addObject:SPKCommentAction(@"分享", @"share", ^{
                 performDownload(SPKDownloadDestinationShare);
             })];
    [actions addObject:SPKCommentAction(@"保存到图库", @"sparkle_gallery", ^{
                 performDownload(SPKDownloadDestinationGallery);
             })];
    [actions addObject:SPKCommentAction(@"复制", @"copy", ^{
                 performDownload(SPKDownloadDestinationClipboard);
             })];

    if (linkURLString.length > 0) {
        [actions addObject:SPKCommentAction(copyLinkTitle, @"link", ^{
                     UIPasteboard.generalPasteboard.string = linkURLString;
                     SPKNotify(kSPKNotificationCopyGIFLink, copyLinkToastMessage, nil, @"copy_filled", SPKNotificationToneSuccess);
                 })];
    }

    return actions;
}

static id (*SPKOriginalCommentContextMenu)(id, SEL, id, id, CGPoint);

static id SPKCommentContextMenu(id self, SEL _cmd, id collectionView, id indexPath, CGPoint point) {
    UIContextMenuConfiguration *configuration = SPKOriginalCommentContextMenu(self, _cmd, collectionView, indexPath, point);
    if (!configuration)
        return nil;

    id comment = SPKCommentLongPressedComment(self);
    NSString *text = SPKCommentStringForSelector(comment, @"text");
    BOOL mediaActionsEnabled = [SPKUtils getBoolPref:kSPKCommentMediaActionsPref];

    NSString *gifID = SPKCommentStringForSelector(comment, @"gifMediaId");
    NSString *gifURLString = gifID.length > 0 ? SPKCommentAttachmentURLString(comment) : nil;
    BOOL offersGIFActions = mediaActionsEnabled && gifURLString.length > 0;

    NSString *photoURLString = nil;
    UIImage *photoLocalImage = nil;
    BOOL offersPhotoActions = NO;
    if (!offersGIFActions && gifID.length == 0) {
        photoURLString = SPKCommentPhotoURLString(comment);
        if (photoURLString.length == 0) {
            photoLocalImage = SPKCommentUserUploadedImage(comment);
        }
        BOOL isPhotoComment = SPKCommentBoolForSelector(comment, @"isPhotoComment");
        offersPhotoActions = mediaActionsEnabled && (isPhotoComment || photoURLString.length > 0 || photoLocalImage != nil);
    }

    BOOL offersCopyText = text.length > 0 && [SPKUtils getBoolPref:kSPKCommentCopyTextPref];
    if (!offersCopyText && !offersGIFActions && !offersPhotoActions)
        return configuration;

    UIContextMenuActionProvider originalProvider = [configuration valueForKey:@"actionProvider"];
    id<NSCopying> identifier = [configuration valueForKey:@"identifier"];
    UIContextMenuContentPreviewProvider previewProvider = [configuration valueForKey:@"previewProvider"];
    UIContextMenuActionProvider actionProvider = ^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIMenu *baseMenu = originalProvider ? originalProvider(suggestedActions) : [UIMenu menuWithChildren:suggestedActions];
        NSMutableArray<UIMenuElement *> *extraActions = [NSMutableArray array];

        if (offersCopyText) {
            [extraActions addObject:SPKCommentAction(@"复制评论", @"copy", ^{
                              UIPasteboard.generalPasteboard.string = text;
                              SPKNotify(kSPKNotificationCopyComment, @"评论已复制", nil, @"copy_filled", SPKNotificationToneSuccess);
                          })];
        }

        if (offersGIFActions) {
            NSURL *gifURL = [NSURL URLWithString:gifURLString];
            NSString *pageURLString = gifID.length > 0 ? [NSString stringWithFormat:@"https://giphy.com/gifs/%@", gifID] : gifURLString;
            NSArray<UIMenuElement *> *gifActions = SPKCommentMediaActionItems(comment, gifURL, @"gif", nil, gifID, @"复制 GIF 链接", pageURLString, @"GIF 链接已复制");
            [extraActions addObject:[UIMenu menuWithTitle:@"GIF 操作"
                                                    image:SPKCommentIcon(@"action")
                                               identifier:nil
                                                  options:0
                                                 children:gifActions]];
        } else if (offersPhotoActions) {
            NSURL *photoURL = photoURLString.length > 0 ? [NSURL URLWithString:photoURLString] : nil;
            NSString *extension = photoURL.pathExtension.length > 0 ? photoURL.pathExtension : @"jpg";
            NSArray<UIMenuElement *> *photoActions = SPKCommentMediaActionItems(comment, photoURL, extension, photoLocalImage, nil, @"复制下载链接", photoURLString, @"下载链接已复制");
            [extraActions addObject:[UIMenu menuWithTitle:@"照片操作"
                                                    image:SPKCommentIcon(@"action")
                                               identifier:nil
                                                  options:0
                                                 children:photoActions]];
        }

        if (extraActions.count == 0)
            return baseMenu;
        UIMenu *inlineMenu = [UIMenu menuWithTitle:@""
                                             image:nil
                                        identifier:nil
                                           options:UIMenuOptionsDisplayInline
                                          children:extraActions];
        NSMutableArray<UIMenuElement *> *children = [baseMenu.children mutableCopy] ?: [NSMutableArray array];
        NSUInteger insertionIndex = children.count > 0 ? children.count - 1 : 0;
        [children insertObject:inlineMenu atIndex:insertionIndex];
        return [baseMenu menuByReplacingChildren:children];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:identifier
                                                   previewProvider:previewProvider
                                                    actionProvider:actionProvider];
}

extern "C" void SPKInstallCommentActionsHooksIfEnabled(void) {
    if (![SPKUtils getBoolPref:kSPKCommentCopyTextPref] &&
        ![SPKUtils getBoolPref:kSPKCommentMediaActionsPref]) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"IGCommentThreadViewController");
        SEL selector = @selector(collectionView:contextMenuConfigurationForItemAtIndexPath:point:);
        if (cls && class_getInstanceMethod(cls, selector)) {
            MSHookMessageEx(cls, selector, (IMP)SPKCommentContextMenu, (IMP *)&SPKOriginalCommentContextMenu);
        }
    });
}
