"""The one interface a site has to implement, plus the registry that finds it.

Adding a site means dropping a module into `crawlers/sources/` with a class that
subclasses `Source` and carries `@register`. Nothing else has to be touched —
the package imports everything in that folder on startup.
"""

from abc import ABC, abstractmethod
from typing import ClassVar

from crawlers.models import Item

REGISTRY: dict[str, type["Source"]] = {}


class UnknownSource(LookupError):
    """Asked for a source that isn't registered. Plain LookupError, so that
    printing it doesn't wrap the message in quotes the way KeyError does."""


class Source(ABC):
    """A listing on one site — paginated, or a single document like a sitemap."""

    name: ClassVar[str]

    # What language the audio on this site is in, as an ISO 639-1 code.
    #
    # Nothing downstream can work this out for itself: HLS carries no language
    # tag on these streams, and a dub's name is a studio ("Le Doyen") or a
    # technique ("Багатоголосий закадровий"), never a language. The site knows,
    # because a site like this one publishes in one language; so the site's
    # crawler is where that fact is written down.
    #
    # None means nobody has said, which the seeder treats as "don't claim to
    # know" rather than as a default.
    language: ClassVar[str | None] = None

    # False means there is exactly one document to read; the engine then ignores
    # the page count instead of fetching the same URL over and over.
    paginated: ClassVar[bool] = True

    # True means each listed item has a page of its own worth opening — see
    # `parse_item`. It costs a request per item, so the engines only follow those
    # when the caller asks for details.
    item_pages: ClassVar[bool] = False

    @abstractmethod
    def page_url(self, number: int) -> str:
        """Absolute URL of listing page `number` (1-based)."""

    @abstractmethod
    def parse(self, html: str) -> list[Item]:
        """Items on one listing page, in document order."""

    def parse_item(self, html: str, url: str) -> Item | None:
        """What an item's own page adds, for sources that set `item_pages`.

        The engines merge the result over the listing item, so returning only
        what the page actually said is enough. None means this HTML wasn't an
        item page at all — a 404, a section index — and the listing item stands.
        """
        return None


def page_numbers(source: Source, pages: int, start: int) -> list[int]:
    """Which pages to walk. Shared by both engines so they can't disagree.

    A source that isn't paginated has exactly one document; asking for more would
    just refetch it.
    """
    if not source.paginated:
        return [1]
    return [start + offset for offset in range(max(0, pages))]


def register(cls: type[Source]) -> type[Source]:
    if not getattr(cls, "name", None):
        raise ValueError(f"{cls.__name__} needs a `name`")
    if cls.name in REGISTRY and REGISTRY[cls.name] is not cls:
        raise ValueError(f"two sources claim the name {cls.name!r}")
    REGISTRY[cls.name] = cls
    return cls


def get(name: str) -> Source:
    _load()
    if name not in REGISTRY:
        raise UnknownSource(f"unknown source {name!r} — have: {', '.join(names())}")
    return REGISTRY[name]()


def names() -> list[str]:
    _load()
    return sorted(REGISTRY)


def _load() -> None:
    """Import every module under `crawlers.sources` so decorators run."""
    import importlib
    import pkgutil

    import crawlers.sources as package

    for module in pkgutil.iter_modules(package.__path__):
        importlib.import_module(f"{package.__name__}.{module.name}")
