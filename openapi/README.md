# OpenAPI snapshots

**Do not edit these files by hand.** They are published copies, not the source of truth.

Each specification is maintained next to the code that serves it, and a sync workflow
copies it here whenever it changes on `main`. Editing a snapshot directly would be
silently overwritten by the next sync, and worse, would make the published contract
disagree with the running service.

| File | Served by | Source of truth |
|------|-----------|-----------------|
| `orchestrator.yaml` | Orchestrator client HTTP API, port 9000 | `wqc-orchestrator` `openapi/openapi.yaml` |
| `core.yaml` | Node-local compute engine HTTP API, port 3000 | `wqc-core` `openapi/openapi.yaml` |

`sources.json` records the exact implementation commit each snapshot was taken from.
The implementation repositories are private, so this file is how a reader outside the
organization pins down which revision the published contract corresponds to.

## Rendered output

These files are published with [ReDoc](https://redocly.com/docs/redoc/) at
<https://world-qc.github.io/wqc-docs/>. The rendering is a static page; there is no
public endpoint to call, and the `servers` entries refer to local binds.

## Changing an API

Open the pull request against the implementation repository. The sync runs on merge to
`main` and raises a follow-up pull request here. Both repositories keep a drift test
that fails when routes and specification disagree, so a route added without a
specification change is caught before it can reach this directory.

## Scope

These describe HTTP surfaces only. The libp2p wire contract between the orchestrator and
worker nodes is in [`spec/p2p-protocols.md`](../spec/p2p-protocols.md), and circuit
payload semantics are in [`spec/circuit-payload.md`](../spec/circuit-payload.md).
