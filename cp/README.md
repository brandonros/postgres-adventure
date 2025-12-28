# postgres-adventure (CP branch)

Proof of concept **synchronous streaming replication** with manual failover.

**See the [main branch](https://github.com/brandonros/postgres-adventure/tree/main) for the AP (active-active pglogical) setup.**

## What this demonstrates

- Primary-Standby topology with synchronous replication
- Zero data loss guarantee (synchronous commit)
- Hot standby (read-only queries on standby)
- Manual failover via `pg_promote()`

## Architecture

```
dc1 (Primary)  ──WAL──>  dc2 (Standby)
   writes                 read-only
```

- **dc1**: Primary node, accepts all writes
- **dc2**: Hot standby, receives WAL stream, read-only queries allowed
- **Synchronous**: Primary waits for standby ACK before commit returns

## CAP theorem

The CAP theorem states distributed databases can only guarantee two of three properties:
- **C**onsistency: All nodes see the same data at the same time
- **A**vailability: Every request gets a response (even during failures)
- **P**artition tolerance: System works despite network failures between nodes

Since network partitions *will* happen, real systems choose either CP (consistent but may reject writes during partitions) or AP (available but may have temporary inconsistencies).

**This setup is CP** (Consistent + Partition-tolerant):

| Property | Behavior |
|----------|----------|
| Consistency | Guaranteed - standby always has committed data |
| Availability | Sacrificed - writes block if standby unreachable |
| Partition tolerance | Yes - system handles network failures |

When the standby is unreachable, the primary will **block writes** rather than risk data loss. This is the CP tradeoff.

## Beyond CAP: PACELC

CAP only describes behavior during partitions. But what about normal operation? The **PACELC** model extends CAP:

> "If there's a **P**artition, choose **A** or **C**. **E**lse (normal operation), choose **L**atency or **C**onsistency."

This gives us three practical modes for streaming replication:

| Mode | During Partition | Normal Operation | PACELC |
|------|------------------|------------------|--------|
| **Synchronous** (this demo) | Blocks writes (C) | Waits for standby ACK (C) | PC/EC |
| **Asynchronous** | Blocks writes (C) | Commits immediately (L) | PC/EL |
| AP (pglogical) | Both nodes write (A) | Async replication (L) | PA/EL |

### Synchronous vs Asynchronous

Both use the same streaming replication mechanism, but differ in commit behavior:

```
SYNCHRONOUS (PC/EC):
Client ──► Primary ──► WAL ──► Standby ACK ──► Commit ──► Response
                              (waits here)

ASYNCHRONOUS (PC/EL):
Client ──► Primary ──► WAL ──► Commit ──► Response
                         └──► Standby (eventually)
```

| | Synchronous | Asynchronous |
|---|---|---|
| Latency | Higher (network round-trip) | Lower |
| Data loss on failover | Zero | Possible (recent commits) |
| Standby down | Primary blocks | Primary continues |
| Use case | Financial, inventory | Most production workloads |

**Async is what most production databases actually run.** The risk of losing a few seconds of commits on failover is acceptable for the latency benefits. Sync is reserved for cases where *any* data loss is unacceptable.

### Switching to Async

This demo defaults to synchronous. To switch to async, comment out the `synchronous_standby_names` line in the Justfile's `setup-replication` recipe (see the comments there).

## How synchronous streaming replication works

1. Client sends `INSERT` to primary
2. Primary writes to WAL (Write-Ahead Log)
3. Primary streams WAL to standby
4. Standby writes WAL to disk and ACKs
5. Primary commits and returns success to client

The key is step 4-5: the primary **waits for standby acknowledgment** before telling the client the transaction succeeded. If the standby is down, writes block.

### Key configuration

```
# Primary postgresql.conf
wal_level = replica
synchronous_commit = on
synchronous_standby_names = 'standby1'

# Standby (created by pg_basebackup)
primary_conninfo = 'host=<primary> user=replicator application_name=standby1'
primary_slot_name = 'standby1_slot'
```

## Manual failover procedure

This setup uses **manual failover**. When the primary fails:

1. Verify standby is caught up (check `pg_stat_replication`)
2. Stop writes to primary (application-level)
3. Promote standby: `SELECT pg_promote();`
4. Update application connection strings to point to new primary
5. (Optional) Rebuild old primary as new standby

```shell
# Check replication status
just status

# Promote standby to primary
just failover
just rebuild-standby dc1    # dc1 becomes standby of dc2
```

### Why manual failover?

For critical workloads (banks, fintech), manual failover is often preferred:
- Operators verify the situation before acting
- No risk of split-brain from automated decisions
- Downtime is acceptable; data loss is not

For automatic failover, use tools like Patroni or pg_auto_failover (not included here).

## Comparison with AP setup

| Aspect | This branch (CP) | Main branch (AP) |
|--------|------------------|------------------|
| Topology | Primary-Standby | Active-Active |
| Writes | Single node only | Both nodes |
| Consistency | Strong | Eventual |
| Partition behavior | Blocks writes | Both continue, conflicts possible |
| Data loss risk | Zero | Possible (last-write-wins) |
| Failover | Manual promotion | N/A (both always active) |

## Technologies used

* Terraform - https://github.com/vultr/terraform-provider-vultr
* Vultr - https://www.vultr.com/
* cloud-init - https://cloud-init.io/
* k3s (Kubernetes) - https://github.com/k3s-io/k3s
* Docker
* PostgreSQL 17 (official image) - https://hub.docker.com/_/postgres
* just (Justfile) - https://github.com/casey/just

## How to use

```shell
# Setup both nodes and configure replication
just setup-replication

# Check replication status
just status

# Verify data exists on both nodes
just verify-data

# Insert test data on primary
just insert-test

# Manual failover (promote standby)
just failover
```

## File structure

```
manifests/
  postgresql.yaml       # K8s manifest (same for both nodes)

sql/
  common/
    postgres-setup.sql  # Create database, replication user, slot
  templates/
    schema.sql          # Table definitions
    verify-replication.sql  # Status queries
  data/
    sample-data.sql     # Test data

terraform/
  modules/vultr_instance/
    main.tf             # VM provisioning with cloud-init

Justfile                # Automation tasks
```
