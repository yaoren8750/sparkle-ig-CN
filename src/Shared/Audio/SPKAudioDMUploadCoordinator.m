#import "SPKAudioDMUploadCoordinator.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGalleryPickerViewController.h"
#import "../MediaTrim/SPKTrimConfiguration.h"
#import "../MediaTrim/SPKTrimEditorViewController.h"
#import "../MediaTrim/SPKTrimRenderer.h"
#import "../MediaTrim/SPKTrimResult.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "../UI/SPKNotificationCenter.h"

@interface SPKAudioDMUploadCoordinator () <UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) id senderTarget;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic, strong) SPKNotificationPillView *progressView;
@end

static SPKAudioDMUploadCoordinator *sSPKAudioActiveDMUploadCoordinator;

extern void SPKDMConfirmVoiceMessageIfNeeded(void (^confirmBlock)(void), void (^cancelBlock)(void));

static SEL SPKAudioDMSendSelector(void) {
    return NSSelectorFromString(@"sendAudioWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:messageID:quotedPublishedMessage:");
}

static SEL SPKAudioDMSendLegacySelector(void) {
    return NSSelectorFromString(@"sendAudioWithURL:waveform:duration:entryPoint:messageID:quotedPublishedMessage:");
}

static SEL SPKAudioDMVoiceSelector(void) {
    return NSSelectorFromString(@"voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:aiVoiceEffectType:sendButtonTypeTapped:");
}

static SEL SPKAudioDMVoiceLegacySelector(void) {
    return NSSelectorFromString(@"voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:sendButtonTypeTapped:");
}

static NSURL *SPKAudioDMTemporaryURL(NSString *extension) {
    NSString *name = [NSString stringWithFormat:@"sparkle-dm-audio-%@.%@",
                                                NSUUID.UUID.UUIDString,
                                                extension.length ? extension : @"m4a"];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

static id SPKAudioDMCreateWaveform(NSTimeInterval duration) {
    NSUInteger sampleCount = 50;
    NSMutableArray<NSNumber *> *averageVolume = [NSMutableArray arrayWithCapacity:sampleCount];
    for (NSUInteger i = 0; i < sampleCount; i++) {
        double phase = (double)(i % 10) / 10.0;
        [averageVolume addObject:@(0.12 + (phase * 0.18))];
    }

    Class waveformClass = NSClassFromString(@"IGDirectAudioWaveform");
    SEL initializer = NSSelectorFromString(@"initWithVolumeRecordingInterval:averageVolume:");
    if (!waveformClass || ![waveformClass instancesRespondToSelector:initializer])
        return nil;

    double interval = (isfinite(duration) && duration > 0.1) ? MAX(duration / (double)sampleCount, 0.02) : 0.1;
    id waveform = ((id (*)(id, SEL, double, id))objc_msgSend)([waveformClass alloc],
                                                              initializer,
                                                              interval,
                                                              [averageVolume copy]);
    return [waveform respondsToSelector:@selector(averageVolume)] ? waveform : nil;
}

static id SPKAudioDMIvarValue(id object, const char *name) {
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

static id SPKAudioDMCall(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector])
        return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id SPKAudioDMThreadContextFromTarget(id target) {
    return SPKAudioDMCall(target, @"threadViewControllerContext") ?: SPKAudioDMIvarValue(target, "_threadViewControllerContext");
}

static id SPKAudioDMVoiceControllerFromTarget(id target) {
    id voiceController = SPKAudioDMCall(target, @"voiceController") ?: SPKAudioDMIvarValue(target, "_voiceController");
    if (voiceController)
        return voiceController;

    id threadContext = SPKAudioDMThreadContextFromTarget(target);
    voiceController = SPKAudioDMCall(threadContext, @"voiceController") ?: SPKAudioDMIvarValue(threadContext, "_voiceController");
    if (voiceController)
        return voiceController;

    id featureDelegate = SPKAudioDMCall(target, @"featureDelegate") ?: SPKAudioDMIvarValue(target, "_featureDelegate");
    voiceController = SPKAudioDMCall(featureDelegate, @"voiceController") ?: SPKAudioDMIvarValue(featureDelegate, "_voiceController");
    if (voiceController)
        return voiceController;

    id composerTapHandler = SPKAudioDMCall(featureDelegate, @"composerTapHandler") ?: SPKAudioDMIvarValue(featureDelegate, "_composerTapHandler");
    return SPKAudioDMCall(composerTapHandler, @"voiceController") ?: SPKAudioDMIvarValue(composerTapHandler, "_voiceController");
}

static id SPKAudioDMMessageSenderFromTarget(id target) {
    id sender = SPKAudioDMCall(target, @"messageSenderFeatureController") ?: SPKAudioDMIvarValue(target, "_messageSenderFeatureController");
    if (sender)
        return sender;

    id threadContext = SPKAudioDMThreadContextFromTarget(target);
    sender = SPKAudioDMCall(threadContext, @"messageSenderFeatureController") ?: SPKAudioDMIvarValue(threadContext, "_messageSenderFeatureController");
    if (sender)
        return sender;

    id featureDelegate = SPKAudioDMCall(target, @"featureDelegate") ?: SPKAudioDMIvarValue(target, "_featureDelegate");
    return SPKAudioDMCall(featureDelegate, @"messageSenderFeatureController") ?: SPKAudioDMIvarValue(featureDelegate, "_messageSenderFeatureController");
}

static void SPKAudioDMNotify(NSString *title, NSString *message, BOOL success) {
    SPKNotify(kSPKNotificationDownloadShare,
              title,
              message,
              success ? @"checkmark_circle" : @"error_filled",
              success ? SPKNotificationToneSuccess : SPKNotificationToneError);
}

@implementation SPKAudioDMUploadCoordinator

+ (BOOL)senderTargetSupportsAudioUpload:(id)senderTarget {
    id voiceController = SPKAudioDMVoiceControllerFromTarget(senderTarget);
    SEL voiceSelector = SPKAudioDMVoiceSelector();
    SEL voiceLegacySelector = SPKAudioDMVoiceLegacySelector();
    if (voiceController && ([voiceController respondsToSelector:voiceSelector] || [voiceController respondsToSelector:voiceLegacySelector]))
        return YES;

    id sender = SPKAudioDMMessageSenderFromTarget(senderTarget) ?: senderTarget;
    return sender && ([sender respondsToSelector:SPKAudioDMSendSelector()] || [sender respondsToSelector:SPKAudioDMSendLegacySelector()]);
}

+ (void)presentUploadPickerForSenderTarget:(id)senderTarget
                                 presenter:(UIViewController *)presenter
                                sourceView:(UIView *)sourceView {
    if (![self senderTargetSupportsAudioUpload:senderTarget] || !presenter) {
        SPKAudioDMNotify(@"音频上传不可用", @"This Instagram build does not expose the direct audio sender.", NO);
        SPKWarnLog(@"AudioUpload", @"Missing direct audio sender on target: %@", senderTarget);
        return;
    }

    SPKAudioDMUploadCoordinator *coordinator = [[SPKAudioDMUploadCoordinator alloc] init];
    coordinator.senderTarget = senderTarget;
    coordinator.presenter = presenter;
    coordinator.sourceView = sourceView ?: presenter.view;
    sSPKAudioActiveDMUploadCoordinator = coordinator;

    [SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                        title:@"发送音频消息"
                                                      message:@"选择音频或视频文件，将其转换并作为语音消息发送。"
                                                      actions:@[
                                                          [SPKIGAlertAction actionWithTitle:@"Select from Photos"
                                                                                      style:SPKIGAlertActionStyleDefault
                                                                                    handler:^{
                                                                                        [coordinator presentLibraryPicker];
                                                                                    }],
                                                          [SPKIGAlertAction actionWithTitle:@"Select from Gallery"
                                                                                      style:SPKIGAlertActionStyleDefault
                                                                                    handler:^{
                                                                                        [coordinator presentGalleryPicker];
                                                                                    }],
                                                          [SPKIGAlertAction actionWithTitle:@"Select from Files"
                                                                                      style:SPKIGAlertActionStyleDefault
                                                                                    handler:^{
                                                                                        [coordinator presentFilesPicker];
                                                                                    }],
                                                          [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                      style:SPKIGAlertActionStyleCancel
                                                                                    handler:^{
                                                                                        if (sSPKAudioActiveDMUploadCoordinator == coordinator)
                                                                                            sSPKAudioActiveDMUploadCoordinator = nil;
                                                                                    }]
                                                      ]];
}

- (void)presentFilesPicker {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.audio", @"public.movie", @"public.mpeg-4" ]
                                                                                                    inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    picker.popoverPresentationController.sourceView = self.sourceView ?: self.presenter.view;
    picker.popoverPresentationController.sourceRect = self.sourceView ? self.sourceView.bounds : self.presenter.view.bounds;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)presentLibraryPicker {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        SPKAudioDMNotify(@"Library unavailable", @"Photo Library is not available on this device.", NO);
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[ @"public.movie" ];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    picker.popoverPresentationController.sourceView = self.sourceView ?: self.presenter.view;
    picker.popoverPresentationController.sourceRect = self.sourceView ? self.sourceView.bounds : self.presenter.view.bounds;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)presentGalleryPicker {
    __weak typeof(self) weakSelf = self;
    NSSet<NSNumber *> *mediaTypes = [NSSet setWithArray:@[ @(SPKGalleryMediaTypeAudio), @(SPKGalleryMediaTypeVideo) ]];
    if (![SPKGalleryPickerViewController hasSelectableFilesForAllowedMediaTypes:mediaTypes]) {
        SPKAudioDMNotify(@"No Gallery audio", @"Save audio or video to Gallery first.", NO);
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    [SPKGalleryPickerViewController presentFromViewController:self.presenter
                                                        title:@"图库"
                                            allowedMediaTypes:mediaTypes
                                      allowsMultipleSelection:NO
                                                   completion:^(NSArray<SPKGalleryFile *> *selectedFiles) {
                                                       SPKGalleryFile *file = selectedFiles.firstObject;
                                                       NSURL *fileURL = [file fileURL];
                                                       if (!file || ![file fileExists] || !fileURL) {
                                                           SPKAudioDMNotify(@"No Gallery audio", @"Save audio or video to Gallery first.", NO);
                                                           if (sSPKAudioActiveDMUploadCoordinator == weakSelf)
                                                               sSPKAudioActiveDMUploadCoordinator = nil;
                                                           return;
                                                       }
                                                       [weakSelf convertAndSendURL:fileURL];
                                                   }];
}

- (void)beginUploadProgressWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    if (!SPKNotificationIsEnabled(kSPKNotificationDownloadShare))
        return;
    if (!self.progressView) {
        self.progressView = SPKNotifyProgress(kSPKNotificationDownloadShare, title ?: @"正在准备音频", nil);
    }
    [self.progressView updateProgressTitle:title ?: @"正在准备音频" subtitle:subtitle];
    [self.progressView setProgress:0.05f animated:NO];
}

- (void)updateUploadProgress:(float)progress title:(NSString *)title subtitle:(NSString *)subtitle {
    if (!self.progressView)
        return;
    [self.progressView updateProgressTitle:title subtitle:subtitle];
    [self.progressView setProgress:progress animated:YES];
}

- (void)finishUploadProgressWithSuccess {
    if (self.progressView) {
        [self.progressView showSuccessWithTitle:@"音频已发送"
                                       subtitle:@"已将所选文件作为语音消息上传。"
                                           icon:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SPKNotificationPillDuration() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.progressView dismiss];
            self.progressView = nil;
        });
    } else {
        SPKAudioDMNotify(@"音频已发送", @"已将所选文件作为语音消息上传。", YES);
    }
}

- (void)finishUploadProgressWithErrorTitle:(NSString *)title subtitle:(NSString *)subtitle {
    if (self.progressView) {
        [self.progressView showErrorWithTitle:title ?: @"音频上传失败" subtitle:subtitle icon:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SPKNotificationPillDuration() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.progressView dismiss];
            self.progressView = nil;
        });
    } else {
        SPKAudioDMNotify(title ?: @"音频上传失败", subtitle, NO);
    }
}

- (void)finishUploadProgressWithCancel {
    if (self.progressView) {
        [self.progressView dismiss];
        self.progressView = nil;
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (sSPKAudioActiveDMUploadCoordinator == self)
        sSPKAudioActiveDMUploadCoordinator = nil;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    [self convertAndSendURL:url];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (sSPKAudioActiveDMUploadCoordinator == self)
        sSPKAudioActiveDMUploadCoordinator = nil;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSURL *url = info[UIImagePickerControllerMediaURL];
    [picker dismissViewControllerAnimated:YES
                               completion:^{
                                   if (url) {
                                       [self convertAndSendURL:url];
                                   } else if (sSPKAudioActiveDMUploadCoordinator == self) {
                                       sSPKAudioActiveDMUploadCoordinator = nil;
                                   }
                               }];
}

- (void)convertAndSendURL:(NSURL *)url {
    BOOL securityScoped = [url startAccessingSecurityScopedResource];
    NSURL *inputURL = url;
    NSURL *copiedURL = SPKAudioDMTemporaryURL(url.pathExtension.length ? url.pathExtension : @"input");
    NSError *copyError = nil;
    [[NSFileManager defaultManager] removeItemAtURL:copiedURL error:nil];
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:copiedURL error:&copyError]) {
        inputURL = copiedURL;
    }
    if (securityScoped)
        [url stopAccessingSecurityScopedResource];

    if (copyError && ![inputURL isFileURL]) {
        SPKAudioDMNotify(@"音频上传失败", copyError.localizedDescription ?: @"Could not import the selected file.", NO);
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    [self beginUploadProgressWithTitle:@"正在准备音频" subtitle:@"正在准备兼容语音消息的文件。"];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    NSArray<NSString *> *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = [compatiblePresets containsObject:AVAssetExportPresetAppleM4A] ? AVAssetExportPresetAppleM4A : AVAssetExportPresetPassthrough;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!session) {
        [self finishUploadProgressWithErrorTitle:@"音频上传失败" subtitle:@"无法创建音频转换会话。"];
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    NSURL *outputURL = SPKAudioDMTemporaryURL(@"m4a");
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    session.outputURL = outputURL;
    session.outputFileType = AVFileTypeAppleM4A;
    [self updateUploadProgress:0.15f title:@"正在转换音频" subtitle:@"正在准备兼容语音消息的文件。"];

    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (session.status != AVAssetExportSessionStatusCompleted || ![[NSFileManager defaultManager] fileExistsAtPath:outputURL.path]) {
                NSString *message = session.error.localizedDescription ?: @"Instagram may not support this media format.";
                [self finishUploadProgressWithErrorTitle:@"Audio conversion failed" subtitle:message];
                if (sSPKAudioActiveDMUploadCoordinator == self)
                    sSPKAudioActiveDMUploadCoordinator = nil;
                return;
            }

            [self offerTrimThenSendURL:outputURL duration:CMTimeGetSeconds(asset.duration)];
        });
    }];
}

#pragma mark - Trim before send

// After the file is converted to a voice-note-compatible m4a, optionally let the
// user trim it first (pref-gated so it can be turned off). "Send" uses the file
// as-is; "Trim & Send" opens the audio trim editor and sends the rendered cut.
- (void)offerTrimThenSendURL:(NSURL *)url duration:(NSTimeInterval)duration {
    if (![SPKUtils getBoolPref:@"msgs_audio_upload_trim"]) {
        [self updateUploadProgress:0.85f title:@"正在发送音频" subtitle:nil];
        [self sendConvertedURL:url duration:duration];
        return;
    }

    UIViewController *presenter = self.presenter;
    if (!presenter) {
        [self updateUploadProgress:0.85f title:@"正在发送音频" subtitle:nil];
        [self sendConvertedURL:url duration:duration];
        return;
    }

    // Drop the progress pill while the choice / editor is up.
    [self finishUploadProgressWithCancel];

    __weak typeof(self) weakSelf = self;
    [SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                        title:@"发送语音消息"
                                                      message:@"立即发送，或先裁剪音频。"
                                                      actions:@[
                                                          [SPKIGAlertAction actionWithTitle:@"Send"
                                                                                      style:SPKIGAlertActionStyleDefault
                                                                                    handler:^{
                                                                                        [weakSelf beginUploadProgressWithTitle:@"正在发送音频" subtitle:nil];
                                                                                        [weakSelf sendConvertedURL:url duration:duration];
                                                                                    }],
                                                          [SPKIGAlertAction actionWithTitle:@"Trim & Send"
                                                                                      style:SPKIGAlertActionStyleDefault
                                                                                    handler:^{
                                                                                        [weakSelf presentAudioTrimForURL:url];
                                                                                    }],
                                                          [SPKIGAlertAction actionWithTitle:@"取消"
                                                                                      style:SPKIGAlertActionStyleCancel
                                                                                    handler:^{
                                                                                        if (sSPKAudioActiveDMUploadCoordinator == weakSelf)
                                                                                            sSPKAudioActiveDMUploadCoordinator = nil;
                                                                                    }]
                                                      ]];
}

- (void)presentAudioTrimForURL:(NSURL *)url {
    UIViewController *presenter = self.presenter;
    if (!presenter) {
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }
    SPKTrimConfiguration *config = [SPKTrimConfiguration configurationWithAudioURL:url];
    __weak typeof(self) weakSelf = self;
    [SPKTrimEditorViewController presentWithConfiguration:config
                                                     from:presenter
                                               completion:^(SPKTrimResult *result) {
                                                   __strong typeof(weakSelf) strongSelf = weakSelf;
                                                   if (!strongSelf)
                                                       return;
                                                   if (!result) {
                                                       // Cancelled the editor → abort the whole send.
                                                       if (sSPKAudioActiveDMUploadCoordinator == strongSelf)
                                                           sSPKAudioActiveDMUploadCoordinator = nil;
                                                       return;
                                                   }
                                                   [strongSelf renderTrimResultThenSend:result];
                                               }];
}

- (void)renderTrimResultThenSend:(SPKTrimResult *)result {
    [self beginUploadProgressWithTitle:@"Trimming audio" subtitle:nil];
    NSString *basename = [NSString stringWithFormat:@"sparkle-dm-audio-trim-%@", NSUUID.UUID.UUIDString];
    __weak typeof(self) weakSelf = self;
    [SPKTrimRenderer renderTrimAudioForSourceURL:result.sourceURL
                                           asset:nil
                                    startSeconds:result.startSeconds
                                 durationSeconds:result.durationSeconds
                                        basename:basename
                                      completion:^(NSURL *outputURL, NSError *error) {
                                          __strong typeof(weakSelf) strongSelf = weakSelf;
                                          if (!strongSelf)
                                              return;
                                          if (!outputURL) {
                                              [strongSelf finishUploadProgressWithErrorTitle:@"Audio trim failed"
                                                                                    subtitle:error.localizedDescription ?: @"Could not trim the audio."];
                                              if (sSPKAudioActiveDMUploadCoordinator == strongSelf)
                                                  sSPKAudioActiveDMUploadCoordinator = nil;
                                              return;
                                          }
                                          [strongSelf updateUploadProgress:0.85f title:@"正在发送音频" subtitle:nil];
                                          [strongSelf sendConvertedURL:outputURL duration:result.durationSeconds];
                                      }];
}

- (void)sendConvertedURL:(NSURL *)url duration:(NSTimeInterval)duration {
    if (![SPKAudioDMUploadCoordinator senderTargetSupportsAudioUpload:self.senderTarget]) {
        [self finishUploadProgressWithErrorTitle:@"音频上传不可用" subtitle:@"The direct audio sender disappeared before sending."];
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    NSTimeInterval safeDuration = isfinite(duration) && duration > 0 ? duration : 0;
    id waveform = SPKAudioDMCreateWaveform(safeDuration);
    if (!waveform) {
        [self finishUploadProgressWithErrorTitle:@"音频上传不可用" subtitle:@"Could not create an Instagram audio waveform."];
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    id voiceController = SPKAudioDMVoiceControllerFromTarget(self.senderTarget);
    SEL voiceSelector = SPKAudioDMVoiceSelector();
    SEL voiceLegacySelector = SPKAudioDMVoiceLegacySelector();
    if (voiceController && ([voiceController respondsToSelector:voiceSelector] || [voiceController respondsToSelector:voiceLegacySelector])) {
        SPKDMConfirmVoiceMessageIfNeeded(^{
            if ([voiceController respondsToSelector:voiceSelector]) {
                void (*sendVoice)(id, SEL, id, id, id, double, long long, id, id, long long) = (void (*)(id, SEL, id, id, id, double, long long, id, id, long long))objc_msgSend;
                sendVoice(voiceController, voiceSelector, nil, url, waveform, safeDuration, 0, nil, nil, 0);
            } else {
                void (*sendVoiceLegacy)(id, SEL, id, id, id, double, long long, long long) = (void (*)(id, SEL, id, id, id, double, long long, long long))objc_msgSend;
                sendVoiceLegacy(voiceController, voiceLegacySelector, nil, url, waveform, safeDuration, 0, 0);
            }
            [self updateUploadProgress:1.0f title:@"音频已发送" subtitle:nil];
            [self finishUploadProgressWithSuccess];
            if (sSPKAudioActiveDMUploadCoordinator == self)
                sSPKAudioActiveDMUploadCoordinator = nil;
        },
                                         ^{
                                             [self finishUploadProgressWithCancel];
                                             if (sSPKAudioActiveDMUploadCoordinator == self)
                                                 sSPKAudioActiveDMUploadCoordinator = nil;
                                         });
        return;
    }

    id sender = SPKAudioDMMessageSenderFromTarget(self.senderTarget) ?: self.senderTarget;
    if (![sender respondsToSelector:SPKAudioDMSendSelector()] && ![sender respondsToSelector:SPKAudioDMSendLegacySelector()]) {
        [self finishUploadProgressWithErrorTitle:@"音频上传不可用" subtitle:@"The direct audio sender disappeared before sending."];
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
        return;
    }

    SPKDMConfirmVoiceMessageIfNeeded(^{
        if ([sender respondsToSelector:SPKAudioDMSendSelector()]) {
            void (*sendAudio)(id, SEL, id, id, double, long long, id, id, id, id) = (void (*)(id, SEL, id, id, double, long long, id, id, id, id))objc_msgSend;
            sendAudio(sender,
                      SPKAudioDMSendSelector(),
                      url,
                      waveform,
                      safeDuration,
                      0,
                      nil,
                      nil,
                      nil,
                      nil);
        } else {
            SEL legacySelector = SPKAudioDMSendLegacySelector();
            void (*sendAudioLegacy)(id, SEL, id, id, double, long long, id, id) = (void (*)(id, SEL, id, id, double, long long, id, id))objc_msgSend;
            sendAudioLegacy(sender,
                            legacySelector,
                            url,
                            waveform,
                            safeDuration,
                            0,
                            nil,
                            nil);
        }
        [self updateUploadProgress:1.0f title:@"音频已发送" subtitle:nil];
        [self finishUploadProgressWithSuccess];
        if (sSPKAudioActiveDMUploadCoordinator == self)
            sSPKAudioActiveDMUploadCoordinator = nil;
    },
                                     ^{
                                         [self finishUploadProgressWithCancel];
                                         if (sSPKAudioActiveDMUploadCoordinator == self)
                                             sSPKAudioActiveDMUploadCoordinator = nil;
                                     });
}

@end
