# postgres-adventure
Proof of concept active-active PostgreSQL setup

## How to use

```shell
INSTANCE_NAME=dc1 just connect
INSTANCE_NAME=dc2 just connect

source ~/.bashrc
kubectl exec -it postgresql-0 -n postgresql -- bash
psql -U postgres # Test_Password123!

# load context
source .instance_details_dc1
DC1_IP=$INSTANCE_IPV4
DC1_SSH_PORT=$INSTANCE_SSH_PORT
DC1_USERNAME=$INSTANCE_USERNAME
source .instance_details_dc2
DC2_IP=$INSTANCE_IPV4
DC2_SSH_PORT=$INSTANCE_SSH_PORT
DC2_USERNAME=$INSTANCE_USERNAME

# dc1 postgres-setup
ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres"' < sql/node1-postgres-setup.sql

# dc2 postgres-setup
ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d postgres"' < sql/node2-postgres-setup.sql

# dc1 my_db-setup
sed "s/{{NODE1_IP}}/$DC1_IP/g; s/{{NODE2_IP}}/$DC2_IP/g" sql/node1-my_db-setup.sql | ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

# dc2 my_db-setup
sed "s/{{NODE1_IP}}/$DC1_IP/g; s/{{NODE2_IP}}/$DC2_IP/g" sql/node2-my_db-setup.sql | ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

# dc1 my_db-sync
sed "s/{{NODE1_IP}}/$DC1_IP/g; s/{{NODE2_IP}}/$DC2_IP/g" sql/node1-my_db-sync.sql | ssh -p $DC1_SSH_PORT $DC1_USERNAME@$DC1_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'

# dc2 my_db-sync
sed "s/{{NODE1_IP}}/$DC1_IP/g; s/{{NODE2_IP}}/$DC2_IP/g" sql/node2-my_db-sync.sql | ssh -p $DC2_SSH_PORT $DC2_USERNAME@$DC2_IP 'KUBECONFIG=/home/debian/.kube/config kubectl exec -i postgresql-0 -n postgresql -- bash -c "PGPASSWORD=\"Test_Password123!\" psql -U postgres -d my_db"'
```
