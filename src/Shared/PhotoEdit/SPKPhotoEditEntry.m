#import "SPKPhotoEditEntry.h"
#import "../../Utils.h"
#import "../Gallery/SPKGallerySaveMetadata.h"
#import "../MediaTrim/SPKTrimSaveCoordinator.h"
#import "../UI/SPKNotificationCenter.h"
#import "SPKPhotoEditorViewController.h"

@interface SPKPhotoEditEntry () <NSURLSessionDownloadDelegate>
@property (nonatomic, strong, nullable) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDownloadTask *task;
@property (nonatomic, strong, nullable) SPKNotificationPillView *prepPill;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, strong, nullable) SPKGallerySaveMetadata *metadata;
@property (nonatomic, copy, nullable) NSString *tempPath;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, strong, nullable) SPKPhotoEditEntry *selfRetain;
@end

@implementation SPKPhotoEditEntry

+ (void)beginEditAndSaveForMediaObject:(id)mediaObject
                              photoURL:(NSURL *)photoURL
                              metadata:(SPKGallerySaveMetadata *)metadata
                             presenter:(UIViewController *)presenter {
    if (!presenter)
        return;
    if (!photoURL) {
        SPKNotify(@"spk.photoedit.entry", @"No photo to edit", nil, @"error_filled",
                  SPKNotificationToneError);
        return;
    }

    SPKPhotoEditEntry *entry = [[self alloc] init];
    entry.presenter = presenter;
    entry.metadata = metadata;
    entry.selfRetain = entry; // keep alive across the async flow

    // A local file (e.g. gallery / already-downloaded) needs no fetch.
    if (photoURL.isFileURL) {
        UIImage *image = [UIImage imageWithContentsOfFile:photoURL.path];
        if (!image) {
            SPKNotify(@"spk.photoedit.entry", @"Cannot Edit",
                      @"The image is unavailable.", @"error_filled", SPKNotificationToneError);
            [entry finish];
            return;
        }
        [entry presentEditorWithImage:image];
        return;
    }

    [entry downloadPhotoURL:photoURL];
}

#pragma mark - Download

- (void)downloadPhotoURL:(NSURL *)url {
    __weak typeof(self) weakSelf = self;
    self.prepPill = [[SPKNotificationCenter shared] beginUnmanagedProgressWithTitle:@"Preparing photo..."
                                                                           onCancel:^{
                                                                               [SPKTrimSaveCoordinator confirmCancelThen:^{
                                                                                   __strong typeof(weakSelf) self = weakSelf;
                                                                                   self.cancelled = YES;
                                                                                   [self.task cancel];
                                                                                   [self.prepPill dismiss];
                                                                                   self.prepPill = nil;
                                                                                   [self cleanupAndFinish];
                                                                               }];
                                                                           }];

    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:nil];
    self.task = [self.session downloadTaskWithURL:url];
    [self.task resume];
}

- (void)URLSession:(NSURLSession *)session
                 downloadTask:(NSURLSessionDownloadTask *)downloadTask
                 didWriteData:(int64_t)bytesWritten
            totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0)
        return;
    float p = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.prepPill setProgress:MAX(0.0f, MIN(1.0f, p)) animated:YES];
    });
}

- (void)URLSession:(NSURLSession *)session
                 downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didFinishDownloadingToURL:(NSURL *)location {
    NSString *dest = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"SPKEditSrc-%@.jpg", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    if ([[NSFileManager defaultManager] moveItemAtPath:location.path toPath:dest error:nil]) {
        self.tempPath = dest;
    }
}

- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled)
            return;
        UIImage *image = self.tempPath ? [UIImage imageWithContentsOfFile:self.tempPath] : nil;
        if (error || !image) {
            [self.prepPill showError:error.localizedDescription ?: @"Could not download the photo."];
            self.prepPill = nil;
            [self cleanupAndFinish];
            return;
        }
        [self.prepPill dismiss];
        self.prepPill = nil;
        [self presentEditorWithImage:image];
    });
}

#pragma mark - Editor

- (void)presentEditorWithImage:(UIImage *)image {
    UIViewController *presenter = self.presenter;
    if (!presenter) {
        [self cleanupAndFinish];
        return;
    }
    SPKPhotoEditorConfiguration *config = [SPKPhotoEditorConfiguration freeformConfiguration];
    config.doneOptions = @[
        [SPKPhotoEditorDoneOption optionWithTitle:@"保存到照片"
                                       identifier:@"photos"
                                         iconName:@"download"],
        [SPKPhotoEditorDoneOption optionWithTitle:@"分享"
                                       identifier:@"share"
                                         iconName:@"share"],
        [SPKPhotoEditorDoneOption optionWithTitle:@"复制"
                                       identifier:@"clipboard"
                                         iconName:@"copy"],
        [SPKPhotoEditorDoneOption optionWithTitle:@"保存到图库"
                                       identifier:@"gallery"
                                         iconName:@"sparkle_gallery"],
    ];
    __weak typeof(self) weakSelf = self;
    [SPKPhotoEditorViewController presentWithSourceImage:image
                                           configuration:config
                                                    from:presenter
                                   destinationCompletion:^(UIImage *edited, NSString *destinationTag) {
                                       __strong typeof(weakSelf) self = weakSelf;
                                       if (!self)
                                           return;
                                       // Cancel is signalled as a nil image (destination mode), so the entry is
                                       // always released whether the user saves or backs out.
                                       if (!edited) {
                                           [self cleanupAndFinish];
                                           return;
                                       }
                                       [SPKTrimSaveCoordinator routeEditedImage:edited
                                                                  toDestination:(destinationTag ?: @"gallery")
                                                                                metadata:self.metadata
                                                                      presenter:self.presenter
                                                                     completion:^(BOOL ok) {
                                                                         [self cleanupAndFinish];
                                                                     }];
                                   }];
}

#pragma mark - Lifecycle

- (void)cleanupAndFinish {
    if (self.tempPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempPath error:nil];
        self.tempPath = nil;
    }
    [self finish];
}

- (void)finish {
    [self.session finishTasksAndInvalidate];
    self.session = nil;
    self.selfRetain = nil; // allow deallocation
}

@end
