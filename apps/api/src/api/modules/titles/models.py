"""One catalogue out of several, and the evidence that says which is which.

Two catalogues describe the same films with different slugs, different spellings
and different years, and neither has an id the other has ever heard of. What
this schema is for is holding the *answer* to "these two rows are the same
film" — together with what made us believe it, so that a wrong answer can be
found later rather than argued about.

The shape is one aggregate and four things hanging off it:

    Title          what a person searches for and picks
      Identifier   a claim of identity strong enough to be unique on its own
      Alias        how it is spelled, for when no strong claim exists
      Source       who told us, and what they call it
      Stream       what actually plays

**No duplicates is a constraint, not a habit.** Three unique constraints do the
whole of it, and each one refuses a different mistake:

- `Identifier(kind, value)` — one IMDb id belongs to one title, forever. A
  second import that meets `tt0083658` finds the title rather than making one.
- `Source(source, external_id)` — one kinostrain slug lands once. Re-running
  the importer updates rather than doubles.
- `Source(title_id, source)` — **a title holds at most one row per source.**
  This is the interesting one: it is the invariant the matcher enforces while
  running, written down so a later import cannot break it. Without it, one bad
  match propagates: "Рейд 2" joins "Рейд: Спокута" and the two are one film
  from then on.

`Season` and `Episode` come from whoever bothered to enumerate them —
kinostrain lists every episode as its own player, kinoukr hands over one link
for a whole serial and lets the player sort it out. That is why `Stream` points
at a `Title` always and at an `Episode` only when somebody said which one.
"""

from datetime import datetime
from enum import StrEnum

from sqlalchemy import (
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.core.models import Base, TimestampMixin, UTCDateTime, utcnow


class Source(StrEnum):
    """Where a row came from. Lower-case because SQLAlchemy persists an enum by
    its *name* and the wire value is the lower-case one."""

    kinostrain = "kinostrain"
    kinoukr = "kinoukr"


class Kind(StrEnum):
    film = "film"
    serial = "serial"


class IdentifierKind(StrEnum):
    """Claims strong enough to be unique on their own.

    `imdb` is canonical and comes from both catalogues — kinoukr states it,
    kinostrain hides it inside the `vsembed` player URL. `ashdi` is the id of an
    upload rather than of a film, which is weaker but still decisive: two
    catalogues pointing at the same file are describing the same thing.
    """

    imdb = "imdb"
    ashdi = "ashdi"


class Host(StrEnum):
    """Who serves the bytes. Not the same axis as `Source`: kinoukr and
    kinostrain both hand out ashdi links."""

    ashdi = "ashdi"
    tortuga = "tortuga"
    vsembed = "vsembed"


class Title(Base, TimestampMixin):
    """One film or one serial, whoever happens to carry it."""

    __tablename__ = "titles"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Ours, not either catalogue's. Both of theirs live on `TitleSource`, and a
    # title that loses a source should not lose its address.
    slug: Mapped[str] = mapped_column(String(200), unique=True, index=True)

    kind: Mapped[Kind] = mapped_column(Enum(Kind, name="title_kind", native_enum=False, length=16))
    name: Mapped[str] = mapped_column(String(300))
    original_name: Mapped[str | None] = mapped_column(String(300), nullable=True)
    year_start: Mapped[int | None] = mapped_column(Integer, nullable=True)
    year_end: Mapped[int | None] = mapped_column(Integer, nullable=True)

    poster_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    imdb_mark: Mapped[float | None] = mapped_column(Float, nullable=True)
    imdb_votes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # What a shortlist is ordered by when a query is ambiguous — and on a
    # keypad every query is. Derived from the two above plus recency, stored
    # rather than computed so the search does arithmetic on nothing.
    rank: Mapped[float] = mapped_column(Float, default=0.0, server_default="0")

    identifiers: Mapped[list["TitleIdentifier"]] = relationship(
        back_populates="title", cascade="all, delete-orphan"
    )
    aliases: Mapped[list["TitleAlias"]] = relationship(
        back_populates="title", cascade="all, delete-orphan"
    )
    sources: Mapped[list["TitleSource"]] = relationship(
        back_populates="title", cascade="all, delete-orphan"
    )
    seasons: Mapped[list["Season"]] = relationship(
        back_populates="title", cascade="all, delete-orphan"
    )
    streams: Mapped[list["Stream"]] = relationship(
        back_populates="title", cascade="all, delete-orphan"
    )
    keys: Mapped[list["TitleKey"]] = relationship(
        back_populates="title", cascade="all, delete-orphan"
    )


class TitleIdentifier(Base):
    """A claim that is decisive on its own, and therefore unique."""

    __tablename__ = "title_identifiers"
    __table_args__ = (
        # The whole of the no-duplicates guarantee, in one line: an id belongs
        # to one title. An importer that meets it again finds that title; an
        # importer that tries to give it to a second one is refused by the
        # database rather than by somebody's memory of the rule.
        UniqueConstraint("kind", "value", name="uq_identifier"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    title_id: Mapped[int] = mapped_column(ForeignKey("titles.id", ondelete="CASCADE"), index=True)
    kind: Mapped[IdentifierKind] = mapped_column(
        Enum(IdentifierKind, name="identifier_kind", native_enum=False, length=16)
    )
    #: `tt0083658`, or `vod/133070` — the path kept, because `serial/6959` and
    #: `vod/6959` are different uploads and collapsing them merges two films.
    value: Mapped[str] = mapped_column(String(120))

    title: Mapped[Title] = relationship(back_populates="identifiers")


class TitleAlias(Base):
    """How a title is spelled, folded for comparison.

    Deliberately *not* unique: two different films are allowed to share a name
    and a year, and a schema that forbade it would be lying. This is the key of
    last resort, and the matcher treats it as such.
    """

    __tablename__ = "title_aliases"
    __table_args__ = (
        UniqueConstraint("title_id", "folded", "year", name="uq_alias"),
        Index("ix_alias_lookup", "folded", "year"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    title_id: Mapped[int] = mapped_column(ForeignKey("titles.id", ondelete="CASCADE"), index=True)
    #: Lower-cased, accents folded, punctuation gone. A name written
    #: `Хвиля / Die Welle` contributes two aliases, because either half is what
    #: the other catalogue might have chosen.
    folded: Mapped[str] = mapped_column(String(200))
    year: Mapped[int | None] = mapped_column(Integer, nullable=True)

    title: Mapped[Title] = relationship(back_populates="aliases")


class TitleSource(Base, TimestampMixin):
    """One catalogue's version of this title."""

    __tablename__ = "title_sources"
    __table_args__ = (
        UniqueConstraint("source", "external_id", name="uq_source_row"),
        UniqueConstraint("title_id", "source", name="uq_one_row_per_source"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    title_id: Mapped[int] = mapped_column(ForeignKey("titles.id", ondelete="CASCADE"), index=True)
    source: Mapped[Source] = mapped_column(
        Enum(Source, name="title_source", native_enum=False, length=32)
    )
    #: Their id, their way: a slug for kinostrain, a numeric id for kinoukr.
    external_id: Mapped[str] = mapped_column(String(200))
    external_url: Mapped[str | None] = mapped_column(String(500), nullable=True)

    # What they call it, kept even when it disagrees with the title's own name.
    # This is what makes a bad merge findable afterwards: two rows that spell
    # the same film differently are a question, not a contradiction.
    name: Mapped[str] = mapped_column(String(300))
    year: Mapped[int | None] = mapped_column(Integer, nullable=True)

    #: Which keys agreed when this row was attached — `imdb+ashdi+name`. A
    #: title held together by `name` alone is one to look at again; on the
    #: current data there are 213 of those and 1500 of the other kind.
    evidence: Mapped[str] = mapped_column(String(64))
    fetched_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)

    title: Mapped[Title] = relationship(back_populates="sources")


class Season(Base):
    __tablename__ = "seasons"
    __table_args__ = (UniqueConstraint("title_id", "number", name="uq_season"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    title_id: Mapped[int] = mapped_column(ForeignKey("titles.id", ondelete="CASCADE"), index=True)
    number: Mapped[int] = mapped_column(Integer)
    name: Mapped[str | None] = mapped_column(String(300), nullable=True)

    title: Mapped[Title] = relationship(back_populates="seasons")
    episodes: Mapped[list["Episode"]] = relationship(
        back_populates="season", cascade="all, delete-orphan"
    )


class Episode(Base):
    __tablename__ = "episodes"
    __table_args__ = (UniqueConstraint("season_id", "number", name="uq_episode"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    season_id: Mapped[int] = mapped_column(ForeignKey("seasons.id", ondelete="CASCADE"), index=True)
    number: Mapped[int] = mapped_column(Integer)
    name: Mapped[str | None] = mapped_column(String(300), nullable=True)

    season: Mapped[Season] = relationship(back_populates="episodes")
    streams: Mapped[list["Stream"]] = relationship(
        back_populates="episode", cascade="all, delete-orphan"
    )


class Stream(Base, TimestampMixin):
    """A playable address.

    `episode_id` is null far more often than it looks like it should be, and
    that is the data rather than a gap: kinoukr hands over one `serial/6959`
    for an entire show and lets the player deal with the episodes. Forcing an
    episode row for it would be inventing one.

    Unique per title rather than globally: two sources offering the same ashdi
    upload for the same film is exactly the duplicate worth collapsing, while
    the same upload turning up under a *different* title is a contradiction the
    identifier table should be the one to raise.
    """

    __tablename__ = "streams"
    __table_args__ = (
        UniqueConstraint("title_id", "host", "external_id", name="uq_stream"),
        Index("ix_stream_external", "host", "external_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    title_id: Mapped[int] = mapped_column(ForeignKey("titles.id", ondelete="CASCADE"), index=True)
    episode_id: Mapped[int | None] = mapped_column(
        ForeignKey("episodes.id", ondelete="CASCADE"), nullable=True, index=True
    )
    host: Mapped[Host] = mapped_column(Enum(Host, name="stream_host", native_enum=False, length=32))
    #: `vod/133070`, `serial/6959` — the same string an `ashdi` identifier
    #: carries, so the two can be compared without parsing a URL twice.
    external_id: Mapped[str] = mapped_column(String(120))
    url: Mapped[str] = mapped_column(String(500))
    #: The dub, as the catalogue names it: `1+1`, `ТЕТ`, `Багатоголосий
    #: закадровий`. What a picker shows, and the only thing telling two
    #: otherwise identical streams apart.
    label: Mapped[str | None] = mapped_column(String(200), nullable=True)
    offered_by: Mapped[Source] = mapped_column(
        Enum(Source, name="stream_source", native_enum=False, length=32)
    )

    title: Mapped[Title] = relationship(back_populates="streams")
    episode: Mapped["Episode | None"] = relationship(back_populates="streams")


#: How much of a code is worth keeping. Sixty-four digits is a sixty-four
#: letter title, and a query that long does not exist — the index answers
#: prefixes, and a prefix nobody will ever type is a prefix worth truncating.
KEY_LENGTH = 64


class TitleKey(Base):
    """The keypad index: one row per digit sequence that finds this title.

    A row per word start, so `489` finds "Family Guy" without the first word —
    see `packages/python/t9`, which builds these and which the box uses to
    build the same ones for a query.

    **Queried as a range, never as `LIKE`.** `code >= '489' AND code < '48:'`
    is the same answer and it uses a plain btree index on both dialects, where
    `LIKE 'code%'` needs `text_pattern_ops` on Postgres and gets a sequential
    scan without it. `:` is the character after `9`, so no code can fall inside
    the bound by accident.
    """

    __tablename__ = "title_keys"
    __table_args__ = (
        UniqueConstraint("title_id", "code", name="uq_title_key"),
        Index("ix_title_key_code", "code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    title_id: Mapped[int] = mapped_column(ForeignKey("titles.id", ondelete="CASCADE"), index=True)
    code: Mapped[str] = mapped_column(String(KEY_LENGTH))

    title: Mapped[Title] = relationship(back_populates="keys")
