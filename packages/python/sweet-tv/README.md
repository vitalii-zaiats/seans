# sweet-tv

Client for [sweet.tv](https://sweet.tv)'s free channels — the list, what is on,
and a playable stream. A port of the Dart `sweet_tv` package.

```bash
pip install sweet-tv
```

```python
from sweet_tv import AsyncSweetTv

async with AsyncSweetTv() as tv:
    catalogue = await tv.channels()
    for channel in catalogue.in_category(29):
        print(channel.name, "—", channel.now_playing)

    stream = await tv.open_stream(catalogue.channels[0].id)
    print(stream.url)  # a lease, good for stream.refresh_after
```

No account and no login: a uuid the caller invents stands in for one, which is
all the free tier asks for. Keep the same `Device` across restarts — a fresh
uuid each launch looks to the service like a fleet of boxes.

## Why this exists in Python

Three hosts, and only one of them is a problem:

| host | serves | CORS |
|---|---|---|
| `sweet.tv` | the channel list | **none at all** |
| `api.sweet.tv` | opening a stream | `*` |
| `static.sweet.tv` | the schedule, the icons | `*` |
| the ad-stitching host | the HLS master, variants and segments | `*` |

So the catalogue is the one call a browser cannot make for itself, and the video
is not something to relay: proxying it would spend bandwidth fixing a problem
nobody has. Measured, not assumed — `Origin` and `Referer` change nothing on any
of them, in either direction.

Icons arrive as `http://static.sweet.tv/…`, which a page on https refuses as
mixed content. The same file is there over https, so `Channel.icon_url` is
rewritten rather than proxied.

## A stream is a lease, not an address

`open_stream` returns a session that points at an ad-stitching host and goes
stale after `refresh_after` (five minutes in every answer seen). Store the
channel id and ask again; do not store the URL.

`Stream.plain_url` is the same stream over plain http. Not a fallback to reach
for lightly, but on Android it is the one that works: the stitching host presents
a chain ending in the old Go Daddy Class 2 root signed with SHA-1, and Android
rejects the whole chain over it even though a modern root is already in there.
Desktop clients accept the same chain, which is why it only shows up on a box.
