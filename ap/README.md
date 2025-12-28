# postgres-adventure

Proof of concept active-active PostgreSQL replication across two datacenters using pglogical.

## What this demonstrates

- Bidirectional logical replication between two PostgreSQL instances
- Both nodes can accept writes simultaneously
- Automatic conflict resolution when the same row is modified on both nodes

## Important: CAP theorem implications

The CAP theorem states distributed databases can only guarantee two of three properties:
- **C**onsistency: All nodes see the same data at the same time
- **A**vailability: Every request gets a response (even during failures)
- **P**artition tolerance: System works despite network failures between nodes

Since network partitions *will* happen, real systems choose either CP (consistent but may reject writes during partitions) or AP (available but may have temporary inconsistencies).

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

## Replication topologies

Database replication keeps copies of data on multiple servers for high availability (survive failures), disaster recovery (survive datacenter loss), and read scaling (distribute query load).

Two common patterns:

### Primary-Standby (Active-Passive)

```
Primary (writes) → Standby (read-only)
                 → Standby (read-only)
```

One node accepts all writes. Standbys receive replicated data and handle read traffic. On primary failure, a standby is promoted. This is what most production databases use (banks, fintech, etc.) because it avoids conflicts entirely—there's only one source of truth at any moment.

**Replication modes:**
- **Async**: Primary commits immediately, replicates later. Fast, but standby may lag behind. Risk: data loss if primary dies before replication.
- **Sync**: Primary waits for standby acknowledgment before commit returns. Slower, but guarantees zero data loss on failover. This is CP.

### Active-Active (Multi-Master)

```
Node A (writes) ⇄ Node B (writes)
```

Both nodes accept writes simultaneously. Changes replicate bidirectionally. This is what pglogical enables.

**Tradeoff**: Higher availability (either DC can serve writes), but conflicts are possible when the same row is modified on both nodes before sync. Conflict resolution is always async—clients get "success" before replication happens. This is AP.

### PostgreSQL AP options

| Method | Built-in | Multi-Master | Notes |
|--------|----------|--------------|-------|
| Async streaming replication | Yes | No | Standby can lag; data loss possible on failover |
| Native logical replication | Yes (PG10+) | No | One-way pub/sub, async |
| pglogical | Extension | Yes | Bidirectional, conflict resolution (this project) |
| BDR | Commercial | Yes | Enterprise version of pglogical (EDB) |

### PostgreSQL CP options

| Method | What it is | Automatic Failover | Notes |
|--------|------------|-------------------|-------|
| Sync streaming replication | Built-in feature | No | Raw capability; if primary dies, you manually promote standby |
| Patroni (sync mode) | HA orchestration | Yes | Requires etcd/Consul/ZK for leader election; battle-tested, complex |
| pg_auto_failover | HA orchestration | Yes | Simpler than Patroni; uses monitor node instead of external consensus |

**Sync streaming** is the underlying mechanism—Patroni and pg_auto_failover are wrappers that add automatic failover on top of it. Without them, an operator must manually detect failure and promote a standby.

CP requires Primary-Standby topology—there's no way to get CP with multi-master in PostgreSQL.

### Why external tools?

PostgreSQL provides the replication engine but **not** high availability orchestration:

| PostgreSQL provides | External tools provide |
|---------------------|------------------------|
| Replication mechanisms (streaming, logical) | Failure detection (is primary dead or just slow?) |
| Promotion command (`pg_promote()`) | Automatic promotion decision (which standby?) |
| | Fencing (preventing split-brain) |

The reasoning: failure detection and leader election are hard distributed systems problems that require consensus. PostgreSQL's philosophy is "do one thing well" (be a database engine).

```
PostgreSQL (replication engine)
     ↑
Patroni / pg_auto_failover / repmgr (HA orchestration)
     ↑
etcd / Consul / ZooKeeper (consensus for leader election)
```

This differs from MySQL Group Replication or SQL Server Always On, which bake HA logic into the database. PostgreSQL makes you assemble the stack, but gives you flexibility in how you do it.

### Consensus-based alternatives

For true CP with multi-master writes, you need a database designed around distributed consensus (Raft, Paxos):

| System | Protocol | Postgres-compatible | Notes |
|--------|----------|---------------------|-------|
| CockroachDB | Raft | Yes (wire protocol) | Distributed SQL, serializable by default |
| YugabyteDB | Raft | Yes (wire protocol) | Distributed SQL, Postgres-compatible |
| Spanner | Paxos + TrueTime | No | Google Cloud only, atomic clocks |

These systems coordinate writes across nodes *before* committing, so all nodes agree on the order of operations. The tradeoff is latency—every write requires a network round-trip for consensus.

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
