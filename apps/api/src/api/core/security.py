"""Tokens and passwords.

Two different problems, deliberately solved two different ways.

*Session tokens* are 256 bits of `secrets` output. Nobody guesses those, so the
lookup hash only has to be one-way, not slow — SHA-256 is right, and it lets the
token column carry a unique index a single `SELECT` can hit.

*Passwords* are whatever a person typed, so the hash has to be expensive on
purpose. `hashlib.scrypt` is memory-hard and it is in the standard library,
which is worth more here than shaving milliseconds off with a third-party argon2
build that has to be compiled into every image.
"""

import hashlib
import hmac
import secrets

#: 32 bytes of entropy, url-safe. Long enough that guessing is not a strategy.
TOKEN_BYTES = 32


def new_token() -> str:
    return secrets.token_urlsafe(TOKEN_BYTES)


def token_digest(token: str) -> str:
    """SHA-256, hex. No salt and no work factor on purpose: this is a 256-bit
    random string, not a password — there is no dictionary to attack it with,
    and a slow hash on every request would only slow us down."""
    return hashlib.sha256(token.encode()).hexdigest()


# ~16 MiB and ~100 ms on the kind of box this runs on. The parameters travel
# inside the stored string, so raising them later does not invalidate old hashes.
_N = 2**14
_R = 8
_P = 1
_DKLEN = 32
_MAXMEM = 64 * 1024 * 1024
_SCHEME = "scrypt"


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    derived = hashlib.scrypt(
        password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=_DKLEN, maxmem=_MAXMEM
    )
    return f"{_SCHEME}${_N}${_R}${_P}${salt.hex()}${derived.hex()}"


def verify_password(password: str, encoded: str | None) -> bool:
    """False for a wrong password, and false for an account that has none.

    A guest has `password_hash = None`; treating that as "no password matches"
    rather than "any password matches" is the whole reason this takes an
    optional.
    """
    if not encoded:
        return False

    try:
        scheme, n, r, p, salt, expected = encoded.split("$")
        if scheme != _SCHEME:
            return False
        derived = hashlib.scrypt(
            password.encode(),
            salt=bytes.fromhex(salt),
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(expected) // 2,
            maxmem=_MAXMEM,
        )
    except (ValueError, TypeError):
        return False

    return hmac.compare_digest(derived.hex(), expected)
