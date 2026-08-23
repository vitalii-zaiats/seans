"""Every kinostrain title, raw, into jsonl.

Raw on purpose: `kinostrain.ContentCard` refuses a null `originalName` and a
null `posterUrl`, and upstream sends both. Parsing here would lose exactly the
rows that prove the parser wrong. What lands is the `data` object as it came,
one JSON document per line.

    uv run python pull_raw.py catalog     slugs, from /catalog
    uv run python pull_raw.py content     one /content/{slug} per slug
    uv run python pull_raw.py seasons     the seasons a serial does not fill in

Every stage resumes: what is already in the file is not asked for again.
"""

import asyncio
import json
import sys
import time
from pathlib import Path

import httpx

BASE = "https://api.kinostrain.com/api"
AT_ONCE = 6
TRIES = 4

# The browser's, as captured — minus the three a client does not get to set.
# `Accept-Encoding` is httpx's business: it advertises what it can actually
# decode, and the captured list promises zstd, which it cannot. `Connection`
# and `TE` are hop-by-hop and belong to the connection, not the request.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:154.0) Gecko/20100101 Firefox/154.0"
    ),
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://kinostrain.com/",
    "Origin": "https://kinostrain.com",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-site",
    "Sec-GPC": "1",
    "DNT": "1",
}

CATALOG = Path("kinostrain_catalog.jsonl")
CONTENT = Path("kinostrain_content.jsonl")
SEASONS = Path("kinostrain_seasons.jsonl")


def already(path: Path, key: str) -> set[str]:
    """What a previous run finished, so a resume asks for the rest."""
    if not path.exists():
        return set()
    done = set()
    with path.open(encoding="utf-8") as lines:
        for line in lines:
            try:
                done.add(str(json.loads(line)[key]))
            except (json.JSONDecodeError, KeyError):
                continue
    return done


class Puller:
    def __init__(self, client: httpx.AsyncClient, out: Path) -> None:
        self.client = client
        self.out = out
        self.gate = asyncio.Semaphore(AT_ONCE)
        self.lock = asyncio.Lock()
        self.done = 0
        self.failed: list[tuple[str, str]] = []

    async def get(self, path: str, params: dict[str, str] | None = None) -> dict | None:
        async with self.gate:
            for attempt in range(TRIES):
                try:
                    answer = await self.client.get(f"{BASE}{path}", params=params)
                    if answer.status_code == 429 or answer.status_code >= 500:
                        raise httpx.HTTPError(f"HTTP {answer.status_code}")
                    answer.raise_for_status()
                    return answer.json()
                except Exception as exc:
                    if attempt == TRIES - 1:
                        self.failed.append((path, f"{type(exc).__name__}: {exc}"))
                        return None
                    await asyncio.sleep(1.5 * (attempt + 1))
        return None

    async def write(self, row: dict) -> None:
        line = json.dumps(row, ensure_ascii=False)
        # Appended as each one lands rather than all at the end: this runs for
        # minutes, and a run that dies at minute six should not start over.
        async with self.lock:
            with self.out.open("a", encoding="utf-8") as out:
                out.write(line + "\n")
            self.done += 1
            if self.done % 200 == 0:
                print(f"  {self.done} written", flush=True)


async def catalog(client: httpx.AsyncClient) -> None:
    puller = Puller(client, CATALOG)
    first = await puller.get("/catalog", {"page": "1"})
    if first is None:
        sys.exit("could not read page 1")
    total = first["meta"]["totalPages"]
    print(f"{first['meta']['total']} titles over {total} pages")

    seen = already(CATALOG, "slug")

    async def page(number: int) -> None:
        got = await puller.get("/catalog", {"page": str(number)})
        if got is None:
            return
        for card in got["data"]:
            if card["slug"] not in seen:
                seen.add(card["slug"])
                await puller.write(card)

    for card in first["data"]:
        if card["slug"] not in seen:
            seen.add(card["slug"])
            await puller.write(card)
    await asyncio.gather(*(page(n) for n in range(2, total + 1)))
    report(puller, len(seen))


async def content(client: httpx.AsyncClient) -> None:
    slugs = [json.loads(line)["slug"] for line in CATALOG.read_text(encoding="utf-8").splitlines()]
    done = already(CONTENT, "slug")
    todo = [slug for slug in slugs if slug not in done]
    print(f"{len(slugs)} slugs, {len(done)} already here, {len(todo)} to fetch")

    puller = Puller(client, CONTENT)

    async def one(slug: str) -> None:
        got = await puller.get(f"/content/{slug}")
        if got is not None:
            await puller.write(got["data"])

    await asyncio.gather(*(one(slug) for slug in todo))
    report(puller, len(todo))


async def seasons(client: httpx.AsyncClient) -> None:
    """A serial lists every season and fills in one. This asks for the rest.

    "Filled" is decided by the players, not by the episode list: a film has one
    season and no episodes at all, and asking for it again would be four
    thousand requests that can only return what is already on disk.
    """
    wanted: list[tuple[str, int]] = []
    with CONTENT.open(encoding="utf-8") as lines:
        for line in lines:
            title = json.loads(line)
            for season in title.get("seasons") or []:
                if not (season.get("playerData") or season.get("players")):
                    wanted.append((title["slug"], season["number"]))

    done = already(SEASONS, "key")
    todo = [(slug, n) for slug, n in wanted if f"{slug}#{n}" not in done]
    print(f"{len(wanted)} unfilled seasons, {len(todo)} to fetch")

    puller = Puller(client, SEASONS)

    async def one(slug: str, number: int) -> None:
        got = await puller.get(f"/content/{slug}", {"season": str(number)})
        if got is not None:
            await puller.write(
                {"key": f"{slug}#{number}", "slug": slug, "season": number, "data": got["data"]}
            )

    await asyncio.gather(*(one(slug, n) for slug, n in todo))
    report(puller, len(todo))


def report(puller: Puller, expected: int) -> None:
    print(f"{puller.done}/{expected} written to {puller.out}")
    if puller.failed:
        print(f"{len(puller.failed)} failed:")
        for path, why in puller.failed[:20]:
            print(f"  {path}  {why}")


async def main() -> None:
    stage = sys.argv[1] if len(sys.argv) > 1 else "catalog"
    started = time.perf_counter()
    async with httpx.AsyncClient(
        headers=HEADERS, timeout=httpx.Timeout(30.0, connect=15.0), follow_redirects=True
    ) as client:
        await {"catalog": catalog, "content": content, "seasons": seasons}[stage](client)
    print(f"{stage}: {time.perf_counter() - started:.0f}s")


asyncio.run(main())
