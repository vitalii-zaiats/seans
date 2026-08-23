"""Deciding which rows are the same film.

Four rules, and each one exists because leaving it out produced a wrong answer
on the real catalogues rather than because it sounded prudent.

1. **Three keys, weighted.** `imdb` (4), `ashdi` (2), name-and-year (1). An
   edge carries the sum, so a pair agreed by all three is applied before a pair
   held together by its name alone.
2. **An IMDb disagreement vetoes everything else.** Two rows that both name an
   IMDb id and name different ones are not the same film, whatever else
   matches. This is what keeps "Той, що біжить по лезу" apart from "…2049",
   which share an ashdi upload.
3. **An edge always crosses sources.** Two kinostrain rows are never merged
   with each other: if that catalogue holds a duplicate, that is its business
   and not something to be silently corrected here.
4. **At most one row per source in a title.** Applied greedily, strongest edge
   first. Without it a chain of three edges fuses a film with its sequel —
   transitivity does not care that the middle step was weak.

`ashdi` is the id of an *upload*, not of a film, and two catalogues can attach
one upload to different entries. That is why it is worth two rather than four,
and why rule 2 outranks it.
"""

import collections
from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass

from api.modules.titles.reading import Incoming, SourceName

#: What each key is worth when edges are ordered. Only the ordering matters,
#: not the absolute numbers — an `imdb` agreement must simply outrank any pile
#: of weaker ones.
WEIGHT = {"imdb": 4, "ashdi": 2, "name": 1}

#: How far apart two catalogues may date the same film. One year, because they
#: disagree about release and premiere often and about nothing else.
YEAR_SLACK = 1

#: The evidence a title carries when it is the only row anybody has.
SOLE = "sole"


@dataclass(frozen=True, slots=True)
class Attached:
    """One source's row, and what put it in this title."""

    row: Incoming
    #: `imdb+ashdi+name` — which keys agreed. `sole` when nothing agreed with
    #: it, because nothing else in either catalogue is this film.
    evidence: str


@dataclass(frozen=True, slots=True)
class Merged:
    """One title: at most one row per source, and why they are together."""

    rows: tuple[Attached, ...]

    @property
    def primary(self) -> Incoming:
        """Whose fields the title takes.

        The fullest row rather than the first: one catalogue writes a synopsis
        and the other a line, and a title that took the line because its source
        was listed first would be worse for no reason.
        """
        return max(self.rows, key=lambda a: _richness(a.row)).row

    @property
    def sources(self) -> frozenset[SourceName]:
        return frozenset(attached.row.source for attached in self.rows)


def _richness(row: Incoming) -> tuple[int, int, int, int]:
    return (
        len(row.description or ""),
        len(row.episodes),
        1 if row.poster_url else 0,
        1 if row.imdb_mark is not None else 0,
    )


def merge(rows: Iterable[Incoming]) -> tuple[Merged, ...]:
    """Every row, grouped into titles."""
    entries = tuple(rows)
    edges = _edges(entries)

    parent = list(range(len(entries)))
    held: list[frozenset[SourceName]] = [frozenset({entry.source}) for entry in entries]

    def root(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    evidence: dict[int, str] = {}
    for _, (left, right), why in sorted(edges, key=lambda edge: -edge[0]):
        a, b = root(left), root(right)
        if a == b or held[a] & held[b]:
            # Rule 4. Refusing here rather than repairing later is the whole of
            # why every group comes out with one row per source.
            continue
        parent[a] = b
        held[b] = held[a] | held[b]
        # Both rows carry it: for a pair, neither is the one that "was found" —
        # they were put together by the same agreement, and a later reader
        # asking why this title has a kinoukr row wants the answer on that row.
        evidence.setdefault(left, why)
        evidence.setdefault(right, why)

    groups: dict[int, list[int]] = collections.defaultdict(list)
    for index in range(len(entries)):
        groups[root(index)].append(index)

    return tuple(
        Merged(
            rows=tuple(
                Attached(row=entries[index], evidence=evidence.get(index, SOLE))
                for index in sorted(members)
            )
        )
        for members in groups.values()
    )


def _edges(entries: Sequence[Incoming]) -> list[tuple[int, tuple[int, int], str]]:
    """Every cross-source pair a key proposes, weighted, minus the vetoed."""
    found: dict[tuple[int, int], set[str]] = collections.defaultdict(set)

    by_claim: dict[tuple[str, str], list[int]] = collections.defaultdict(list)
    for index, entry in enumerate(entries):
        for claim in entry.claims:
            by_claim[(claim.kind, claim.value)].append(index)
    for (kind, _), members in by_claim.items():
        for left, right in _pairs(members, entries):
            found[(left, right)].add(kind)

    for left, right in _by_name(entries):
        found[(left, right)].add("name")

    imdb = [frozenset(c.value for c in entry.claims if c.kind == "imdb") for entry in entries]
    edges = []
    for (left, right), why in found.items():
        if imdb[left] and imdb[right] and not (imdb[left] & imdb[right]):
            continue  # Rule 2.
        edges.append((sum(WEIGHT[key] for key in why), (left, right), "+".join(sorted(why))))
    return edges


def _pairs(members: Sequence[int], entries: Sequence[Incoming]) -> Iterator[tuple[int, int]]:
    """Every cross-source pair in a bucket. Rule 3 lives here."""
    for position, left in enumerate(members):
        for right in members[position + 1 :]:
            if entries[left].source != entries[right].source:
                yield (left, right) if left < right else (right, left)


def _too_far(left: int | None, right: int | None) -> bool:
    """A year nobody stated cannot disagree with anything."""
    return left is not None and right is not None and abs(left - right) > YEAR_SLACK


def _by_name(entries: Sequence[Incoming]) -> Iterator[tuple[int, int]]:
    """Pairs whose spellings match and whose years are within `YEAR_SLACK`."""
    buckets: dict[str, list[tuple[int, int | None]]] = collections.defaultdict(list)
    for index, entry in enumerate(entries):
        for alias in entry.aliases:
            buckets[alias.folded].append((index, alias.year))

    for members in buckets.values():
        if len(members) < 2:
            continue
        for position, (left, left_year) in enumerate(members):
            for right, right_year in members[position + 1 :]:
                if entries[left].source == entries[right].source:
                    continue
                if _too_far(left_year, right_year):
                    continue
                yield (left, right) if left < right else (right, left)
