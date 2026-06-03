# Manifest CLI — Tracker

Open work for the Manifest CLI repo, as one flat list.

- Every item names a concrete deliverable and an anchor; the `§X.Y` label is a stable ID (referenced from commits, memory, and the Cloud/workspace trackers — do not renumber).
- Drift policy: when an item ships, **delete it** from this file. Provenance lives in the merge commit and release history.
- Status tag (2026-05-22 enterprise-readiness triage):
  - **T1** — release-blocking; absence allows lost user state, lost git history, or unrecoverable partial fleet state.
  - **T2** — contract integrity; absence allows the safe-by-default contract to drift or bypass.
  - **T3** — coverage, audit, or docs required before declaring the v1 enterprise release done.
  - **DEFER** — real value, but absence causes no safety harm at fleet-of-dozens scale.
  - **CUT** — considered and rejected; kept here so it doesn't reappear by accident. File a fresh item rather than reviving a cut entry verbatim if the reasoning changes.

---

- **§3.1 Cloud handoff CLI work — gated by Cloud-side milestones M0–M3.**
  - **Status:** DEFER.
  - **Why:** every CLI-side Cloud item activates 1:1 with a Cloud-tracker milestone — contract sources, `cloud.*` config surface, provider wiring, payload privacy assertions, recipe metadata, user-facing docs, and container verification. Tracking them as separate CLI items duplicates the Cloud tracker and creates drift sites for two-step changes. Cloud stays a no-op stub today ([`modules/stubs/manifest-cloud-stub.sh`](../modules/stubs/manifest-cloud-stub.sh)). Source of truth: [Cloud TRACKER §1 (Contracts/M0)](../../fidenceio.manifest.cloud/docs/TRACKER.md#1-contracts-m0-gate), [§2 (Service implementation/M1/M3)](../../fidenceio.manifest.cloud/docs/TRACKER.md#2-service-implementation-m1--m3-gates), [§3 (Security & platform/M3)](../../fidenceio.manifest.cloud/docs/TRACKER.md#3-security--platform-m3-gate). When a Cloud milestone lands, re-file specific CLI deliverables as new items here against the freshly-stable Cloud contract — do not pre-fork them.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

- **§5.11 Standardize on GNU userland to make CI fully container-only.**
  - **Status:** T3 — **code shipped 2026-06-02; one residual step gated on §5.12.** The macOS CI leg can be dropped (→ 100% container-only) only after §5.12 confirms the forced GNU userland works on a real `macos-latest` runner.
  - **Shipped:** `gnu-sed` added alongside `coreutils` as a declared Homebrew dep ([`formula/manifest.rb`](../formula/manifest.rb)); a single `manifest_requirement_prepend_gnu_userland_path` ([`modules/core/manifest-requirements.sh`](../modules/core/manifest-requirements.sh)) forces the coreutils + gnu-sed `gnubin` onto PATH on macOS (idempotent, Bash-3.2-safe, only shadows the GNU tool names), wired into all four channels — the brew formula bin wrapper, the source-install wrapper, the dev/test path via `manifest-core.sh`, and the helper itself. Call sites converted to one GNU codepath: `sed -i` ([`manifest-core.sh`](../modules/core/manifest-core.sh) `update_homebrew_formula`, the only GNU-only `sed -i` site — guarded to fail loud with `brew install gnu-sed` rather than let BSD sed corrupt the formula), `stat -c %Y` ([`manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh)), `date -d` ([`manifest-os.sh`](../modules/system/manifest-os.sh), [`manifest-status.sh`](../modules/core/manifest-status.sh), [`manifest-documentation.sh`](../modules/docs/manifest-documentation.sh)). macOS CI now installs `gnu-sed`. Native-BSD fallbacks kept only where harmless (date forms); the doc/`shared-functions` `sed` sites already used the portable `-i''`/`-i.bak` forms.
  - **Residual:** drop the `macos-latest` matrix leg so `test.yml` is 100% container-only and remove the host-native exception + the container-only docs caveat — **only after §5.12 is green.** Source/dev installs on macOS without `gnu-sed` now hit the loud guard on `ship`; consider an installer-time `gnu-sed` check (or fold into the §-Homebrew-tap-trust install work).
  - **Anchor:** [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`formula/manifest.rb`](../formula/manifest.rb), [`scripts/manifest-cli-wrapper.sh`](../scripts/manifest-cli-wrapper.sh), [`modules/core/manifest-requirements.sh`](../modules/core/manifest-requirements.sh), [`modules/system/manifest-os.sh`](../modules/system/manifest-os.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **§5.12 Verify the forced GNU userland on a real macOS CI runner.**
  - **Status:** T3 (verification gate for §5.11's container-only step).
  - **Why:** §5.11 was validated on Linux/in-container and partly on local macOS (coreutils present), but the full forced-GNU path cannot be confirmed until CI runs on a real `macos-latest` runner. Note §5.11 **removed** the BSD `stat -f %m` fallback this item originally targeted — macOS now takes the GNU `stat -c %Y` branch via the forced `gnubin`, so there is no BSD-stat path left to verify; the verification target has shifted to the forced-GNU userland itself. Local-macOS gap: `gnu-sed` is not installed here, so the `sed -i` formula-update path is unverified locally (the loud guard covers its absence) and rests on the macOS CI leg.
  - **Deliverable:** on the first push to `main` / PR-to-main that triggers the full matrix, confirm the macOS leg is green — specifically that the forced `gnubin` lands GNU `sed`/`date`/`stat` on PATH (so `update_homebrew_formula`'s GNU `sed -i`, `_fleet_dir_mtime_epoch`'s `stat -c %Y`, and the `date -d` sites all run their GNU form) and the brew-provisioned suite passes. If the macOS leg fails, fix forward before §5.11's leg-drop.
  - **Anchor:** [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`modules/core/manifest-requirements.sh`](../modules/core/manifest-requirements.sh) (`manifest_requirement_prepend_gnu_userland_path`), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh) (`_fleet_dir_mtime_epoch`).

- **§6.1 Fleet-service config editor.** **Status:** CUT (command creep). `manifest.fleet.config.yaml` is the source of truth for `services.<name>.release.enabled` / `.strategy`; the file is human-editable and schema-validated on load. A CLI subcommand wrapping `vim` of a transparent YAML file adds a validation, bug, and test surface in exchange for keystrokes that don't reduce risk.

- **§6.2 Workspace/fleet membership drift detection.** **Status:** CUT (command creep / doctor-style sprawl). Users discover drift naturally on the next `ship fleet` preview, which already enumerates members from fleet config against the working tree. A dedicated read-only diff command would add CLI, validation, and test surface for information the next fleet preview already surfaces.

- **§6.3 `--json` summaries for `refresh` and `ship`.** **Status:** CUT (no current customer ask). `status` and `config list` already emit JSON; streaming side-effect commands would need a structured per-step result object plumbed through the orchestrator — meaningful surface area for zero current demand. Re-file as a fresh item if CI/automation integration becomes a tier-1 request.

- **§6.4 Cached-timestamp precision label.** **Status:** CUT (cosmetic). Fleet ship output reads `Trusted timestamp ±0.000000` for cached values; the `±0.000000` reads as bogus precision, but the values are correct and the label causes no compliance, safety, or workflow harm. Carry only if a user surfaces confusion in an auditing context.

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
