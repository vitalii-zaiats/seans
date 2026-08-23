"""One catalogue merged out of several, and the only module here that owns films.

`catalogue/` is a proxy: it asks kinostrain and passes the answer on. This is
the opposite — the rows live here, they come from more than one site, and the
hard part is deciding when two of those sites are describing the same film.

Three keys answer that, in order of how much they are believed:

    imdb    canonical. kinoukr states it; kinostrain hides it inside the
            `vsembed` player URL, which is where it was found.
    ashdi   the id of an *upload*, not of a film — but two catalogues pointing
            at the same file are talking about the same thing. `vod/133070`
            and `serial/6959` are different namespaces and the path is kept.
    name    folded name plus year, within a year either way. The key of last
            resort, and the only one that is ever wrong on its own.

Two rules keep a wrong match from spreading, and both are in `models.py` as
constraints rather than as good intentions: a title holds **at most one row per
source**, and an identifier belongs to **exactly one title**.
"""
