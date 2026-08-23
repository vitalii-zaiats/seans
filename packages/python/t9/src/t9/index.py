"""An index from a name to the digits you press to find it.

The point of the thing: a remote has ten keys, so a query is ambiguous by
construction and the answer has to be a *list* of candidates. Everything here
exists to make that list appear between two presses.

Two decisions are worth knowing before you read the code.

**Every word start gets its own code**, so `489` finds "Family Guy" without
anybody typing the first word, and without a separator key. That is why `0`
is not a space here: you never need one.

**A title is indexed under all of its names.** "Ґріфіни" is typed on a Ukrainian
keypad and "Family Guy" on a Latin one, and both must land on the same slug.
The keypad is chosen per *word*, so "Дюна 2: Part Two" indexes correctly too.
"""

import unicodedata
from bisect import bisect_left
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from functools import cache
from heapq import nsmallest

from t9.layouts import Layout, layout_for


@dataclass(frozen=True, slots=True)
class Entry:
    """One findable thing."""

    #: Yours to interpret — a slug, an id. The index never looks inside it.
    ref: str
    #: Every name that should find it: the localised title, the original one,
    #: an alias. The first is what `find` orders by when all else is equal.
    names: tuple[str, ...]
    #: Bigger wins a tie. IMDb score, view count, recency — whatever "the one
    #: they meant" means for you. Ties below it break on the shortest name.
    rank: float = 0.0


@dataclass(frozen=True, slots=True)
class Hit:
    entry: Entry
    #: The code that matched, of which the query is a prefix. Useful for
    #: showing how much of the title is still ahead of the typist.
    code: str


@dataclass(frozen=True, slots=True)
class Index:
    """Codes and their owners, sorted, so a prefix is a slice.

    Sorted arrays and `bisect` rather than a trie: a prefix range is two binary
    searches over a `tuple[str, ...]` the interpreter never has to walk, it
    builds in one `sort`, and the same layout is what a `LIKE 'code%'` on a
    btree index does on the server. A trie would win on paper and lose in
    Python.
    """

    #: Sorted. Parallel to `owners` — `owners[i]` owns `codes[i]`.
    codes: tuple[str, ...]
    owners: tuple[Entry, ...]

    @classmethod
    def of(cls, entries: Iterable[Entry], *, layout: Layout | None = None) -> "Index":
        """`layout=None` picks a keypad per word, which is what mixed titles want."""
        pairs = {
            (code, entry.ref): (code, entry)
            for entry in entries
            for name in entry.names
            for code in codes_for(name, layout)
        }
        ordered = sorted(pairs.values(), key=lambda pair: pair[0])
        return cls(
            codes=tuple(code for code, _ in ordered),
            owners=tuple(entry for _, entry in ordered),
        )

    def find(self, keys: str, *, limit: int = 20) -> tuple[Hit, ...]:
        """Everything whose code starts with `keys`, best first.

        Non-digits in `keys` are ignored, so a client may send them however it
        collected them. One entry appears once even when several of its names
        matched.
        """
        wanted = "".join(char for char in keys if char.isdigit())
        if not wanted or limit <= 0:
            return ()

        best: dict[str, Hit] = {}
        for position in range(*self._range(wanted)):
            entry = self.owners[position]
            code = self.codes[position]
            standing = best.get(entry.ref)
            if standing is None or len(code) < len(standing.code):
                best[entry.ref] = Hit(entry=entry, code=code)

        return tuple(nsmallest(limit, best.values(), key=_order(len(wanted))))

    def _range(self, wanted: str) -> tuple[int, int]:
        """Half-open slice of `codes` that starts with `wanted`.

        The upper bound bumps the last digit: no code contains `:`, so
        `"99" + ":"` sorts after every code that starts with `"99"` and before
        anything that does not.
        """
        after = wanted[:-1] + chr(ord(wanted[-1]) + 1)
        return bisect_left(self.codes, wanted), bisect_left(self.codes, after)


def _order(typed: int) -> Callable[[Hit], tuple[bool, float, int, str]]:
    """Best first: a name the query spells out completely, then rank, then the
    shortest code.

    The first term is not decoration. Rank on its own buries the title somebody
    typed in full under whatever blockbuster happens to start with the same
    keys — on the real catalogue that is the difference between finding a
    late word in five presses and never finding it at all.
    """

    def key(hit: Hit) -> tuple[bool, float, int, str]:
        return len(hit.code) != typed, -hit.entry.rank, len(hit.code), hit.entry.names[0]

    return key


def codes_for(text: str, layout: Layout | None = None) -> tuple[str, ...]:
    """One code per word start: the word and everything after it, run together.

    "Family Guy" → `("326459489", "489")`. What you write into a `title_keys`
    table, one row each, if the index lives in SQL rather than in memory.
    """
    words = [_code(word, layout) for word in _words(text)]
    return tuple({"".join(words[start:]) for start in range(len(words)) if words[start]})


def _words(text: str) -> tuple[str, ...]:
    """Lower-cased, punctuation gone, apostrophes closed up so "П'ятниця" stays
    one word."""
    folded = "".join(_fold(char) for char in text.lower())
    words, current = [], ""
    for char in folded:
        if char.isalnum():
            current += char
        elif current:
            words.append(current)
            current = ""
    if current:
        words.append(current)
    return tuple(words)


#: Apostrophes vanish rather than split; the Russian four fold onto their nearest
#: Ukrainian letter, because a Russian title in the catalogue should still be
#: findable on the keypad the box actually has.
_FOLD = {"'": "", "’": "", "ʼ": "", "`": "", "ё": "е", "ъ": "ь", "ы": "и", "э": "е"}


@cache
def _fold(char: str) -> str:
    # Cached because a catalogue is millions of characters and a few hundred
    # distinct ones, and `unicodedata.normalize` is not free.
    if char in _FOLD:
        return _FOLD[char]
    # NFKD would also pull `й` apart into `и` + a breve and `ї` into `і`, which
    # is not ours to decide — so only an ASCII base is taken, and `é` becomes
    # `e` while the Cyrillic letters are left whole.
    base = unicodedata.normalize("NFKD", char)[0]
    return base if base.isascii() and base.isalpha() else char


def _code(word: str, layout: Layout | None) -> str:
    """A digit in a title stays itself: somebody looking for "1917" presses
    `1917`, and those keys carry no letters to be confused with."""
    keypad = layout if layout is not None else layout_for(word)
    out = []
    for char in word:
        press = keypad.press_for(char)
        if press is not None:
            out.append(press.digit)
        elif char.isdigit():
            out.append(char)
    return "".join(out)
