# Containers

Container runtime and orchestration installers for Ubuntu. Full usage in each script's header.

## Docker

| Script | Purpose |
|--------|---------|
| `docker/install-docker.sh` | Docker CE from the official apt repo (keyring method), service enabled, user added to `docker` group |
| `docker/install-docker-and-docker-compose.sh` | Docker CE + Docker Compose plugin in one pass |

## Docker Swarm

| Script | Purpose |
|--------|---------|
| `docker/swarm/setup-docker-swarm.sh` | Interactive Swarm cluster setup — first manager (leader) or join an existing cluster |
| `docker/swarm/docker-swarm-node.sh` | Prepare an Ubuntu node for Swarm membership |
| `docker/swarm/deploy-ds-portainer-agent.sh` | Deploy the Portainer Agent across a Swarm cluster (prompts for SSH credentials once) |

## Kubernetes

| Script | Purpose |
|--------|---------|
| `kubernetes/install-master-node.sh` | kubeadm control-plane node |
| `kubernetes/install-worker-node.sh` | kubeadm worker node (join an existing cluster) |
| `kubernetes/install-management-node.sh` | Management workstation: kubectl + tooling |
| `kubernetes/install-minikube-kubectl-dashboard.sh` | Single-node Minikube with dashboard, auto-restart on reboot (8 CPU / 16 GB) |

## Portainer

| Script | Purpose |
|--------|---------|
| `portainer/install-portainer.sh` | Portainer CE server (web UI on port 9443) |
| `portainer/install-portainer-agent.sh` | Portainer Agent on a remote Docker host, ready to attach to the CE server |

## Typical order

```bash
sudo ./containers/docker/install-docker.sh          # every Docker host
sudo ./containers/portainer/install-portainer.sh    # management host
sudo ./containers/portainer/install-portainer-agent.sh   # each remote host
```
