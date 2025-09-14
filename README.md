# postgres-adventure
Proof of concept active-active PostgreSQL setup

## Replication

```shell
source ~/.bashrc
kubectl exec -it postgresql-0 -n postgresql -- bash
psql -U postgres # Test_Password123!
```

```sql
-- database
CREATE DATABASE my_db;

-- user
CREATE USER replicator WITH REPLICATION LOGIN;
ALTER USER replicator PASSWORD 'test';
GRANT CONNECT ON DATABASE my_db TO replicator;

-- connect to database
-- \c my_db

-- extension
CREATE EXTENSION pglogical;

-- Grant table-level permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO replicator;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO replicator;

-- Grant schema permissions for pglogical
GRANT USAGE ON SCHEMA pglogical TO replicator;
GRANT SELECT ON ALL TABLES IN SCHEMA pglogical TO replicator;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA pglogical TO replicator;

-- Grant replication origin functions
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_setup(text) TO replicator;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_reset() TO replicator;
GRANT EXECUTE ON FUNCTION pg_replication_origin_create(text) TO replicator;
GRANT EXECUTE ON FUNCTION pg_replication_origin_drop(text) TO replicator;
GRANT EXECUTE ON FUNCTION pg_replication_origin_advance(text, pg_lsn) TO replicator;
GRANT EXECUTE ON FUNCTION pg_replication_origin_progress(text, boolean) TO replicator;

-- Grant parameter setting permissions
ALTER USER replicator SET session_replication_role = 'replica';

-- Grant access to system catalogs
GRANT SELECT ON pg_replication_origin TO replicator;
GRANT SELECT ON pg_replication_origin_status TO replicator;

-- Make sure future tables are accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO replicator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO replicator;

GRANT SET ON PARAMETER session_replication_role TO replicator;

-- table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50)
);

-- create node1 on node1
SELECT pglogical.create_node(
    node_name := 'node1',
    dsn := 'host=155.138.163.127 port=30432 dbname=my_db user=replicator password=test'
);

-- create node2 on node2
SELECT pglogical.create_node(
    node_name := 'node2',
    dsn := 'host=155.138.220.186 port=30432 dbname=my_db user=replicator password=test'
);

-- replicate table
SELECT pglogical.replication_set_add_table('default', 'public.users');

-- node1 -> node2
SELECT pglogical.drop_subscription('sub_from_node2');
SELECT pglogical.create_subscription(
    subscription_name := 'sub_from_node2',
    provider_dsn := 'host=155.138.220.186 port=30432 dbname=my_db user=replicator password=test',
    forward_origins := '{}'
);

-- node2 -> node1
SELECT pglogical.drop_subscription('sub_from_node1');
SELECT pglogical.create_subscription(
    subscription_name := 'sub_from_node1',
    provider_dsn := 'host=155.138.163.127 port=30432 dbname=my_db user=replicator password=test',
    forward_origins := '{}'
);

-- set conflict resolution
ALTER SYSTEM SET pglogical.conflict_resolution = 'error';

-- wait for sync (node1)
SELECT pglogical.wait_for_subscription_sync_complete('sub_from_node2');

-- wait for sync (node2)
SELECT pglogical.wait_for_subscription_sync_complete('sub_from_node1');

-- verify
SELECT * FROM pglogical.show_subscription_status();
```