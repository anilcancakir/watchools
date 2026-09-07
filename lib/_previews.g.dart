// GENERATED: do not edit by hand.
// Regenerate via: dart run magic:artisan previews:refresh
//
// Source: *.preview.dart files discovered under the scan dir.

import 'package:magic_devtools/preview.dart';

import 'ui/components/artwork/artwork.preview.dart';
import 'ui/components/channel_mark/channel_mark.preview.dart';
import 'ui/components/episode_row/episode_row.preview.dart';
import 'ui/components/fact_chip/fact_chip.preview.dart';
import 'ui/components/favourite_button/favourite_button.preview.dart';
import 'ui/components/play_progress/play_progress.preview.dart';
import 'ui/components/status_badge/status_badge.preview.dart';
import 'ui/components/title_poster/title_poster.preview.dart';

List<PreviewEntry> previewEntries() {
  return <PreviewEntry>[
    PreviewEntry(label: 'Artwork', slug: 'artwork', builder: (_) => const ArtworkPreview()),
    PreviewEntry(label: 'ChannelMark', slug: 'channel_mark', builder: (_) => const ChannelMarkPreview()),
    PreviewEntry(label: 'EpisodeRow', slug: 'episode_row', builder: (_) => const EpisodeRowPreview()),
    PreviewEntry(label: 'FactChip', slug: 'fact_chip', builder: (_) => const FactChipPreview()),
    PreviewEntry(label: 'FavouriteButton', slug: 'favourite_button', builder: (_) => const FavouriteButtonPreview()),
    PreviewEntry(label: 'PlayProgress', slug: 'play_progress', builder: (_) => const PlayProgressPreview()),
    PreviewEntry(label: 'StatusBadge', slug: 'status_badge', builder: (_) => const StatusBadgePreview()),
    PreviewEntry(label: 'TitlePoster', slug: 'title_poster', builder: (_) => const TitlePosterPreview()),
  ];
}
