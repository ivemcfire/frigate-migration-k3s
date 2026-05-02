# Frigate Migration: k3s Bare-Metal

Manifests, node configuration, and the small pile of scripts behind moving
Frigate NVR off a shared k3s control plane and onto a dedicated node with a
GPU. Companion repo to the blog post:

> [Migrating Frigate NVR to a New Node: Bare-Metal Lessons in a k3s Cluster](https://ivemcfire.github.io/posts/frigate-migration.html)

The blog tells the story. This repo is the receipts.

## What's Here

```
manifests/         Frigate workload — Deployment, Service, ConfigMap, RBAC,
                   write-back sidecar, Cloudflare Tunnel, nightly backup.

node-config/       What had to happen on the host before the workload would
                   schedule: containerd template patch for the nvidia
                   runtime, the RuntimeClass, and the kubelet reservations
                   that protect the control plane.

storage/           A second local-path provisioner pinned to the HDD, so
                   recordings land on spinning rust while SQLite stays on
                   the SSD.

network/           The router-side firewall script that re-applies the
                   camera VLAN isolation after every power cut, because
                   the stock firmware does not persist iptables rules.
```

All IPs are sanitized to `192.168.X.X`. The Cloudflare tunnel UUID is a
placeholder. Camera passwords come from a Kubernetes Secret that lives
outside this repo.

## The Migration in Four Moves

The post goes deeper. Here is the operator's summary.

### 1. Get the GPU into the cluster

The chain is: drivers → nvidia-container-runtime → containerd template →
RuntimeClass → device plugin → workload. Each step is silent if it is
wrong.

The trap is the containerd config — k3s regenerates
`/var/lib/rancher/k3s/agent/etc/containerd/config.toml` on every restart
from a template. Edit the template (`node-config/containerd-config.toml.tmpl`),
not the rendered file.

After this, `kubectl describe node <name>` should list `nvidia.com/gpu: 1`
in Capacity and Allocatable. Until it does, no workload will schedule
with a GPU request.

### 2. Separate storage tiers

Frigate writes constantly. If the recordings land on the same disk as the
kubelet's working directory, eventually the disk fills, the eviction
manager wakes up, and it does not care that traefik and coredns are
critical — it evicts the largest writer first and keeps going.

The fix is two storage classes:

- **default `local-path`** — SSD, used for the Frigate config + SQLite DB.
- **`local-path-hdd`** — pinned to the HDD via a per-node config map
  (`storage/local-path-hdd-config.yaml`), used only for recordings.

SQLite on the HDD is a trap. The DB needs the SSD.

### 3. Reserve resources for the control plane

If the node hosts the API server (most homelabs do), Frigate can saturate
the CPU and starve the kubelet. Symptoms look unrelated — leader elections
flap, scheduling slows, things go red in random places.

`node-config/k3s-server.env` reserves 500m CPU + 512Mi memory for system
components and another 500m CPU + 512Mi for the kubelet itself. The
Frigate Deployment then sets explicit CPU limits so it cannot exceed its
slice. Failure mode becomes "dropped frames" instead of "API timeout."

### 4. Network reality check

Cameras live on a restricted VLAN with no gateway. The Frigate node has a
firewall punch-through to reach them. The router does not persist its
iptables rules, so `network/router-firewall.sh` re-applies them on
boot via the vendor startup hook.

Not elegant. Survives a power cut. That is the bar in a real homelab.

## Apply Order

```bash
# --- node side, on the GPU node ---
sudo cp node-config/containerd-config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/
sudo cp node-config/k3s-server.env /etc/systemd/system/k3s.service.env
sudo systemctl restart k3s

# --- cluster side ---
kubectl apply -f node-config/runtime-class.yaml
kubectl apply -f storage/local-path-hdd-config.yaml

# Device plugin (upstream — pin a version, do not track latest)
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/deployments/static/nvidia-device-plugin.yml

# --- workload ---
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml

# Camera password — never commit this
kubectl -n frigate create secret generic frigate-rtsp-creds \
  --from-literal=reolink-password='<your password>'

kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/backup-cronjob.yaml

# Optional: Cloudflare Tunnel for remote access
kubectl -n frigate create secret generic cloudflared-tunnel-creds \
  --from-file=credentials.json=/path/to/<tunnel-creds>.json
kubectl apply -f manifests/cloudflared.yaml
```

## Verifying the GPU Chain

The fastest sanity check after a restart:

```bash
kubectl describe node <gpu-node> | grep -A2 'Capacity:\|Allocatable:'
# nvidia.com/gpu: 1   <- this line is what you want to see

kubectl -n frigate exec deploy/frigate -- nvidia-smi
# Should list the card and any processes Frigate has running on it.
```

If `nvidia.com/gpu` is missing from Capacity but the device plugin pod is
Running, your containerd template is the problem. Check that
`default_runtime_name = "nvidia"` is set, that the rendered
`config.toml` matches the template, and that `runtimeClassName: nvidia`
is set on the workload.

## Related

- [Blog: Migrating Frigate NVR to a New Node](https://ivemcfire.github.io/posts/frigate-migration.html)
- [Blog: Running Frigate NVR on Kubernetes](https://ivemcfire.github.io/posts/frigate-nvr.html)
- [Blog: Running Edge AI on Broken Phones](https://ivemcfire.github.io/posts/edge-ai-phones.html)
- [More posts](https://ivemcfire.github.io/)
