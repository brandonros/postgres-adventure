-- create node2 on node2
SELECT pglogical.create_node(
    node_name := 'node2',
    dsn := 'host={{NODE2_IP}} port=30432 dbname=my_db user=replicator password=test'
);

-- replicate table
SELECT pglogical.replication_set_add_table('default', 'public.users');

-- node2 -> node1
SELECT pglogical.create_subscription(
    subscription_name := 'sub_from_node1',
    provider_dsn := 'host={{NODE1_IP}} port=30432 dbname=my_db user=replicator password=test',
    forward_origins := '{}'
);

-- wait for sync (node2)
SELECT pglogical.wait_for_subscription_sync_complete('sub_from_node1');

-- verify
SELECT * FROM pglogical.show_subscription_status();
