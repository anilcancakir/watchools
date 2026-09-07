// GENERATED: do not edit by hand.
// Regenerate via: dart run magic:artisan previews:refresh
//
// Source: *.preview.dart files discovered under the scan dir.

import 'package:magic_devtools/preview.dart';
import 'ui/components/channel_mark/channel_mark.preview.dart';
import 'ui/components/channel_row/channel_row.preview.dart';
import 'ui/components/epg_row/epg_row.preview.dart';
import 'ui/components/fact_chip/fact_chip.preview.dart';
import 'ui/components/favourite_button/favourite_button.preview.dart';
import 'ui/components/hero_billboard/hero_billboard.preview.dart';
import 'ui/components/status_badge/status_badge.preview.dart';

List<PreviewEntry> previewEntries() {
  return <PreviewEntry>[
    PreviewEntry(
      label: 'ChannelMark',
      slug: 'channel_mark',
      builder: (_) => const ChannelMarkPreview(),
    ),
    PreviewEntry(
      label: 'ChannelRow',
      slug: 'channel_row',
      builder: (_) => const ChannelRowPreview(),
    ),
    PreviewEntry(
      label: 'EpgRow',
      slug: 'epg_row',
      builder: (_) => const EpgRowPreview(),
    ),
    PreviewEntry(
      label: 'FactChip',
      slug: 'fact_chip',
      builder: (_) => const FactChipPreview(),
    ),
    PreviewEntry(
      label: 'FavouriteButton',
      slug: 'favourite_button',
      builder: (_) => const FavouriteButtonPreview(),
    ),
    PreviewEntry(
      label: 'HeroBillboard',
      slug: 'hero_billboard',
      builder: (_) => const HeroBillboardPreview(),
    ),
    PreviewEntry(
      label: 'StatusBadge',
      slug: 'status_badge',
      builder: (_) => const StatusBadgePreview(),
    ),
  ];
}

