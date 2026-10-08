"""Check fleet.json, the list `frappe-nix repo apply|audit|rollout --all --fleet` iterates.

The format is frappe-nix's fleet schema 1 (docs/app-standards/spec.md §4.9). This checks
what frappe-nix can't know about our fleet: the shape of every entry, no repository or app
listed twice, the top-level profile is this repository's v1 branch, and every replace
entry matches a [[replace-apps]] pair in profile.toml (and the reverse), so
frappe-rename-app refuses the same pairs whether it reads the fleet or the profile.

Usage: python3 -I scripts/check_fleet.py fleet.json profile.toml
"""

import json
import re
import sys
import tomllib

PROFILE = "github:Avunu/frappe-standards-profile/v1"
REPO = re.compile(r"^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$")
APP = re.compile(r"^[a-z][a-z0-9_]*$")
KEYS = {
	"repo": str,
	"app": str,
	"target_app": str,
	"private": bool,
	"list": bool,
	"documentation": str,
	"rename_mode": str,
	"profile": str,
	"integration_branch": str,
}
REQUIRED = ("repo", "app", "private", "list")


def check(fleet: dict, profile: dict) -> list[str]:
	errors: list[str] = []
	if fleet.get("schema") != 1:
		errors.append("schema must be 1")
	if fleet.get("profile") != PROFILE:
		errors.append(f"profile must be {PROFILE!r}")
	extra = set(fleet) - {"schema", "profile", "apps"}
	if extra:
		errors.append(f"unknown top-level keys: {sorted(extra)}")
	apps = fleet.get("apps")
	if not isinstance(apps, list) or not apps:
		return [*errors, "apps must be a non-empty list"]

	seen_repos: set[str] = set()
	seen_apps: set[str] = set()
	replaces: set[tuple[str, str]] = set()
	for i, entry in enumerate(apps):
		where = f"apps[{i}]"
		if not isinstance(entry, dict):
			errors.append(f"{where}: not an object")
			continue
		where = f"apps[{i}] ({entry.get('repo', '?')})"
		errors.extend(f"{where}: missing {key!r}" for key in REQUIRED if key not in entry)
		for key, value in entry.items():
			if key not in KEYS:
				errors.append(f"{where}: unknown key {key!r}")
			elif not isinstance(value, KEYS[key]):
				errors.append(f"{where}: {key!r} must be a {KEYS[key].__name__}")
		repo, app = entry.get("repo", ""), entry.get("app", "")
		if isinstance(repo, str) and not REPO.match(repo):
			errors.append(f"{where}: repo {repo!r} is not <owner>/<repo>")
		for key in ("app", "target_app"):
			value = entry.get(key)
			if isinstance(value, str) and not APP.match(value):
				errors.append(f"{where}: {key} {value!r} is not a Python package name")
		if entry.get("target_app") == app:
			errors.append(f"{where}: target_app equals app; leave it out when there is no rename")
		mode = entry.get("rename_mode", "rename")
		if mode not in ("rename", "replace"):
			errors.append(f"{where}: rename_mode must be 'rename' or 'replace'")
		if mode == "replace":
			if "target_app" not in entry:
				errors.append(f"{where}: a replace entry needs target_app")
			else:
				replaces.add((app, entry["target_app"]))
		doc = entry.get("documentation")
		if isinstance(doc, str) and not doc.startswith("https://"):
			errors.append(f"{where}: documentation must be an https URL")
		if repo in seen_repos:
			errors.append(f"{where}: repo listed twice")
		if app in seen_apps:
			errors.append(f"{where}: app listed twice")
		seen_repos.add(repo)
		seen_apps.add(app)

	pairs = {(p["from"], p["to"]) for p in profile.get("replace-apps", [])}
	errors.extend(
		f"fleet replaces {old} with {new}, but profile.toml has no such [[replace-apps]]"
		for old, new in sorted(replaces - pairs)
	)
	errors.extend(
		f"profile.toml replaces {old} with {new}, but no fleet entry has that replace"
		for old, new in sorted(pairs - replaces)
	)
	return errors


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(__doc__.strip().splitlines()[-1], file=sys.stderr)
		return 2
	with open(argv[1], encoding="utf-8") as f:
		fleet = json.load(f)
	with open(argv[2], "rb") as f:
		profile = tomllib.load(f)
	errors = check(fleet, profile)
	for error in errors:
		print(f"fleet.json: {error}", file=sys.stderr)
	if errors:
		return 1
	listed = sum(1 for a in fleet["apps"] if a["list"])
	private = [a["repo"] for a in fleet["apps"] if a["private"]]
	print(f"fleet.json: {len(fleet['apps'])} apps ({listed} listed), private: {', '.join(private) or 'none'}")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))
