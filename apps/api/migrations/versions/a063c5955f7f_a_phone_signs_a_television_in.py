"""a phone signs a television in

One table for the pairing dance. Two secrets on it, and they are deliberately
not the same one: `code` is short because it is read off a screen, so knowing it
only lets a phone *approve*; `secret_digest` is the hash of something that never
leaves the television, and only its holder can collect the session.

`consumed_at` is what makes a collection single-use — a token handed out twice
is a token that can be replayed.

Revision ID: a063c5955f7f
Revises: 5442c3077ccc
Create Date: 2026-08-22 23:42:04.122956
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a063c5955f7f"
down_revision: str | None = "5442c3077ccc"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "device_links",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("code", sa.String(length=12), nullable=False),
        sa.Column("secret_digest", sa.String(length=64), nullable=False),
        sa.Column("device_name", sa.String(length=80), nullable=True),
        sa.Column("install_id", sa.Integer(), nullable=True),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["install_id"], ["installs.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_device_links_code"), "device_links", ["code"], unique=True)
    op.create_index(
        op.f("ix_device_links_install_id"), "device_links", ["install_id"], unique=False
    )
    op.create_index(
        op.f("ix_device_links_secret_digest"), "device_links", ["secret_digest"], unique=True
    )
    op.create_index(op.f("ix_device_links_user_id"), "device_links", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_device_links_user_id"), table_name="device_links")
    op.drop_index(op.f("ix_device_links_secret_digest"), table_name="device_links")
    op.drop_index(op.f("ix_device_links_install_id"), table_name="device_links")
    op.drop_index(op.f("ix_device_links_code"), table_name="device_links")
    op.drop_table("device_links")
