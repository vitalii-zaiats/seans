"""The same walk, awaited.

Twin of `engine`: identical decisions — page numbers, what a page means, when to
give up on one — differing only in how it waits.
"""

import asyncio
from collections.abc import AsyncIterator

from crawlers.fetching import AsyncFetcher
from crawlers.models import Item, Page, Stats
from crawlers.sinks import Sink
from crawlers.source import Source, page_numbers


async def acrawl(
    source: Source,
    pages: int = 1,
    start: int = 1,
    *,
    fetcher: AsyncFetcher,
    delay: float = 0.5,
    details: bool = False,
    workers: int = 1,
) -> AsyncIterator[Page]:
    """The pages of a crawl, awaited.

    Listing pages are read one at a time, in order. `workers` is how many of a
    page's item pages may be in flight at once when `details` is on — the one
    place this twin does more than the sync engine, because it's the one place
    where waiting on several things at once is worth the complexity.
    """
    for index, number in enumerate(page_numbers(source, pages, start)):
        url = source.page_url(number)

        if index and delay:
            await asyncio.sleep(delay)

        try:
            page = await fetcher.fetch(url)
        except Exception as exc:  # whatever the injected requester raises
            yield Page.broken(source.name, number, url, str(exc))
            continue

        items = source.parse(page.text)
        if details and source.item_pages:
            items = await _adetails(
                source, items, url, fetcher=fetcher, delay=delay, workers=workers
            )

        yield Page.of(source.name, number, url, items)


async def _adetails(
    source: Source,
    items: list[Item],
    listing_url: str,
    *,
    fetcher: AsyncFetcher,
    delay: float,
    workers: int,
) -> list[Item]:
    """One page's item pages, up to `workers` of them at a time.

    The tasks start now, bounded by the gate; awaiting them in submission order
    keeps the items in the order the listing had them. `delay` is then a pause
    per worker rather than per crawl — the rate is roughly `workers / delay`.
    """
    gate = asyncio.Semaphore(max(1, workers))

    async def one(item: Item) -> Item:
        async with gate:
            return await _adetailed(source, item, listing_url, fetcher=fetcher, delay=delay)

    tasks = [asyncio.create_task(one(item)) for item in items]
    return [await task for task in tasks]


async def _adetailed(
    source: Source,
    item: Item,
    listing_url: str,
    *,
    fetcher: AsyncFetcher,
    delay: float,
) -> Item:
    """The item as its own page describes it, or as it was if that page won't load."""
    if delay:
        await asyncio.sleep(delay)

    try:
        page = await fetcher.fetch(item.url, referer=listing_url)
        detail = source.parse_item(page.text, item.url)
    except Exception as exc:  # the requester's, or a page the parser choked on
        return item.with_error(str(exc))

    return item.with_details(detail) if detail else item


async def arun(
    source: Source,
    pages: int = 1,
    start: int = 1,
    *,
    sink: Sink,
    fetcher: AsyncFetcher,
    delay: float = 0.5,
    details: bool = False,
    workers: int = 1,
) -> Stats:
    stats = Stats(source=source.name)

    async for page in acrawl(
        source, pages, start, fetcher=fetcher, delay=delay, details=details, workers=workers
    ):
        stats.pages += 1
        if page.error:
            stats.failed += 1
            continue
        stats.found += len(page.items)
        stats.stored += sink.write(page.items)

    return stats
