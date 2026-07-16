"""Shared Snowflake session builder for the snowflake-report skill.

Reads ~/.streamlit/secrets.toml (the same file snowflake-streamlit-apps' local-dev
fallback uses) and opens a Snowpark session — typically via Okta external-browser SSO.
The skill's venv includes snowflake-connector-python[secure-local-storage] so the SSO
id token caches via keyring; without it, every new process re-prompts a browser login.
"""

import tomllib
from pathlib import Path

from snowflake.snowpark import Session

SECRETS_PATH = Path.home() / ".streamlit" / "secrets.toml"


def get_session() -> Session:
    if not SECRETS_PATH.exists():
        raise SystemExit(
            f"{SECRETS_PATH} not found — add a [snowflake] section with your account "
            "config (see SKILL.md's Auth section). Never print this file's contents."
        )
    with open(SECRETS_PATH, "rb") as f:
        cfg = tomllib.load(f)["snowflake"]
    return Session.builder.configs(cfg).create()
