#!/usr/bin/env python3
"""Prints the external TestFlight state of one mimamori build, for the waits in SKILL.md step 5.

Usage: python3 .claude/skills/mm-release/beta_state.py <build number>

Prints one word: NO_BUILD while App Store Connect does not list the build yet, otherwise the
build's externalBuildState (PROCESSING, READY_FOR_BETA_SUBMISSION, WAITING_FOR_BETA_REVIEW, ...;
Apple's ExternalBetaState). Exit 0 with a state, 1 when the app is not visible or the API fails.

It only reads (GET). Signing in goes through the author's app-store-connect skill in
~/.claude/skills, which finds the API key itself; this script never names, reads, or prints the key.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path.home() / ".claude/skills/app-store-connect"))

BUNDLE_ID = "com.sagochiko.mimamori"


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print("usage: beta_state.py <build number>", file=sys.stderr)
        return 64
    try:
        from asc import build_client
        from asc_client import ASCError
    except ImportError as e:
        print(f"app-store-connect skill not available: {e.name}", file=sys.stderr)
        return 1

    try:
        client = build_client()
        apps = client.get_all(f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=bundleId")
        app = next((a for a in apps if a["attributes"]["bundleId"] == BUNDLE_ID), None)
        if app is None:
            # Do not list the apps the key does see; they are other projects.
            print(f"{BUNDLE_ID} is not visible to the API key", file=sys.stderr)
            return 1
        body = client.get(
            f"/v1/builds?filter[app]={app['id']}&filter[version]={sys.argv[1]}"
            "&include=buildBetaDetail&fields[buildBetaDetails]=externalBuildState&limit=1"
        )
    except ASCError as e:
        print(f"App Store Connect API: {type(e).__name__}", file=sys.stderr)
        return 1

    details = [i for i in body.get("included", []) if i.get("type") == "buildBetaDetails"]
    if not body.get("data") or not details:
        print("NO_BUILD")
    else:
        print(details[0]["attributes"].get("externalBuildState"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
