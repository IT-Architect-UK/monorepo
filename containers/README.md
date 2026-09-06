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
| `docker/swarm/docker-swarm-node.sh` | Legacy baseline runner for a Swarm node: disables cloud-init, runs a fixed list of scripts (branding, Webmin, extend-disks, IPv6, DNS, iptables, NFS mount, Docker + Compose, `setup-docker-swarm.sh`), upgrades and reboots. Needs passwordless sudo. See Known issue |
| `docker/swarm/deploy-ds-portainer-agent.sh` | Deploy the Portainer Agent across a Swarm cluster — nodes discovered from the Swarm, SSH key + passwordless sudo only |

## Kubernetes

| Script | Purpose |
|--------|---------|
| `kubernetes/install-master-node.sh` | kubeadm control-plane node. Prompts for the load-balancer DNS name and port used as `--control-plane-endpoint`, then deploys Calico |
| `kubernetes/install-worker-node.sh` | kubeadm worker node (join an existing cluster) |
| `kubernetes/install-management-node.sh` | Rancher management host: installs Docker (`docker.io`), kubeadm/kubelet/kubectl and Helm, prompts for a Rancher hostname and deploys Rancher via Helm into `cattle-system`. Helm is pinned (`HELM_VERSION`, default v3.21.3) and verified against its published SHA256. See Known issue |
| `kubernetes/install-minikube-kubectl-dashboard.sh` | Single-node Minikube with dashboard, auto-restart on reboot (8 CPU / 16 GB) |

## Portainer

| Script | Purpose |
|--------|---------|
| `portainer/install-portainer.sh` | Portainer CE server (web UI on port 9443) |
| `portainer/install-portainer-agent.sh` | Portainer Agent on a remote Docker host, ready to attach to the CE server |

## Known issues

- `docker/swarm/docker-swarm-node.sh` resolves its script list under
  `/source-files/github/monorepo/scripts/bash/ubuntu`, a layout this repo no
  longer has; missing scripts are reported and skipped, so on a plain clone it
  only disables cloud-init, upgrades and reboots. Use `install-docker.sh` and
  `setup-docker-swarm.sh` directly.
- `kubernetes/install-management-node.sh` adds the Kubernetes packages with
  `apt-key` and the retired `apt.kubernetes.io kubernetes-xenial` repository,
  which no longer serves packages; the kubeadm/kubelet/kubectl step fails on a
  current Ubuntu.

## Typical order

```bash
sudo ./containers/docker/install-docker.sh          # every Docker host
sudo ./containers/portainer/install-portainer.sh    # management host
sudo ./containers/portainer/install-portainer-agent.sh   # each remote host
```
