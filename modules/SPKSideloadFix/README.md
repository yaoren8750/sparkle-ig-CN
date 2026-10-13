# SPKSideloadFix

Sparkle-local sideload app-group/keychain fix library.

This is derived from [`asdfzxcvbn/zxPluginsInject`](https://github.com/asdfzxcvbn/zxPluginsInject),
which is itself a rewrite of choco's original patch. It also vendors Facebook's
[`fishhook`](https://github.com/facebook/fishhook) for C symbol rebinding.

Compared with upstream `zxPluginsInject`, this variant changes app-group
container handling so `NSUserDefaults` uses the same redirected container policy
as `NSFileManager` in app-extension processes:

- retry app-group lookup until `LSBundleProxy` returns a usable group URL
- fall back to a Documents-backed group path when no app-group URL is available
- create redirected suite container directories before passing them to defaults
- leave main-app `NSUserDefaults` on its original container so Instagram's
  cold-launch UI dismissal flags can persist normally, while mirroring writes
  from `group.*` suites into the shared container used by app extensions

The additive group-defaults mirror keeps notification-extension account state
in sync with the main app. This matters for multi-account installs where the
extension can otherwise treat a signed-in recipient as logged out and redact or
misroute its notification.

It also normalizes Keychain access groups for sideloaded signatures. The four
intercepted `SecItem` operations resolve a usable group from a sentinel Keychain
item first and fall back to runtime entitlements. Existing access-group values
in add/query/delete dictionaries are replaced, and missing values are injected.
For `SecItemUpdate`, the query is normalized the same way while the separate
attributes-to-update dictionary is changed only when it already contains an
access group, avoiding an unintended item migration.

Keychain diagnostics report only the operation, result status, timing, and
whether a group was found/replaced/injected. Access-group strings, Keychain
values, cookies, and credentials are never logged.

Main-bundle identity is left untouched. Runtime `NSBundle` queries therefore
match the identifier in the installed app's `Info.plist`, including identifiers
rewritten by SideStore or another signer. Keeping those identities consistent
also avoids confusing UIKit/CoreUI when it registers the main app's asset
catalog. App-group and Keychain compatibility are handled by their dedicated
hooks instead of by changing the bundle identity seen by the entire process.

Do not add a global main-bundle identity spoof. In an app extension the
extension's own bundle is the main bundle, and `ExtensionFoundation` derives its
XPC listener name from that identity. Rewriting it prevents SpringBoard from
connecting to the notification extension, causing startup timeouts, unchanged
notification content, and duplicate or delayed banners.

## App hand-off routing

Every Instagram copy on a device registers the same URL schemes, and iOS does
not define which app receives a scheme that several claim. Instagram's share
extension finishes a feed, story or reel share by opening `instagram://` or
`instagram-secure-share://`, so with another copy installed the share can open
the wrong app, which cannot read the media: that sits in this install's group
container.

`build.sh` registers one extra scheme in the app that no other copy has
(`sparkle-ig`, with the bundle ID appended for `--bundle-id` builds).
`src/AppHandoff.xm` uses it in both directions:

- In an extension process, any URL using one of the app's own schemes is
  wrapped as `<scheme>://redirect?url=<encoded original>` on its way through
  `UIApplication` or `NSExtensionContext`.
- In the app process, `UIOpenURLContext` hands Instagram the original URL
  again, so its routing runs unchanged on warm and cold opens.
- A wrapped `https` link (what the Safari extension sends) is delivered as a
  universal link: a browsing activity in the scene connection options on a
  cold launch, `scene:continueUserActivity:` on a warm one.

A wrapper is only honoured when it carries one of the app's own schemes or an
Instagram web address, so the extra scheme opens nothing the stock schemes and
universal links could not already open. Without the registered scheme (a
jailbroken install, a `--no-ext` build) the whole file stays inert.

UIKit is reached through the runtime only. This library is loaded into
extensions that never link UIKit, and it must not make them load it.

Build with:

```sh
make -C modules/SPKSideloadFix DEBUG=0 FINALPACKAGE=1
```

`build.sh ipa --patch` builds this dylib and passes it to `ipapatch --dylib`
automatically.
