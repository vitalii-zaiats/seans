"""Free-to-air television, from sweet.tv.

No tables. Everything here belongs to somebody else's service; what this module
adds is the one thing a browser cannot do for itself, plus a cache so that
doing it does not cost a request per viewer.

Of the four hosts involved, only the catalogue's sends no CORS headers — so the
channel list has to come through here. The schedule, the stream lease and the
video itself all answer `access-control-allow-origin: *`, and the video in
particular should stay direct: relaying it would spend bandwidth on a problem
nobody has.
"""
