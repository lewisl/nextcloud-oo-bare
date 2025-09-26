"""Helpers for rendering OnlyOffice configuration artifacts."""
from __future__ import annotations

import argparse
import json
import re
import secrets
from pathlib import Path
from typing import Optional


def _load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        raise FileNotFoundError(f"Template not found: {path}")
    except json.JSONDecodeError as exc:  # pragma: no cover
        raise ValueError(f"Invalid JSON in template {path}: {exc}") from exc


def render_local_json(
    template: Path,
    output: Path,
    nextcloud_fqdn: str,
    onlyoffice_fqdn: Optional[str],
    jwt_secret: str,
    db_name: str,
    db_user: str,
    db_password: str,
) -> None:
    data = _load_json(template)

    coauthoring = data.setdefault("services", {}).setdefault("CoAuthoring", {})
    coauthoring.setdefault("server", {})["ip"] = "127.0.0.1"
    coauthoring["server"]["port"] = 8000

    public_url = f"https://{nextcloud_fqdn}/onlyoffice"
    coauthoring.setdefault("public", {})["url"] = public_url

    sql_cfg = coauthoring.setdefault("sql", {})
    sql_cfg.update(
        {
            "type": "postgres",
            "dbHost": "localhost",
            "dbPort": "5432",
            "dbName": db_name,
            "dbUser": db_user,
            "dbPass": db_password,
        }
    )

    token_cfg = coauthoring.setdefault("token", {})
    token_cfg.setdefault("enable", {})["browser"] = True
    request_enable = token_cfg.setdefault("enable", {}).setdefault("request", {})
    request_enable["inbox"] = True
    request_enable["outbox"] = True
    token_cfg.setdefault("browser", {})["secretFromInbox"] = False

    inbox_cfg = token_cfg.setdefault("inbox", {})
    inbox_cfg.update({"header": "Authorization", "prefix": "Bearer ", "inBody": False})

    outbox_cfg = token_cfg.setdefault("outbox", {})
    outbox_cfg.update(
        {
            "header": "Authorization",
            "prefix": "Bearer ",
            "algorithm": "HS256",
            "expires": "5m",
            "inBody": False,
            "urlExclusionRegex": "",
        }
    )

    token_cfg.setdefault("session", {})["algorithm"] = "HS256"
    token_cfg["session"]["expires"] = "30d"
    token_cfg["verifyOptions"] = {"clockTolerance": 60}

    secret_cfg = coauthoring.setdefault("secret", {})
    for key in ("browser", "inbox", "outbox", "session"):
        secret_cfg.setdefault(key, {})["string"] = jwt_secret
        secret_cfg[key]["file"] = ""

    rf_cfg = coauthoring.setdefault("request-filtering", {})
    rf_cfg["enable"] = True
    rf_cfg["allowPrivateIPAddress"] = True
    rf_cfg["allowLoopback"] = True

    allowed_hosts = {"127.0.0.1", nextcloud_fqdn}
    if onlyoffice_fqdn:
        allowed_hosts.add(onlyoffice_fqdn)
    rf_cfg["allowedHosts"] = sorted(allowed_hosts)

    rabbitmq_cfg = data.setdefault("rabbitmq", {})
    rabbitmq_cfg["url"] = "amqp://guest:guest@localhost"
    data.setdefault("wopi", {})["enable"] = True

    converter_cfg = data.setdefault("FileConverter", {}).setdefault("converter", {})
    converter_cfg["docbuilderPath"] = "/var/www/onlyoffice/documentserver/server/FileConverter/bin/docbuilder"
    converter_cfg["x2tPath"] = "/var/www/onlyoffice/documentserver/server/FileConverter/bin/x2t"

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2) + "\n")


def render_ds_conf(template: Path, output: Path, existing: Optional[Path]) -> str:
    secret: Optional[str] = None
    if existing and existing.exists():
        match = re.search(r"set\s+\$secure_link_secret\s+([A-Za-z0-9]+);", existing.read_text())
        if match:
            secret = match.group(1)
    if not secret:
        secret = secrets.token_hex(16)

    content = template.read_text().replace("__SECURE_LINK_SECRET__", secret)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content)
    return secret


def main() -> None:
    parser = argparse.ArgumentParser(description="OnlyOffice configuration helpers")
    subparsers = parser.add_subparsers(dest="command", required=True)

    local_parser = subparsers.add_parser("render-local-json", help="Render local.json with deployment values")
    local_parser.add_argument("--template", type=Path, required=True)
    local_parser.add_argument("--output", type=Path, required=True)
    local_parser.add_argument("--nextcloud-fqdn", required=True)
    local_parser.add_argument("--onlyoffice-fqdn", default="")
    local_parser.add_argument("--jwt-secret", required=True)
    local_parser.add_argument("--db-name", required=True)
    local_parser.add_argument("--db-user", required=True)
    local_parser.add_argument("--db-password", required=True)

    ds_parser = subparsers.add_parser("render-ds-conf", help="Render DocumentServer nginx ds.conf")
    ds_parser.add_argument("--template", type=Path, required=True)
    ds_parser.add_argument("--output", type=Path, required=True)
    ds_parser.add_argument("--existing", type=Path)

    args = parser.parse_args()

    if args.command == "render-local-json":
        render_local_json(
            template=args.template,
            output=args.output,
            nextcloud_fqdn=args.nextcloud_fqdn,
            onlyoffice_fqdn=args.onlyoffice_fqdn or None,
            jwt_secret=args.jwt_secret,
            db_name=args.db_name,
            db_user=args.db_user,
            db_password=args.db_password,
        )
    elif args.command == "render-ds-conf":
        render_ds_conf(
            template=args.template,
            output=args.output,
            existing=getattr(args, "existing", None),
        )


if __name__ == "__main__":  # pragma: no cover
    main()
