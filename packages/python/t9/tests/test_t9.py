import pytest
from t9 import (
    LATIN,
    UKRAINIAN,
    NotOnTheKeypad,
    digits,
    layout_for,
    taps,
)


def test_the_show() -> None:
    assert digits("FAMILY GUY") == "326459 489"


def test_the_same_show_in_ukrainian() -> None:
    assert digits("ГРІФІНИ") == "2647454"


def test_case_does_not_matter() -> None:
    assert digits("Family Guy") == digits("FAMILY GUY")


def test_the_keypad_is_picked_from_the_text() -> None:
    assert layout_for("Сімпсони") is UKRAINIAN
    assert layout_for("The Simpsons") is LATIN
    #: No letters, nothing to go on.
    assert layout_for("42!") is LATIN


def test_a_named_keypad_wins_over_the_guess() -> None:
    #: "c" is on 2 in Latin and nowhere in Ukrainian, where it stays a "c".
    assert digits("c", layout=UKRAINIAN) == "c"
    assert digits("c", layout=LATIN) == "2"


def test_multi_tap_counts_the_presses() -> None:
    assert taps("GUY") == "488999"
    assert taps("GUY", sep="-") == "4-88-999"
    #: Щ is second on 8, Е second on 3.
    assert taps("ЩЕ", layout=UKRAINIAN) == "8833"


def test_what_is_not_on_the_keypad() -> None:
    assert digits("hi, you!") == "44, 968!"
    assert digits("hi, you!", unknown="drop") == "44968"
    with pytest.raises(NotOnTheKeypad) as raised:
        digits("hi!", unknown="strict")
    assert raised.value.char == "!"


def test_the_ukrainian_keypad_holds_the_whole_alphabet() -> None:
    alphabet = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
    assert "".join(key.letters for key in UKRAINIAN.keys) == alphabet
    assert UKRAINIAN.covers(alphabet) == 33
    #: Ё Ъ Ы Э are Russian; they are not on it.
    assert UKRAINIAN.covers("ёъыэ") == 0
