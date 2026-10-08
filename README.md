# frappe-standards-profile

Avunu's app-standards profile for [frappe-nix](https://github.com/Avunu/frappe-nix).

frappe-nix can manage the tooling of a Frappe app repository: lint and format configs,
pre-commit hooks, TypeScript projects, CI callers, release-please, Dependabot, Marketplace
readiness and more. An app opts in with a `[tool.frappe-nix]` table, and a **profile**
decides which of those modules are on and with which values. frappe-nix ships two
vendor-neutral built-in profiles, `minimal` and `recommended`. This repository is Avunu's
org profile, layered on top of the frozen `recommended@1.0` snapshot. It holds Avunu's
organisation values (publisher, contact, licence, brand colour, URLs) and every switch the
Avunu fleet relies on.

The profile format, the modules and the merge order are documented in frappe-nix's
[app standards docs](https://github.com/Avunu/frappe-nix/tree/main/docs/app-standards)
(`profiles.md`, and §8 of `spec.md`).

## What is here

| Path | What it is |
| --- | --- |
| [`profile.toml`](profile.toml) | The profile. It extends `recommended@1.0` and sets every value explicitly, so a frappe-nix release that changes `recommended` can't move an Avunu app. |
| [`fleet.json`](fleet.json) | The Avunu fleet: the 12 app repositories that `frappe-nix repo apply\|audit\|rollout --all --fleet fleet.json` iterate, with each app's planned package rename, its documentation URL and whether it is private or listed on the Marketplace. |
| [`resolved.snapshot.json`](resolved.snapshot.json) | The resolved configuration (`frappe-nix profile show --format json`) of frappe-nix's fixture app under this profile. CI compares against it, so any change to a resolved value, from this repository or from frappe-nix, is a reviewed diff. |
| [`scripts/check.sh`](scripts/check.sh) | The checks CI runs: `frappe-nix profile validate`, the snapshot comparison, an offline `frappe-nix sync` of the fixture app with this profile, and the fleet list. |
| [`flake.nix`](flake.nix), [`flake.lock`](flake.lock) | Pins the frappe-nix the checks run against. Dependabot moves it. |
| [`repo-policy/`](repo-policy) | This repository's own settings and rulesets, for `frappe-nix repo apply --policy-dir repo-policy --repo Avunu/frappe-standards-profile`. |
| `templates/` | Template overrides (README blocks, the listing seed, repo-policy JSON). None yet: Avunu uses frappe-nix's templates. |

## How an app uses it

In the app's `pyproject.toml`:

```toml
[tool.frappe-nix]
schema = 1
profile = "github:Avunu/frappe-standards-profile/v1"
frappe-major = 16
siblings = ["erpnext"]
```

plus the app's own keys, and per-app switches where an app differs from the fleet:

- An app that isn't listed on the Marketplace (`"list": false` in `fleet.json`) sets
  `[tool.frappe-nix.listing] publish = false` and has no `marketplace/listing.toml`.
- An app with prebuilt assets sets `[tool.frappe-nix.pilot-assets] enable = true`.

`frappe-init --sync` adds the profile to the app's `flake.nix` as the input
`standards-profile` (`flake = false`) and locks it, so every app commit renders from exactly
one revision of this repository. Dependabot never moves that input, because a profile change
can rewrite workflow files. An app takes a new profile release with

```sh
nix flake update standards-profile && nix run --no-pure-eval .#frappe-init -- --sync
```

or, for the whole fleet, `frappe-nix repo rollout --profile-to latest --all --fleet fleet.json`.

## Releases

Releases are cut by release-please from conventional commits on `main`: tags `vX.Y.Z`, and a
moving branch `v1` that the release workflow fast-forwards to each new tag. Apps lock `v1`,
so it only ever points at a release.

Versioning follows frappe-nix's rules for org profiles:

- **MAJOR**: a change that makes `frappe-nix profile validate` or an app's
  `frappe-init --check` fail without an app edit (a module turned on that needs app
  configuration, a stricter value). Apps move by editing `/v1` to `/v2`.
- **MINOR**: modules turned on or parameters changed that `--sync` applies by itself.
- **PATCH**: organisation value fixes (a URL, an e-mail address).

`requires-frappe-nix` declares the frappe-nix versions the profile is written for; sync
refuses a profile whose range excludes the running frappe-nix.

## Changing the profile

1. Edit `profile.toml` (or `fleet.json`) on a branch.
2. Run the checks, inside `nix develop` or with Nix available:

   ```sh
   scripts/check.sh            # what CI runs
   scripts/check.sh --update   # rewrite resolved.snapshot.json after an intended change
   ```

   To try the profile on a real app before publishing, run
   `nix run --no-pure-eval .#frappe-init -- --sync --profile-path ../frappe-standards-profile`
   in that app's checkout (and don't commit the result).
3. Open a PR with a conventional-commit title (`feat:`, `fix:`, `chore:` …). The `validate`
   check must pass.

## One-time repository setup

- **Repository settings and rulesets:** once frappe-nix's `repo apply` exists, an admin runs
  `frappe-nix repo apply --policy-dir repo-policy --repo Avunu/frappe-standards-profile`.
  That requires a PR and the `validate` check on `main`, lets only GitHub Actions move `v*`
  branches, and protects `v*` tags. Until then, the release workflow needs the setting
  "Allow GitHub Actions to create and approve pull requests" (Settings → Actions → General).
- **Fleet audit:** the nightly scorecard across the fleet will run from this repository
  through frappe-nix's reusable `fleet-audit.yml`, once frappe-nix ships it, with a read-only
  fine-grained token (Administration and Contents read on the fleet's repositories) stored as
  the secret `FRAPPE_NIX_AUDIT_TOKEN`.

## Another organisation

Copy `profile.toml`, change `name`, `description`, `[org]` and the switches, publish it as
`github:<owner>/<repo>` with the same release flow, and point your apps at it. A team that
wants no profile repository can use `profile = "recommended"` with a few
`[tool.frappe-nix.org]` values in each app, or keep a profile inside the app's own repository
(`profile = "./.standards-profile"`).

## Licence

[MIT](LICENSE)
