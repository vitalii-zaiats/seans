"""Domain errors.

Services raise these; a transport turns them into whatever it calls a refusal —
a status code over HTTP, a `StatusCode` over gRPC. That way a service never
imports FastAPI and can be called from a script, a job or a test without
pretending to be a request.
"""


class ApiError(Exception):
    """Base for everything this API refuses to do."""


class NotFound(ApiError):
    pass


class Conflict(ApiError):
    pass


class Invalid(ApiError):
    pass


class Unauthorized(ApiError):
    """No usable identity — the caller has to introduce itself first."""


class Forbidden(ApiError):
    """We know who you are; you still can't have this."""


class Upstream(ApiError):
    """Somebody else's service failed us.

    Not our fault and not the caller's, which is why it is neither a 400 nor a
    500 but a 502: the request was fine, and the thing behind us was not.
    """
