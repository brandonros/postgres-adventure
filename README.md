# postgres-adventure
Proof of concept active-active PostgreSQL setup

## How to use

```shell
INSTANCE_NAME=dc1 just connect
INSTANCE_NAME=dc2 just connect

source ~/.bashrc
kubectl exec -it postgresql-0 -n postgresql -- bash
psql -U postgres # Test_Password123!
```