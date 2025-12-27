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

-- Conflict resolution strategy for pglogical replication.
-- Conflicts occur when the same row is modified on both nodes before replication syncs.
-- Options:
--   'error'            - Halt replication, require manual intervention. Use for debugging
--                        or when conflicts indicate a bug that must be investigated.
--   'apply_remote'     - Remote change overwrites local (default). Simple, no halts.
--                        Risk: local changes silently lost if conflict occurs.
--   'keep_local'       - Local change kept, remote discarded. Requires track_commit_timestamp.
--                        Risk: remote changes silently lost.
--   'last_update_wins' - Compare commit timestamps, newest wins. Requires track_commit_timestamp
--                        and synchronized clocks (NTP). Most "correct" for true ordering.
--   'first_update_wins'- Oldest timestamp wins. Rarely used; preserves original value.
--
-- Note: Conflicts are resolved during async replication, NOT at client commit time.
-- The client always gets "success" on commit—conflict resolution happens later.
-- For strong consistency, use synchronous replication or a consensus-based database.
ALTER SYSTEM SET pglogical.conflict_resolution = 'apply_remote';

-- table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50)
);

-- insert sample data for __NODE_NAME__
__SAMPLE_DATA__

-- create __NODE_NAME__ on __NODE_NAME__
SELECT pglogical.create_node(
    node_name := '__NODE_NAME__',
    dsn := 'host=__NODE_IP__ port=30432 dbname=my_db user=replicator password=test'
);

-- replicate table
SELECT pglogical.replication_set_add_table('default', 'public.users');