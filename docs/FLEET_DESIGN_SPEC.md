# Manifest Fleet Design Spec

Status: Active design reference  
Scope: polyrepo orchestration behavior in `manifest fleet`

## Objectives

- Coordinate release and sync operations across multiple repositories.
- Preserve single-repo compatibility.
- Keep fleet config explicit and auditable.

## Current Implementation Snapshot

Implemented subcommands:

- `init`
- `status`
- `discover`
- `sync`
- `ship`
- `validate`
- `add`
- `pr`
- `help`

Scaffolded / not implemented yet:

- `prep`
- `docs`

## Fleet Config

Primary file: `manifest.fleet.yaml`

Design principles:

- fleet-level metadata and service definitions
- explicit repo paths/URLs
- validation-first operations before destructive steps
- minimal assumptions about branch or hosting topology

## Operating Model

1. Discover/validate fleet state.
2. Sync repositories.
3. Execute coordinated operations (`ship`, `pr`, etc.).
4. Report per-service outcomes clearly.

## Future Work

- Implement fleet-wide prep and docs generation.
- Add richer dependency and compatibility signaling.
- Improve partial-failure recovery and resume semantics.
