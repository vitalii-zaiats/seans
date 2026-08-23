/// Typed Dart client for the Super Movies API.
///
/// Start from [SuperMoviesApi]. The one call every app makes is [SuperMoviesApi.start],
/// and what you pass it is the answer to the first-run question:
///
/// ```dart
/// Launch.anonymous(...)   // nothing is written down anywhere but this box
/// Launch.identified(...)  // a guest, whose history follows the token back
/// ```
///
/// A claimed account is not a third kind of launch — it is the identified one
/// with a token already in hand. See [AccountMode].
///
/// The package performs no I/O of its own: it talks to a [Transport], and
/// [HttpTransport] is the one it builds when you supply nothing.
library;

export 'src/client.dart' show SuperMoviesApi;
export 'src/decode.dart' show decodeObject, detailOf;
export 'src/exceptions.dart';
export 'src/http_transport.dart' show HttpTransport;
export 'src/json.dart' show JsonMap, JsonMapReader;
export 'src/models/account.dart' show Account, AccountMode, Identity, Session;
export 'src/models/catalogue.dart'
    show
        CatalogFilters,
        ContentCard,
        ContentType,
        ContentTypeFilters,
        Gender,
        Genre,
        NameSpan,
        PageMeta,
        Paginated,
        Person,
        ReadySeason,
        SearchResult,
        YearOption;
export 'src/models/details.dart'
    show
        ContentDetails,
        Credit,
        Episode,
        Franchise,
        FranchiseItem,
        PlayerSource,
        Season,
        SeasonFrame;
export 'src/models/device_link.dart' show DeviceLink, DeviceLinkStatus;
export 'src/models/launch.dart' show AppPlatform, Launch, playStore;
export 'src/models/playback.dart' show PlaybackStream;
export 'src/models/start.dart' show Install, Start;
export 'src/models/tv.dart'
    show TvCategory, TvChannel, TvChannels, TvProgramme, TvSchedule, TvStream;
export 'src/models/update.dart' show UpdateAction, UpdateChannel, UpdatePlan;
export 'src/transport.dart' show ApiRequest, ApiResponse, Transport;
