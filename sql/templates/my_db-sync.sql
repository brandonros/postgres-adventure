-- Subscribe to changes from __OTHER_NODE_NAME__
-- forward_origins := '{}' is critical for active-active setups. It prevents replication loops:
--   - Without it, changes originating from THIS node would be sent to the other node,
--     then replicated BACK here, then sent again... infinite loop.
--   - '{}' means "don't forward changes that originated from other replication origins"
--   - Only changes that originated locally on the provider are replicated.
SELECT pglogical.create_subscription(
    subscription_name := 'sub_from___OTHER_NODE_NAME__',
    provider_dsn := 'host=__OTHER_NODE_IP__ port=30432 dbname=my_db user=replicator password=test',
    forward_origins := '{}'
);

-- wait for sync (__NODE_NAME__)
SELECT pglogical.wait_for_subscription_sync_complete('sub_from___OTHER_NODE_NAME__');

-- verify
SELECT * FROM pglogical.show_subscription_status();