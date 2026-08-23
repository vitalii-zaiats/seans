"""Who is watching, and how much of that we are told.

Three states, and the app moves between them in one direction only:

    local     nothing here at all. The user declined an account, so no row is
              written and nothing syncs — see `installs`, which answers `POST
              /init` with no identity when the client sends no install id.
    guest     a row with no name on it, reached by a token. This is the default:
              history and progress survive a restart and follow the token.
    claimed   the same row, with an email and a password added to it.

`claim` is the interesting one. It never creates a user, so everything watched
as a guest is still there — the account was always there, it just had nobody's
name on it.
"""
