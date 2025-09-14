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
GRANT SET ON PARAMETER session_replication_role TO replicator;
ALTER USER replicator SET session_replication_role = 'replica';

-- Grant access to system catalogs
GRANT SELECT ON pg_replication_origin TO replicator;
GRANT SELECT ON pg_replication_origin_status TO replicator;

-- Make sure future tables are accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO replicator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO replicator;

-- set conflict resolution
ALTER SYSTEM SET pglogical.conflict_resolution = 'error';

-- table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50)
);

-- insert on node 2
insert into users (name) values ('Mary Smith');

-- create node2 on node2
SELECT pglogical.create_node(
    node_name := 'node2',
    dsn := 'host=__NODE2_IP__ port=30432 dbname=my_db user=replicator password=test'
);

-- replicate table
SELECT pglogical.replication_set_add_table('default', 'public.users');
