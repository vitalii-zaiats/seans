"""Turning a player page into something a browser can open.

The catalogue hands out embed pages, not streams: a title's `player_data` is a
list of `https://ashdi.vip/vod/…` addresses, and what plays is an `.m3u8` buried
in the JavaScript on one of them. Reading that page needs a `Referer` the site
recognises — which a browser is not allowed to set — so the reading happens
here.

The extraction is a port of `packages/dart/ashdi_finder`, which the Android
build uses directly. Two implementations of one parser is a cost paid on
purpose: the box reads the page itself and talks to nobody, and a browser
cannot. When they disagree the fixtures say which is right.
"""
