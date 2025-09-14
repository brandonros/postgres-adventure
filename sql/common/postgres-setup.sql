-- database
CREATE DATABASE my_db;

-- user
CREATE USER replicator WITH REPLICATION LOGIN;
ALTER USER replicator PASSWORD 'test';
GRANT CONNECT ON DATABASE my_db TO replicator;
