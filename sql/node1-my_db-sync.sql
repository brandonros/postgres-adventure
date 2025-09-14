-- node1 -> node2
SELECT pglogical.create_subscription(
    subscription_name := 'sub_from_node2',
    provider_dsn := 'host=__NODE2_IP__ port=30432 dbname=my_db user=replicator password=test',
    forward_origins := '{}'
);

-- wait for sync (node1)
SELECT pglogical.wait_for_subscription_sync_complete('sub_from_node2');

-- verify
SELECT * FROM pglogical.show_subscription_status();
