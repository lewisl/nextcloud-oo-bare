"""Utilities for loading deployment parameters from configs/params.yaml or system config."""
from __future__ import annotations

import argparse
import json
import os
import shlex
from dataclasses import asdict, dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml  # type: ignore
except ModuleNotFoundError as exc:  # pragma: no cover - import guard
    raise RuntimeError(
        "PyYAML is required to load deployment parameters. Install with 'sudo apt install python3-yaml' "
        "or 'pip install pyyaml'."
    ) from exc

SYSTEM_PARAMS_PATH = Path("/etc/nextcloud-onlyoffice/params.yaml")
REPO_PARAMS_PATH = Path(__file__).resolve().parents[1] / "configs" / "params.yaml"
ENV_PARAMS_PATH = "NC_OO_PARAMS_PATH"


class ConfigLoaderError(RuntimeError):
    """Raised when configuration parameters are missing or invalid."""


@dataclass(frozen=True)
class DeploymentConfig:
    base_domain: str
    nextcloud_domain: str
    onlyoffice_domain: str
    admin_email: str
    letsencrypt_email: str
    nextcloud_admin_user: str
    nextcloud_admin_password: str


@dataclass(frozen=True)
class DatabaseConfig:
    name: str
    user: str
    password: str


@dataclass(frozen=True)
class JWTConfig:
    secret: str


@dataclass(frozen=True)
class Params:
    deployment: DeploymentConfig
    nextcloud_db: DatabaseConfig
    onlyoffice_db: DatabaseConfig
    jwt: JWTConfig

    def validate(self) -> List[str]:
        issues: List[str] = []
        if not self.deployment.base_domain:
            issues.append("deployment.base_domain is required")
        if not self.deployment.nextcloud_domain.startswith("docs."):
            issues.append("deployment.nextcloud_domain should start with 'docs.'")
        if not self.deployment.onlyoffice_domain.startswith("onlyoffice."):
            issues.append("deployment.onlyoffice_domain should start with 'onlyoffice.'")
        for label, value in (
            ("admin", self.deployment.admin_email),
            ("letsencrypt", self.deployment.letsencrypt_email),
        ):
            if "@" not in value:
                issues.append(f"deployment.{label}_email must be a valid email address")
        if not self.deployment.nextcloud_admin_user:
            issues.append("deployment.nextcloud_admin_user is required")
        if len(self.deployment.nextcloud_admin_password) < 16:
            issues.append("deployment.nextcloud_admin_password should be at least 16 characters")
        for label, db in (
            ("nextcloud", self.nextcloud_db),
            ("onlyoffice", self.onlyoffice_db),
        ):
            if not db.name:
                issues.append(f"{label} database name is required")
            if not db.user:
                issues.append(f"{label} database user is required")
            if len(db.password) < 16:
                issues.append(f"{label} database password should be at least 16 characters")
        if len(self.jwt.secret) < 32:
            issues.append("JWT secret should be at least 32 characters")
        return issues


CONFIG_KEY_MAP = {
    "deployment.base_domain": "DEPLOYMENT_BASE_DOMAIN",
    "deployment.nextcloud_domain": "NEXTCLOUD_FQDN",
    "deployment.onlyoffice_domain": "ONLYOFFICE_FQDN",
    "deployment.admin_email": "ADMIN_EMAIL",
    "deployment.letsencrypt_email": "LETSENCRYPT_EMAIL",
    "deployment.nextcloud_admin_user": "NEXTCLOUD_ADMIN_USER",
    "deployment.nextcloud_admin_password": "NEXTCLOUD_ADMIN_PASSWORD",
    "nextcloud_db.name": "NEXTCLOUD_DB_NAME",
    "nextcloud_db.user": "NEXTCLOUD_DB_USER",
    "nextcloud_db.password": "NEXTCLOUD_DB_PASSWORD",
    "onlyoffice_db.name": "ONLYOFFICE_DB_NAME",
    "onlyoffice_db.user": "ONLYOFFICE_DB_USER",
    "onlyoffice_db.password": "ONLYOFFICE_DB_PASSWORD",
    "jwt.secret": "JWT_SECRET",
}


def _default_params_path() -> Path:
    env_override = os.environ.get(ENV_PARAMS_PATH)
    if env_override:
        return Path(env_override).expanduser()
    if SYSTEM_PARAMS_PATH.exists():
        return SYSTEM_PARAMS_PATH
    # Fall back to repository sample to aid development/testing.
    return REPO_PARAMS_PATH


def _load_yaml(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise ConfigLoaderError(f"Parameter file not found: {path}")
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
    except yaml.YAMLError as exc:
        raise ConfigLoaderError(f"Failed to parse YAML: {exc}") from exc
    if not isinstance(data, dict):
        raise ConfigLoaderError("Top-level YAML structure must be a mapping")
    return data


def _section(data: Dict[str, Any], key: str) -> Dict[str, Any]:
    raw = data.get(key)
    if raw is None:
        raise ConfigLoaderError(f"Missing required section: {key}")
    if not isinstance(raw, dict):
        raise ConfigLoaderError(f"Section '{key}' must be a mapping")
    return raw


@lru_cache(maxsize=1)
def load_params(path: Optional[Path] = None) -> Params:
    target = Path(path) if path else _default_params_path()
    raw = _load_yaml(target)

    deployment_raw = _section(raw, "deployment")
    nextcloud_raw = _section(raw, "nextcloud")
    onlyoffice_raw = _section(raw, "onlyoffice")
    jwt_raw = _section(raw, "jwt")

    deployment = DeploymentConfig(
        base_domain=str(deployment_raw.get("base_domain", "")).strip(),
        nextcloud_domain=str(deployment_raw.get("nextcloud_domain", "")).strip(),
        onlyoffice_domain=str(deployment_raw.get("onlyoffice_domain", "")).strip(),
        admin_email=str(deployment_raw.get("admin_email", "")).strip(),
        letsencrypt_email=str(deployment_raw.get("letsencrypt_email", "")).strip(),
        nextcloud_admin_user=str(deployment_raw.get("nextcloud_admin_user", "")).strip(),
        nextcloud_admin_password=str(deployment_raw.get("nextcloud_admin_password", "")).strip(),
    )

    nextcloud_db = DatabaseConfig(
        name=str(nextcloud_raw.get("db_name", "")).strip(),
        user=str(nextcloud_raw.get("db_user", "")).strip(),
        password=str(nextcloud_raw.get("db_password", "")).strip(),
    )

    onlyoffice_db = DatabaseConfig(
        name=str(onlyoffice_raw.get("db_name", "")).strip(),
        user=str(onlyoffice_raw.get("db_user", "")).strip(),
        password=str(onlyoffice_raw.get("db_password", "")).strip(),
    )

    jwt = JWTConfig(secret=str(jwt_raw.get("secret", "")).strip())

    params = Params(
        deployment=deployment,
        nextcloud_db=nextcloud_db,
        onlyoffice_db=onlyoffice_db,
        jwt=jwt,
    )

    issues = params.validate()
    if issues:
        issue_text = "; ".join(issues)
        raise ConfigLoaderError(f"Parameter validation failed: {issue_text}")

    return params


def reset_cache() -> None:
    load_params.cache_clear()


def _get_value(mapping: Dict[str, Any], dotted_key: str) -> Any:
    current: Any = mapping
    for part in dotted_key.split('.'):
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            raise ConfigLoaderError(f"Key '{dotted_key}' not found in parameters")
    return current


def _emit_env(data: Dict[str, Any]) -> str:
    exports = []
    for dotted_key, env_key in CONFIG_KEY_MAP.items():
        try:
            value = _get_value(data, dotted_key)
        except ConfigLoaderError:
            continue
        if isinstance(value, (dict, list)):
            raise ConfigLoaderError(f"Cannot export non-scalar value for key '{dotted_key}'")
        exports.append(f"export {env_key}={shlex.quote(str(value))}")
    return "\n".join(exports)


def _cli() -> int:
    parser = argparse.ArgumentParser(description="Inspect Nextcloud/OnlyOffice deployment parameters")
    parser.add_argument(
        "--path",
        type=Path,
        help="Optional explicit path to params.yaml (defaults to $NC_OO_PARAMS_PATH, then /etc/nextcloud-onlyoffice/params.yaml, then repo sample)",
    )
    parser.add_argument(
        "--get",
        metavar="KEY",
        help="Output a single value using dotted notation, e.g. deployment.nextcloud_domain",
    )
    parser.add_argument(
        "--dump",
        action="store_true",
        help="Dump all parameters as JSON",
    )
    parser.add_argument(
        "--env",
        action="store_true",
        help="Emit shell export statements for common keys",
    )

    args = parser.parse_args()

    params = load_params(args.path)
    data = asdict(params)

    if args.get:
        value = _get_value(data, args.get)
        if isinstance(value, (dict, list)):
            print(json.dumps(value, indent=2))
        else:
            print(value)
        return 0

    if args.env:
        print(_emit_env(data))
        return 0

    if args.dump:
        print(json.dumps(data, indent=2))
        return 0

    print("Loaded parameters from", (args.path or _default_params_path()))
    print("Available sections:")
    for key in data:
        print(f" - {key}")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(_cli())
