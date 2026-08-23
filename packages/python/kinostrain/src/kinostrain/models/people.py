"""People, on a title and in the directory."""

from dataclasses import dataclass

from kinostrain.jsonread import JsonMap, int_or_none, require_str, str_list, str_or_none
from kinostrain.models.enums import Gender


@dataclass(frozen=True, slots=True)
class Credit:
    """A person credited on a title — an entry of `cast` or `directors`."""

    name: str
    original_name: str
    #: Matches the `slug` of the same person in `/persons`.
    slug: str
    gender: Gender = Gender.UNSPECIFIED
    #: Role played. Always `None` for directors.
    character: str | None = None
    poster_url: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "Credit":
        owner = "Credit"
        return cls(
            name=require_str(json, "name", owner=owner),
            original_name=require_str(json, "originalName", owner=owner),
            slug=require_str(json, "slug", owner=owner),
            gender=Gender.from_code(int_or_none(json, "gender")),
            character=str_or_none(json, "character"),
            poster_url=str_or_none(json, "posterUrl"),
        )


@dataclass(frozen=True, slots=True)
class Person:
    """An entry of the `/persons` directory."""

    name: str
    original_name: str
    slug: str
    gender: Gender = Gender.UNSPECIFIED
    #: Roles this person is credited with, e.g. `('actor', 'director')`.
    career_roles: tuple[str, ...] = ()
    #: Headshot; `None` when the person has no photo.
    poster_url: str | None = None

    @classmethod
    def from_json(cls, json: JsonMap) -> "Person":
        owner = "Person"
        return cls(
            name=require_str(json, "name", owner=owner),
            original_name=require_str(json, "originalName", owner=owner),
            slug=require_str(json, "slug", owner=owner),
            gender=Gender.from_code(int_or_none(json, "gender")),
            career_roles=str_list(json, "careerRoles"),
            poster_url=str_or_none(json, "posterUrl"),
        )

    @property
    def is_actor(self) -> bool:
        return "actor" in self.career_roles

    @property
    def is_director(self) -> bool:
        return "director" in self.career_roles
