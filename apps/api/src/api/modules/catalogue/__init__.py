"""The film and series catalogue, from kinostrain.com.

No tables. Everything here belongs to somebody else's service, and the reason it
comes through us at all is the header they send back:
`access-control-allow-origin: https://kinostrain.com`. A browser on any other
origin — the web build of the launcher, the landing site — is blocked outright.
Server-side there is no such rule.

So this module is the CORS fix, and the `kinostrain` package is the client. What
this adds on top is a cache for the parts that barely change, and one place
where somebody else's failure becomes a `502` rather than a `500`.
"""
