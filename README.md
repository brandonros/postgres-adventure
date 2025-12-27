# postgres-adventure

Proof of concept active-active PostgreSQL replication across two datacenters using pglogical.

## What this demonstrates

- Bidirectional logical replication between two PostgreSQL instances
- Both nodes can accept writes simultaneously
- Automatic conflict resolution when the same row is modified on both nodes

## Important: CAP theorem implications

This setup is **AP** (Available + Partition-tolerant), **not CP** (Consistent + Partition-tolerant).

| What this means | Implication |
|-----------------|-------------|
| Both nodes stay writable during a network partition | High availability |
| Conflicts are resolved asynchronously after commit | Client gets "success" before replication happens |
| No distributed transactions or consensus protocol | Cannot guarantee consistency across nodes |

**pglogical is structurally AP.** There is no configuration that makes it CP. If you need strong consistency (e.g., financial transactions), use synchronous streaming replication or a consensus-based database (CockroachDB, YugabyteDB, Spanner).

### Conflict resolution

When the same row is modified on both nodes before replication syncs, pglogical resolves conflicts using one of:

- `apply_remote` - Remote wins (default, used here)
- `keep_local` - Local wins
- `last_update_wins` - Newest timestamp wins
- `error` - Halt replication, require manual fix

All options except `error` silently discard one version of the data. This is the tradeoff for availability.

## Technologies used

* GitHub Actions
* GitHub Container Registry
* Terraform - https://github.com/vultr/terraform-provider-vultr
* Vultr - https://www.vultr.com/
* cloud-init - https://cloud-init.io/
* k3s (Kubernetes) - https://github.com/k3s-io/k3s
* Docker
* PostgreSQL - https://hub.docker.com/r/bitnami/postgresql
* pglogical - https://github.com/2ndQuadrant/pglogical
* just (Justfile) - https://github.com/casey/just
* Git / Linux / SSH / Bash

## How to use

```shell
just setup-replication
```
