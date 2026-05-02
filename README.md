```markdown
# Frigate NVR Migration on k3s (Bare-Metal)

Manifests, node configuration, and the supporting scripts behind moving Frigate NVR off a shared k3s control plane and onto a dedicated node with a GPU.

Companion repository to the blog post:
> [Migrating Frigate NVR to a New Node: Bare-Metal Lessons in a k3s Cluster](https://ivemcfire.github.io/posts/frigate-migration.html)

This repository is a working reference for running a stateful, GPU-accelerated workload on a constrained k3s cluster — including the parts Kubernetes does not solve for you.

---

## Architecture

**Before**
* Frigate co-located with control plane (single laptop node)
* Single SSD handling OS, SQLite, and video recordings
* CPU-based inference
* No resource isolation

**After**
* Dedicated node (i5-6600 + GTX 1050Ti)
* GPU exposed to Kubernetes via `nvidia.com/gpu`
* Tiered storage:
  * SSD → OS, kubelet, SQLite
  * HDD → recordings (Persistent Volume)
* CPU strictly reserved for system components
* Camera network isolated via VLAN

---

## What's Here

```text
manifests/         Frigate workload — Deployment, Service, ConfigMap, RBAC,
                   write-back sidecar, Cloudflare Tunnel, nightly backup

node-config/       Host-level configuration required before scheduling:
                   containerd template patch (nvidia runtime),
                   RuntimeClass, kubelet reservations

storage/           Local-path provisioner pinned to HDD so recordings land
                   on spinning disk while SQLite stays on SSD

network/           Router-side firewall script that re-applies camera VLAN
                   isolation after power loss (stock firmware limitation)
```

*Note: All IPs are sanitized to 192.168.X.X. The Cloudflare tunnel UUID is a placeholder. Camera credentials are stored in a Kubernetes Secret outside this repository.*

---

## The Migration in Four Moves

### 1. Get the GPU into the cluster
The chain is: `drivers` → `nvidia-container-runtime` → `containerd template` → `RuntimeClass` → `device plugin` → `workload`.
Each step fails silently if misconfigured.

k3s regenerates `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` on every restart from a template. You must edit `node-config/containerd-config.toml.tmpl` — not the rendered file.

**Verification:**
```bash
kubectl describe node <name>
```
You should see `nvidia.com/gpu: 1` in both Capacity and Allocatable.

### 2. Separate storage tiers
Frigate generates continuous writes. If recordings share disk with kubelet storage:
* Disk fills
* Eviction manager activates
* Largest writers are removed first
* Critical services can follow

**The fix:**
* `default local-path` → SSD (config + SQLite)
* `local-path-hdd` → HDD (recordings only)

**Warning:** SQLite on HDD is a trap — it will cause locking and latency issues.

### 3. Reserve resources for the control plane
Frigate can saturate CPU during motion events. Without isolation, the API server starves, leader elections flap, and scheduling becomes unstable.

**Solution:**
* Reserve resources via `k3s-server.env`:
  * 500m CPU + 512Mi (system)
  * 500m CPU + 512Mi (kubelet)
* Apply CPU limits to Frigate

**Result:** Workload degrades (frame drops), but the cluster remains stable.

### 4. Network reality check
* Cameras isolated in VLAN (no gateway)
* Frigate node allowed controlled access
* Router does not persist iptables rules

**Solution:** `network/router-firewall.sh` reapplies rules on boot. Not elegant. But it survives a power cut, which is the real requirement here.

---

## Design Decisions
* **Local-path over network storage:** Lower latency, simpler setup, accepts node affinity.
* **SQLite on SSD, recordings on HDD:** Prevents lock contention under load.
* **CPU limits instead of scaling hardware:** Matches homelab constraints.
* **Containerd template, not live config:** Survives k3s restarts.
* **Vendor mesh kept, VLAN enforced externally:** Works within real-world limitations.

---

## Failure Modes (Observed)
* **GPU not used:** Container runtime misconfigured.
* **DiskPressure:** Eviction of critical pods.
* **SQLite on HDD:** UI latency and locking.
* **CPU starvation:** API server timeouts.
* **Router reboot:** Firewall rules lost.

---

## Apply Order

```bash
# --- node side, on the GPU node ---
sudo cp node-config/containerd-config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/
sudo cp node-config/k3s-server.env /etc/systemd/system/k3s.service.env
sudo systemctl restart k3s

# --- cluster side ---
kubectl apply -f node-config/runtime-class.yaml
kubectl apply -f storage/local-path-hdd-config.yaml

# Device plugin (pin version)
kubectl apply -f [https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/deployments/static/nvidia-device-plugin.yml](https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/deployments/static/nvidia-device-plugin.yml)

# --- workload ---
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml

kubectl -n frigate create secret generic frigate-rtsp-creds \
  --from-literal=reolink-password='<your password>'

kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/backup-cronjob.yaml

# Optional: Cloudflare Tunnel
kubectl -n frigate create secret generic cloudflared-tunnel-creds \
  --from-file=credentials.json=/path/to/<tunnel-creds>.json

kubectl apply -f manifests/cloudflared.yaml
```

---

## Verifying the GPU Chain

```bash
kubectl describe node <gpu-node> | grep -A2 'Capacity:\|Allocatable:'
# Expected output contains: [nvidia.com/gpu](https://nvidia.com/gpu): 1

kubectl -n frigate exec deploy/frigate -- nvidia-smi
```

If `nvidia.com/gpu` is missing:
* Check containerd template (`default_runtime_name = "nvidia"`)
* Confirm config regeneration
* Verify `runtimeClassName: nvidia`

---

## Impact
* Control plane no longer competes with video workloads.
* No DiskPressure events after storage separation.
* GPU replaces CPU-bound inference.
* Cluster remains responsive under peak load.

---

## Related
* [Blog: Migrating Frigate NVR to a New Node](https://ivemcfire.github.io/posts/frigate-migration.html)
* [Blog: Running Frigate NVR on Kubernetes](https://ivemcfire.github.io/posts/frigate-nvr.html)
* [Blog: Running Edge AI on Broken Phones](https://ivemcfire.github.io/posts/edge-ai-phones.html)
* [More posts](```markdown
# Frigate NVR Migration on k3s (Bare-Metal)

Manifests, node configuration, and the supporting scripts behind moving Frigate NVR off a shared k3s control plane and onto a dedicated node with a GPU.

Companion repository to the blog post:
> [Migrating Frigate NVR to a New Node: Bare-Metal Lessons in a k3s Cluster](https://ivemcfire.github.io/posts/frigate-migration.html)

This repository is a working reference for running a stateful, GPU-accelerated workload on a constrained k3s cluster — including the parts Kubernetes does not solve for you.

---

## Architecture

**Before**
* Frigate co-located with control plane (single laptop node)
* Single SSD handling OS, SQLite, and video recordings
* CPU-based inference
* No resource isolation

**After**
* Dedicated node (i5-6600 + GTX 1050Ti)
* GPU exposed to Kubernetes via `nvidia.com/gpu`
* Tiered storage:
  * SSD → OS, kubelet, SQLite
  * HDD → recordings (Persistent Volume)
* CPU strictly reserved for system components
* Camera network isolated via VLAN

---

## What's Here

```text
manifests/         Frigate workload — Deployment, Service, ConfigMap, RBAC,
                   write-back sidecar, Cloudflare Tunnel, nightly backup

node-config/       Host-level configuration required before scheduling:
                   containerd template patch (nvidia runtime),
                   RuntimeClass, kubelet reservations

storage/           Local-path provisioner pinned to HDD so recordings land
                   on spinning disk while SQLite stays on SSD

network/           Router-side firewall script that re-applies camera VLAN
                   isolation after power loss (stock firmware limitation)
```

*Note: All IPs are sanitized to 192.168.X.X. The Cloudflare tunnel UUID is a placeholder. Camera credentials are stored in a Kubernetes Secret outside this repository.*

---

## The Migration in Four Moves

### 1. Get the GPU into the cluster
The chain is: `drivers` → `nvidia-container-runtime` → `containerd template` → `RuntimeClass` → `device plugin` → `workload`.
Each step fails silently if misconfigured.

k3s regenerates `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` on every restart from a template. You must edit `node-config/containerd-config.toml.tmpl` — not the rendered file.

**Verification:**
```bash
kubectl describe node <name>
```
You should see `nvidia.com/gpu: 1` in both Capacity and Allocatable.

### 2. Separate storage tiers
Frigate generates continuous writes. If recordings share disk with kubelet storage:
* Disk fills
* Eviction manager activates
* Largest writers are removed first
* Critical services can follow

**The fix:**
* `default local-path` → SSD (config + SQLite)
* `local-path-hdd` → HDD (recordings only)

**Warning:** SQLite on HDD is a trap — it will cause locking and latency issues.

### 3. Reserve resources for the control plane
Frigate can saturate CPU during motion events. Without isolation, the API server starves, leader elections flap, and scheduling becomes unstable.

**Solution:**
* Reserve resources via `k3s-server.env`:
  * 500m CPU + 512Mi (system)
  * 500m CPU + 512Mi (kubelet)
* Apply CPU limits to Frigate

**Result:** Workload degrades (frame drops), but the cluster remains stable.

### 4. Network reality check
* Cameras isolated in VLAN (no gateway)
* Frigate node allowed controlled access
* Router does not persist iptables rules

**Solution:** `network/router-firewall.sh` reapplies rules on boot. Not elegant. But it survives a power cut, which is the real requirement here.

---

## Design Decisions
* **Local-path over network storage:** Lower latency, simpler setup, accepts node affinity.
* **SQLite on SSD, recordings on HDD:** Prevents lock contention under load.
* **CPU limits instead of scaling hardware:** Matches homelab constraints.
* **Containerd template, not live config:** Survives k3s restarts.
* **Vendor mesh kept, VLAN enforced externally:** Works within real-world limitations.

---

## Failure Modes (Observed)
* **GPU not used:** Container runtime misconfigured.
* **DiskPressure:** Eviction of critical pods.
* **SQLite on HDD:** UI latency and locking.
* **CPU starvation:** API server timeouts.
* **Router reboot:** Firewall rules lost.

---

## Apply Order

```bash
# --- node side, on the GPU node ---
sudo cp node-config/containerd-config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/
sudo cp node-config/k3s-server.env /etc/systemd/system/k3s.service.env
sudo systemctl restart k3s

# --- cluster side ---
kubectl apply -f node-config/runtime-class.yaml
kubectl apply -f storage/local-path-hdd-config.yaml

# Device plugin (pin version)
kubectl apply -f [https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/deployments/static/nvidia-device-plugin.yml](https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/deployments/static/nvidia-device-plugin.yml)

# --- workload ---
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml

kubectl -n frigate create secret generic frigate-rtsp-creds \
  --from-literal=reolink-password='<your password>'

kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/backup-cronjob.yaml

# Optional: Cloudflare Tunnel
kubectl -n frigate create secret generic cloudflared-tunnel-creds \
  --from-file=credentials.json=/path/to/<tunnel-creds>.json

kubectl apply -f manifests/cloudflared.yaml
```

---

## Verifying the GPU Chain

```bash
kubectl describe node <gpu-node> | grep -A2 'Capacity:\|Allocatable:'
# Expected output contains: [nvidia.com/gpu](https://nvidia.com/gpu): 1

kubectl -n frigate exec deploy/frigate -- nvidia-smi
```

If `nvidia.com/gpu` is missing:
* Check containerd template (`default_runtime_name = "nvidia"`)
* Confirm config regeneration
* Verify `runtimeClassName: nvidia`

---

## Impact
* Control plane no longer competes with video workloads.
* No DiskPressure events after storage separation.
* GPU replaces CPU-bound inference.
* Cluster remains responsive under peak load.

---

## Related
* [Blog: Migrating Frigate NVR to a New Node](https://ivemcfire.github.io/posts/frigate-migration.html)
* [Blog: Running Frigate NVR on Kubernetes](https://ivemcfire.github.io/posts/frigate-nvr.html)
* [Blog: Running Edge AI on Broken Phones](https://ivemcfire.github.io/posts/edge-ai-phones.html)
* [More posts](https://ivemcfire.github.io/)
```
