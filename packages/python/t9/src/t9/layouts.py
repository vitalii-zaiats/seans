"""The keypads, and how to pick one for a piece of text."""

from collections.abc import Mapping
from dataclasses import dataclass, field


@dataclass(frozen=True, slots=True)
class Key:
    """One key: the digit written on it, and its letters in press order."""

    #: "2".."9" as a string, because the result is a string of digits and
    #: nobody ever does arithmetic on it.
    digit: str
    letters: str


@dataclass(frozen=True, slots=True)
class Press:
    """What one letter costs: which key, and how many times you hit it."""

    digit: str
    #: 1 for the first letter on the key, 2 for the second, and so on. T9 proper
    #: presses once and lets the dictionary guess; multi-tap needs the count.
    times: int


@dataclass(frozen=True, slots=True)
class Layout:
    """A keypad. Its letters are stored lowercase; lookups fold case."""

    name: str
    keys: tuple[Key, ...]
    #: Letter to press, built once on the way in. An index built per lookup is
    #: what made a whole-catalogue build take twenty seconds. Derived, so it is
    #: out of `==` and out of `hash`.
    presses: Mapping[str, Press] = field(init=False, repr=False, compare=False)

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "presses",
            {
                letter: Press(digit=key.digit, times=position)
                for key in self.keys
                for position, letter in enumerate(key.letters, start=1)
            },
        )

    def letters_for(self, digit: str) -> str:
        """Empty when this keypad has no such key."""
        for key in self.keys:
            if key.digit == digit:
                return key.letters
        return ""

    def press_for(self, letter: str) -> Press | None:
        """`None` for anything not printed on this keypad: punctuation, a digit,
        a letter from another alphabet."""
        return self.presses.get(letter.lower())

    def covers(self, text: str) -> int:
        """How many of `text`'s characters this keypad knows — what `layout_for`
        compares."""
        return sum(1 for char in text if self.press_for(char) is not None)


#: ITU E.161 — the arrangement on every phone that ever had letters on its keys.
LATIN = Layout(
    name="latin",
    keys=(
        Key("2", "abc"),
        Key("3", "def"),
        Key("4", "ghi"),
        Key("5", "jkl"),
        Key("6", "mno"),
        Key("7", "pqrs"),
        Key("8", "tuv"),
        Key("9", "wxyz"),
    ),
)

#: There is no ITU arrangement for Cyrillic and no Ukrainian standard either:
#: what phones shipped was the Russian keypad (АБВГ / ДЕЁЖЗ / ИЙКЛ / …) with
#: Ё Ъ Ы Э taken out and Ґ Є І Ї put back in alphabetical order, which is what
#: this is. All 33 letters, alphabetical, eight keys. If the keypad you remember
#: split them differently, build your own `Layout` — nothing here is special.
UKRAINIAN = Layout(
    name="ukrainian",
    keys=(
        Key("2", "абвгґ"),
        Key("3", "деєжз"),
        Key("4", "иіїйк"),
        Key("5", "лмно"),
        Key("6", "прст"),
        Key("7", "уфхцч"),
        Key("8", "шщь"),
        Key("9", "юя"),
    ),
)

#: By the short code the CLI takes.
LAYOUTS: Mapping[str, Layout] = {"en": LATIN, "uk": UKRAINIAN}


def layout_for(text: str) -> Layout:
    """The keypad that knows the most of `text`; a tie goes to the first listed,
    so text with no letters at all comes out Latin."""
    return max(LAYOUTS.values(), key=lambda layout: layout.covers(text))
