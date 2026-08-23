"""What a caller has to be ready for.

Three failures, and they mean three different things to whoever catches them:
the server said no, the request never got there, and what came back is not the
shape this package knows. Only the middle one is worth a blind retry — and of
the first, only `is_rate_limited` and `is_server_error`.
"""


class KinostrainError(Exception):
    """Anything this package raises on purpose."""


class HTTPError(KinostrainError):
    """The server answered, with a status outside 2xx."""

    def __init__(self, status_code: int, url: str, body: str | None = None) -> None:
        super().__init__(f"HTTP {status_code} for {url}")
        self.status_code = status_code
        self.url = url
        #: Raw response body, truncated to something sane for a log line.
        self.body = body

    @property
    def is_not_found(self) -> bool:
        """The resource does not exist — unknown slug, unknown id."""
        return self.status_code == 404

    @property
    def is_rate_limited(self) -> bool:
        """The API refused the request rate."""
        return self.status_code == 429

    @property
    def is_server_error(self) -> bool:
        """The failure is upstream's and a retry may well succeed."""
        return self.status_code >= 500


class NetworkError(KinostrainError):
    """The request never produced a response: DNS, TLS, socket, or a timeout."""

    def __init__(self, url: str, cause: BaseException) -> None:
        super().__init__(f"network failure for {url}: {cause}")
        self.url = url
        #: The original error, as the transport raised it.
        self.cause = cause


class SerializationError(KinostrainError):
    """The response arrived but could not be read as the expected shape.

    Raised when upstream changes: a required field disappears or changes type.
    The message names the offending field.
    """

    def __init__(self, message: str, cause: BaseException | None = None) -> None:
        super().__init__(message)
        self.cause = cause
