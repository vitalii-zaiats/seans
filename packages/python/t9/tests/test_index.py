"""The index, from the remote's point of view: press a key, get a shortlist."""

import pytest
from t9 import Entry, Index, codes_for, digits

CATALOGUE = (
    Entry(ref="family-guy", names=("Ґріфіни", "Family Guy"), rank=8.1),
    Entry(ref="the-simpsons", names=("Сімпсони", "The Simpsons"), rank=8.7),
    Entry(ref="futurama", names=("Футурама", "Futurama"), rank=8.4),
    Entry(ref="1917", names=("1917",), rank=8.2),
    Entry(ref="amelie", names=("Амелі", "Amélie"), rank=8.3),
    Entry(ref="friday", names=("П'ятниця 13-те", "Friday the 13th"), rank=6.4),
)


@pytest.fixture(scope="module")
def index() -> Index:
    return Index.of(CATALOGUE)


def found(index: Index, keys: str) -> list[str]:
    return [hit.entry.ref for hit in index.find(keys)]


def test_the_whole_title(index: Index) -> None:
    assert found(index, digits("FAMILYGUY")) == ["family-guy"]


def test_either_alphabet_lands_on_the_same_slug(index: Index) -> None:
    #: Which is the whole point: the box's keypad is Ukrainian, the poster is not.
    assert found(index, "2647454") == ["family-guy"]
    assert found(index, "326459") == ["family-guy"]


def test_a_word_in_the_middle_needs_no_separator(index: Index) -> None:
    #: "guy" and "simpsons", typed without the word before them.
    assert found(index, "489") == ["family-guy"]
    assert found(index, "74677667") == ["the-simpsons"]


def test_a_prefix_narrows_as_you_press(index: Index) -> None:
    assert found(index, "3") == ["futurama", "family-guy", "friday"]
    assert found(index, "38") == ["futurama"]


def test_the_shortlist_is_ordered_by_rank(index: Index) -> None:
    #: "The Simpsons" scores 8.7 and "Футурама" 8.4; both begin on 7.
    assert found(index, "7") == ["the-simpsons", "futurama"]


def test_digits_in_a_title_are_themselves(index: Index) -> None:
    assert found(index, "1917") == ["1917"]


def test_an_accent_is_not_a_wall(index: Index) -> None:
    #: "Amélie" is stored with the é; nobody can press one.
    assert "amelie" in found(index, digits("AMELIE"))


def test_an_apostrophe_does_not_split_a_word(index: Index) -> None:
    assert codes_for("П'ятниця") == ("6965479",)


def test_nothing_typed_is_nothing_found(index: Index) -> None:
    assert index.find("") == ()
    assert index.find("2", limit=0) == ()


def test_a_title_appears_once_however_many_names_matched() -> None:
    twice = Index.of([Entry(ref="x", names=("Кіно", "Kino"))])
    assert [hit.entry.ref for hit in twice.find("5")] == ["x"]


def test_the_codes_of_a_title() -> None:
    assert set(codes_for("Family Guy")) == {"326459489", "489"}
