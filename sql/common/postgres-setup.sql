-- Primary setup for streaming replication (CP)
-- Run this on the primary node (dc1) only
-- Idempotent: safe to run multiple times

-- dblink lets us run CREATE DATABASE outside the current transaction
CREATE EXTENSION IF NOT EXISTS dblink;

-- database
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'my_db') THEN
        PERFORM dblink_exec('dbname=postgres user=postgres password=Test_Password123!', 'CREATE DATABASE my_db');
    END IF;
END
$$;

-- replication user
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
        CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'test';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE my_db TO replicator;

-- replication slot for standby (prevents WAL from being cleaned before standby receives it)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'standby1_slot') THEN
        PERFORM pg_create_physical_replication_slot('standby1_slot');
    END IF;
END
$$;
