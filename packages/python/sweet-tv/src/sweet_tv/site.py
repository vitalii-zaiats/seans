"""Where the three halves of this service live.

Three hosts, three jobs, and they are not interchangeable — which is the whole
reason this is a value rather than a constant:

    sweet.tv           the catalogue. **No CORS headers at all**, so a browser
                       cannot read it and something server-side has to.
    api.sweet.tv       opens streams. Answers `access-control-allow-origin: *`.
    static.sweet.tv    the schedule, and the icons. Also `*`.

The icons the catalogue hands out are `http://`, which a page served over https
refuses as mixed content. The same file is there over https — see `secure`.
"""

from dataclasses import dataclass
from datetime import date


@dataclass(frozen=True, slots=True)
class Site:
    site: str = "https://sweet.tv"
    api: str = "https://api.sweet.tv"
    static: str = "https://static.sweet.tv"
    #: Country and language together, as the path spells it: `ua-uk`, `ua-en`.
    locale: str = "ua-uk"
    #: Just the language, which is what the schedule files are named by.
    language: str = "uk"

    def channel_list(self) -> str:
        return f"{self.site}/webapi/v2/public/{self.locale}/free-tv/channel_list"

    def schedule(self, channel_id: int, day: date) -> str:
        """`…/tv/epg/v3/3554/21-08-2026/uk.json` — the date is day-first, not ISO."""
        return f"{self.static}/tv/epg/v3/{channel_id}/{day:%d-%m-%Y}/{self.language}.json"

    def open_stream(self) -> str:
        return f"{self.api}/TvService/OpenStream.json"

    def close_stream(self) -> str:
        return f"{self.api}/TvService/CloseStream.json"


SWEET = Site()


def secure(url: str | None) -> str | None:
    """The same asset over https.

    The catalogue writes icon addresses as `http://static.sweet.tv/…`; a page on
    https blocks that as mixed content, and an Android box needs a cleartext
    exception for it. The file is served over https from the same host, so the
    fix is one scheme rather than a proxy.
    """
    if not url:
        return None
    return f"https://{url[len('http://') :]}" if url.startswith("http://") else url
