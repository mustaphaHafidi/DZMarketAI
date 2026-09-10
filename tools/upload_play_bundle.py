#!/usr/bin/env python3
"""Upload an Android App Bundle to Google Play using the Android Publisher API."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--aab", required=True, type=Path)
    parser.add_argument("--service-account-json", required=True, type=Path)
    parser.add_argument("--track", default="production")
    parser.add_argument(
        "--status",
        default="completed",
        choices=("completed", "draft", "inProgress", "halted"),
    )
    parser.add_argument("--release-name", default="")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.aab.is_file():
        raise SystemExit(f"AAB not found: {args.aab}")
    if not args.service_account_json.is_file():
        raise SystemExit(
            f"Service account JSON not found: {args.service_account_json}"
        )

    credentials = service_account.Credentials.from_service_account_file(
        str(args.service_account_json),
        scopes=[SCOPE],
    )
    service = build(
        "androidpublisher",
        "v3",
        credentials=credentials,
        cache_discovery=False,
    )

    edit = service.edits().insert(packageName=args.package_name, body={}).execute()
    edit_id = edit["id"]

    try:
        bundle: dict[str, Any] = (
            service.edits()
            .bundles()
            .upload(
                packageName=args.package_name,
                editId=edit_id,
                media_body=MediaFileUpload(
                    str(args.aab),
                    mimetype="application/octet-stream",
                    resumable=True,
                ),
            )
            .execute()
        )
        version_code = str(bundle["versionCode"])
        release = {
            "versionCodes": [version_code],
            "status": args.status,
        }
        if args.release_name:
            release["name"] = args.release_name

        (
            service.edits()
            .tracks()
            .update(
                packageName=args.package_name,
                editId=edit_id,
                track=args.track,
                body={"releases": [release]},
            )
            .execute()
        )
        service.edits().commit(packageName=args.package_name, editId=edit_id).execute()
    except Exception:
        service.edits().delete(packageName=args.package_name, editId=edit_id).execute()
        raise

    print(f"Uploaded versionCode {version_code} to {args.track} as {args.status}.")


if __name__ == "__main__":
    main()
