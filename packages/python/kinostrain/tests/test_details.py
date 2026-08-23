"""Content details: the seasons, the two player shapes, the franchise."""

from conftest import FakeTransport
from kinostrain import ContentType, Gender, KinostrainApi


def api_for(transport: FakeTransport) -> KinostrainApi:
    return KinostrainApi(transport)  # type: ignore[arg-type]


def film() -> object:
    return api_for(FakeTransport.fixture("content_details")).content("zlovisni-merci-u-vogni")


def serial() -> object:
    return api_for(FakeTransport.fixture("content_details_serial")).content("zovnisni-milini")


def test_parses_a_film_its_season_and_its_players() -> None:
    details = film()

    assert details.id == 4953
    assert details.name == "Зловісні мерці у вогні"
    assert details.type is ContentType.MOVIE
    assert not details.is_series
    assert details.imdb_mark == 6.4
    assert (details.average_rating, details.ratings_count) == (6, 5)
    assert details.comments_count == 1
    assert details.time == "1 год 50 хв"
    assert details.country == "США"
    assert details.age_restrictions == 18
    assert len(details.cast) == 10
    assert len(details.directors) == 1
    assert details.directors[0].character is None
    assert details.cast[0].gender in set(Gender)
    assert details.franchise is None

    season = details.first_season
    assert season is not None
    assert (season.id, season.number) == (7892, 1)
    assert season.players == ("ashdi", "tortuga", "vidsrc")
    assert not season.is_episodic
    assert len(season.frames) == 8
    # A film has no episode list at all, which is not the same as being unloaded.
    assert season.episodes == ()
    assert season.is_loaded


def test_a_film_offers_only_the_providers_that_really_carry_a_stream() -> None:
    season = film().first_season
    assert season is not None

    # `players` advertises three; only ashdi shipped anything.
    assert season.available_players() == ("ashdi",)
    sources = season.sources_for("ashdi")
    assert len(sources) == 2
    assert sources[0].name == "DniproFilm"
    assert sources[0].link == "https://ashdi.vip/vod/276636"
    assert season.sources_for("tortuga") == ()
    assert season.is_playable


def test_parses_a_series_whose_streams_are_keyed_by_episode() -> None:
    details = serial()

    assert details.is_series
    assert [season.number for season in details.seasons] == [1, 2]

    first = details.seasons[0]
    assert first.is_episodic
    assert first.playable_episodes == (1, 2, 3)
    assert [episode.name for episode in first.episodes] == [
        "Пілотний епізод",
        "Щасливий компас",
        "Заборонена зона",
    ]
    assert first.episodes[0].ready
    air_date = first.episodes[0].air_date
    assert air_date is not None and air_date.date().isoformat() == "2020-04-15"


def test_resolves_sources_for_a_specific_episode() -> None:
    season = serial().seasons[0]

    sources = season.sources_for("ashdi", episode=1)
    assert sources[0].name == "Le-Doyen"
    assert sources[0].link == "https://ashdi.vip/vod/140685"
    assert season.available_players(episode=1) == ("ashdi",)
    # Asked without an episode, an episodic season answers for the first playable one.
    assert season.sources_for("ashdi") == sources


def test_tells_a_season_that_was_not_fetched_from_one_with_nothing_in_it() -> None:
    details = serial()

    fetched, not_fetched = details.seasons[0], details.seasons[1]
    assert fetched.is_loaded
    assert not not_fetched.is_loaded
    assert not_fetched.players == ()
    assert not_fetched.episodes == ()
    assert not not_fetched.is_playable


def test_finds_the_first_and_last_playable_season_of_a_sparse_series() -> None:
    details = serial()

    first = details.first_playable_season
    latest = details.latest_playable_season
    assert first is not None and first.number == 1
    assert latest is not None and latest.number == 1
    assert details.is_playable


def test_parses_a_franchise_and_marks_the_current_entry() -> None:
    details = api_for(FakeTransport.fixture("content_details_franchise")).content(
        "odna-mila-rozdil-drugij"
    )

    franchise = details.franchise
    assert franchise is not None
    assert franchise.name == "One Mile Collection"
    assert franchise.slug == "one-mile-collection"
    assert len(franchise.items) == 2
    current = franchise.current
    assert current is not None
    assert current.slug == "odna-mila-rozdil-drugij"
    assert current.year == 2026


def test_a_rights_blocked_season_is_never_playable() -> None:
    body = (
        '{"data": {"id": 1, "name": "X", "originalName": "X", "slug": "x", "type": "movie",'
        ' "format": "film", "posterUrl": "p", "seasons": [{"id": 1, "number": 1,'
        ' "rightsBlocked": true, "players": ["ashdi"],'
        ' "playerData": {"ashdi": [{"name": "n", "link": "l"}]}}]}}'
    )
    details = api_for(FakeTransport.json(body)).content("x")

    season = details.seasons[0]
    assert season.is_loaded
    assert season.available_players() == ("ashdi",)
    assert not season.is_playable
    assert not details.is_playable


def test_a_provider_shipping_a_stream_without_being_listed_still_counts() -> None:
    body = (
        '{"data": {"id": 1, "name": "X", "originalName": "X", "slug": "x", "type": "movie",'
        ' "format": "film", "posterUrl": "p", "seasons": [{"id": 1, "number": 1,'
        ' "players": ["ashdi"], "playerData": {"ashdi": [{"name": "a", "link": "la"}],'
        ' "tortuga": [{"name": "t", "link": "lt"}]}}]}}'
    )
    season = api_for(FakeTransport.json(body)).content("x").seasons[0]

    assert season.available_players() == ("ashdi", "tortuga")
