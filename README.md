# Frigate NVR Migration on k3s (Bare-Metal)

Manifests, node configuration, and the supporting scripts behind moving Frigate NVR off a shared k3s control plane and onto a dedicated node with a GPU.

Companion repository to the blog post:

> [Migrating Frigate NVR to a New Node: Bare-Metal Lessons in a k3s Cluster](https://ivemcfire.github.io/posts/frigate-migration.html)

This repository is a working reference for running a stateful, GPU-accelerated workload on a constrained k3s cluster — including the parts Kubernetes does not solve for you.

---

## Architecture

**Before**
- Frigate co-located with control plane (single laptop node)
- Single SSD handling OS, SQLite, and video recordings
- CPU-based inference
- No resource isolation

**After**
- Dedicated node (i5-6600 + GTX 1050Ti)
- GPU exposed to Kubernetes via `nvidia.com/gpu`
- Tiered storage:
  - SSD → OS, kubelet, SQLite
  - HDD → recordings (Persistent Volume)
- CPU strictly reserved for system components
- Camera network isolated via VLAN

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
