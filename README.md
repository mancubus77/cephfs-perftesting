# ceph-tests

Benchmark scripts for CephFS on OpenShift Data Foundation (ODF).

## Scripts

- **`run-cephfs-bench.sh`** — Runs CephFS benchmark via the native `cephfs-tool` (libcephfs). Deploys an ephemeral pod, injects Ceph credentials from ODF secrets, executes the benchmark, and cleans up.
- **`run-cephfs-bench-posix.sh`** — Runs CephFS benchmark over POSIX (kernel mount). Creates a PVC backed by CephFS, launches a Kubernetes Job with `fs-bench`, and streams the results.

## Container Images

- `quay.io/mancubus77/ceph-tools:latest` — used by the direct CephFS benchmark
- `quay.io/mancubus77/bench-cephfs-fs:latest` — used by the POSIX benchmark

## Benchmark Tool Sources

- [cephfs-tool.cc](https://github.com/mancubus77/ceph/blob/latency/src/tools/cephfs/cephfs-tool.cc) — Direct CephFS benchmark (libcephfs). Enhancement of Pull Requst to CEPH Upstream project: https://github.com/ceph/ceph/pull/67032
 
- [fs-bench.c](https://github.com/mancubus77/ceph/blob/latency/src/tools/cephfs/fs-bench.c) — CephFS POSIX benchmark

## Requirements

- OpenShift cluster with ODF installed
- `oc` CLI authenticated to the cluster
