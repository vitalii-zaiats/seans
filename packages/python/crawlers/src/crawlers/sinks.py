"""Where crawled items end up.

A sink is anything with `write(items)` and `close()`. Add one by writing a class
with those two methods; `from_spec` is the string form the CLI and apps use.
"""

import json
import sqlite3
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol, runtime_checkable

from crawlers.models import Item


@runtime_checkable
class Sink(Protocol):
    def write(self, items: Sequence[Item]) -> int:
        """Persist items, return how many were actually new."""

    def close(self) -> None: ...


class MemorySink:
    """Keeps everything in a list — for apps that want the data in-process."""

    def __init__(self) -> None:
        self.items: list[Item] = []

    def write(self, items: Sequence[Item]) -> int:
        self.items.extend(items)
        return len(items)

    def close(self) -> None:
        pass


class StdoutSink:
    """Prints as it goes. This is the 'just let me look at it' sink."""

    def write(self, items: Sequence[Item]) -> int:
        for item in items:
            print(f"  {item.title}")
            print(f"    {item.url}")
            print(f"    {item.poster or '(no poster)'}")
        return len(items)

    def close(self) -> None:
        pass


class JsonlSink:
    """Appends one JSON object per line, skipping URLs the file already holds.

    Re-running a crawl is therefore safe: only genuinely new items get appended.
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.seen = self._existing_urls()
        self.written = 0
        self.skipped = 0
        self._handle = self.path.open("a", encoding="utf-8")

    def _existing_urls(self) -> set[str]:
        if not self.path.exists():
            return set()

        urls = set()
        with self.path.open(encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    urls.add(json.loads(line)["url"])
                except (json.JSONDecodeError, KeyError):
                    continue  # a half-written line shouldn't kill the run
        return urls

    def write(self, items: Sequence[Item]) -> int:
        new = 0
        for item in items:
            if item.url in self.seen:
                self.skipped += 1
                continue
            self.seen.add(item.url)
            self._handle.write(json.dumps(item.to_dict(), ensure_ascii=False) + "\n")
            new += 1
        self._handle.flush()
        self.written += new
        return new

    def close(self) -> None:
        self._handle.close()


class SqliteSink:
    """One row per item, keyed by URL, so re-running a crawl is idempotent.

    `first_seen` is only set on insert — it stays the moment the item showed up.
    """

    SCHEMA = """
        CREATE TABLE IF NOT EXISTS items (
            url        TEXT PRIMARY KEY,
            source     TEXT NOT NULL,
            title      TEXT NOT NULL,
            poster     TEXT,
            extra      TEXT,
            first_seen TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS items_source ON items (source);
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path)
        self.connection.executescript(self.SCHEMA)
        self.connection.commit()
        self.written = 0
        self.skipped = 0

    def write(self, items: Sequence[Item]) -> int:
        now = datetime.now(UTC).isoformat(timespec="seconds")
        new = 0

        with self.connection:  # one transaction per page
            for item in items:
                cursor = self.connection.execute(
                    """
                    INSERT INTO items (url, source, title, poster, extra, first_seen)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(url) DO NOTHING
                    """,
                    (
                        item.url,
                        item.source,
                        item.title,
                        item.poster,
                        json.dumps(item.extra, ensure_ascii=False) if item.extra else None,
                        now,
                    ),
                )
                if cursor.rowcount:
                    new += 1
                else:
                    self.skipped += 1

        self.written += new
        return new

    def close(self) -> None:
        self.connection.close()


def from_spec(spec: str) -> Sink:
    """`stdout` | `memory` | `jsonl:<path>` | `sqlite:<path>` | a bare path."""
    if spec in ("stdout", "-"):
        return StdoutSink()
    if spec == "memory":
        return MemorySink()

    kind, separator, target = spec.partition(":")
    if target:
        if kind == "jsonl":
            return JsonlSink(Path(target))
        if kind == "sqlite":
            return SqliteSink(Path(target))
    elif not separator:
        # A bare path is allowed when the extension says what it is.
        if spec.endswith(".jsonl"):
            return JsonlSink(Path(spec))
        if spec.endswith((".db", ".sqlite", ".sqlite3")):
            return SqliteSink(Path(spec))

    raise ValueError(f"unknown sink {spec!r} — use stdout, memory, jsonl:<path> or sqlite:<path>")
