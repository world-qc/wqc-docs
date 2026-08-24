# wqc-docs (The Archive)

[![License: GFDL-1.3](https://img.shields.io/badge/License-GFDL--1.3-blue.svg)](https://www.gnu.org/licenses/fdl-1.3.html)
[![Whitepaper](https://img.shields.io/badge/Whitepaper-Latest-blue.svg)](https://world-qc.io/docs/WHITEPAPER_en.pdf)

This repository serves as the single source of truth for the World Quantum Computer (WQC) protocol. It contains the mathematical foundations, economic models, and philosophical manifestos of the project.

## Document Map

| Path | Status | Tier | Contents |
|------|--------|------|----------|
| [`/whitepaper`](whitepaper/) | Present | A | Versioned English whitepapers (`WHITEPAPER_x.x_en.md`) and scope notes |
| [`/spec`](spec/) | Present | mixed | Protocol specifications — each file declares `Tier:` in front matter |
| [`/spec/architecture.md`](spec/architecture.md) | Draft | A | Target (sovereign) architecture: actors, trust, on-chain settlement, DHT coordination |
| [`/spec/architecture-current.md`](spec/architecture-current.md) | Working spec | B | Live implementation map: daemons, trust boundaries, task lifecycle |
| [`/spec/zk-STARK.md`](spec/zk-STARK.md) | Present | A | zk-STARK protocol specification (narrative + normative appendices) |
| [`/spec/economics.md`](spec/economics.md) | Draft | A | D-PoUW fees, escrow, economics receipt, on-chain settlement (atomic finalize, optimistic commitment) |
| [`/examples`](examples/) | Present | B | Circuit SSOT, E2E harness, [`compose.yml`](examples/compose.yml) (builds need sibling monorepo checkouts — see [`examples/README.md`](examples/README.md)) |
| [`/examples/E2E.md`](examples/E2E.md) | Present | B | Reference-stack E2E guide (manual + automated + signoff) |
| `/tokenomics` | Planned | A | Fair launch ops and vesting package (must align with [`spec/economics.md`](spec/economics.md) and the whitepaper) |

Directories marked **Planned** may be empty or absent until the corresponding documents are published.

## Vision
Quantum computation should be a human right. We document the transition from centralized "Fortress Computing" to a global "Neural Swarm."

## Contributing

We welcome typo fixes, translation proposals, and new specifications. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute — including how document **tiers** are decided and reviewed. The table above is the inventory; CONTRIBUTING is the rule.

## License
All documentation is licensed under the GNU Free Documentation License v1.3 (GFDL-1.3).
