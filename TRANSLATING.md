# Translating Sparkle

Sparkle ships its own localization bundle because it runs inside Instagram and cannot use Instagram's main localization table.

**Sparkle ships English only.** Every other language lives in `translations/` as a community catalog, and reaches users in one of two ways:

- as a **language pack** the user installs from Settings, at any time, without waiting for a release;
- by being **promoted into the shipped bundle** once a native speaker has reviewed it, after which it needs no pack at all.

The catalogs in `translations/` were produced in bulk by machine translation, and none has been reviewed by a native speaker. That is exactly why they no longer ship: a translation nobody who speaks the language has read looks official while quietly describing the wrong setting. They are kept because they are a useful starting point. Correcting one is far less work than translating from scratch, and it is the fastest route to getting a language shipped.

Known failure modes already found and fixed once include help text generated from the catalog key instead of the English value, one generic sentence reused across dozens of unrelated settings, and Instagram product terms translated in some strings and left in English in others. Similar problems very likely remain in every language nobody has read yet.

Two consequences for contributors:

- A correction does not need justification. If it reads wrong to you as a speaker of that language, it is wrong.
- Compare against the English value, not against neighbouring translated strings. The neighbours are not a reliable style reference, and copying them has already propagated at least one error.

## Report a single correction

No code, no checkout. Use **Report a Translation Issue** at the bottom of the language sheet (the Translate button in Sparkle Settings), or [open a translation issue](https://github.com/efibalogh/sparkle-ig/issues/new?template=3-translation.yaml). The form asks for the language, where the text appears, what it says now, and what it should say, and the language is prefilled when Sparkle is already running in it.

The **Contribute a Translation** row beside it opens this guide.

## Correct or finish a language

1. Open `translations/<locale>.lproj/Localizable.strings` and translate the right-hand side of each line. Leave the keys alone.
2. Check your work: `tools/lint-i18n.py --locale <locale>`
3. Open a pull request. Append `?template=translation.md` to the pull request URL to swap the general template for the translation checklist.

That is the whole loop. You do not need Theos, Xcode, or a build.

To start a language that has no catalog yet, seed one from English first:

```sh
tools/new-locale.py nl
```

The seed starts as English, so a half-finished catalog is still usable and the linter's "still in English" warnings are your to-do list.

## Test it on your own device before submitting

Any translation, finished or not, can be installed as a language pack:

1. Zip the `<locale>.lproj` folder. In Files, long-press the folder and choose Compress.
2. In Sparkle Settings, tap **Translate** → **Import Language Pack** and pick the zip. Several can be picked at once.
3. The language appears in the list above. Tap it to switch, then restart when prompted.

A zip is the only accepted shape, and that is an iOS constraint rather than a preference: the file picker will navigate into a `.lproj` folder but never let you select it, and a file picked on its own is copied out of its folder before the app sees it, so a bare `Localizable.strings` arrives with nothing to say what language it is. The archive keeps the folder name, and the folder name is the language.

An imported pack overrides a shipped catalog of the same language, so this also works for previewing corrections to a language that already ships. Re-import to update it; swipe a language left to remove its pack. The share button at the top of the language sheet (**Export Strings**) shares a zip of exactly that shape for the language you pick. English (`en.lproj`) is what a new translation starts from, and it is the easiest way to get the strings onto a phone or over to someone else. Any other language listed, shipped or installed, exports the catalog Sparkle is currently using for it, which is the file to start from when correcting a language that already ships.

## Rules

- Every catalog is sorted by key and carries every key English has. `tools/sync-catalog-keys.py` fills any key a catalog is missing and refreshes entries whose English wording changed while they were still untranslated, comparing against `translations/.english-baseline.strings`. A value you have actually translated is never touched. That is why the linter reports "still in English" rather than "missing".
- A value identical to English only counts as untranslated when it is a phrase. Single tokens (`Instagram`, `VideoToolbox`, `GIF`, `1:1`) and format-only strings (`%@ - %@`) read the same everywhere, so leaving them alone is correct and does not count against a catalog's coverage.
- A new entry belongs in its alphabetical position, not at the end.
- Translate values only. Never rename catalog keys, and never touch preference keys, selectors, identifiers, asset names, URLs, or other runtime signals.
- Preserve placeholders exactly, including type and positional markers (`%@`, `%ld`, `%lu`, `%1$@`). Keep escape sequences and intentional line breaks.
- Use natural grammar and capitalization for the target language rather than copying English title case.
- Provide the plural categories the target language actually requires in `Localizable.stringsdict`. Never build a plural by appending a suffix.
- A footer that numbers its lines maps one line per row in the section above it. Keep the count.

## Validate

```sh
tools/lint-i18n.py --locale <locale>      # one catalog
tools/lint-i18n.py                        # everything, plus a coverage summary
tools/lint-i18n.py --table                # coverage as a Markdown table
```

The linter fails on anything that would break at runtime or leave a pack incomplete: malformed entries, missing keys, keys English does not have, placeholder mismatches, unsorted keys, invalid plural definitions. How much is actually translated only warns, so an unfinished catalog still passes. English parity, unused keys, unsafe localization calls, and raw user-interface strings in source are checked at the same time and always fail.

## Getting a language shipped

A catalog is promoted out of `translations/` and into `resources/Sparkle.bundle/` when a native speaker has read it end to end. Nothing else changes: the language list, the picker, and the linter all discover the split from the directories, so promotion is a directory move plus a line in `README.md` and `FEATURES.md`.

Translators are credited in `README.md` and the in-app About page if they want public attribution. The translation issue form and pull request template both ask.

Where possible, check the language on a device after restarting Instagram: settings, alerts, Action Button menus, Gallery, downloads, notifications, dates, plural-heavy screens, and accessibility labels. Right-to-left languages should also be checked for layout and navigation direction.
