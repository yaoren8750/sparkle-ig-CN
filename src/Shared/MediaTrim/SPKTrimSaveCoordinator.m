#import "SPKTrimSaveCoordinator.h"
#import "../../Utils.h"
#import "../Downloads/SPKDownloadDestinationWriter.h"
#import "../Gallery/SPKGalleryFile.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../Gallery/SPKGalleryViewController.h"
#import "../UI/SPKIGAlertPresenter.h"
#import "../UI/SPKNotificationCenter.h"
#import "SPKTrimRenderer.h"
#import "SPKTrimResult.h"

#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Presents the system "Save Audio to Files" (document export) sheet and reports
// the outcome back through the store completion. Retains itself until the picker
// finishes, since UIDocumentPickerViewController holds its delegate weakly.
@interface SPKTrimFilesExporter : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^done)(BOOL, NSString *);
@property (nonatomic, strong) SPKTrimFilesExporter *selfRef;
@end

@implementation SPKTrimFilesExporter
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.done)
        self.done(YES, @"已保存到文件");
    self.selfRef = nil;
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (self.done)
        self.done(YES, nil); // no error, just nothing saved
    self.selfRef = nil;
}
@end

@interface SPKTrimSaveCoordinator ()
+ (void)extractFrameFromURLs:(NSArray<NSURL *> *)urls
                   atSeconds:(NSTimeInterval)seconds
                    basename:(NSString *)basename
                  completion:(void (^)(NSURL *_Nullable, NSError *_Nullable))completion;
@end

@implementation SPKTrimSaveCoordinator

+ (void)saveResult:(SPKTrimResult *)result
        originFile:(SPKGalleryFile *)originFile
    fallbackSource:(SPKGallerySource)fallbackSource
        folderPath:(NSString *)folderPath
         presenter:(UIViewController *)presenter
        completion:(void (^)(BOOL))completion {
    SPKGalleryMediaType mediaType = SPKGalleryMediaTypeVideo;
    if (result.mode == SPKTrimResultModeFrameOnly) {
        mediaType = SPKGalleryMediaTypeImage;
    } else if (result.mode == SPKTrimResultModeTrimmedAudio) {
        mediaType = SPKGalleryMediaTypeAudio;
    }

    SPKTrimStoreBlock copyStore = ^(NSURL *rendered, void (^done)(BOOL, NSString *)) {
        SPKGallerySource source = originFile ? (SPKGallerySource)originFile.source : fallbackSource;
        NSString *folder = originFile ? originFile.folderPath : folderPath;
        // Carry the original's origin metadata onto the copy so its filename and
        // Open Profile/Post links match (otherwise it falls back to media_other_...).
        SPKGallerySaveMetadata *metadata = originFile ? [originFile saveMetadata] : nil;
        NSError *error = nil;
        SPKGalleryFile *saved = [SPKGalleryFile saveFileToGallery:rendered
                                                           source:source
                                                        mediaType:mediaType
                                                       folderPath:folder
                                                         metadata:metadata
                                                            error:&error];
        if (saved) {
            // The copy inherits the original's date via saveMetadata (for
            // filename/attribution), but should sort as the newest item — the
            // edit happened just now.
            [saved markAddedNow];
            done(YES, (mediaType == SPKGalleryMediaTypeImage) ? @"帧已保存到图库" : (mediaType == SPKGalleryMediaTypeAudio) ? @"音频已保存到图库"
                                                                                                                                    : @"裁剪片段已保存到图库");
        } else {
            done(NO, error.localizedDescription ?: @"无法保存裁剪后的文件");
        }
    };

    BOOL shouldPrompt = (originFile != nil) && [SPKUtils getBoolPref:@"trim_gallery_prompt_replace"];
    if (!shouldPrompt) {
        [self renderResult:result
             progressTitle:nil
              existingPill:nil
                     store:copyStore
              onSuccessTap:^{
                  [SPKGalleryViewController presentGallery];
              }
                completion:completion];
        return;
    }

    SPKTrimStoreBlock replaceStore = ^(NSURL *rendered, void (^done)(BOOL, NSString *)) {
        NSError *error = nil;
        BOOL ok = [originFile replaceMediaWithFileURL:rendered mediaType:mediaType error:&error];
        done(ok, ok ? @"已替换原文件" : (error.localizedDescription ?: @"无法替换原文件。"));
    };

    NSString *title = (result.mode == SPKTrimResultModeFrameOnly) ? @"保存照片" : (result.mode == SPKTrimResultModeTrimmedAudio) ? @"保存音频"
                                                                                                                                   : @"保存裁剪片段";
    SPKIGAlertAction *copy = [SPKIGAlertAction actionWithTitle:@"另存为副本"
                                                         style:SPKIGAlertActionStyleDefault
                                                       handler:^{
                                                           [self renderResult:result
                                                                progressTitle:nil
                                                                 existingPill:nil
                                                                        store:copyStore
                                                                 onSuccessTap:^{
                                                                     [SPKGalleryViewController presentGallery];
                                                                 }
                                                                   completion:completion];
                                                       }];
    SPKIGAlertAction *replace = [SPKIGAlertAction actionWithTitle:@"替换原文件"
                                                            style:SPKIGAlertActionStyleDestructive
                                                          handler:^{
                                                              [self renderResult:result
                                                                   progressTitle:nil
                                                                    existingPill:nil
                                                                           store:replaceStore
                                                                    onSuccessTap:^{
                                                                        [SPKGalleryViewController presentGallery];
                                                                    }
                                                                      completion:completion];
                                                          }];
    SPKIGAlertAction *cancel = [SPKIGAlertAction actionWithTitle:@"取消"
                                                           style:SPKIGAlertActionStyleCancel
                                                         handler:^{
                                                             if (completion)
                                                                 completion(NO);
                                                         }];

    BOOL presented = [SPKIGAlertPresenter presentActionSheetFromViewController:presenter
                                                                         title:title
                                                                       message:@"要替换原文件还是保存副本？"
                                                                       actions:@[ replace, copy, cancel ]];
    if (!presented) {
        [self renderResult:result
             progressTitle:nil
              existingPill:nil
                     store:copyStore
              onSuccessTap:^{
                  [SPKGalleryViewController presentGallery];
              }
                completion:completion];
    }
}

#pragma mark - Edited image

+ (void)saveEditedImage:(UIImage *)image
             originFile:(SPKGalleryFile *)originFile
         fallbackSource:(SPKGallerySource)fallbackSource
             folderPath:(NSString *)folderPath
              presenter:(UIViewController *)presenter
             completion:(void (^)(BOOL))completion {
    NSURL *tempURL = [self writeEditedImageToTemp:image];
    if (!tempURL) {
        SPKNotify(@"spk.photoedit.save", @"保存失败",
                  @"无法编码编辑后的图片。", @"error_filled",
                  SPKNotificationToneError);
        if (completion)
            completion(NO);
        return;
    }
    // Route through the shared trim save path: a frame-only result with its output
    // already rendered (renderResult: short-circuits on a pre-filled outputURL), so
    // the Replace/Save-as-Copy prompt, the progress→success pill, and cleanup are
    // all identical to a trimmed frame's save.
    SPKTrimResult *result = [SPKTrimResult requestWithMode:SPKTrimResultModeFrameOnly
                                                 sourceURL:tempURL
                                              startSeconds:0.0
                                           durationSeconds:0.0];
    result.outputURL = tempURL;
    [self saveResult:result
            originFile:originFile
        fallbackSource:fallbackSource
            folderPath:folderPath
             presenter:presenter
            completion:completion];
}

+ (void)routeEditedImage:(UIImage *)image
           toDestination:(NSString *)destination
                metadata:(SPKGallerySaveMetadata *)metadata
               presenter:(UIViewController *)presenter
              completion:(void (^)(BOOL))completion {
    NSURL *tempURL = [self writeEditedImageToTemp:image];
    if (!tempURL) {
        SPKNotify(@"spk.photoedit.save", @"保存失败",
                  @"无法编码编辑后的图片。", @"error_filled",
                  SPKNotificationToneError);
        if (completion)
            completion(NO);
        return;
    }
    // Frame-only result with its output already rendered (renderResult:
    // short-circuits on a pre-filled outputURL), so the destination routing +
    // progress/success pill are identical to a trimmed frame's save.
    SPKTrimResult *result = [SPKTrimResult requestWithMode:SPKTrimResultModeFrameOnly
                                                 sourceURL:tempURL
                                              startSeconds:0.0
                                           durationSeconds:0.0];
    result.outputURL = tempURL;
    [self routeResult:result
        toDestination:destination
             metadata:metadata
            presenter:presenter
         existingPill:nil
           completion:completion];
}

// Encodes an edited image to a unique temp JPEG. Returns nil on failure.
+ (NSURL *)writeEditedImageToTemp:(UIImage *)image {
    NSData *data = image ? UIImageJPEGRepresentation(image, 0.85) : nil;
    if (!data)
        return nil;
    NSString *name = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"jpg"];
    NSURL *tempURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:name];
    if (![data writeToURL:tempURL options:NSDataWritingAtomic error:NULL])
        return nil;
    return tempURL;
}

#pragma mark - Destination routing

+ (void)routeResult:(SPKTrimResult *)result
      toDestination:(NSString *)destination
           metadata:(SPKGallerySaveMetadata *)metadata
          presenter:(UIViewController *)presenter
       existingPill:(SPKNotificationPillView *)existingPill
         completion:(void (^)(BOOL))completion {
    SPKGalleryMediaType mediaType = SPKGalleryMediaTypeVideo;
    if (result.mode == SPKTrimResultModeFrameOnly) {
        mediaType = SPKGalleryMediaTypeImage;
    } else if (result.mode == SPKTrimResultModeTrimmedAudio) {
        mediaType = SPKGalleryMediaTypeAudio;
    }

    SPKTrimStoreBlock store;
    if ([destination isEqualToString:@"photos"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            [SPKDownloadDestinationWriter saveFileURLToPhotos:rendered
                                                     metadata:metadata
                                                   completion:^(BOOL ok, NSError *error) {
                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                           done(ok, ok ? @"已保存到照片" : (error.localizedDescription ?: @"无法保存到照片。"));
                                                       });
                                                   }];
        };
    } else if ([destination isEqualToString:@"clipboard"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            NSString *ext = rendered.pathExtension.lowercaseString;
            BOOL isVideo = [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"];
            BOOL isAudio = [ext isEqualToString:@"m4a"] || [ext isEqualToString:@"mp3"] || [ext isEqualToString:@"wav"] || [ext isEqualToString:@"aac"];
            if (isVideo) {
                NSData *data = [NSData dataWithContentsOfURL:rendered options:NSDataReadingMappedIfSafe error:nil];
                if (data) {
                    [UIPasteboard generalPasteboard].items = @[ @{UTTypeMovie.identifier : data} ];
                    done(YES, @"片段已复制到剪贴板");
                } else {
                    done(NO, @"无法复制片段。");
                }
            } else if (isAudio) {
                NSData *data = [NSData dataWithContentsOfURL:rendered options:NSDataReadingMappedIfSafe error:nil];
                if (data) {
                    [UIPasteboard generalPasteboard].items = @[ @{UTTypeAudio.identifier : data} ];
                    done(YES, @"音频已复制到剪贴板");
                } else {
                    done(NO, @"无法复制音频。");
                }
            } else {
                UIImage *image = [UIImage imageWithContentsOfFile:rendered.path];
                if (image) {
                    [[UIPasteboard generalPasteboard] setImage:image];
                    done(YES, @"帧已复制到剪贴板");
                } else {
                    done(NO, @"无法复制帧。");
                }
            }
        };
    } else if ([destination isEqualToString:@"files"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            UIViewController *host = presenter ?: topMostController();
            if (!host) {
                done(NO, @"无法打开文件选择器。");
                return;
            }
            SPKTrimFilesExporter *exporter = [SPKTrimFilesExporter new];
            exporter.done = done;
            exporter.selfRef = exporter;
            // asCopy:YES so the picker copies our temp file; the temp is cleaned up
            // by renderResult once `done` fires (after the export completes).
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
                initForExportingURLs:@[ rendered ]
                              asCopy:YES];
            picker.delegate = exporter;
            picker.shouldShowFileExtensions = YES;
            if (picker.popoverPresentationController) {
                picker.popoverPresentationController.sourceView = host.view;
                picker.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                                                             CGRectGetMidY(host.view.bounds), 1, 1);
                picker.popoverPresentationController.permittedArrowDirections = 0;
            }
            [host presentViewController:picker animated:YES completion:nil];
        };
    } else if ([destination isEqualToString:@"share"]) {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            UIViewController *host = presenter ?: topMostController();
            if (!host) {
                done(NO, @"无法打开分享面板。");
                return;
            }
            UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[ rendered ]
                                                                             applicationActivities:nil];
            vc.completionWithItemsHandler = ^(UIActivityType _Nullable type, BOOL completed,
                                              NSArray *_Nullable items, NSError *_Nullable err) {
                done(YES, completed ? @"已分享" : nil);
            };
            if (vc.popoverPresentationController) {
                vc.popoverPresentationController.sourceView = host.view;
                vc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(host.view.bounds),
                                                                         CGRectGetMidY(host.view.bounds), 1, 1);
                vc.popoverPresentationController.permittedArrowDirections = 0;
            }
            [host presentViewController:vc animated:YES completion:nil];
        };
    } else {
        store = ^(NSURL *rendered, SPKTrimStoreCompletion done) {
            SPKGallerySource source = metadata ? (SPKGallerySource)metadata.source : SPKGallerySourceOther;
            NSError *error = nil;
            SPKGalleryFile *saved = [SPKGalleryFile saveFileToGallery:rendered
                                                               source:source
                                                            mediaType:mediaType
                                                           folderPath:nil
                                                             metadata:metadata
                                                                error:&error];
            if (saved)
                done(YES, (mediaType == SPKGalleryMediaTypeImage) ? @"帧已保存到图库" : (mediaType == SPKGalleryMediaTypeAudio) ? @"音频已保存到图库"
                                                                                                                                        : @"裁剪片段已保存到图库");
            else
                done(NO, error.localizedDescription ?: @"无法保存到图库。");
        };
    }

    void (^onSuccessTap)(void) = nil;
    if ([destination isEqualToString:@"gallery"]) {
        onSuccessTap = ^{
            [SPKGalleryViewController presentGallery];
        };
    } else if ([destination isEqualToString:@"photos"]) {
        onSuccessTap = ^{
            [SPKUtils openPhotosApp];
        };
    }

    // Name the render with the standard scheme so Save Audio to Files / Share Audio carry
    // a proper filename instead of the temp UUID (Gallery renames on import anyway).
    if (!result.preferredBasename.length) {
        result.preferredBasename = [SPKFileNameForMedia(result.sourceURL, mediaType, metadata) stringByDeletingPathExtension];
    }

    [self renderResult:result
         progressTitle:nil
          existingPill:existingPill
                 store:store
          onSuccessTap:onSuccessTap
            completion:completion];
}

#pragma mark - Background render

// Renders in the background behind a progress pill (cancellable), then stores
// the output. The app stays usable throughout.
+ (void)renderResult:(SPKTrimResult *)result
       progressTitle:(NSString *)progressTitle
        existingPill:(SPKNotificationPillView *)existingPill
               store:(SPKTrimStoreBlock)store
        onSuccessTap:(void (^)(void))onSuccessTap
          completion:(void (^)(BOOL))completion {
    BOOL isFrameOnly = (result.mode == SPKTrimResultModeFrameOnly);
    BOOL isAudio = (result.mode == SPKTrimResultModeTrimmedAudio);
    // Prefer the caller-supplied name (epoch_user_source_date) so Files/Share
    // exports don't leak the temp UUID; fall back to a unique temp name.
    NSString *basename = result.preferredBasename.length
                             ? result.preferredBasename
                             : [NSString stringWithFormat:@"SPKTrim-%@", NSUUID.UUID.UUIDString];
    NSString *title = progressTitle.length > 0 ? progressTitle
                                               : (isFrameOnly ? @"正在提取帧..." : (isAudio ? @"正在裁剪音频..." : @"正在裁剪..."));

    // Continue an in-flight pill (e.g. from a preceding download) instead of
    // stacking a second notification.
    SPKNotificationPillView *pill = existingPill;
    if (pill) {
        [pill updateProgressTitle:title subtitle:nil];
        [pill setProgress:0.0f animated:NO];
    } else {
        pill = [[SPKNotificationCenter shared] beginUnmanagedProgressWithTitle:title onCancel:nil];
    }

    __block dispatch_block_t cancelRender = nil;
    __block BOOL cancelled = NO;
    __weak SPKNotificationPillView *weakPill = pill;
    pill.onCancel = ^{
        // Confirm first (mirrors the download cancel). The pill's close button
        // calls onCancel without dismissing, so dismiss on confirm.
        [SPKTrimSaveCoordinator confirmCancelThen:^{
            cancelled = YES;
            if (cancelRender)
                cancelRender();
            [weakPill dismiss];
        }];
    };

    void (^onRendered)(NSURL *, NSError *) = ^(NSURL *renderedURL, NSError *error) {
        if (cancelled) {
            if (renderedURL)
                [[NSFileManager defaultManager] removeItemAtURL:renderedURL error:nil];
            if (completion)
                completion(NO);
            return;
        }
        if (!renderedURL) {
            // The reason goes in the subtitle so the pill always leads with what
            // failed; an encoder message is too long to read as a title.
            [pill showErrorWithTitle:@"裁剪失败" subtitle:error.localizedDescription icon:nil];
            if (completion)
                completion(NO);
            return;
        }
        store(renderedURL, ^(BOOL ok, NSString *message) {
            [[NSFileManager defaultManager] removeItemAtURL:renderedURL error:nil];
            if (ok) {
                [pill showSuccessWithTitle:message subtitle:(onSuccessTap ? @"点击查看" : nil)icon:nil];
                if (onSuccessTap)
                    pill.onTapWhenCompleted = onSuccessTap;
            } else {
                [pill showError:message ?: @"保存失败"];
            }
            if (completion)
                completion(ok);
        });
    };

    void (^progressToPill)(double) = ^(double p) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [pill setProgress:(float)MAX(0.0, MIN(1.0, p)) animated:YES];
        });
    };

    // Pre-rendered output (e.g. a frame the user edited in the photo editor):
    // skip extraction/encoding and hand the existing file straight to `store`, so
    // the whole save/route pipeline (Gallery copy/replace, destination menu, the
    // progress pill) runs unchanged.
    if (result.outputURL && [[NSFileManager defaultManager] fileExistsAtPath:result.outputURL.path]) {
        onRendered(result.outputURL, nil);
        return;
    }

    if (isFrameOnly) {
        // Extract from the chosen-quality video when overridden, else the edit
        // file. For DASH the chosen-quality source is a standalone fragmented
        // MP4 that AVFoundation can occasionally fail to decode a still from, so
        // fall back to the muxed edit file the user actually scrubbed (always
        // AVFoundation-friendly) before giving up.
        NSMutableArray<NSURL *> *frameSources = [NSMutableArray array];
        if (result.renderVideoURL)
            [frameSources addObject:result.renderVideoURL];
        if (result.sourceURL && ![result.sourceURL isEqual:result.renderVideoURL]) {
            [frameSources addObject:result.sourceURL];
        }
        [self extractFrameFromURLs:frameSources
                         atSeconds:result.startSeconds
                          basename:basename
                        completion:onRendered];
    } else if (isAudio) {
        // Audio-only trim → native AAC .m4a via AVAssetExportSession.
        [SPKTrimRenderer renderTrimAudioForSourceURL:(result.renderAudioURL ?: result.sourceURL)
                                               asset:nil
                                        startSeconds:result.startSeconds
                                     durationSeconds:result.durationSeconds
                                            basename:basename
                                          completion:onRendered];
    } else if (result.renderAudioURL) {
        // DASH: merge the chosen-quality video + audio over the selected range.
        [SPKTrimRenderer renderTrimMergeForVideoURL:result.renderVideoURL
                                           audioURL:result.renderAudioURL
                                       startSeconds:result.startSeconds
                                    durationSeconds:result.durationSeconds
                                               crop:result.crop
                                              width:result.width
                                             height:result.height
                                           basename:basename
                                           progress:progressToPill
                                         completion:onRendered
                                          cancelOut:^(dispatch_block_t cancel) {
                                              cancelRender = cancel;
                                          }];
    } else {
        [SPKTrimRenderer renderTrimForSourceURL:(result.renderVideoURL ?: result.sourceURL)
                                          asset:nil
                                   startSeconds:result.startSeconds
                                durationSeconds:result.durationSeconds
                                           crop:result.crop
                                       basename:basename
                                       progress:progressToPill
                                     completion:onRendered
                                      cancelOut:^(dispatch_block_t cancel) {
                                          cancelRender = cancel;
                                      }];
    }
}

#pragma mark - Frame extraction (with source fallback)

// Tries each candidate URL in order, returning the first frame that decodes.
// Lets us prefer the chosen-quality video but fall back to the muxed edit file
// when AVFoundation can't pull a still from a DASH fragment.
+ (void)extractFrameFromURLs:(NSArray<NSURL *> *)urls
                   atSeconds:(NSTimeInterval)seconds
                    basename:(NSString *)basename
                  completion:(void (^)(NSURL *_Nullable, NSError *_Nullable))completion {
    if (urls.count == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"Sparkle.TrimSave"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey : @"无法提取所选帧。"}]);
        }
        return;
    }
    NSURL *candidate = urls.firstObject;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:candidate options:nil];
    [SPKTrimRenderer renderFrameForAsset:asset
                               atSeconds:seconds
                                basename:basename
                              completion:^(NSURL *output, NSError *error) {
                                  if (output) {
                                      if (completion)
                                          completion(output, nil);
                                      return;
                                  }
                                  if (urls.count <= 1) {
                                      if (completion)
                                          completion(nil, error);
                                      return;
                                  }
                                  [self extractFrameFromURLs:[urls subarrayWithRange:NSMakeRange(1, urls.count - 1)]
                                                   atSeconds:seconds
                                                    basename:basename
                                                  completion:completion];
                              }];
}

#pragma mark - Cancel confirmation

+ (void)confirmCancelThen:(void (^)(void))onConfirm {
    UIViewController *host = topMostController();
    if (!host) {
        if (onConfirm)
            onConfirm();
        return;
    }
    SPKIGAlertAction *keep = [SPKIGAlertAction actionWithTitle:@"继续"
                                                         style:SPKIGAlertActionStyleCancel
                                                       handler:nil];
    SPKIGAlertAction *stop = [SPKIGAlertAction actionWithTitle:@"停止"
                                                         style:SPKIGAlertActionStyleDestructive
                                                       handler:^{
                                                           if (onConfirm)
                                                               onConfirm();
                                                       }];
    [SPKIGAlertPresenter presentAlertFromViewController:host
                                                  title:@"取消裁剪"
                                                message:@"停止裁剪并放弃当前进度？"
                                                actions:@[ keep, stop ]];
}

@end
