#!/bin/bash
set -e

NAMESPACE="openshift-storage"
POD_NAME="cephfs-bench-runner"
IMAGE="quay.io/mancubus77/ceph-tools:latest"
FILESYSTEM="ocs-storagecluster-cephfilesystem"
ROOT_PATH="/"
FILES=16384
SIZE=4K
THREADS=16
ITERATIONS=3
BLOCK_SIZE=128

echo "=========================================="
echo " Starting CephFS Benchmark Setup"
echo "=========================================="

echo "[1/4] Extracting Ceph configuration from ODF..."
MON_HOST=$(oc get secret rook-ceph-config -n "$NAMESPACE" -o jsonpath='{.data.mon_host}' | base64 -d)
KEYRING=$(oc get secret rook-ceph-admin-keyring -n "$NAMESPACE" -o jsonpath='{.data.keyring}' | base64 -d)

if [ -z "$MON_HOST" ] || [ -z "$KEYRING" ]; then
    echo "Error: Failed to extract Ceph configuration from secrets in namespace $NAMESPACE."
    exit 1
fi

echo "[2/4] Deploying ephemeral benchmark pod..."
echo "      Cleaning up any existing pod..."
oc delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true >/dev/null 2>&1

oc run "$POD_NAME" --image="$IMAGE" --image-pull-policy=Always -n "$NAMESPACE" --command -- /bin/bash -c "sleep infinity" >/dev/null

echo "      Waiting for pod to become ready..."
oc wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s >/dev/null

echo "[3/4] Injecting Ceph configuration into pod..."
oc exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "cat << 'CONFEOF' > /root/ceph.conf
[global]
mon_host = $MON_HOST
CONFEOF"

oc exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "cat << 'KEYEOF' > /root/keyring
$KEYRING
KEYEOF"

echo "[4/4] Running CephFS Benchmark..."
echo "------------------------------------------"
oc exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "env CEPH_ARGS='--log-to-stderr=false --log-to-file=false --log-file=/tmp/bench.log' \
    /usr/bin/cephfs-tool \
    -c /root/ceph.conf \
    -k /root/keyring \
    -i admin \
    --filesystem $FILESYSTEM \
    bench \
    --root-path=$ROOT_PATH \
    --files $FILES \
    --size=$SIZE \
    --threads=$THREADS \
    --iterations $ITERATIONS \
    --block-size $BLOCK_SIZE"
echo "------------------------------------------"

echo "Cleaning up ephemeral pod..."
oc delete pod "$POD_NAME" -n "$NAMESPACE" --wait=false >/dev/null 2>&1

echo "Benchmark execution complete."