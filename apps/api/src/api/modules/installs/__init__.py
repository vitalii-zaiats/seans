"""One row per copy of the app that has ever started.

`POST /init` is the first call a client makes and the only one this module
serves. It answers three questions at once — who you are, whether you should
update, what you may switch on — and only the first is this module's own.
"""
