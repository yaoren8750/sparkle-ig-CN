#import "SPKVideoCropViewController.h"

#import "../../Utils.h"
#import "../Crop/SPKCropCanvasView.h"
#import "../UI/SPKChipBar.h"
#import "../UI/SPKMediaChrome.h"
#import "SPKVideoCropContentView.h"

#import <AVFoundation/AVFoundation.h>

static const CGFloat kSPKVideoCropControlsRow = 56.0;

#pragma mark - Controller

@interface SPKVideoCropViewController () <SPKChipBarDelegate>
@property (nonatomic, copy) NSURL *videoURL;
@property (nonatomic, assign) CGFloat lockedAspectRatio;
@property (nonatomic, copy, nullable) SPKTrimCrop *initialCrop;
@property (nonatomic, copy) void (^completion)(SPKTrimCrop *_Nullable);

@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) SPKCropCanvasView *canvas;
@property (nonatomic, strong) SPKVideoCropContentView *contentView;
@property (nonatomic, strong) UIView *toolRow;
@property (nonatomic, strong) SPKChipBar *aspectChips;
@property (nonatomic, assign) CGSize orientedSize;
@property (nonatomic, assign) NSInteger rotationQuarters;
@property (nonatomic, assign) BOOL mirrored;
@end

@implementation SPKVideoCropViewController

+ (void)presentForVideoURL:(NSURL *)videoURL
         lockedAspectRatio:(CGFloat)lockedAspectRatio
               initialCrop:(SPKTrimCrop *)initialCrop
                     title:(NSString *)title
                      from:(UIViewController *)presenter
                completion:(void (^)(SPKTrimCrop *_Nullable))completion {
    if (!videoURL || !presenter) {
        SPKLog(@"裁剪", @"[Sparkle] crop editor not presented (url=%d presenter=%d)", videoURL != nil, presenter != nil);
        if (completion)
            completion(nil);
        return;
    }
    // Presenting onto a controller that is still finishing a dismissal is
    // silently refused by UIKit, which looks exactly like the editor opening and
    // closing again. Go to whatever is actually frontmost instead.
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    SPKVideoCropViewController *editor = [[self alloc] init];
    editor.videoURL = videoURL;
    editor.lockedAspectRatio = lockedAspectRatio;
    editor.initialCrop = initialCrop;
    editor.completion = completion;
    editor.title = title.length > 0 ? title : @"裁剪";
    // Same chrome as the trim and photo editors: native bars (Liquid Glass on
    // iOS 26), always dark so the black canvas and light controls read correctly.
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SPKUtils SPKColor_InstagramBackground] ?: [UIColor blackColor];
    _rotationQuarters = self.initialCrop.rotationQuarters;
    _mirrored = self.initialCrop.mirrored;

    [self setupChrome];
    [self setupCanvas];
    [self setupToolRow];
    [self setupAspectChipsIfNeeded];
    [self loadAsset];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.player pause];
}

#pragma mark - Setup

- (void)setupChrome {
    UIBarButtonItem *cancelItem = SPKMediaChromeTopBarButtonItem(@"close", self, @selector(cancelTapped));
    cancelItem.accessibilityLabel = @"取消";
    // Plain and untinted: confirming here returns the framing to the trim
    // editor, whose own Done is the one that commits the edit.
    UIBarButtonItem *doneItem = SPKMediaChromeTopBarButtonItem(@"check", self, @selector(confirmTapped));
    doneItem.accessibilityLabel = @"完成";
    SPKMediaChromeSetLeadingTopBarItems(self.navigationItem, @[ cancelItem ]);
    SPKMediaChromeSetTrailingTopBarItems(self.navigationItem, @[ doneItem ]);
}

- (void)setupCanvas {
    _canvas = [[SPKCropCanvasView alloc] initWithFrame:CGRectZero];
    _canvas.translatesAutoresizingMaskIntoConstraints = NO;
    _canvas.aspectMode = self.lockedAspectRatio > 0.0 ? SPKCropAspectModeLocked : SPKCropAspectModeFreeform;
    _canvas.lockedAspectRatio = self.lockedAspectRatio > 0.0 ? self.lockedAspectRatio : 1.0;
    _canvas.aspect = SPKCropAspectOriginal;
    [self.view addSubview:_canvas];
    [NSLayoutConstraint activateConstraints:@[
        [_canvas.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_canvas.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_canvas.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupToolRow {
    _toolRow = SPKCropMakeToolRow(self, @selector(rotateLeftTapped), @selector(flipTapped), @selector(rotateRightTapped));
    [self.view addSubview:_toolRow];
    [NSLayoutConstraint activateConstraints:@[
        [_toolRow.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:48.0],
        [_toolRow.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-48.0],
        [_toolRow.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0],
        [_toolRow.heightAnchor constraintEqualToConstant:kSPKVideoCropControlsRow],
    ]];
}

- (void)setupAspectChipsIfNeeded {
    if (self.lockedAspectRatio > 0.0) {
        // Locked ratio: no picker, the canvas pins straight above the tools.
        [_canvas.bottomAnchor constraintEqualToAnchor:_toolRow.topAnchor constant:-8.0].active = YES;
        return;
    }

    _aspectChips = [[SPKChipBar alloc] init];
    _aspectChips.translatesAutoresizingMaskIntoConstraints = NO;
    _aspectChips.delegate = self;
    _aspectChips.distributesToFit = NO;
    NSInteger aspectCount = SPKCropAspectPresetCount();
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:(NSUInteger)aspectCount];
    for (NSInteger i = 0; i < aspectCount; i++) {
        [titles addObject:SPKCropAspectTitle(SPKCropAspectPresetAtIndex(i))];
    }
    [_aspectChips setItems:titles symbols:@[]];
    _aspectChips.selectedIndex = 0; // Original (first)
    [self.view addSubview:_aspectChips];
    [NSLayoutConstraint activateConstraints:@[
        [_aspectChips.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_aspectChips.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [_aspectChips.bottomAnchor constraintEqualToAnchor:_toolRow.topAnchor constant:-4.0],
        [_canvas.bottomAnchor constraintEqualToAnchor:_aspectChips.topAnchor constant:-4.0],
    ]];
}

#pragma mark - Asset

- (void)loadAsset {
    _asset = [AVURLAsset URLAssetWithURL:self.videoURL options:nil];
    __weak typeof(self) weakSelf = self;
    [_asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ]
                          completionHandler:^{
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [weakSelf assetTracksLoaded];
                              });
                          }];
}

- (void)assetTracksLoaded {
    NSError *error = nil;
    AVKeyValueStatus status = [self.asset statusOfValueForKey:@"tracks" error:&error];
    AVAssetTrack *videoTrack = [self.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!videoTrack) {
        SPKLog(@"裁剪", @"[Sparkle] crop editor closing: no video track (status=%ld err=%@ url=%@)", (long)status,
               error.localizedDescription, self.videoURL.lastPathComponent);
        [self cancelTapped];
        return;
    }
    CGSize rendered = CGSizeApplyAffineTransform(videoTrack.naturalSize, videoTrack.preferredTransform);
    _orientedSize = CGSizeMake(fabs(rendered.width), fabs(rendered.height));
    if (_orientedSize.width <= 0.0 || _orientedSize.height <= 0.0) {
        SPKLog(@"裁剪", @"[Sparkle] crop editor closing: bad oriented size %@ (natural %@)",
               NSStringFromCGSize(_orientedSize), NSStringFromCGSize(videoTrack.naturalSize));
        [self cancelTapped];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:self.asset];
    _player = [AVPlayer playerWithPlayerItem:item];
    // Framing is a silent job, and staying muted keeps us out of the app's audio
    // session entirely (IG is often mid-playback behind this screen).
    _player.muted = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];

    _contentView = [[SPKVideoCropContentView alloc] initWithPlayer:_player orientedSize:_orientedSize];
    _contentView.rotationQuarters = _rotationQuarters;
    _contentView.mirrored = _mirrored;
    [_canvas setContentView:_contentView contentSize:[self currentContentSize]];
    if (self.initialCrop && !self.initialCrop.isIdentity) {
        [_canvas restoreNormalizedCropRect:self.initialCrop.normalizedRect];
    }
    [_player play];
}

- (CGSize)currentContentSize {
    if (_rotationQuarters % 2 == 1)
        return CGSizeMake(_orientedSize.height, _orientedSize.width);
    return _orientedSize;
}

- (void)playerItemDidReachEnd:(__unused NSNotification *)note {
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self.player play];
}

#pragma mark - Rotate / flip

- (void)rotateLeftTapped {
    [self applyOrientationChange:^{
        self.rotationQuarters = self.rotationQuarters - 1;
    }];
}

- (void)rotateRightTapped {
    [self applyOrientationChange:^{
        self.rotationQuarters = self.rotationQuarters + 1;
    }];
}

- (void)flipTapped {
    [self applyOrientationChange:^{
        self.mirrored = !self.mirrored;
    }];
}

- (void)applyOrientationChange:(void (^)(void))mutate {
    mutate();
    _rotationQuarters = ((_rotationQuarters % 4) + 4) % 4;
    _contentView.rotationQuarters = _rotationQuarters;
    _contentView.mirrored = _mirrored;
    // A quarter turn swaps the frame's axes, so the canvas re-fits its crop around
    // the new dimensions (same contract the photo editor uses after re-baking).
    [_canvas setContentSize:[self currentContentSize]];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
}

#pragma mark - SPKChipBarDelegate (aspect)

- (void)chipBar:(__unused SPKChipBar *)bar didSelectIndex:(NSInteger)index {
    if (index < 0 || index >= SPKCropAspectPresetCount())
        return;
    _canvas.aspect = SPKCropAspectPresetAtIndex(index);
}

#pragma mark - Confirm / cancel

- (void)cancelTapped {
    void (^completion)(SPKTrimCrop *) = [self.completion copy];
    self.completion = nil;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (completion)
                                     completion(nil);
                             }];
}

- (void)confirmTapped {
    CGRect normalized = _canvas.normalizedCropRect;
    SPKTrimCrop *crop = [SPKTrimCrop cropWithNormalizedRect:normalized
                                          rotationQuarters:_rotationQuarters
                                                  mirrored:_mirrored];
    void (^completion)(SPKTrimCrop *) = [self.completion copy];
    self.completion = nil;
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 if (completion)
                                     completion(crop.isIdentity ? nil : crop);
                             }];
}

@end
