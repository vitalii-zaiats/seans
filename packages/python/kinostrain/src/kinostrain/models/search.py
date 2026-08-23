"""A `/search` hit, and the server's idea of what matched."""

from dataclasses import dataclass

from kinostrain.jsonread import JsonMap, map_or_none, str_or_none
from kinostrain.models.card import ContentCard

_OPEN = "<mark>"
_CLOSE = "</mark>"


@dataclass(frozen=True, slots=True)
class NameSpan:
    """A run of a hit's title, and whether the server matched it."""

    text: str
    #: Draw this run in the accent when true — it is what the query hit.
    matched: bool = False

    def __str__(self) -> str:
        return f"[{self.text}]" if self.matched else self.text


@dataclass(frozen=True, slots=True)
class SearchResult:
    """One hit from `/search`.

    The payload is a slimmer card than the catalog's — no genres, no season
    counts — plus the highlight.
    """

    card: ContentCard
    #: The title with the matched span wrapped in `<mark>`, e.g.
    #: `Дріт <mark>мерця</mark>`. `None` when the API marked nothing, which it
    #: often does not — never rely on this being present.
    highlighted_name: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "SearchResult":
        highlight = map_or_none(json, "highlight")
        return cls(
            card=ContentCard.from_json(json),
            highlighted_name=None if highlight is None else str_or_none(highlight, "name"),
        )

    def name_spans(self) -> tuple[NameSpan, ...]:
        """The name split into runs, each flagged with whether it matched.

        Falls back to the plain name as a single unmatched run, so a caller
        renders one way whether or not a highlight came back.
        """
        marked = self.highlighted_name
        plain = (NameSpan(self.card.name),)
        if marked is None:
            return plain

        spans: list[NameSpan] = []
        rest = marked
        while True:
            open_at = rest.find(_OPEN)
            if open_at < 0:
                break
            close_at = rest.find(_CLOSE, open_at)
            if close_at < 0:
                break
            if open_at > 0:
                spans.append(NameSpan(rest[:open_at]))
            spans.append(NameSpan(rest[open_at + len(_OPEN) : close_at], matched=True))
            rest = rest[close_at + len(_CLOSE) :]
        if rest:
            spans.append(NameSpan(rest))

        return tuple(spans) if spans else plain
