# postgres-adventure
Proof of concept active-active PostgreSQL setup

## Replication

```shell
source ~/.bashrc
kubectl exec -it postgresql-0 -n postgresql -- bash
su postgres
psql

# database
CREATE DATABASE my_db;

# user
CREATE USER replicator WITH REPLICATION LOGIN;
ALTER USER replicator PASSWORD 'test';
GRANT CONNECT ON DATABASE my_db TO replicator;

\c my_db

# replica
CREATE PUBLICATION my_pub FOR ALL TABLES;
# dc1 -> dc2
CREATE SUBSCRIPTION my_sub 
CONNECTION 'host=155.138.218.53 port=30432 dbname=my_db user=replicator password=test' 
PUBLICATION my_pub 
WITH (
    copy_data = false, 
    enabled = true
);
# dc2 -> dc1
CREATE SUBSCRIPTION my_sub 
CONNECTION 'host=45.32.216.198 port=30432 dbname=my_db user=replicator password=test' 
PUBLICATION my_pub 
WITH (
    copy_data = false, 
    enabled = true
);

create table foo(a int);
insert into foo values (1);
```