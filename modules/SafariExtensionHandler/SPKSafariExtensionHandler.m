#import <Foundation/Foundation.h>

// Native half of the Safari web extension. Everything the extension does
// happens in its scripts; iOS only loads a web extension whose bundle carries
// an executable and the principal class named in its Info.plist, so this one
// answers any request by completing it.
//
// Linked with NSExtensionMain as the entry point: there is no main().

@interface SPKSafariExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation SPKSafariExtensionHandler

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
	[context completeRequestReturningItems:@[] completionHandler:nil];
}

@end
