"""Compare a resolved configuration with resolved.snapshot.json, allowing only added keys.

The validate workflow's `latest` job checks this profile against the newest frappe-nix v1
release, while resolved.snapshot.json is computed with the frappe-nix flake.lock pins. A
newer release may add options the pinned one doesn't know (a new key with its default); they
can change what apps render, but don't move any value of ours. Every value the snapshot
records must still resolve to the same value, compared as JSON: a changed or removed key, or
any change inside a list, fails. So does a new
module that resolves on, since profile.toml decides every module the fleet runs. Other added
keys are reported, as notices under GitHub Actions; the pin bump that takes the release
updates the snapshot with them on purpose.

Usage: python3 -I scripts/compare_snapshot.py resolved.snapshot.json resolved.json
"""

import json
import os
import sys

MISSING = object()


def child(path: str, key: str) -> str:
	return f"{path}.{key}" if path else key


def compare(old: object, new: object, path: str, changes: list[str], added: list[str]) -> None:
	if isinstance(old, dict) and isinstance(new, dict):
		for key, value in old.items():
			compare(value, new.get(key, MISSING), child(path, key), changes, added)
		for key, value in new.items():
			if key in old:
				continue
			if path == "modules" and value is not False:
				changes.append(f"{child(path, key)}: a new module, on ({json.dumps(value)})")
			else:
				added.append(f"{child(path, key)}: {json.dumps(value)}")
	elif new is MISSING:
		changes.append(f"{path}: removed (was {json.dumps(old)})")
	elif json.dumps(old, sort_keys=True) != json.dumps(new, sort_keys=True):
		changes.append(f"{path}: {json.dumps(old)} -> {json.dumps(new)}")


def main(argv: list[str]) -> int:
	if len(argv) != 3:
		print(__doc__.strip().splitlines()[-1], file=sys.stderr)
		return 2
	with open(argv[1], encoding="utf-8") as f:
		old = json.load(f)
	with open(argv[2], encoding="utf-8") as f:
		new = json.load(f)
	changes: list[str] = []
	added: list[str] = []
	compare(old, new, "", changes, added)
	notice = "::notice::" if os.environ.get("GITHUB_ACTIONS") else ""
	for line in added:
		print(f"{notice}added, not in resolved.snapshot.json: {line}")
	for line in changes:
		print(f"changed: {line}", file=sys.stderr)
	if changes:
		return 1
	print(f"every value in resolved.snapshot.json is unchanged ({len(added)} added)")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))
