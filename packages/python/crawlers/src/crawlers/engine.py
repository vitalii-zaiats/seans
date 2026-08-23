"""Walks a source's pages, synchronously.

Sequencing only: which pages to read comes from `source.page_numbers`, what a
page means comes from `Page`, and how to make a request comes from the caller.
"""

import time
from collections.abc import Iterator

from crawlers.fetching import Fetcher, FetchError
from crawlers.models import Item, Page, Stats
from crawlers.sinks import Sink
from crawlers.source import Source, page_numbers


def crawl(
    source: Source,
    pages: int = 1,
    start: int = 1,
    *,
    fetcher: Fetcher,
    delay: float = 0.5,
    details: bool = False,
) -> Iterator[Page]:
    """Yield pages one request at a time.

    A page that fails to load is yielded with `error` set rather than raising, so
    one bad page doesn't end the run. Storing is the caller's job — see `run`.

    `details` opens each item's own page too, where the source has one. That's a
    request per item on top of the page itself, so it's off by default.
    """
    for index, number in enumerate(page_numbers(source, pages, start)):
        url = source.page_url(number)

        if index and delay:
            time.sleep(delay)  # don't hammer the site

        try:
            page = fetcher.fetch(url)
        except Exception as exc:  # whatever the injected requester raises
            yield Page.broken(source.name, number, url, str(exc))
            continue

        items = source.parse(page.text)
        if details and source.item_pages:
            items = [_detailed(source, item, url, fetcher=fetcher, delay=delay) for item in items]

        yield Page.of(source.name, number, url, items)


def _detailed(
    source: Source,
    item: Item,
    listing_url: str,
    *,
    fetcher: Fetcher,
    delay: float,
) -> Item:
    """The item as its own page describes it.

    A page that won't load leaves the listing item as it was, carrying the reason
    — one dead item page is no reason to drop the item, let alone the crawl.
    """
    if delay:
        time.sleep(delay)

    try:
        page = fetcher.fetch(item.url, referer=listing_url)
        detail = source.parse_item(page.text, item.url)
    except Exception as exc:  # the requester's, or a page the parser choked on
        return item.with_error(str(exc))

    return item.with_details(detail) if detail else item


def run(
    source: Source,
    pages: int = 1,
    start: int = 1,
    *,
    sink: Sink,
    fetcher: Fetcher,
    delay: float = 0.5,
    details: bool = False,
) -> Stats:
    """Same crawl, drained and summarised. What apps call."""
    stats = Stats(source=source.name)

    for page in crawl(source, pages, start, fetcher=fetcher, delay=delay, details=details):
        stats.pages += 1
        if page.error:
            stats.failed += 1
            continue
        stats.found += len(page.items)
        stats.stored += sink.write(page.items)

    return stats


__all__ = ["FetchError", "Stats", "crawl", "run"]
