"""Driving a television from a phone.

No tables. A command is an instruction about *now* — if the box is not
listening, the right thing to do with it is nothing, and a queue would turn
"volume up" into something that fires when the television wakes up tomorrow.
State is a fact rather than an instruction, so the newest one is kept in memory
and handed to whoever connects.

Authorisation is not a secret code, it is ownership: you may drive a box you are
signed in on. That relation already exists in `auth_sessions`, which is why this
module has no schema of its own.
"""
