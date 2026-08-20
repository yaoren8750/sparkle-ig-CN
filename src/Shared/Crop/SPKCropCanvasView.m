#import "SPKCropCanvasView.h"

#import "../../AssetUtils.h"
#import "../../Utils.h"

#pragma mark - Aspect presets

// Order of the aspect chips (freeform mode). Index in this array == chip index.
// Original leads (it's the default selection); each ratio is paired with its
// landscape counterpart.
static const SPKCropAspect kSPKCropAspectOrder[] = {
    SPKCropAspectOriginal, SPKCropAspectFreeform, SPKCropAspectSquare,
    SPKCropAspectPortrait23, SPKCropAspectLandscape32,
    SPKCropAspectPortrait34, SPKCropAspectLandscape43,
    SPKCropAspectPortrait45, SPKCropAspectLandscape54,
    SPKCropAspectPortrait916, SPKCropAspectLandscape169};
static const NSInteger kSPKCropAspectCount = sizeof(kSPKCropAspectOrder) / sizeof(kSPKCropAspectOrder[0]);

NSInteger SPKCropAspectPresetCount(void) {
    return kSPKCropAspectCount;
}

SPKCropAspect SPKCropAspectPresetAtIndex(NSInteger index) {
    if (index < 0 || index >= kSPKCropAspectCount)
        return SPKCropAspectOriginal;
    return kSPKCropAspectOrder[index];
}

NSString *SPKCropAspectTitle(SPKCropAspect aspect) {
    switch (aspect) {
    case SPKCropAspectOriginal:
        return @"原始";
    case SPKCropAspectFreeform:
        return @"自由";
    case SPKCropAspectSquare:
        return @"1:1";
    case SPKCropAspectPortrait23:
        return @"2:3";
    case SPKCropAspectLandscape32:
        return @"3:2";
    case SPKCropAspectPortrait34:
        return @"3:4";
    case SPKCropAspectLandscape43:
        return @"4:3";
    case SPKCropAspectPortrait45:
        return @"4:5";
    case SPKCropAspectLandscape54:
        return @"5:4";
    case SPKCropAspectPortrait916:
        return @"9:16";
    case SPKCropAspectLandscape169:
        return @"16:9";
    }
    return @"";
}

CGFloat SPKCropAspectRatio(SPKCropAspect aspect) {
    switch (aspect) {
    case SPKCropAspectSquare:
        return 1.0;
    case SPKCropAspectPortrait23:
        return 2.0 / 3.0;
    case SPKCropAspectLandscape32:
        return 3.0 / 2.0;
    case SPKCropAspectPortrait34:
        return 3.0 / 4.0;
    case SPKCropAspectLandscape43:
        return 4.0 / 3.0;
    case SPKCropAspectPortrait45:
        return 4.0 / 5.0;
    case SPKCropAspectLandscape54:
        return 5.0 / 4.0;
    case SPKCropAspectPortrait916:
        return 9.0 / 16.0;
    case SPKCropAspectLandscape169:
        return 16.0 / 9.0;
    case SPKCropAspectFreeform:
    case SPKCropAspectOriginal:
        return 0.0;
    }
    return 0.0;
}

#pragma mark - Tool row

// Mirrors a glyph horizontally and/or vertically, preserving scale and rendering
// mode. The rotate-left/right tool icons share one base asset
// (arrow_bottom_right_bend), flipped to point the right way.
static UIImage *SPKCropMirroredGlyph(UIImage *image, BOOL horizontal, BOOL vertical) {
    if (!image || (!horizontal && !vertical))
        return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = image.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
    UIImage *output = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        CGContextTranslateCTM(ctx, horizontal ? image.size.width : 0.0, vertical ? image.size.height : 0.0);
        CGContextScaleCTM(ctx, horizontal ? -1.0 : 1.0, vertical ? -1.0 : 1.0);
        [image drawInRect:CGRectMake(0.0, 0.0, image.size.width, image.size.height)];
    }];
    return [output imageWithRenderingMode:image.renderingMode];
}

static UIButton *SPKCropToolButton(UIImage *image, NSString *accessibility, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (image) {
        [button setImage:image forState:UIControlStateNormal];
    } else {
        [button setTitle:accessibility forState:UIControlStateNormal];
    }
    button.tintColor = [SPKUtils SPKColor_InstagramPrimaryText] ?: [UIColor whiteColor];
    button.accessibilityLabel = accessibility;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    // A comfortable 44pt tap target around the 24pt glyph.
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [button.heightAnchor constraintEqualToConstant:44.0],
    ]];
    return button;
}

UIView *SPKCropMakeToolRow(id target, SEL rotateLeft, SEL flip, SEL rotateRight) {
    // rotate_left / rotate_right resolve to one shared base arrow asset, flipped
    // into the two directions. The modern bend arrow needs a vertical flip to
    // point upward; the IG 410 fallback (arrow_right_bend_filled) already points
    // the right way, so it skips the vertical flip. "Left" is always the
    // horizontal mirror of "right".
    UIImage *rotBase = [SPKAssetUtils instagramIconNamed:@"rotate_right"
                                               pointSize:24.0
                                           renderingMode:UIImageRenderingModeAlwaysTemplate];
    NSString *resolvedRotate = [SPKAssetUtils resolvedInstagramIconNameForName:@"rotate_right"];
    BOOL verticalFlip = ![resolvedRotate isEqualToString:@"ig_icon_arrow_right_bend_filled_24"];
    UIImage *rotateRightIcon = SPKCropMirroredGlyph(rotBase, NO, verticalFlip);
    UIImage *rotateLeftIcon = SPKCropMirroredGlyph(rotBase, YES, verticalFlip);
    UIImage *mirror = [SPKAssetUtils instagramIconNamed:@"mirror"
                                              pointSize:24.0
                                          renderingMode:UIImageRenderingModeAlwaysTemplate];
    NSArray<UIButton *> *buttons = @[
        SPKCropToolButton(rotateLeftIcon, @"向左旋转", target, rotateLeft),
        SPKCropToolButton(mirror, @"翻转", target, flip),
        SPKCropToolButton(rotateRightIcon, @"向右旋转", target, rotateRight),
    ];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionEqualCentering;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

#pragma mark - Canvas geometry

static const CGFloat kSPKCropInsetH = 24.0;
static const CGFloat kSPKCropInsetV = 24.0;
static const CGFloat kSPKCropHandleTouch = 44.0;
static const CGFloat kSPKCropMinSide = 64.0;

#pragma mark - Canvas

@interface SPKCropCanvasView () <UIScrollViewDelegate>
@end

@implementation SPKCropCanvasView {
    UIScrollView *_scrollView;
    UIView *_contentView;
    UIView *_overlayView;
    CAShapeLayer *_dimLayer;
    CAShapeLayer *_borderLayer;
    NSArray<UIView *> *_handles;

    CGSize _contentSize;
    CGRect _cropRect; // in canvas coordinates
    BOOL _configured;
    CGRect _pendingRestore; // a restore requested before the first layout pass
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _aspectMode = SPKCropAspectModeFreeform;
        _lockedAspectRatio = 1.0;
        _aspect = SPKCropAspectOriginal;
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.delegate = self;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.bouncesZoom = YES;
        _scrollView.backgroundColor = [UIColor blackColor];
        [self addSubview:_scrollView];

        _overlayView = [[UIView alloc] init];
        _overlayView.userInteractionEnabled = NO;
        [self addSubview:_overlayView];

        _dimLayer = [CAShapeLayer layer];
        _dimLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:0.55].CGColor;
        _dimLayer.fillRule = kCAFillRuleEvenOdd;
        [_overlayView.layer addSublayer:_dimLayer];

        _borderLayer = [CAShapeLayer layer];
        _borderLayer.fillColor = UIColor.clearColor.CGColor;
        _borderLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
        _borderLayer.lineWidth = 1.0;
        [_overlayView.layer addSublayer:_borderLayer];
    }
    return self;
}

#pragma mark - Content

- (void)setContentView:(UIView *)contentView contentSize:(CGSize)contentSize {
    if (!contentView)
        return;
    [_contentView removeFromSuperview];
    _contentView = contentView;
    _contentSize = contentSize;
    [_scrollView addSubview:_contentView];
    _configured = NO;
    [self setNeedsLayout];
}

- (void)setContentSize:(CGSize)contentSize {
    _contentSize = contentSize;
    if (!_configured)
        return;
    [self resetCrop];
}

- (void)setAspectMode:(SPKCropAspectMode)aspectMode {
    _aspectMode = aspectMode;
    if (aspectMode == SPKCropAspectModeFreeform) {
        [self ensureHandles];
    }
}

- (void)setAspect:(SPKCropAspect)aspect {
    _aspect = aspect;
    if (_configured)
        [self resetCrop];
}

#pragma mark - Handles

- (void)ensureHandles {
    if (_handles.count == 4)
        return;
    NSMutableArray<UIView *> *handles = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger i = 0; i < 4; i++) {
        UIView *handle = [[UIView alloc] init];
        handle.backgroundColor = UIColor.clearColor;
        handle.tag = i; // 0=TL 1=TR 2=BL 3=BR
        handle.hidden = YES;
        CALayer *knob = [CALayer layer];
        knob.backgroundColor = UIColor.whiteColor.CGColor;
        knob.cornerRadius = 5.0;
        knob.frame = CGRectMake((kSPKCropHandleTouch - 10.0) / 2.0,
                                (kSPKCropHandleTouch - 10.0) / 2.0, 10.0, 10.0);
        [handle.layer addSublayer:knob];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [handle addGestureRecognizer:pan];
        [self addSubview:handle];
        [handles addObject:handle];
    }
    _handles = handles;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (_contentSize.width <= 0.0 || _contentSize.height <= 0.0 ||
        bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return;
    }
    _scrollView.frame = bounds;
    _overlayView.frame = bounds;

    if (!_configured) {
        _configured = YES;
        if (!CGRectIsEmpty(_pendingRestore)) {
            CGRect restore = _pendingRestore;
            _pendingRestore = CGRectZero;
            [self restoreNormalizedCropRect:restore];
            return;
        }
        _cropRect = [self maxCropRectForCurrentAspect];
        [self configureScrollForCropRect];
    }
    [self updateOverlay];
    [self layoutHandles];
}

- (void)restoreNormalizedCropRect:(CGRect)normalizedRect {
    CGRect r = CGRectIntersection(normalizedRect, CGRectMake(0.0, 0.0, 1.0, 1.0));
    if (CGRectIsNull(r) || CGRectIsEmpty(r))
        return;
    if (!_configured || _contentSize.width <= 0.0 || _contentSize.height <= 0.0) {
        _pendingRestore = r;
        return;
    }

    // Re-fit a crop rect with the restored selection's shape, then solve the zoom
    // and offset that put exactly that part of the content inside it.
    CGRect area = self.bounds;
    CGFloat selectionW = r.size.width * _contentSize.width;
    CGFloat selectionH = r.size.height * _contentSize.height;
    CGFloat ratio = selectionW / MAX(selectionH, 1.0);
    CGFloat maxW = area.size.width - kSPKCropInsetH * 2.0;
    CGFloat maxH = area.size.height - kSPKCropInsetV * 2.0;
    CGFloat w = maxW;
    CGFloat h = w / ratio;
    if (h > maxH) {
        h = maxH;
        w = h * ratio;
    }
    _cropRect = CGRectMake(area.size.width / 2.0 - w / 2.0,
                           area.size.height / 2.0 - h / 2.0, w, h);

    CGFloat zoom = _cropRect.size.width / MAX(selectionW, 1.0);
    CGFloat minZoom = MAX(_cropRect.size.width / _contentSize.width,
                          _cropRect.size.height / _contentSize.height);
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = 1.0;
    _scrollView.zoomScale = 1.0;
    _contentView.transform = CGAffineTransformIdentity;
    _contentView.frame = (CGRect){CGPointZero, _contentSize};
    _scrollView.contentSize = _contentSize;
    _scrollView.minimumZoomScale = MIN(minZoom, zoom);
    _scrollView.maximumZoomScale = MAX(MAX(minZoom * 4.0, 1.0), zoom);
    _scrollView.zoomScale = zoom;
    [self syncScrollInsetForCropRect];
    _scrollView.contentOffset = CGPointMake(r.origin.x * _contentSize.width * zoom - CGRectGetMinX(_cropRect),
                                            r.origin.y * _contentSize.height * zoom - CGRectGetMinY(_cropRect));
    [self updateOverlay];
    [self layoutHandles];
}

- (void)resetCrop {
    _cropRect = [self maxCropRectForCurrentAspect];
    [self configureScrollForCropRect];
    [self updateOverlay];
    [self layoutHandles];
}

// The effective ratio of the current selection: the locked ratio, the preset's,
// or the content's own (Original / Freeform).
- (CGFloat)effectiveAspectRatio {
    if (_aspectMode == SPKCropAspectModeLocked)
        return _lockedAspectRatio > 0.0 ? _lockedAspectRatio : 1.0;
    CGFloat ratio = SPKCropAspectRatio(_aspect);
    if (ratio > 0.0)
        return ratio;
    return _contentSize.width / MAX(_contentSize.height, 1.0);
}

// The largest centred crop rect for the current aspect, fitted inside the canvas
// with padding. Also the bound a ratio-locked grabber can grow back to.
- (CGRect)maxCropRectForCurrentAspect {
    CGRect area = self.bounds;
    CGFloat maxW = area.size.width - kSPKCropInsetH * 2.0;
    CGFloat maxH = area.size.height - kSPKCropInsetV * 2.0;
    if (maxW <= 0 || maxH <= 0)
        return area;

    CGFloat ratio = [self effectiveAspectRatio];
    CGFloat w = maxW;
    CGFloat h = w / ratio;
    if (h > maxH) {
        h = maxH;
        w = h * ratio;
    }
    return CGRectMake(area.size.width / 2.0 - w / 2.0,
                      area.size.height / 2.0 - h / 2.0, w, h);
}

// Sets zoom + inset so the content can pan to fill the current crop rect.
- (void)configureScrollForCropRect {
    CGRect area = self.bounds;
    if (_contentSize.width <= 0.0 || _contentSize.height <= 0.0)
        return;
    // Reset to an unzoomed baseline first. Reconfiguring (aspect change / rotate /
    // flip) while the scroll view still holds the previous zoomScale makes each
    // call re-scale the already-scaled content view, zooming in without bound.
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = 1.0;
    _scrollView.zoomScale = 1.0;
    _contentView.transform = CGAffineTransformIdentity;
    _contentView.frame = (CGRect){CGPointZero, _contentSize};
    _scrollView.contentSize = _contentSize;
    CGFloat minZoom = MAX(_cropRect.size.width / _contentSize.width,
                          _cropRect.size.height / _contentSize.height);
    _scrollView.minimumZoomScale = minZoom;
    _scrollView.maximumZoomScale = MAX(minZoom * 4.0, 1.0);
    _scrollView.zoomScale = minZoom;
    _scrollView.contentInset = UIEdgeInsetsMake(CGRectGetMinY(_cropRect),
                                                CGRectGetMinX(_cropRect),
                                                area.size.height - CGRectGetMaxY(_cropRect),
                                                area.size.width - CGRectGetMaxX(_cropRect));
    CGFloat offsetX = (_contentSize.width * minZoom - CGRectGetWidth(_cropRect)) / 2.0 - CGRectGetMinX(_cropRect);
    CGFloat offsetY = (_contentSize.height * minZoom - CGRectGetHeight(_cropRect)) / 2.0 - CGRectGetMinY(_cropRect);
    _scrollView.contentOffset = CGPointMake(MAX(-_scrollView.contentInset.left, offsetX),
                                            MAX(-_scrollView.contentInset.top, offsetY));
}

// Keeps scroll insets in sync when the crop rect is resized by a grabber, without
// changing zoom, so the content can still pan under the new rect.
- (void)syncScrollInsetForCropRect {
    CGRect area = self.bounds;
    _scrollView.contentInset = UIEdgeInsetsMake(CGRectGetMinY(_cropRect),
                                                CGRectGetMinX(_cropRect),
                                                area.size.height - CGRectGetMaxY(_cropRect),
                                                area.size.width - CGRectGetMaxX(_cropRect));
}

- (void)updateOverlay {
    UIBezierPath *dimPath = [UIBezierPath bezierPathWithRect:_overlayView.bounds];
    UIBezierPath *cropPath = [UIBezierPath bezierPathWithRect:_cropRect];
    [dimPath appendPath:cropPath];
    dimPath.usesEvenOddFillRule = YES;
    _dimLayer.frame = _overlayView.bounds;
    _dimLayer.path = dimPath.CGPath;
    _borderLayer.frame = _overlayView.bounds;
    _borderLayer.path = cropPath.CGPath;
}

- (void)layoutHandles {
    if (_handles.count != 4)
        return;
    CGRect r = _cropRect; // already in canvas coordinates
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r)),
        CGPointMake(CGRectGetMaxX(r), CGRectGetMinY(r)),
        CGPointMake(CGRectGetMinX(r), CGRectGetMaxY(r)),
        CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)),
    };
    for (NSInteger i = 0; i < 4; i++) {
        UIView *handle = _handles[i];
        handle.hidden = NO; // grabbers show for every aspect (ratio-locked resize)
        handle.frame = CGRectMake(corners[i].x - kSPKCropHandleTouch / 2.0,
                                  corners[i].y - kSPKCropHandleTouch / 2.0,
                                  kSPKCropHandleTouch, kSPKCropHandleTouch);
    }
}

#pragma mark - Grabber drag

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint p = [pan locationInView:self];
    NSInteger corner = pan.view.tag; // 0=TL 1=TR 2=BL 3=BR
    if (_aspectMode == SPKCropAspectModeFreeform && _aspect == SPKCropAspectFreeform) {
        [self freeformResizeToPoint:p corner:corner];
    } else {
        [self ratioLockedResizeToPoint:p corner:corner];
    }
    [self syncScrollInsetForCropRect];
    [self updateOverlay];
    [self layoutHandles];
}

// Freeform: each corner moves independently, clamped to the content's on-screen
// frame so the selection can't drag into empty/letterboxed area.
- (void)freeformResizeToPoint:(CGPoint)p corner:(NSInteger)corner {
    CGRect contentRect = [_contentView convertRect:_contentView.bounds toView:self];
    CGRect area = CGRectIntersection(contentRect, self.bounds);
    if (CGRectIsNull(area) || CGRectIsEmpty(area))
        area = self.bounds;
    p.x = MIN(MAX(p.x, CGRectGetMinX(area)), CGRectGetMaxX(area));
    p.y = MIN(MAX(p.y, CGRectGetMinY(area)), CGRectGetMaxY(area));

    CGFloat left = CGRectGetMinX(_cropRect), right = CGRectGetMaxX(_cropRect);
    CGFloat top = CGRectGetMinY(_cropRect), bottom = CGRectGetMaxY(_cropRect);
    BOOL isLeft = (corner == 0 || corner == 2);
    BOOL isTop = (corner == 0 || corner == 1);
    if (isLeft)
        left = MIN(p.x, right - kSPKCropMinSide);
    else
        right = MAX(p.x, left + kSPKCropMinSide);
    if (isTop)
        top = MIN(p.y, bottom - kSPKCropMinSide);
    else
        bottom = MAX(p.y, top + kSPKCropMinSide);
    _cropRect = CGRectMake(left, top, right - left, bottom - top);
}

// Fixed ratios (and Original): the grabber shrinks/grows the crop while keeping
// its aspect ratio, anchored at the opposite corner and bounded by the aspect's
// max-fit rect (so the content always covers it — only shrink/regrow, no reshape).
- (void)ratioLockedResizeToPoint:(CGPoint)p corner:(NSInteger)corner {
    CGRect bounds = [self maxCropRectForCurrentAspect];
    CGFloat ratio = [self effectiveAspectRatio];
    if (ratio <= 0.0)
        ratio = _cropRect.size.width / MAX(_cropRect.size.height, 1.0);

    p.x = MIN(MAX(p.x, CGRectGetMinX(bounds)), CGRectGetMaxX(bounds));
    p.y = MIN(MAX(p.y, CGRectGetMinY(bounds)), CGRectGetMaxY(bounds));

    BOOL isLeft = (corner == 0 || corner == 2);
    BOOL isTop = (corner == 0 || corner == 1);
    CGFloat anchorX = isLeft ? CGRectGetMaxX(_cropRect) : CGRectGetMinX(_cropRect);
    CGFloat anchorY = isTop ? CGRectGetMaxY(_cropRect) : CGRectGetMinY(_cropRect);

    // Largest ratio-correct box that fits between the anchor and the drag point.
    CGFloat w = fabs(p.x - anchorX);
    CGFloat h = w / ratio;
    if (h > fabs(p.y - anchorY)) {
        h = fabs(p.y - anchorY);
        w = h * ratio;
    }
    // Enforce a minimum, keeping the ratio.
    if (h < kSPKCropMinSide) {
        h = kSPKCropMinSide;
        w = h * ratio;
    }
    if (w < kSPKCropMinSide) {
        w = kSPKCropMinSide;
        h = w / ratio;
    }

    CGFloat newLeft = isLeft ? (anchorX - w) : anchorX;
    CGFloat newTop = isTop ? (anchorY - h) : anchorY;
    _cropRect = CGRectMake(newLeft, newTop, w, h);
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(__unused UIScrollView *)scrollView {
    return _contentView;
}

#pragma mark - Output

- (CGRect)normalizedCropRect {
    if (!_configured || _contentSize.width <= 0.0 || _contentSize.height <= 0.0)
        return CGRectZero;
    CGFloat zoom = _scrollView.zoomScale;
    if (zoom <= 0.0)
        return CGRectZero;
    CGPoint offset = _scrollView.contentOffset;
    // The crop rect, expressed in unzoomed content points.
    CGRect visible = CGRectMake((CGRectGetMinX(_cropRect) + offset.x) / zoom,
                                (CGRectGetMinY(_cropRect) + offset.y) / zoom,
                                CGRectGetWidth(_cropRect) / zoom,
                                CGRectGetHeight(_cropRect) / zoom);
    CGRect normalized = CGRectMake(visible.origin.x / _contentSize.width,
                                   visible.origin.y / _contentSize.height,
                                   visible.size.width / _contentSize.width,
                                   visible.size.height / _contentSize.height);
    return CGRectIntersection(normalized, CGRectMake(0.0, 0.0, 1.0, 1.0));
}

@end
