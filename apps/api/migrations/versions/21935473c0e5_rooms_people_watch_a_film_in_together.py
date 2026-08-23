"""rooms people watch a film in together

Two tables for one idea: a seat is not a person. `watch_members.token_hash` is
what says "you are in this room" and "you are the host" — never an account —
because a room has to admit somebody who has told us nothing at all. Both
`user_id` columns are nullable for exactly that reason, and both are `SET NULL`
rather than `CASCADE`: deleting an account must not take a room full of other
people down with it.

The room carries what it is showing rather than a pointer to it. Nothing in this
schema has heard of the catalogue, so the same row holds a film, an episode or a
live channel.

`position` is only meaningful next to `playback_at` — a position with no
timestamp is a lie the moment it is read.

Revision ID: 21935473c0e5
Revises: a063c5955f7f
Create Date: 2026-08-23 15:01:30.076724
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "21935473c0e5"
down_revision: str | None = "a063c5955f7f"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "watch_rooms",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=32), nullable=False),
        sa.Column("code", sa.String(length=12), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column(
            "visibility",
            sa.Enum("public", "private", name="room_visibility", native_enum=False, length=16),
            server_default="public",
            nullable=False,
        ),
        sa.Column("host_user_id", sa.Integer(), nullable=True),
        sa.Column(
            "media_kind",
            sa.Enum(
                "movie",
                "episode",
                "channel",
                "other",
                name="room_media_kind",
                native_enum=False,
                length=16,
            ),
            nullable=True,
        ),
        sa.Column("media_id", sa.String(length=200), nullable=True),
        sa.Column("media_title", sa.String(length=300), nullable=True),
        sa.Column("media_poster", sa.String(length=500), nullable=True),
        sa.Column("media_season", sa.Integer(), nullable=True),
        sa.Column("media_episode", sa.Integer(), nullable=True),
        sa.Column("position", sa.Float(), server_default="0", nullable=False),
        sa.Column("paused", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column(
            "playback_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "last_active_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["host_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_watch_rooms_code"), "watch_rooms", ["code"], unique=True)
    op.create_index(
        op.f("ix_watch_rooms_host_user_id"), "watch_rooms", ["host_user_id"], unique=False
    )
    op.create_index(
        op.f("ix_watch_rooms_last_active_at"), "watch_rooms", ["last_active_at"], unique=False
    )
    op.create_index(op.f("ix_watch_rooms_public_id"), "watch_rooms", ["public_id"], unique=True)
    op.create_table(
        "watch_members",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=32), nullable=False),
        sa.Column("room_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("display_name", sa.String(length=80), nullable=False),
        sa.Column(
            "seat",
            sa.Enum("host", "viewer", name="room_seat", native_enum=False, length=16),
            server_default="viewer",
            nullable=False,
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("left_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["room_id"], ["watch_rooms.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_watch_members_public_id"), "watch_members", ["public_id"], unique=True)
    op.create_index(op.f("ix_watch_members_room_id"), "watch_members", ["room_id"], unique=False)
    op.create_index(
        op.f("ix_watch_members_token_hash"), "watch_members", ["token_hash"], unique=True
    )
    op.create_index(op.f("ix_watch_members_user_id"), "watch_members", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_watch_members_user_id"), table_name="watch_members")
    op.drop_index(op.f("ix_watch_members_token_hash"), table_name="watch_members")
    op.drop_index(op.f("ix_watch_members_room_id"), table_name="watch_members")
    op.drop_index(op.f("ix_watch_members_public_id"), table_name="watch_members")
    op.drop_table("watch_members")
    op.drop_index(op.f("ix_watch_rooms_public_id"), table_name="watch_rooms")
    op.drop_index(op.f("ix_watch_rooms_last_active_at"), table_name="watch_rooms")
    op.drop_index(op.f("ix_watch_rooms_host_user_id"), table_name="watch_rooms")
    op.drop_index(op.f("ix_watch_rooms_code"), table_name="watch_rooms")
    op.drop_table("watch_rooms")
