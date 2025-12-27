-- Primary setup for streaming replication (CP)
-- Run this on the primary node (dc1) only

-- database
CREATE DATABASE my_db;

-- replication user
CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'test';
GRANT CONNECT ON DATABASE my_db TO replicator;

-- replication slot for standby (prevents WAL from being cleaned before standby receives it)
SELECT pg_create_physical_replication_slot('standby1_slot');
