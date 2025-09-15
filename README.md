# postgres-adventure
Proof of concept active-active PostgreSQL setup

## Technologies used

* GitHub Actions
* GitHub Container Registry
* Terraform - https://github.com/vultr/terraform-provider-vultr
* Vultr - https://www.vultr.com/
* cloud-init - https://cloud-init.io/
* k3s (Kubernetes) - https://github.com/k3s-io/k3s
* helm-controller - https://github.com/k3s-io/helm-controller
* Helm + HULL (Helm Uniform Layer Library) - https://github.com/vidispine/hull + https://github.com/brandonros/hull-wrapper
* Docker
* PostgreSQL - https://hub.docker.com/r/bitnami/postgresql
* pglogical - https://github.com/2ndQuadrant/pglogical
* just (Justfile) - https://github.com/casey/just
* Git / Linux / SSH / Bash

## How to use

```shell
just setup-replication
```
