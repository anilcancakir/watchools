/// What the two live toolbars need before they fit on one line.
///
/// Both views draw the same row at the same widths on purpose: they are two
/// cuts of one screen, and a control that moves between them is the fastest
/// way to break that. The arithmetic belongs beside neither of them, so it
/// lives here and each reads it.
///
/// ### Why a number at all, and why it is measured against the row
///
/// The arrangement used to key off the layouts' `wide`, which is the nav
/// rail's 640 pixel VIEWPORT breakpoint. The row lives inside a column the
/// rail has already narrowed, and it carries a fixed 470 pixel search field,
/// so between 640 and roughly 830 the single line was selected for a row that
/// could not hold it and the toolbar spilled: 110 pixels on the running app at
/// an 800 pixel window, and up to 148 in a widget test at 640. `CLAUDE.md`
/// lists that trap first of four and prescribes the fix this file is: a
/// component whose columns depend on real width takes a `double` and decides
/// in Dart.
library;

/// The narrowest row that can carry the single-line toolbar.
///
/// Against the width the toolbar's own parent offers, never the window's. The
/// budget, all of it from the row itself:
///
/// | Part | Pixels | Where |
/// |---|---|---|
/// | Page gutters, both sides | 48 | `PageGutter.x` |
/// | Search field | 470 | `w-[470px] shrink-0` |
/// | Two `gap-3` | 24 | the row's own className |
/// | View switch | 190 | two labelled segments plus padding |
/// | Count, readable minimum | 100 | enough for `23 kanal` before ellipsis |
///
/// 832, rounded to 840 so the boundary is not a coincidence of one label's
/// width. The switch figure is the widget-test measurement (182.5 under the
/// square font, which is 1.5x to 2x wider than Schibsted Grotesk), so the real
/// row clears this with room rather than exactly, which is the safe direction:
/// stacking one size early costs a line of vertical space, and stacking one
/// size late costs a toolbar that runs off the screen.
///
/// The count's 100 is the part that is a judgement rather than a measurement,
/// and it is deliberate. Letting the count ellipsise to nothing would keep the
/// single line down to about 730 and drop the missing-guide note with it,
/// which is the sentence the toolbar exists to carry.
const double guideToolbarOneLineAt = 840;
