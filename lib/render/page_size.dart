/// Verovio's `pageWidth`/`pageHeight` are the **physical paper size in
/// tenths of a millimetre** (the defaults, 2100x2970, are A4), not a
/// resolution: the scene is vector, and the `.vsb` carries the viewBox in
/// hundredths of a millimetre (`DEFINITION_FACTOR = 10`) plus the page fit,
/// so generating it for a bigger page changes nothing on screen except how
/// much music lands on each page.
///
/// That makes the page size the knob for **how large the notation is
/// displayed**: a smaller page holds fewer systems, so it reflows onto more
/// pages and each staff gets more pixels in the same widget.
const int kVerovioMinPageWidth = 500;
const int kVerovioMaxPageWidth = 10000;
const int kVerovioMinPageHeight = 300;
const int kVerovioMaxPageHeight = 6000;

/// Page size for callers with no widget to measure (tests, headless
/// renders). The app derives its own from the score box instead — see
/// `_pageWidth` in `lib/main.dart`.
const int kFallbackPageWidth = 1250;
const int kFallbackPageHeight = 456;
