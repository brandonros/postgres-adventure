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

## Why pglogical?

PostgreSQL has built-in replication, but it doesn't support multi-master out of the box:

| Type | Since | Extension | Multi-Master | CAP |
|------|-------|-----------|--------------|-----|
| Streaming replication (physical) | 9.0 | No | No (read-only standbys) | CP (if sync) |
| Logical replication (native) | 10 | No | No (one-way pub/sub) | AP |
| pglogical | - | Yes | Yes | AP |

### Built-in streaming replication

```
Primary → WAL bytes → Standby (read-only)
```

Ships raw WAL (Write-Ahead Log) bytes. Standby is read-only. Can be synchronous for CP guarantees. This is what most production HA setups use (Patroni, pg_auto_failover).

### Built-in logical replication (PostgreSQL 10+)

```sql
CREATE PUBLICATION my_pub FOR TABLE users;      -- on publisher
CREATE SUBSCRIPTION my_sub CONNECTION '...' PUBLICATION my_pub;  -- on subscriber
```

Row-level changes, one-way only. Can replicate a subset of tables, cross major versions.

### pglogical adds

- **Bidirectional replication** (both nodes accept writes)
- **Conflict resolution** (what to do when same row modified on both)
- Works on older PostgreSQL versions

If you don't need multi-master, use built-in replication. It's simpler and (for streaming) can be CP.

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
