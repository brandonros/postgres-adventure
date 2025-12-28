-- Verify streaming replication status
-- Run on primary to check standby connection

-- Replication status (run on primary)
-- sync_state should be 'sync' for synchronous replication
SELECT
    client_addr,
    application_name,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    (sent_lsn = replay_lsn) AS caught_up
FROM pg_stat_replication;

-- Replication slot status (run on primary)
SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn
FROM pg_replication_slots;

-- WAL receiver status (run on standby)
-- SELECT * FROM pg_stat_wal_receiver;
