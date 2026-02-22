#!/bin/bash
set -e

NAMESPACE="fs-bench"
JOB_NAME="fs-bench-job"
PVC_NAME="fs-bench-pvc"
IMAGE="quay.io/mancubus77/bench-cephfs-fs:latest"
STORAGE_CLASS="ocs-storagecluster-cephfs"
PVC_SIZE="50Gi"
MOUNT_PATH="/data"

# Benchmark parameters
FILES=256
SIZE="128M"
THREADS=16
ITERATIONS=3

echo "=========================================="
echo " POSIX CephFS Benchmark (fs-bench)"
echo "=========================================="

echo "[1/6] Creating namespace '${NAMESPACE}'..."
oc create namespace "$NAMESPACE" --dry-run=client -o yaml | oc apply -f - >/dev/null

echo "[2/6] Granting privileged SCC (needed for drop_caches)..."
oc adm policy add-scc-to-user privileged -z default -n "$NAMESPACE" >/dev/null 2>&1 || true

echo "[3/6] Cleaning up any previous run..."
oc delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true >/dev/null 2>&1

echo "[4/6] Ensuring PVC exists..."
oc apply -f - <<EOF >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: ${STORAGE_CLASS}
EOF

echo "      Waiting for PVC to be bound..."
oc wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC_NAME" -n "$NAMESPACE" --timeout=120s >/dev/null

echo "[5/6] Launching benchmark job..."
oc apply -f - <<EOF >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: fs-bench
    spec:
      securityContext:
        fsGroupChangePolicy: "OnRootMismatch"
      containers:
        - name: fs-bench
          image: ${IMAGE}
          imagePullPolicy: Always
          securityContext:
            privileged: true
          command: ["/usr/bin/fs-bench"]
          args:
            - "--path"
            - "${MOUNT_PATH}"
            - "--files"
            - "${FILES}"
            - "--size"
            - "${SIZE}"
            - "--threads"
            - "${THREADS}"
            - "--iterations"
            - "${ITERATIONS}"
          volumeMounts:
            - name: cephfs-data
              mountPath: ${MOUNT_PATH}
      volumes:
        - name: cephfs-data
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
      restartPolicy: Never
EOF

echo "      Waiting for pod to start..."
oc wait --for=condition=Ready pod -l app=fs-bench -n "$NAMESPACE" --timeout=120s >/dev/null 2>&1 || true

echo "[6/6] Streaming benchmark output..."
echo "------------------------------------------"
oc logs -f job/"$JOB_NAME" -n "$NAMESPACE"
echo "------------------------------------------"

# Check job status
STATUS=$(oc get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
if [ "$STATUS" = "Complete" ]; then
    echo "Benchmark completed successfully."
else
    echo "Benchmark finished with status: ${STATUS}"
    echo "Check pod logs: oc logs -l app=fs-bench -n ${NAMESPACE}"
fi

echo ""
echo "Cleanup (when ready):"
echo "  oc delete job ${JOB_NAME} -n ${NAMESPACE}"
echo "  oc delete pvc ${PVC_NAME} -n ${NAMESPACE}"
echo "  oc delete namespace ${NAMESPACE}"
