"""What the television endpoints hand back."""

from datetime import date, datetime, timedelta

from pydantic import BaseModel
from sweet_tv import Catalogue, Category, Channel, Programme, Schedule, Stream

from api.modules.tv.ports import Relay


class CategoryOut(BaseModel):
    id: int
    title: str
    #: Absent on the "all" pseudo-category, which has no page of its own.
    slug: str | None
    is_all: bool

    @classmethod
    def of(cls, category: Category) -> "CategoryOut":
        return cls(
            id=category.id,
            title=category.title,
            slug=category.slug,
            is_all=category.is_all,
        )


class ChannelOut(BaseModel):
    id: int
    slug: str
    name: str
    #: Rewritten to https. The catalogue hands these out as plain http, which a
    #: page on https refuses as mixed content.
    icon_url: str | None
    banner_url: str | None
    colour: str | None
    categories: list[int]
    #: How many days back the archive goes; `0` for live only.
    catchup_days: int
    #: What is on right now, as the list itself reports it — no times. It comes
    #: free with the list, so a whole grid can say what is on without one
    #: request per channel.
    now_playing: str | None

    @classmethod
    def of(cls, channel: Channel) -> "ChannelOut":
        return cls(
            id=channel.id,
            slug=channel.slug,
            name=channel.name,
            icon_url=channel.icon_url,
            banner_url=channel.banner_url,
            colour=channel.colour,
            categories=list(channel.categories),
            catchup_days=channel.catchup_days,
            now_playing=channel.now_playing,
        )


class ChannelList(BaseModel):
    items: list[ChannelOut]
    #: In the order the site shows them, which is not the order they arrive in.
    categories: list[CategoryOut]

    @classmethod
    def of(cls, catalogue: Catalogue) -> "ChannelList":
        return cls(
            items=[ChannelOut.of(one) for one in catalogue.channels],
            categories=[CategoryOut.of(one) for one in catalogue.categories],
        )


class ProgrammeOut(BaseModel):
    id: int
    title: str
    #: Absolute, and aware. The upstream sends unix seconds and says nothing
    #: about a zone; whoever draws a grid decides which clock to show it on.
    start: datetime
    stop: datetime
    #: Whether the archive holds it. False for programmes rights do not cover.
    available: bool

    @classmethod
    def of(cls, programme: Programme) -> "ProgrammeOut":
        return cls(
            id=programme.id,
            title=programme.title,
            start=programme.start,
            stop=programme.stop,
            available=programme.available,
        )


class ScheduleOut(BaseModel):
    channel_id: int
    day: date
    items: list[ProgrammeOut]

    @classmethod
    def of(cls, channel_id: int, day: date, schedule: Schedule) -> "ScheduleOut":
        return cls(
            channel_id=channel_id,
            day=day,
            items=[ProgrammeOut.of(one) for one in schedule.programmes],
        )


class StreamOut(BaseModel):
    """A lease, not an address.

    It carries a session and goes stale after `refresh_in`. Store the channel id
    and ask again; do not store the URL.
    """

    channel_id: int
    url: str
    #: The same stream over plain http. On Android it is the one that works: the
    #: stitching host presents a chain ending in the old Go Daddy Class 2 root
    #: signed with SHA-1, which Android rejects outright.
    plain_url: str | None
    #: Without the ad stitching, offered for casting. Undocumented upstream.
    direct_url: str | None
    refresh_in: int

    @classmethod
    def of(cls, channel_id: int, stream: Stream, *, through: Relay | None = None) -> "StreamOut":
        """The lease, optionally pointed at a relay.

        `through` is set for a client that cannot fetch the stream host itself —
        a browser, which the host's CORS policy shuts out. Everything else gets
        the addresses untouched and talks to the host directly, which is both
        faster and none of our bandwidth.
        """
        relay = through or (lambda url: url)
        return cls(
            channel_id=channel_id,
            url=relay(stream.url),
            plain_url=None if stream.plain_url is None else relay(stream.plain_url),
            direct_url=None if stream.direct_url is None else relay(stream.direct_url),
            refresh_in=int(stream.refresh_after / timedelta(seconds=1)),
        )
