#import "SPKFullScreenImageViewController.h"
#import "SPKImageFormat.h"
#import "SPKMediaCacheManager.h"
#import "SPKMediaItem.h"
#import <objc/message.h>

static CGFloat const kMaxZoom = 5.0;
static CGFloat const kMinZoom = 1.0;
static CGFloat const kZoomEpsilon = 0.02;

@interface SPKFullScreenImageViewController () <UIScrollViewDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) UIEdgeInsets desiredContentInsets;
@property (nonatomic, assign) BOOL hasDesiredContentInsets;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIView *errorView;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, assign) BOOL isLoadingImage;
@property (nonatomic, assign) BOOL lastReportedZoomState;
@property (nonatomic, strong) id liveTextBridge;

@end

@implementation SPKFullScreenImageViewController

- (instancetype)initWithMediaItem:(SPKMediaItem *)item {
    self = [super init];
    if (self) {
        _mediaItem = item;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    [self setupScrollView];
    [self setupImageView];
    [self setupLoadingIndicator];
    [self setupErrorView];
    [self setupGestures];
    [self preloadContent];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateImageViewFrame];
}

- (void)applyMediaContentInsets:(UIEdgeInsets)insets {
    self.desiredContentInsets = insets;
    self.hasDesiredContentInsets = YES;
    // Insets only affect the min-zoom fit/centering. While zoomed the image
    // uses the full screen, so there's nothing to update (and nothing jumps);
    // the new insets take effect naturally when the user returns to min zoom.
    if (self.isZoomed)
        return;
    [self updateImageViewFrame];
}

- (UIEdgeInsets)effectiveMinZoomInsets {
    UIEdgeInsets insets = self.hasDesiredContentInsets ? self.desiredContentInsets : UIEdgeInsetsZero;
    if (UIEdgeInsetsEqualToEdgeInsets(insets, UIEdgeInsetsZero))
        return UIEdgeInsetsZero;

    UIImage *image = _imageView.image;
    CGSize boundsSize = _scrollView.bounds.size;
    if (!image || boundsSize.width <= 0 || boundsSize.height <= 0)
        return insets;

    CGSize imageSize = image.size;
    if (imageSize.width <= 0 || imageSize.height <= 0)
        return insets;

    CGFloat availW = MAX(1.0, boundsSize.width - insets.left - insets.right);
    CGFloat availH = MAX(1.0, boundsSize.height - insets.top - insets.bottom);
    CGFloat ratioFull = MIN(boundsSize.width / imageSize.width,
                            boundsSize.height / imageSize.height);
    CGFloat ratioAvail = MIN(availW / imageSize.width, availH / imageSize.height);

    // Only inset images the bars would actually cover. A width-constrained fit
    // (square/landscape photos) already sits clear of the top/bottom bars, so
    // the between-bars region doesn't shrink it any further (ratioAvail ==
    // ratioFull). Insetting those would just shift/resize them and make them
    // jump when the chrome toggles, so leave them full-bleed and centered.
    // Height-constrained fits (tall ~9:16 photos) would run under the bars, so
    // those do get inset.
    if (ratioAvail >= ratioFull - 0.0001)
        return UIEdgeInsetsZero;
    return insets;
}

#pragma mark - Setup

- (void)setupScrollView {
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = kMinZoom;
    _scrollView.maximumZoomScale = kMaxZoom;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.bouncesZoom = YES;
    _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:_scrollView];

    // The scroll view always spans the full screen so a zoomed image can pan
    // edge-to-edge with no black bars. The between-bars inset (pushed by the
    // host via applyMediaContentInsets:) is applied only to the min-zoom fit and
    // centering of the image, so toggling the chrome while zoomed changes
    // nothing visible.
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupImageView {
    Class animatedImageViewClass = NSClassFromString(@"FLAnimatedImageView");
    Class imageViewClass = animatedImageViewClass ?: UIImageView.class;
    _imageView = [[imageViewClass alloc] initWithFrame:CGRectZero];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.clipsToBounds = YES;
    [_scrollView addSubview:_imageView];
}

- (void)setupLoadingIndicator {
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingIndicator.color = [UIColor whiteColor];
    _loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:_loadingIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [_loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)setupErrorView {
    _errorView = [[UIView alloc] initWithFrame:CGRectZero];
    _errorView.translatesAutoresizingMaskIntoConstraints = NO;
    _errorView.hidden = YES;
    [self.view addSubview:_errorView];

    _errorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _errorLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    _errorLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _errorLabel.textAlignment = NSTextAlignmentCenter;
    _errorLabel.numberOfLines = 0;
    [_errorView addSubview:_errorLabel];

    _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_retryButton setTitle:@"重试" forState:UIControlStateNormal];
    [_retryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _retryButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _retryButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    _retryButton.layer.cornerRadius = 18;
    [_retryButton addTarget:self action:@selector(retryLoading) forControlEvents:UIControlEventTouchUpInside];
    [_errorView addSubview:_retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [_errorView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_errorView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_errorView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
                                                              constant:40],

        [_errorLabel.topAnchor constraintEqualToAnchor:_errorView.topAnchor],
        [_errorLabel.leadingAnchor constraintEqualToAnchor:_errorView.leadingAnchor],
        [_errorLabel.trailingAnchor constraintEqualToAnchor:_errorView.trailingAnchor],

        [_retryButton.topAnchor constraintEqualToAnchor:_errorLabel.bottomAnchor
                                               constant:16],
        [_retryButton.centerXAnchor constraintEqualToAnchor:_errorView.centerXAnchor],
        [_retryButton.widthAnchor constraintEqualToConstant:100],
        [_retryButton.heightAnchor constraintEqualToConstant:36],
        [_retryButton.bottomAnchor constraintEqualToAnchor:_errorView.bottomAnchor],
    ]];
}

- (void)setupGestures {
    _doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    _doubleTapGesture.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:_doubleTapGesture];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:_doubleTapGesture];
    [_scrollView addGestureRecognizer:singleTap];
}

#pragma mark - Image Loading

- (void)preloadContent {
    if (self.mediaItem.image) {
        if (self.isViewLoaded) {
            [self displayImage:self.mediaItem.image];
        }
        return;
    }

    NSURL *url = self.mediaItem.fileURL;
    if (!url) {
        if (self.isViewLoaded) {
            [self showError:@"No image URL"];
        }
        return;
    }

    if (self.isLoadingImage) {
        if (self.isViewLoaded) {
            [_loadingIndicator startAnimating];
            _errorView.hidden = YES;
        }
        return;
    }

    self.isLoadingImage = YES;
    if (self.isViewLoaded) {
        [_loadingIndicator startAnimating];
        _errorView.hidden = YES;
    }

    __weak typeof(self) weakSelf = self;
    [[SPKMediaCacheManager sharedManager] loadImageForItem:self.mediaItem
                                                completion:^(UIImage *_Nullable image, NSError *_Nullable error) {
                                                    __strong typeof(weakSelf) strongSelf = weakSelf;
                                                    if (!strongSelf)
                                                        return;

                                                    [strongSelf.loadingIndicator stopAnimating];
                                                    strongSelf.isLoadingImage = NO;

                                                    if (image) {
                                                        if (strongSelf.isViewLoaded) {
                                                            [strongSelf displayImage:image];
                                                        }
                                                        return;
                                                    }

                                                    if (strongSelf.isViewLoaded) {
                                                        [strongSelf showError:error.localizedDescription.length > 0 ? error.localizedDescription : @"Failed to load image"];
                                                    }
                                                }];
}

- (void)retryLoading {
    self.isLoadingImage = NO;
    [self preloadContent];
}

- (void)displayImage:(UIImage *)image {
    _imageView.image = image;
    [self displayAnimatedImageIfAvailable];
    [self configureLiveTextForImage:image];
    _scrollView.hidden = NO;
    _errorView.hidden = YES;
    [_scrollView setZoomScale:kMinZoom animated:NO];
    [self updateImageViewFrame];
}

- (void)configureLiveTextForImage:(UIImage *)image {
    [self.liveTextBridge cleanup];
    self.liveTextBridge = nil;
    NSURL *localURL = [[SPKMediaCacheManager sharedManager] bestAvailableFileURLForItem:self.mediaItem];
    SPKImageFormat format = SPKImageFormatForFileURL(localURL);
    if (format == SPKImageFormatGIF || format == SPKImageFormatWebP)
        return;

    Class bridgeClass = NSClassFromString(@"SPKLiveTextBridge");
    if (!bridgeClass || ![bridgeClass respondsToSelector:@selector(supported)] ||
        !((BOOL (*)(id, SEL))objc_msgSend)(bridgeClass, @selector(supported)))
        return;
    id bridge = ((id (*)(id, SEL, UIImageView *))objc_msgSend)([bridgeClass alloc], NSSelectorFromString(@"initWithImageView:"), _imageView);
    if (!bridge)
        return;
    self.liveTextBridge = bridge;
    ((void (*)(id, SEL, UIImage *))objc_msgSend)(bridge, NSSelectorFromString(@"analyzeImage:"), image);
}

- (void)displayAnimatedImageIfAvailable {
    NSURL *localURL = [[SPKMediaCacheManager sharedManager] bestAvailableFileURLForItem:self.mediaItem];
    SPKImageFormat format = SPKImageFormatForFileURL(localURL);
    if (format != SPKImageFormatGIF && format != SPKImageFormatWebP)
        return;

    Class factory = NSClassFromString(@"FLAnimatedImageFactory");
    SEL setAnimatedImage = NSSelectorFromString(@"setAnimatedImage:");
    if (!factory || ![_imageView respondsToSelector:setAnimatedImage])
        return;

    NSData *data = [NSData dataWithContentsOfURL:localURL options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length)
        return;

    BOOL isGIF = format == SPKImageFormatGIF;
    CGSize size = _imageView.image.size;

    // IG <=435 took a trailing `flAnimatedFrameCacheOOMFixEnabled:` BOOL; IG 436+
    // dropped it. Prefer the 4-arg variant, fall back to the 3-arg one.
    SEL decode4 = NSSelectorFromString(isGIF
                                           ? @"animatedImageWithGIFData:size:targetQueueForFrameCache:flAnimatedFrameCacheOOMFixEnabled:"
                                           : @"animatedImageWithWebPData:size:targetQueueForFrameCache:flAnimatedFrameCacheOOMFixEnabled:");
    SEL decode3 = NSSelectorFromString(isGIF
                                           ? @"animatedImageWithGIFData:size:targetQueueForFrameCache:"
                                           : @"animatedImageWithWebPData:size:targetQueueForFrameCache:");

    id animatedImage = nil;
    if ([factory respondsToSelector:decode4]) {
        animatedImage = ((id (*)(id, SEL, NSData *, CGSize, id, BOOL))objc_msgSend)(
            factory, decode4, data, size, nil, YES);
    } else if ([factory respondsToSelector:decode3]) {
        animatedImage = ((id (*)(id, SEL, NSData *, CGSize, id))objc_msgSend)(
            factory, decode3, data, size, nil);
    }
    if (!animatedImage)
        return;
    ((void (*)(id, SEL, id))objc_msgSend)(_imageView, setAnimatedImage, animatedImage);
    SEL play = NSSelectorFromString(@"play");
    if ([_imageView respondsToSelector:play])
        ((void (*)(id, SEL))objc_msgSend)(_imageView, play);
}

- (void)showError:(NSString *)message {
    _errorLabel.text = message;
    _errorView.hidden = NO;
    _scrollView.hidden = YES;

    if ([self.delegate respondsToSelector:@selector(mediaContent:didFailWithError:)]) {
        NSError *error = [NSError errorWithDomain:@"SPKFullScreenImageViewController" code:-1 userInfo:@{NSLocalizedDescriptionKey : message}];
        [self.delegate mediaContent:self didFailWithError:error];
    }
}

#pragma mark - Frame Management

/// Centers the image inside the scroll view using frame origin (stable with
/// `UIScrollView` zoom). At minimum zoom the image is centered within the
/// between-bars region; when zoomed it centers/pans across the full screen.
- (void)spk_recenterZoomedImage {
    CGSize boundsSize = _scrollView.bounds.size;
    CGSize contentSize = _scrollView.contentSize;
    BOOL atMinimumZoom = (_scrollView.zoomScale <= kMinZoom + kZoomEpsilon);

    if (atMinimumZoom) {
        UIEdgeInsets insets = [self effectiveMinZoomInsets];
        CGFloat availW = MAX(1.0, boundsSize.width - insets.left - insets.right);
        CGFloat availH = MAX(1.0, boundsSize.height - insets.top - insets.bottom);
        _imageView.center = CGPointMake(insets.left + availW * 0.5,
                                        insets.top + availH * 0.5);
        return;
    }

    CGFloat offsetX = (boundsSize.width > contentSize.width) ? (boundsSize.width - contentSize.width) * 0.5 : 0.0;
    CGFloat offsetY = (boundsSize.height > contentSize.height) ? (boundsSize.height - contentSize.height) * 0.5 : 0.0;

    _imageView.center = CGPointMake(contentSize.width * 0.5 + offsetX, contentSize.height * 0.5 + offsetY);
}

- (void)updateImageViewFrame {
    UIImage *image = _imageView.image;
    if (!image)
        return;

    CGSize boundsSize = _scrollView.bounds.size;
    if (boundsSize.width <= 0 || boundsSize.height <= 0)
        return;

    BOOL atMinimumZoom = (_scrollView.zoomScale <= kMinZoom + kZoomEpsilon);

    if (atMinimumZoom) {
        // Fit into the between-bars region so the un-zoomed image never sits
        // under the top/bottom chrome.
        UIEdgeInsets insets = [self effectiveMinZoomInsets];
        CGFloat availW = MAX(1.0, boundsSize.width - insets.left - insets.right);
        CGFloat availH = MAX(1.0, boundsSize.height - insets.top - insets.bottom);

        CGSize imageSize = image.size;
        CGFloat ratio = MIN(availW / imageSize.width, availH / imageSize.height);

        CGFloat newWidth = imageSize.width * ratio;
        CGFloat newHeight = imageSize.height * ratio;

        _imageView.frame = CGRectMake(0, 0, newWidth, newHeight);
        _scrollView.contentSize = CGSizeMake(newWidth, newHeight);
        [self spk_recenterZoomedImage];
    } else {
        [self spk_recenterZoomedImage];
    }
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self spk_recenterZoomedImage];
    [self notifyZoomStateIfChanged];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    // Back at minimum zoom: re-fit into the current between-bars region (the
    // insets may have changed via a chrome toggle while the image was zoomed).
    if (!self.isZoomed) {
        [self updateImageViewFrame];
    }
    [self notifyZoomStateIfChanged];
}

/// Notifies the delegate when the zoomed/unzoomed state flips so the host can
/// adapt its chrome (material backing behind the bars when zoomed in).
- (void)notifyZoomStateIfChanged {
    BOOL zoomed = self.isZoomed;
    if (zoomed == _lastReportedZoomState)
        return;
    _lastReportedZoomState = zoomed;
    if ([self.delegate respondsToSelector:@selector(mediaContent:didChangeZoomState:)]) {
        [self.delegate mediaContent:self didChangeZoomState:zoomed];
    }
}

#pragma mark - Gestures

- (BOOL)isZoomed {
    return _scrollView.zoomScale > kMinZoom + kZoomEpsilon;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (self.isZoomed) {
        [_scrollView setZoomScale:kMinZoom animated:YES];
    } else {
        CGPoint point = [recognizer locationInView:_imageView];
        CGFloat newZoom = kMaxZoom / 2.0;
        CGSize scrollSize = _scrollView.bounds.size;
        CGFloat w = scrollSize.width / newZoom;
        CGFloat h = scrollSize.height / newZoom;
        CGRect zoomRect = CGRectMake(point.x - w / 2.0, point.y - h / 2.0, w, h);
        [_scrollView zoomToRect:zoomRect animated:YES];
    }
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
    if ([self.delegate respondsToSelector:@selector(mediaContentDidTap:)]) {
        [self.delegate mediaContentDidTap:self];
    }
}

- (void)resetZoomIfNeeded {
    if (!self.isZoomed) {
        [_scrollView setZoomScale:kMinZoom animated:NO];
        [self updateImageViewFrame];
    }
    [self notifyZoomStateIfChanged];
}

#pragma mark - Cleanup

- (void)cleanup {
    [self.liveTextBridge cleanup];
    self.liveTextBridge = nil;
    SEL setAnimatedImage = NSSelectorFromString(@"setAnimatedImage:");
    if ([_imageView respondsToSelector:setAnimatedImage]) {
        ((void (*)(id, SEL, id))objc_msgSend)(_imageView, setAnimatedImage, nil);
    }
    _imageView.image = nil;
    // The item outlives this page, so clearing only the image view left the
    // full-size image alive on the item -- browsing a long run of photos kept
    // every one of them in memory. Drop it whenever it can be reloaded from disk
    // (an item made straight from a UIImage has no file to reload from, so it
    // keeps its copy); the shared image cache still serves the way back.
    if (self.mediaItem.fileURL || self.mediaItem.resolvedFileURL) {
        self.mediaItem.image = nil;
    }
}

@end
