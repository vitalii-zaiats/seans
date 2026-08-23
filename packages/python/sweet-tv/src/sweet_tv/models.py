"""Everything the service returns."""

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sweet_tv.jsonread import (
    JsonMap,
    bool_or,
    int_list,
    int_or,
    list_of,
    map_or_none,
    require_int,
    str_or,
    str_or_none,
    text_or_none,
)
from sweet_tv.site import secure

#: The catch-all every channel belongs to. It is the one category without a page
#: of its own, and the only one with no slug.
ALL_CATEGORY = 1000


@dataclass(frozen=True, slots=True)
class Channel:
    """One free channel."""

    #: What `open_stream` wants. The slug is only ever part of a URL.
    id: int
    slug: str
    name: str
    #: Rewritten to https — the catalogue hands these out as plain http, which a
    #: page on https refuses as mixed content.
    icon_url: str | None = None
    banner_url: str | None = None
    #: The channel's own accent, `#23D3DC`, as the catalogue writes it.
    colour: str | None = None
    #: Category ids. A channel belongs to several, and `1000` means "all".
    categories: tuple[int, ...] = ()
    #: Whether it opens without an account. Everything on the free list does.
    free_to_watch: bool = True
    #: How many days back the archive goes. `0` for live only.
    catchup_days: int = 0
    #: Whatever is on right now, as the list itself reports it — no times.
    #: Worth having: it comes free with the list, so a whole grid can say what
    #: is on without one request per channel.
    now_playing: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "Channel":
        owner = "Channel"
        return cls(
            id=require_int(json, "id", owner=owner),
            slug=str_or(json, "slug"),
            name=str_or(json, "name") or str_or(json, "title"),
            icon_url=secure(
                str_or_none(json, "icon_v2_url") or str_or_none(json, "icon_small_url")
            ),
            banner_url=secure(str_or_none(json, "banner_url")),
            colour=str_or_none(json, "colour"),
            categories=int_list(json, "category"),
            free_to_watch=bool_or(json, "available_without_auth"),
            catchup_days=int_or(json, "catchup_duration") if bool_or(json, "catchup") else 0,
            now_playing=text_or_none(json, "epg_now"),
        )

    @property
    def has_catchup(self) -> bool:
        return self.catchup_days > 0


@dataclass(frozen=True, slots=True)
class Category:
    """A grouping the catalogue offers as a chip."""

    id: int
    title: str
    #: Absent on the "all" pseudo-category.
    slug: str | None = None
    #: What the site sorts them by — not the order they arrive in.
    order: int = 0

    @classmethod
    def from_json(cls, json: JsonMap) -> "Category":
        owner = "Category"
        return cls(
            id=require_int(json, "id", owner=owner),
            title=str_or(json, "title") or str_or(json, "caption"),
            slug=str_or_none(json, "slug"),
            order=int_or(json, "order"),
        )

    @property
    def is_all(self) -> bool:
        return self.id == ALL_CATEGORY


@dataclass(frozen=True, slots=True)
class Catalogue:
    """The whole free list, in one answer."""

    channels: tuple[Channel, ...] = ()
    #: In the order the site shows them, which is not the order they arrive in.
    categories: tuple[Category, ...] = ()

    @classmethod
    def from_json(cls, json: JsonMap) -> "Catalogue":
        return cls(
            channels=list_of(json, "channels", Channel.from_json),
            categories=tuple(
                sorted(list_of(json, "categories", Category.from_json), key=lambda c: c.order)
            ),
        )

    def in_category(self, category_id: int) -> tuple[Channel, ...]:
        return tuple(one for one in self.channels if category_id in one.categories)

    def by_id(self, channel_id: int) -> Channel | None:
        return next((one for one in self.channels if one.id == channel_id), None)


@dataclass(frozen=True, slots=True)
class Programme:
    """One programme in a channel's day."""

    id: int
    title: str
    #: The API sends unix seconds and says nothing about a zone. Kept as aware
    #: UTC here; whoever draws a grid decides which clock to show it on.
    start: datetime
    stop: datetime
    #: Whether the archive holds it. False for programmes rights do not cover.
    available: bool = True

    @classmethod
    def from_json(cls, json: JsonMap) -> "Programme":
        return cls(
            id=int_or(json, "id"),
            title=text_or_none(json, "text") or "",
            start=_moment(int_or(json, "time_start")),
            stop=_moment(int_or(json, "time_stop")),
            available=bool_or(json, "available", fallback=True),
        )

    @property
    def length(self) -> timedelta:
        return self.stop - self.start

    def is_on_at(self, moment: datetime) -> bool:
        return self.start <= moment < self.stop

    def progress_at(self, moment: datetime) -> float:
        """0–1 through this programme, clamped. Where the bar under "now" comes
        from."""
        total = self.length.total_seconds()
        if total <= 0:
            return 0.0
        return min(1.0, max(0.0, (moment - self.start).total_seconds() / total))


@dataclass(frozen=True, slots=True)
class Schedule:
    """A channel's programmes for one day, in order."""

    programmes: tuple[Programme, ...] = ()

    def on_at(self, moment: datetime) -> Programme | None:
        """What is on, or `None` outside the day this covers."""
        return next((one for one in self.programmes if one.is_on_at(moment)), None)

    def after(self, moment: datetime) -> Programme | None:
        """What follows.

        `None` inside the last programme of the day — the next one belongs to
        tomorrow's answer, and this does not stitch two days together behind the
        caller's back.
        """
        for index, one in enumerate(self.programmes):
            if one.is_on_at(moment):
                return self.programmes[index + 1] if index + 1 < len(self.programmes) else None
        # Between programmes, or before the first: the next one to start.
        return next((one for one in self.programmes if one.start > moment), None)

    def __len__(self) -> int:
        return len(self.programmes)

    def __iter__(self) -> Iterator[Programme]:
        return iter(self.programmes)


@dataclass(frozen=True, slots=True)
class Stream:
    """A lease on a channel's stream, not an address.

    It carries a session, points at an ad-stitching host rather than at
    sweet.tv, and goes stale after `refresh_after`. Store the channel id and ask
    again; do not store this.
    """

    url: str
    stream_id: int = 0
    #: How long before the lease should be renewed. Five minutes in every answer
    #: seen so far.
    refresh_after: timedelta = timedelta(minutes=5)
    #: The same stream over plain http, built from the `http_stream` block.
    #:
    #: Not a fallback to reach for lightly, but on Android it is the one that
    #: works: the stitching host presents a chain ending in the old Go Daddy
    #: Class 2 root signed with SHA-1, and Android rejects the whole chain over
    #: it even though a modern root is already in there. Desktop clients accept
    #: the same chain, which is why it only shows up on a box.
    plain_url: str | None = None
    #: The same stream without the ad stitching, offered for casting. Present in
    #: every captured answer, undocumented, not something to rely on.
    direct_url: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "Stream":
        return cls(
            url=str_or(json, "url"),
            stream_id=int_or(json, "stream_id"),
            refresh_after=timedelta(seconds=int_or(json, "update_interval", 300)),
            plain_url=_plain(map_or_none(json, "http_stream")),
            direct_url=str_or_none(json, "chrome_cast_url"),
        )


def _moment(seconds: int) -> datetime:
    return datetime.fromtimestamp(seconds, tz=UTC)


def _plain(host_block: JsonMap | None) -> str | None:
    """`http://host[:port]/path?query` out of the `http_stream` block."""
    if host_block is None:
        return None
    host = map_or_none(host_block, "host")
    path = str_or_none(host_block, "url")
    if host is None or path is None:
        return None
    address = str_or_none(host, "address")
    if address is None:
        return None
    port = int_or(host, "port", 80)
    return f"http://{address}{'' if port == 80 else f':{port}'}{path}"
