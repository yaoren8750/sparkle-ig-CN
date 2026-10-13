#import "Header.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Keeps hand-offs into the app pointed at this install.
//
// Every Instagram copy on a device registers the same URL schemes, and iOS does
// not say which one receives a scheme that several apps claim. The share
// extension finishes a feed, story or reel share by opening instagram:// or
// instagram-secure-share://, so with a second copy installed the share can land
// in the wrong app, which cannot even read the media: that sits in this
// install's group container.
//
// The build registers one extra scheme that only this install answers. In an
// extension process, URLs meant for the containing app are wrapped in it:
//
//     <scheme>://redirect?url=<percent-encoded original URL>
//
// In the app process the wrapper is taken off again before Instagram reads the
// URL, so its own routing runs unchanged. The Safari extension uses the same
// wrapper around an https link, which is handed over as a universal link.
//
// UIKit is only named through the runtime here: this library is also loaded into
// extensions that never link it.

static NSString *const kSchemePrefix = @"sparkle-ig";
static NSString *const kRedirectHost = @"redirect";
static NSString *const kRedirectQueryName = @"url";

static NSDictionary *appInfoDictionary(void) {
	static NSDictionary *info = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSBundle *bundle = [NSBundle mainBundle];
		if (!isAppExtensionProcess()) {
			info = bundle.infoDictionary;
			return;
		}
		// <App>.app/PlugIns/<Name>.appex
		NSURL *appURL = [[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
		info = [NSDictionary dictionaryWithContentsOfURL:[appURL URLByAppendingPathComponent:@"Info.plist"]];
	});
	return info;
}

// Lowercased schemes the app registers.
static NSSet<NSString *> *appURLSchemes(void) {
	static NSSet<NSString *> *schemes = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSMutableSet<NSString *> *found = [NSMutableSet set];
		id types = appInfoDictionary()[@"CFBundleURLTypes"];
		if ([types isKindOfClass:[NSArray class]]) {
			for (id type in (NSArray *)types) {
				if (![type isKindOfClass:[NSDictionary class]]) continue;
				id entries = ((NSDictionary *)type)[@"CFBundleURLSchemes"];
				if (![entries isKindOfClass:[NSArray class]]) continue;
				for (id entry in (NSArray *)entries) {
					if ([entry isKindOfClass:[NSString class]]) [found addObject:[(NSString *)entry lowercaseString]];
				}
			}
		}
		schemes = [found copy];
	});
	return schemes;
}

// The scheme only this install answers, or nil when the build registered none.
static NSString *privateScheme(void) {
	static NSString *scheme = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		for (NSString *candidate in appURLSchemes()) {
			if (![candidate hasPrefix:kSchemePrefix]) continue;
			// Shortest wins so the choice is stable if several are registered.
			if (!scheme || candidate.length < scheme.length) scheme = candidate;
		}
	});
	return scheme;
}

static BOOL isWebURL(NSURL *url) {
	NSString *scheme = url.scheme.lowercaseString;
	return [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"];
}

static BOOL isInstagramWebURL(NSURL *url) {
	if (!isWebURL(url)) return NO;
	NSString *host = url.host.lowercaseString;
	if (!host.length) return NO;
	for (NSString *domain in @[@"instagram.com", @"ig.me", @"instagr.am"]) {
		if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) return YES;
	}
	return NO;
}

// YES for a URL the app itself would have received through a shared scheme.
static BOOL isAppSchemeURL(NSURL *url) {
	NSString *scheme = url.scheme.lowercaseString;
	return scheme.length && ![scheme hasPrefix:kSchemePrefix] && [appURLSchemes() containsObject:scheme];
}

static NSURL *wrappedURL(NSURL *url) {
	if (![url isKindOfClass:[NSURL class]] || !isAppSchemeURL(url)) return url;
	NSString *scheme = privateScheme();
	if (!scheme) return url;

	NSString *encoded = [url.absoluteString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
	NSURL *wrapped = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@?%@=%@", scheme, kRedirectHost, kRedirectQueryName, encoded]];
	if (!wrapped) return url;

	SPKSideloadLog(@"Routing %@://%@ hand-off through the private scheme", url.scheme, url.host);
	return wrapped;
}

// The URL inside a wrapper, or nil when `url` is not one or carries something
// this app would never have been handed directly.
static NSURL *unwrappedURL(NSURL *url) {
	if (![url isKindOfClass:[NSURL class]]) return nil;
	NSString *scheme = privateScheme();
	if (!scheme || ![url.scheme.lowercaseString isEqualToString:scheme]) return nil;
	if (![url.host.lowercaseString isEqualToString:kRedirectHost]) return nil;

	NSString *value = nil;
	for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
		if ([item.name isEqualToString:kRedirectQueryName]) {
			value = item.value;
			break;
		}
	}
	if (!value.length) return nil;

	NSURL *inner = [NSURL URLWithString:value];
	if (!inner || !(isInstagramWebURL(inner) || isAppSchemeURL(inner))) return nil;
	return inner;
}

// The web link inside a wrapper, which has to arrive as a universal link.
static NSURL *wrappedWebURL(NSURL *url) {
	NSURL *inner = unwrappedURL(url);
	return isWebURL(inner) ? inner : nil;
}

static NSUserActivity *browsingActivity(NSURL *webURL) {
	NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
	activity.webpageURL = webURL;
	return activity;
}

#pragma mark - Extension process

%group SPKExtensionHandoff

%hook UIApplication

- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
	%orig(wrappedURL(url), options, completion);
}

- (BOOL)openURL:(NSURL *)url {
	return %orig(wrappedURL(url));
}

%end

%hook NSExtensionContext

- (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL))completion {
	%orig(wrappedURL(url), completion);
}

%end

%end

#pragma mark - App process

// Set while the connection options' own hooks need the contexts as delivered.
static BOOL readingDeliveredContexts = NO;
static const void *kWebActivitiesKey = &kWebActivitiesKey;

%group SPKAppHandoff

// Instagram reads its launch and open URLs from here. A wrapped app URL comes
// back as the original; a wrapped web link stays wrapped so the hooks below can
// find it and deliver it as a universal link.
%hook UIOpenURLContext

- (NSURL *)URL {
	NSURL *url = %orig;
	NSURL *inner = unwrappedURL(url);
	return (inner && !isWebURL(inner)) ? inner : url;
}

%end

// Cold launch: a wrapped web link leaves the URL contexts and shows up as a
// browsing activity, exactly what a universal link launch looks like.
%hook UISceneConnectionOptions

- (NSSet *)URLContexts {
	NSSet *contexts = %orig;
	if (readingDeliveredContexts || !contexts.count) return contexts;

	NSMutableSet *kept = nil;
	for (UIOpenURLContext *context in contexts) {
		if (!wrappedWebURL(context.URL)) continue;
		if (!kept) kept = [contexts mutableCopy];
		[kept removeObject:context];
	}
	return kept ? [kept copy] : contexts;
}

- (NSSet *)userActivities {
	NSSet *activities = %orig;

	NSSet *added = objc_getAssociatedObject(self, kWebActivitiesKey);
	if (!added) {
		readingDeliveredContexts = YES;
		NSSet *contexts = [self URLContexts];
		readingDeliveredContexts = NO;

		NSMutableSet *built = [NSMutableSet set];
		for (UIOpenURLContext *context in contexts) {
			NSURL *webURL = wrappedWebURL(context.URL);
			if (webURL) [built addObject:browsingActivity(webURL)];
		}
		// Cached so every read hands Instagram the same activity objects.
		added = [built copy];
		objc_setAssociatedObject(self, kWebActivitiesKey, added, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	if (!added.count) return activities;
	return activities ? [activities setByAddingObjectsFromSet:added] : added;
}

%end

%end

static void continueWebURL(id sceneDelegate, id scene, NSURL *webURL) {
	NSUserActivity *activity = browsingActivity(webURL);
	if ([sceneDelegate respondsToSelector:@selector(scene:continueUserActivity:)]) {
		[sceneDelegate scene:scene continueUserActivity:activity];
		return;
	}

	Class applicationClass = objc_getClass("UIApplication");
	UIApplication *application = [applicationClass sharedApplication];
	id<UIApplicationDelegate> appDelegate = application.delegate;
	if ([appDelegate respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
		[appDelegate application:application
		    continueUserActivity:activity
		      restorationHandler:^(NSArray *restorableObjects) {
		      }];
	}
}

// Warm opens reach the scene delegate as URL contexts. Its class differs between
// Instagram versions, so the delegate each scene really uses gets patched when
// the scene connects.
static void hookSceneDelegateIfNeeded(id sceneDelegate) {
	if (!sceneDelegate) return;

	static NSMutableSet<Class> *hookedClasses = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		hookedClasses = [NSMutableSet set];
	});

	Class cls = [sceneDelegate class];
	if ([hookedClasses containsObject:cls]) return;
	[hookedClasses addObject:cls];

	SEL selector = @selector(scene:openURLContexts:);
	Method method = class_getInstanceMethod(cls, selector);
	if (!method) return;

	typedef void (*OpenContextsIMP)(id, SEL, id, NSSet *);
	__block OpenContextsIMP original = (OpenContextsIMP)method_getImplementation(method);

	IMP replacement = imp_implementationWithBlock(^(id delegate, id scene, NSSet *contexts) {
		NSMutableSet *remaining = [NSMutableSet set];
		for (UIOpenURLContext *context in contexts) {
			NSURL *webURL = wrappedWebURL(context.URL);
			if (webURL) {
				continueWebURL(delegate, scene, webURL);
			} else {
				[remaining addObject:context];
			}
		}
		if (remaining.count || !contexts.count) original(delegate, selector, scene, remaining);
	});

	// Added rather than replaced when the method is inherited, so the superclass
	// and its other subclasses keep their own implementation.
	if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
		original = (OpenContextsIMP)method_setImplementation(method, replacement);
	}
}

%ctor {
	if (!privateScheme()) return;

	if (isAppExtensionProcess()) {
		// Extensions without UI never load UIKit and have nothing to open.
		if (objc_getClass("UIApplication")) {
			%init(SPKExtensionHandoff);
		}
		return;
	}

	%init(SPKAppHandoff);

	void (^hookDelegate)(NSNotification *) = ^(NSNotification *notification) {
		id scene = notification.object;
		if ([scene respondsToSelector:@selector(delegate)]) {
			hookSceneDelegateIfNeeded([(UIScene *)scene delegate]);
		}
	};
	// Names spelled out to avoid linking UIKit for two constants. Activation is
	// the backstop for a delegate assigned after the connect notification.
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	for (NSString *name in @[@"UISceneWillConnectNotification", @"UISceneDidActivateNotification"]) {
		[center addObserverForName:name object:nil queue:nil usingBlock:hookDelegate];
	}
}
