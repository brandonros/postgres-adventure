-- node2 -> node1
SELECT pglogical.create_subscription(
    subscription_name := 'sub_from_node1',
    provider_dsn := 'host=__NODE1_IP__ port=30432 dbname=my_db user=replicator password=test',
    forward_origins := '{}'
);

-- wait for sync (node2)
SELECT pglogical.wait_for_subscription_sync_complete('sub_from_node1');

-- verify
SELECT * FROM pglogical.show_subscription_status();
