# PostgreSQL Replication: CAP Theorem in Practice

This project demonstrates two PostgreSQL replication strategies through the lens of the CAP theorem. Each approach makes different tradeoffs between Consistency, Availability, and Partition tolerance.

## The CAP Theorem

In distributed systems, you can only guarantee two of three properties:

- **C**onsistency: Every read receives the most recent write
- **A**vailability: Every request receives a response
- **P**artition tolerance: System continues operating despite network partitions

Since network partitions are inevitable, the real choice is between **CP** and **AP**.

## Two Approaches

| | [AP](./ap/) | [CP](./cp/) |
|---|---|---|
| **Tradeoff** | Availability + Partition tolerance | Consistency + Partition tolerance |
| **Topology** | Active-Active | Active-Passive |
| **Replication** | Logical (pglogical) | Physical (streaming) |
| **Writeable nodes** | Both | Primary only |
| **During partition** | Both nodes accept writes | Primary blocks until standby reachable |
| **Conflict handling** | Application must resolve | N/A (single writer) |
| **Failover** | Automatic (both always active) | Manual promotion required |
| **Data loss risk** | Conflicts possible | Zero (synchronous) |

## AP: Available During Partitions

```
┌─────────┐                    ┌─────────┐
│   dc1   │◄──── pglogical ───►│   dc2   │
│ (write) │     replication    │ (write) │
└─────────┘                    └─────────┘
```

Both nodes accept writes. Changes replicate bidirectionally. If a partition occurs, both continue serving requests independently. When connectivity resumes, conflicts may need resolution.

**Best for**: High availability requirements, geo-distributed writes, read scaling

```bash
cd ap && just setup-replication
```

## CP: Consistent During Partitions

```
┌─────────┐                    ┌─────────┐
│   dc1   │───── streaming ───►│   dc2   │
│ PRIMARY │     replication    │ STANDBY │
│ (write) │                    │ (read)  │
└─────────┘                    └─────────┘
```

Single primary accepts writes. Synchronous replication ensures standby has all committed data. If standby is unreachable, primary blocks writes rather than risk inconsistency.

**Best for**: Financial systems, inventory, anywhere consistency is non-negotiable

```bash
cd cp && just setup-replication
```

### Failover (CP)

```bash
cd cp
just failover           # Promote standby to primary
just rebuild-standby dc1  # Rebuild old primary as new standby
```

## Prerequisites

- Terraform
- Just (command runner)
- SSH key at `~/.ssh/id_rsa.pub`
- Vultr API key (or modify terraform for your cloud)

## Quick Start

```bash
# Choose your tradeoff
cd ap  # or cd cp

# Provision infrastructure and setup replication
just setup-replication

# Check status
just status

# Clean up
just destroy
```

## Further Reading

- [CAP Theorem](https://en.wikipedia.org/wiki/CAP_theorem)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- [pglogical](https://github.com/2ndQuadrant/pglogical)
