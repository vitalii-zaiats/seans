"""Playlists and segments, fetched somewhere a browser cannot reach.

A different thing from `api.modules.proxy`, and the difference is the whole
design of both. That one mirrors exactly one configured host and takes a path,
so it can never become an open relay. This one has to take a *URL*, because HLS
is a tree of them: a master playlist names variants, a variant names segments,
and every one of those addresses is decided upstream at request time. There is
no path to mirror.

What replaces the path rule is an allowlist that fails closed, and a refusal to
resolve anywhere private. See `targets.py` — it is the part worth reading.
"""
