# The icon is drawn in code

`src/Icon.swift` draws the face with Core Graphics, in 83 lines. No image file
is shipped. The same drawing produces the 18 pt menu-bar template, all ten
sizes of `Sleepless.icns`, and the picture in the README.

## This was not decided at the time

It should be said plainly: nobody weighed the alternatives. The app needed an
icon, there was no asset and no designer, and drawing in code let each round
of candidates reach the screen in seconds instead of minutes — four zombies,
then four faces, then the true 18 pt pixels magnified so the choice could be
made on what macOS actually shows.

Speed of iteration chose for us. This ADR is the decision being taken
afterwards, knowing what the alternatives were.

## Considered Options

**SF Symbols.** The system way: free accessibility, adapts to weight and
appearance, no code. It cannot express this design — there is no pair of
symbols for "staring wide-eyed" and "eyes closed". The first version used
`cup.and.saucer` and was rejected for being unclear at 18 pt.

**A vector asset (PDF template) in an asset catalog.** The standard way, and
the only one a designer can open. It needs `actool`, which effectively means
an Xcode project. This project builds with one `swiftc` call and a shell
script. Adding a whole asset pipeline to ship two pictures is a large
structural change for a small gain.

**PNG at 1× and 2×.** Simple, no catalog needed. But four files, resolution
locked, and the `.icns` still has to be produced some other way.

## Decision

Keep the menu-bar glyph in code. It is one monochrome shape; the code is the
only source, so the menu-bar image and the `.icns` cannot drift apart; it
renders at any size, which is what made the magnified-pixel previews possible;
and it is testable — the suite asserts that both states draw and that they are
not the same picture. None of that is true of a PNG.

## Consequences

- **A designer cannot touch it.** Changing the face means editing numbers in
  `CGRect`. If a designer ever joins, this decision should be reopened for the
  glyph as well.
- **The Finder icon is a known placeholder.** It is the menu-bar glyph scaled
  up on a green tile. That is not an app icon; it is a glyph wearing one.
  Apple's guidelines assume a designed composition with depth. When the Finder
  icon starts to matter, it should become a real asset — and that can happen
  without disturbing the glyph.
- Changing the drawing means rebuilding the README picture. `./build.sh &&
  ./build/icontool sheet build/icons.png` shows the true 18 pt result before
  committing, and `icontool docs` regenerates `docs/states.png`.
