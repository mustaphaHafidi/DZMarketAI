/// Compact two-column cards reserve their content height for the title and
/// location. Extra delivery badges would otherwise overflow on small phones.
bool shouldShowListingCardBadges({
  required bool isCompactCard,
  required bool hasBadges,
  required double contentHeight,
}) {
  return !isCompactCard && hasBadges && contentHeight >= 82;
}
