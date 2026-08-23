"""Text in, keypresses out."""

from collections.abc import Callable
from typing import Literal

from t9.layouts import Layout, Press, layout_for

#: What to do with a character the keypad has no key for.
#:
#: - ``keep`` — pass it through unchanged, so spaces and punctuation survive
#: - ``drop`` — leave it out
#: - ``strict`` — raise `NotOnTheKeypad`
Unknown = Literal["keep", "drop", "strict"]


class NotOnTheKeypad(ValueError):
    """What ``unknown="strict"`` raises."""

    def __init__(self, char: str, layout: Layout) -> None:
        super().__init__(f"{char!r} is not on the {layout.name} keypad")
        self.char = char
        self.layout = layout


def digits(text: str, layout: Layout | None = None, unknown: Unknown = "keep") -> str:
    """One digit per letter — what a T9 phone sends before the dictionary guesses.

    ``"FAMILY GUY"`` → ``"326459 489"``. `None` picks the keypad from the text.
    """
    return _render(text, layout, unknown, lambda press: press.digit, sep="")


def taps(
    text: str,
    layout: Layout | None = None,
    unknown: Unknown = "keep",
    sep: str = "",
) -> str:
    """Every press, the way you typed it on a phone with no dictionary.

    ``"GUY"`` → ``"488999"``: G is first on 4, U second on 8, Y third on 9. Two
    letters from one key run together, which is why `sep` is here.
    """
    return _render(text, layout, unknown, lambda press: press.digit * press.times, sep=sep)


def _render(
    text: str,
    layout: Layout | None,
    unknown: Unknown,
    of_press: Callable[[Press], str],
    sep: str,
) -> str:
    keypad = layout if layout is not None else layout_for(text)
    out: list[str] = []
    for char in text:
        press = keypad.press_for(char)
        if press is not None:
            out.append(of_press(press))
        elif unknown == "keep":
            out.append(char)
        elif unknown == "strict":
            raise NotOnTheKeypad(char, keypad)
    return sep.join(out)
