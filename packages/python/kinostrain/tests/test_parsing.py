"""Parsing the captured payloads — the part a port has to get exactly right."""

from conftest import FakeTransport
from kinostrain import ContentType, Gender, KinostrainApi


def api_for(transport: FakeTransport) -> KinostrainApi:
    return KinostrainApi(transport)  # type: ignore[arg-type]


def test_catalog_parses_cards_and_pagination() -> None:
    page = api_for(FakeTransport.fixture("catalog_movie_page1")).catalog(type=ContentType.MOVIE)

    assert (page.meta.page, page.meta.per_page, page.meta.total) == (1, 24, 3436)
    assert page.meta.total_pages == 144
    assert page.has_next_page and page.meta.next_page == 2

    card = page[0]
    assert card.name == "Одна миля: Розділ другий"
    assert card.slug == "odna-mila-rozdil-drugij"
    assert card.type is ContentType.MOVIE
    assert card.type_raw == "movie"
    assert not card.is_series
    assert card.year_label == "2026"
    assert len(card.genres) == 3
    assert card.first_ready_season is not None
    assert card.first_ready_season.number == 1
    assert card.first_ready_season.last_ready_episode is None


def test_catalog_widens_an_integer_imdb_mark_to_a_float() -> None:
    page = api_for(FakeTransport.fixture("catalog_movie_page1")).catalog()

    assert page[0].imdb_mark == 5.0
    assert isinstance(page[0].imdb_mark, float)


def test_catalog_labels_a_finished_series_with_both_years() -> None:
    page = api_for(FakeTransport.fixture("catalog_serial_genre")).catalog()

    card = page[0]
    assert card.is_series
    assert card.year_label == "2026 – 2026"
    assert card.last_ready_season is not None
    assert card.last_ready_season.ready_episodes_count == 8


def test_filters_group_genres_and_years_per_section() -> None:
    filters = api_for(FakeTransport.fixture("catalog_filters")).catalog_filters()

    movie = filters[ContentType.MOVIE]
    assert len(movie.popular_genres) == 11
    assert len(movie.other_genres) == 31
    assert len(movie.all_genres) == 42
    assert movie.total_count == 3436
    assert movie.genre_by_slug("bojovik") is not None
    assert movie.genre_by_slug("nope") is None
    assert set(filters.by_type) == set(ContentType)
    assert filters.unknown_type_keys == ()


def test_filters_flag_year_buckets_that_span_a_range() -> None:
    filters = api_for(FakeTransport.fixture("catalog_filters")).catalog_filters()

    years = {year.slug: year for year in filters[ContentType.MOVIE].years}
    assert not years["2026"].is_range
    assert years["2006-2010"].is_range
    assert years["2000-1900"].is_range


def test_filters_keep_unknown_sections_aside_instead_of_failing() -> None:
    body = '{"movie": {"totalCount": 1}, "documentary": {"totalCount": 2}, "junk": 3}'
    filters = api_for(FakeTransport.json(body)).catalog_filters()

    assert filters.unknown_type_keys == ("documentary",)
    assert list(filters.by_type) == [ContentType.MOVIE]
    assert filters.get(ContentType.ANIME) is None


def test_trending_carries_the_fields_catalog_cards_lack() -> None:
    cards = api_for(FakeTransport.fixture("trending_movie")).trending(type=ContentType.MOVIE)

    card = cards[0]
    assert card.name == "Сусіди зверху"
    assert card.slider_poster_url is not None
    assert card.short_description is not None
    assert card.time == "107 хв"
    assert card.country == "Сполучені Штати"
    assert card.last_update_page is not None
    assert card.last_update_page.year == 2026


def test_slider_carries_trailer_id_and_age_restriction() -> None:
    cards = api_for(FakeTransport.fixture("slider_movie")).slider()

    card = cards[0]
    assert card.trailer_youtube_id == "QZUFUvULWqs"
    assert card.age_restrictions == 18


def test_search_parses_hits_and_the_matched_span() -> None:
    hits = api_for(FakeTransport.fixture("search")).search("мерц")

    assert len(hits) == 4
    hit = hits[0]
    assert hit.card.name == "Дріт мерця"
    assert hit.card.original_name == "Dead Man's Wire"
    assert hit.highlighted_name == "Дріт <mark>мерця</mark>"
    assert [(span.text, span.matched) for span in hit.name_spans()] == [
        ("Дріт ", False),
        ("мерця", True),
    ]
    # The search card is the thin one: no genres, no season counts.
    assert hit.card.genres == ()
    assert hit.card.seasons_count == 0


def test_search_falls_back_to_the_plain_name_when_nothing_was_marked() -> None:
    body = (
        '{"data": [{"name": "Дюна", "originalName": "Dune", "slug": "duna", "type": "movie",'
        ' "format": "film", "posterUrl": "p"}]}'
    )
    hits = api_for(FakeTransport.json(body)).search("дюна")

    spans = hits[0].name_spans()
    assert [(span.text, span.matched) for span in spans] == [("Дюна", False)]


def test_search_degrades_a_malformed_highlight_to_the_plain_name() -> None:
    body = (
        '{"data": [{"name": "Дюна", "originalName": "Dune", "slug": "duna", "type": "movie",'
        ' "format": "film", "posterUrl": "p", "highlight": {"name": "<mark>Дюна"}}]}'
    )
    hits = api_for(FakeTransport.json(body)).search("дюна")

    assert [(span.text, span.matched) for span in hits[0].name_spans()] == [("<mark>Дюна", False)]


def test_persons_parses_the_directory_page() -> None:
    page = api_for(FakeTransport.fixture("persons")).persons()

    assert page.meta.total == 34219
    person = page[0]
    assert person.name == "Інде Наварретт"
    assert person.gender is Gender.FEMALE
    assert person.career_roles == ("actor",)
    assert person.is_actor and not person.is_director


def test_cards_batch_carries_the_site_rating() -> None:
    cards = api_for(FakeTransport.fixture("content_cards")).cards(["lihtari", "grifini-sim-anin"])

    assert len(cards) == 2
    assert cards[0].average_rating == 10
    assert cards[0].ratings_count == 4
    assert cards[0].time == "55 хв"


def test_comments_returns_raw_maps_and_an_empty_page() -> None:
    page = api_for(FakeTransport.fixture("comments_empty")).comments(458)

    assert page.items == ()
    assert page.meta.total == 0
    assert not page.has_next_page
