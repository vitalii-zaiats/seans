"""One entry point among several: look at a source's pages from the terminal.

`crawlers.run` and `crawlers.arun` are the others — that's what apps call.

This module is the only one in the package that knows an HTTP library exists,
and it imports it lazily.
"""

import argparse
import asyncio
import contextlib
import json
import sys
from types import TracebackType
from typing import Protocol

from crawlers import source as sources
from crawlers.aengine import acrawl
from crawlers.engine import crawl
from crawlers.fetching import AsyncFetcher, Fetcher
from crawlers.models import Page
from crawlers.sinks import Sink, from_spec
from crawlers.source import Source


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="crawl",
        description="Read listing pages from a registered source.",
    )
    parser.add_argument("source", nargs="?", help="source name (see --list)")
    parser.add_argument(
        "pages", type=int, nargs="?", default=1, help="how many pages to read (default: 1)"
    )
    parser.add_argument("--start", type=int, default=1, help="first page number (default: 1)")
    parser.add_argument(
        "--sink",
        help="where items go: stdout (default), memory, jsonl:<path>",
    )
    parser.add_argument(
        "--delay", type=float, default=0.5, help="pause between pages, seconds (default: 0.5)"
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="also open each item's own page — one request per item, so it's slow",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="item pages fetched at once, with --details (default: 1, one at a time)",
    )
    parser.add_argument(
        "--timeout", type=float, default=20.0, help="request timeout, seconds (default: 20)"
    )
    parser.add_argument(
        "--proxy",
        help="proxy URL, comma-separated list, or @file (default: $PROXY_URL)",
    )
    parser.add_argument("--json", action="store_true", help="print the crawl as JSON")
    parser.add_argument("--list", action="store_true", help="list registered sources and exit")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.list:
        for name in sources.names():
            print(name)
        return 0

    try:
        source = sources.get(args.source) if args.source else _only_source()
    except sources.UnknownSource as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.pages < 1 or args.start < 1:
        print("error: pages and --start must be >= 1", file=sys.stderr)
        return 2

    if args.details and not source.item_pages:
        print(f"note: {source.name} items have no page of their own", file=sys.stderr)

    if args.workers < 1:
        print("error: --workers must be >= 1", file=sys.stderr)
        return 2

    # Printing is itself a sink, so JSON output just swaps it for an in-memory one.
    sink = from_spec(args.sink or ("memory" if args.json else "stdout"))
    pages: list[Page] = []

    try:
        with contextlib.closing(sink):
            # One request at a time unless asked otherwise, in which case the
            # async engine is the one that can hold several item pages open.
            if args.workers > 1:
                found = asyncio.run(_awalk(source, args, sink, pages))
            else:
                found = _walk(source, args, sink, pages)
    except ImportError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(
            json.dumps(
                {"source": source.name, "count": found, "pages": [p.to_dict() for p in pages]},
                ensure_ascii=False,
                indent=2,
            )
        )

    return 0 if found else 1


def _walk(source: Source, args: argparse.Namespace, sink: Sink, pages: list[Page]) -> int:
    found = 0
    with _fetcher(args) as fetcher:
        for page in crawl(
            source,
            args.pages,
            args.start,
            fetcher=fetcher,
            delay=args.delay,
            details=args.details,
        ):
            found += _take(page, args, sink, pages)
    return found


async def _awalk(source: Source, args: argparse.Namespace, sink: Sink, pages: list[Page]) -> int:
    found = 0
    async with _async_fetcher(args) as fetcher:
        async for page in acrawl(
            source,
            args.pages,
            args.start,
            fetcher=fetcher,
            delay=args.delay,
            details=args.details,
            workers=args.workers,
        ):
            found += _take(page, args, sink, pages)
    return found


def _take(page: Page, args: argparse.Namespace, sink: Sink, pages: list[Page]) -> int:
    """Report one page and store it — shared, so the two walks can't drift apart."""
    pages.append(page)

    if page.error:
        print(f"page {page.number}  failed: {page.error}", file=sys.stderr)
        return 0

    for item in page.items:
        if error := item.extra.get("error"):
            print(f"{item.url}  failed: {error}", file=sys.stderr)

    if not args.json:
        print(f"page {page.number}  ({len(page.items)} items)  {page.url}")
    sink.write(page.items)
    if not args.json:
        print()

    return len(page.items)


class ManagedFetcher(Fetcher, Protocol):
    """A fetcher this CLI opens and closes.

    Wider than what the engines ask for, and declared here rather than in
    `fetching` on purpose: an engine only ever calls `fetch`, and a library that
    insisted on a context manager would turn away a perfectly good closure.
    """

    def __enter__(self) -> Fetcher: ...

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None: ...


class ManagedAsyncFetcher(AsyncFetcher, Protocol):
    """The same, awaited."""

    async def __aenter__(self) -> AsyncFetcher: ...

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None: ...


def _fetcher(args: argparse.Namespace) -> ManagedFetcher:
    """The default requester. Only the CLI needs one, so it's an optional extra."""
    try:
        from httpkit import build_fetcher, resolve_pool
    except ImportError as exc:  # pragma: no cover
        raise ImportError(
            "the CLI needs a requester: install crawlers[cli], or use the library "
            "with a fetcher of your own"
        ) from exc

    return build_fetcher(proxy=resolve_pool(args.proxy), timeout=args.timeout)


def _async_fetcher(args: argparse.Namespace) -> ManagedAsyncFetcher:
    """The awaited twin, for when --workers asks for several pages at once."""
    try:
        from httpkit import build_async_fetcher, resolve_pool
    except ImportError as exc:  # pragma: no cover
        raise ImportError(
            "the CLI needs a requester: install crawlers[cli], or use the library "
            "with a fetcher of your own"
        ) from exc

    return build_async_fetcher(proxy=resolve_pool(args.proxy), timeout=args.timeout)


def _only_source() -> Source:
    """No name given: fine while there's exactly one source, ambiguous after that."""
    names = sources.names()
    if len(names) == 1:
        return sources.get(names[0])
    raise sources.UnknownSource(f"pick a source: {', '.join(names)}")


if __name__ == "__main__":
    raise SystemExit(main())
