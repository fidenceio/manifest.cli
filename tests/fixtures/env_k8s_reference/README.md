# The reference renderer's acceptance fixture

`golden/` holds the files Manifest CLI itself wrote under `k8s/env` for
`service.spec.yaml`, in a checkout folder named `acme.widget` with no origin
remote. They were captured by running `manifest env generate -y` on the last
release that rendered them, before the rendering was removed.

- `golden/full/`: `env.secrets.provider: external-secrets`, `store.name:
  platform-store`, `path: secret/data/{env}/{identity}/{group}`, `env_label:
  environment`, every other setting at its default.
- `golden/none/`: `env.secrets.provider: none`.

`tests/env_k8s_reference.bats` renders the same spec through `manifest env
export` and `examples/env-k8s-render.sh` and compares the result with these
files, comment lines aside. Do not edit them: they are a record of what an
earlier release produced, and no current code can regenerate them.
