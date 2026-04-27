/// Spacing, sizing, and typography scale used across the UI.
library;

/// Numeric layout constants shared by widgets and themes.
abstract final class AppDimensions {
  // Spacing
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;

  /// Alias for [spaceXs] (extra-small layout gap).
  static const double spacingXs = spaceXs;

  /// Alias for [spaceSm] (small layout gap).
  static const double spacingSm = spaceSm;

  /// Alias for [spaceLg] (medium layout gap).
  static const double spacingMd = spaceLg;

  /// Alias for [spaceLg] (layout section spacing).
  static const double spacingLg = spaceLg;

  /// Alias for [spaceXl] (extra-large layout gap).
  static const double spacingXl = spaceXl;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;
  static const double spaceSection = 40;

  // Padding
  static const double paddingScreenHorizontal = spaceLg;
  static const double paddingScreenVertical = spaceLg;
  static const double paddingCard = spaceLg;
  static const double paddingButtonHorizontal = spaceXl;
  static const double paddingButtonVertical = spaceMd;
  static const double paddingInputHorizontal = spaceLg;
  static const double paddingInputVertical = spaceMd;
  static const double paddingListTile = spaceSm;

  /// Standard horizontal/vertical padding for cards and sections.
  static const double paddingMd = spaceMd;

  /// Compact padding for dense rows.
  static const double paddingSm = spaceSm;

  /// Generous padding for section edges.
  static const double paddingLg = spaceXl;

  // Border radius
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusFull = 999;

  // Icon sizes
  static const double iconSm = 16;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 48;

  // Font sizes
  static const double fontSizeDisplay = 36;
  static const double fontSizeHeadline = 24;
  static const double fontSizeTitle = 20;
  static const double fontSizeTitleSmall = 18;
  static const double fontSizeBody = 16;
  static const double fontSizeBodySmall = 14;
  static const double fontSizeLabel = 14;
  static const double fontSizeCaption = 12;

  // Thumbnails (download cards, etc.)
  static const double downloadThumbWidth = 64;
  static const double downloadThumbHeight = 48;

  /// Home video card thumbnail.
  static const double videoInfoThumbWidth = 120;
  static const double videoInfoThumbHeight = 80;

  // Component heights
  static const double minTouchTarget = 48;
  static const double buttonHeight = 56;
  static const double appBarHeight = 56;
  static const double progressBarHeight = 6;
  static const double textFieldHeight = 56;

  static const double cardElevation = 0.0;
  static const double cardRadius = 16.0;
  static const double chipRadius = 20.0;
  static const double buttonRadius = 14.0;
  static const double inputRadius = 14.0;
  static const double bottomSheetRadius = 24.0;
  static const double progressHeight = 6.0;
  static const double progressHeightLg = 8.0;
  static const double thumbnailWidth = 96.0;
  static const double thumbnailHeight = 64.0;
  static const double avatarSize = 40.0;
  static const double fabSize = 56.0;
}
