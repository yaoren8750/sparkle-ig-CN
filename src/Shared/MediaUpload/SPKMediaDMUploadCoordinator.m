#import "SPKMediaDMUploadCoordinator.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGalleryPickerViewController.h"
#import "../UI/SPKNotificationCenter.h"

static SEL SPKMediaDMSendImageSelector(void) {
    return NSSelectorFromString(@"sendImage:");
}

static id SPKMediaDMIvarValue(id object, const char *name) {
    if (!object || !name)
        return nil;
    @try {
        for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            Ivar ivar = class_getInstanceVariable(cls, name);
            if (!ivar)
                continue;
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (encoding && encoding[0] == '@')
                return object_getIvar(object, ivar);
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static id SPKMediaDMCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector])
        return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SPKMediaDMThreadContextFromTarget(id target) {
    return SPKMediaDMCall(target, @"threadViewControllerContext") ?: SPKMediaDMIvarValue(target, "_threadViewControllerContext");
}

static id SPKMediaDMMessageSenderFromTarget(id target) {
    id sender = SPKMediaDMCall(target, @"messageSenderFeatureController") ?: SPKMediaDMIvarValue(target, "_messageSenderFeatureController");
    if (sender)
        return sender;

    id threadContext = SPKMediaDMThreadContextFromTarget(target);
    sender = SPKMediaDMCall(threadContext, @"messageSenderFeatureController") ?: SPKMediaDMIvarValue(threadContext, "_messageSenderFeatureController");
    if (sender)
        return sender;

    id featureDelegate = SPKMediaDMCall(target, @"featureDelegate") ?: SPKMediaDMIvarValue(target, "_featureDelegate");
    return SPKMediaDMCall(featureDelegate, @"messageSenderFeatureController") ?: SPKMediaDMIvarValue(featureDelegate, "_messageSenderFeatureController");
}

static void SPKMediaDMNotify(NSString *title, NSString *message, BOOL success) {
    SPKNotify(kSPKNotificationDownloadShare,
              title,
              message,
              success ? @"checkmark_circle" : @"error_filled",
              success ? SPKNotificationToneSuccess : SPKNotificationToneError);
}

@interface SPKMediaDMUploadCoordinator ()
@property (nonatomic, strong) id senderTarget;
@end

static SPKMediaDMUploadCoordinator *sSPKMediaActiveDMUploadCoordinator;

@implementation SPKMediaDMUploadCoordinator

+ (BOOL)senderTargetSupportsMediaUpload:(id)senderTarget {
    id sender = SPKMediaDMMessageSenderFromTarget(senderTarget) ?: senderTarget;
    return sender && [sender respondsToSelector:SPKMediaDMSendImageSelector()];
}

+ (void)presentGalleryUploadPickerForSenderTarget:(id)senderTarget
                                        presenter:(UIViewController *)presenter
                                       sourceView:(UIView *)sourceView {
    if (![self senderTargetSupportsMediaUpload:senderTarget] || !presenter) {
        SPKMediaDMNotify(@"Media upload unavailable", @"This Instagram build does not expose the direct media sender.", NO);
        SPKWarnLog(@"MediaUpload", @"Missing direct media sender on target: %@", senderTarget);
        return;
    }

    NSSet<NSNumber *> *mediaTypes = [NSSet setWithObject:@(SPKGalleryMediaTypeImage)];
    if (![SPKGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:mediaTypes]) {
        SPKMediaDMNotify(@"No Gallery photos", @"Save a photo to Gallery first.", NO);
        return;
    }

    SPKMediaDMUploadCoordinator *coordinator = [[SPKMediaDMUploadCoordinator alloc] init];
    coordinator.senderTarget = senderTarget;
    sSPKMediaActiveDMUploadCoordinator = coordinator;

    __weak typeof(coordinator) weakCoordinator = coordinator;
    [SPKGalleryPickerViewController presentFromViewController:presenter
                                                        title:@"图库"
                                            allowedMediaTypes:mediaTypes
                                      allowsMultipleSelection:NO
                                                   completion:^(NSArray<SPKGalleryFile *> *selectedFiles) {
                                                       SPKGalleryFile *file = selectedFiles.firstObject;
                                                       NSURL *fileURL = [file fileURL];
                                                       if (!file || ![file fileExists] || !fileURL) {
                                                           if (sSPKMediaActiveDMUploadCoordinator == weakCoordinator)
                                                               sSPKMediaActiveDMUploadCoordinator = nil;
                                                           return;
                                                       }
                                                       [weakCoordinator sendImageFromURL:fileURL];
                                                   }];
}

- (void)sendImageFromURL:(NSURL *)url {
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    if (!image) {
        SPKMediaDMNotify(@"Media upload failed", @"Could not read the selected photo.", NO);
        if (sSPKMediaActiveDMUploadCoordinator == self)
            sSPKMediaActiveDMUploadCoordinator = nil;
        return;
    }

    id sender = SPKMediaDMMessageSenderFromTarget(self.senderTarget) ?: self.senderTarget;
    if (![sender respondsToSelector:SPKMediaDMSendImageSelector()]) {
        SPKMediaDMNotify(@"Media upload unavailable", @"The direct media sender disappeared before sending.", NO);
        if (sSPKMediaActiveDMUploadCoordinator == self)
            sSPKMediaActiveDMUploadCoordinator = nil;
        return;
    }

    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(sender, SPKMediaDMSendImageSelector(), image);
        SPKMediaDMNotify(@"Photo sent", @"Sent the selected photo to this chat.", YES);
    } @catch (__unused NSException *exception) {
        SPKMediaDMNotify(@"Media upload failed", @"Instagram rejected the selected photo.", NO);
    }
    if (sSPKMediaActiveDMUploadCoordinator == self)
        sSPKMediaActiveDMUploadCoordinator = nil;
}

@end
