"""The merged catalogue: what makes two rows one film, and what refuses to.

The merge is arithmetic over data and is tested as such — no database — while
the route is tested end to end over a catalogue built in the test itself.
"""

import httpx2
import pytest
from api.core.database import get_session
from api.modules.titles.loading import load, rank_of
from api.modules.titles.merging import SOLE, merge
from api.modules.titles.models import Title
from api.modules.titles.reading import (
    Claim,
    EpisodeIn,
    Incoming,
    Play,
    aliases_of,
    fold,
)
from api.modules.titles.service import TitleService
from fastapi import FastAPI
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession


def row(
    source: str = "kinostrain",
    external_id: str = "one",
    name: str = "Ґріфіни",
    original: str | None = "Family Guy",
    year: int | None = 1999,
    claims: tuple[Claim, ...] = (),
    **rest: object,
) -> Incoming:
    return Incoming(
        source=source,  # type: ignore[arg-type]
        external_id=external_id,
        kind="serial",
        name=name,
        original_name=original,
        year_start=year,
        claims=claims,
        aliases=aliases_of(original, name, year=year),
        **rest,  # type: ignore[arg-type]
    )


# --- the keys ----------------------------------------------------------------


def test_an_imdb_id_merges_two_rows() -> None:
    merged = merge(
        [
            row(claims=(Claim("imdb", "tt0182576"),)),
            row(
                source="kinoukr",
                external_id="42",
                name="Сім'янин",
                claims=(Claim("imdb", "tt0182576"),),
            ),
        ]
    )

    assert len(merged) == 1
    assert {attached.evidence for attached in merged[0].rows} == {"imdb+name"}


def test_a_shared_upload_merges_rows_that_spell_it_differently() -> None:
    #: The ashdi id is the id of a file, and two catalogues pointing at one file
    #: are describing one film however they spell it.
    merged = merge(
        [
            row(name="Поганці мусять помирати", original="Bad Men Must Bleed"),
            row(
                source="kinoukr",
                external_id="7",
                name="Погані хлопці",
                original="Bad Men",
                claims=(),
            ),
        ]
    )
    assert len(merged) == 2

    shared = (Claim("ashdi", "vod/1"),)
    merged = merge(
        [
            row(name="Поганці мусять помирати", original="Bad Men Must Bleed", claims=shared),
            row(
                source="kinoukr",
                external_id="7",
                name="Погані хлопці",
                original="Bad Men",
                claims=shared,
            ),
        ]
    )
    assert len(merged) == 1


def test_a_disagreeing_imdb_id_vetoes_a_shared_upload() -> None:
    #: What keeps "Той, що біжить по лезу" apart from "…2049": they share an
    #: ashdi upload, and one of the two catalogues attached it to the wrong film.
    shared = Claim("ashdi", "vod/4886")
    merged = merge(
        [
            row(
                name="Той, що біжить по лезу",
                original="Blade Runner",
                year=1982,
                claims=(shared, Claim("imdb", "tt0083658")),
            ),
            row(
                source="kinoukr",
                external_id="9",
                name="Той, хто біжить по лезу 2049",
                original="Blade Runner 2049",
                year=2017,
                claims=(shared, Claim("imdb", "tt1856101")),
            ),
        ]
    )
    assert len(merged) == 2


def test_a_year_may_differ_by_one_and_no_more() -> None:
    def pair(year: int) -> int:
        return len(merge([row(year=2015), row(source="kinoukr", external_id="8", year=year)]))

    assert pair(2015) == 1
    assert pair(2016) == 1
    assert pair(2017) == 2


def test_two_rows_of_one_source_are_never_merged() -> None:
    #: A duplicate inside kinostrain is kinostrain's business. Merging it here
    #: would be correcting somebody else's catalogue without being asked.
    merged = merge([row(external_id="a"), row(external_id="b")])
    assert len(merged) == 2


def test_a_title_never_holds_two_rows_from_one_source() -> None:
    #: Transitivity is what this stops: a weak edge and a strong one chained
    #: together would otherwise fuse a film with its sequel.
    merged = merge(
        [
            row(external_id="a", name="Рейд 2", original="The Raid 2", year=2014),
            row(external_id="b", name="Рейд", original="The Raid", year=2012),
            row(source="kinoukr", external_id="c", name="Рейд", original="The Raid", year=2013),
        ]
    )
    for group in merged:
        assert len(group.sources) == len(group.rows)


def test_a_row_nothing_agrees_with_says_so() -> None:
    (group,) = merge([row()])
    assert group.rows[0].evidence == SOLE


# --- reading -----------------------------------------------------------------


def test_a_name_with_a_slash_is_two_names() -> None:
    #: Either half is what the other catalogue may have picked.
    aliases = aliases_of("Хвиля / Die Welle", None, year=2008)
    assert {alias.folded for alias in aliases} == {"хвиля", "diewelle"}


def test_folding_leaves_cyrillic_alone_and_takes_accents_off_latin() -> None:
    assert fold("Amélie") == "amelie"
    #: NFKD would pull `й` into `и` plus a breve, and that is a different
    #: letter rather than the same one decorated.
    assert fold("Йосип") == "йосип"


# --- the rank ----------------------------------------------------------------


def test_votes_never_carry_a_worse_film_past_a_better_one() -> None:
    famous = row(name="a", claims=(), imdb_mark=7.1, imdb_votes=900_000)
    better = row(name="b", claims=(), imdb_mark=8.1)
    assert rank_of(famous) < rank_of(better)


def test_votes_break_a_tie() -> None:
    watched = row(name="a", claims=(), imdb_mark=7.5, imdb_votes=500_000)
    ignored = row(name="b", claims=(), imdb_mark=7.5)
    assert rank_of(watched) > rank_of(ignored)


# --- over HTTP ---------------------------------------------------------------


@pytest.fixture
async def catalogue(app: FastAPI, sessions: object) -> None:
    """A catalogue of three, written through the same path the CLI uses."""
    session_for_request = app.dependency_overrides[get_session]
    async for session in session_for_request():
        await load(
            session,
            merge(
                [
                    row(
                        external_id="fg",
                        name="Ґріфіни",
                        original="Family Guy",
                        year=1999,
                        episodes=(EpisodeIn(season=1, number=1, name="Death Has a Shadow"),),
                        plays=(
                            Play(
                                host="ashdi",
                                external_id="vod/1",
                                url="https://ashdi.vip/vod/1",
                                label="1+1",
                                season=1,
                                episode=1,
                            ),
                        ),
                    ),
                    row(
                        source="kinoukr",
                        external_id="fg2",
                        name="Сім'янин",
                        original="Family Guy",
                        year=1999,
                        imdb_mark=8.1,
                        claims=(Claim("imdb", "tt0182576"),),
                        plays=(
                            Play(
                                host="ashdi",
                                external_id="vod/1",
                                url="https://ashdi.vip/vod/1",
                                label="1+1",
                            ),
                        ),
                    ),
                    row(
                        external_id="sp",
                        name="Сімпсони",
                        original="The Simpsons",
                        year=1989,
                        imdb_mark=8.6,
                    ),
                ]
            ),
        )
        await session.commit()
        break


async def test_a_keypad_finds_a_title_under_either_alphabet(
    v2: httpx2.AsyncClient, catalogue: None
) -> None:
    #: 2-6-4-7-4-5-4 spells Ґріфіни on a Ukrainian keypad; 3-2-6-4-5-9-4-8-9
    #: spells FAMILYGUY on a Latin one. One title.
    for keys in ("2647454", "326459489"):
        answer = await v2.get("/titles/keys", params={"keys": keys})
        assert answer.status_code == 200, keys
        assert [item["original_name"] for item in answer.json()["items"]] == ["Family Guy"]


async def test_a_later_word_needs_no_separator(v2: httpx2.AsyncClient, catalogue: None) -> None:
    #: 4-8-9 is GUY, typed without the word in front of it.
    answer = await v2.get("/titles/keys", params={"keys": "489"})
    assert [item["original_name"] for item in answer.json()["items"]] == ["Family Guy"]


async def test_one_key_is_refused_rather_than_answered(v2: httpx2.AsyncClient) -> None:
    #: It selects a third of the catalogue and narrows nothing.
    assert (await v2.get("/titles/keys", params={"keys": "4"})).status_code == 400


async def test_a_title_says_who_told_us_and_why_we_believed_them(
    v2: httpx2.AsyncClient, catalogue: None, db: AsyncSession
) -> None:
    slug = await db.scalar(select(Title.slug).where(Title.original_name == "Family Guy"))
    answer = await v2.get(f"/titles/{slug}")

    body = answer.json()
    assert {source["source"] for source in body["sources"]} == {"kinostrain", "kinoukr"}
    assert {source["evidence"] for source in body["sources"]} == {"name"}
    assert body["episodes"] == [{"season": 1, "number": 1, "name": "Death Has a Shadow"}]


async def test_one_upload_offered_twice_is_one_stream(
    v2: httpx2.AsyncClient, catalogue: None, db: AsyncSession
) -> None:
    #: Both catalogues hand out `ashdi.vip/vod/1`. The duplicate dies here.
    slug = await db.scalar(select(Title.slug).where(Title.original_name == "Family Guy"))
    streams = (await v2.get(f"/titles/{slug}")).json()["streams"]
    assert [stream["url"] for stream in streams] == ["https://ashdi.vip/vod/1"]


async def test_a_slug_nobody_has_is_a_404(v2: httpx2.AsyncClient) -> None:
    assert (await v2.get("/titles/nothing-1999")).status_code == 404


async def test_the_catalogue_is_empty_until_it_is_loaded(db: AsyncSession) -> None:
    assert await db.scalar(select(func.count()).select_from(Title)) == 0
    assert await TitleService(db).count() == 0
