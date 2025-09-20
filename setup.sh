# ==========================
# Auth & set project info
# ==========================
gcloud auth list

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

# ==========================
# Get credentials for cluster (if exists)
# ==========================
gcloud container clusters get-credentials hello-demo-cluster --zone "$ZONE"

# Scale & resize (optional)
kubectl scale deployment hello-server --replicas=2
gcloud container clusters resize hello-demo-cluster --node-pool my-node-pool --num-nodes=3 --zone "$ZONE" --quiet

# ==========================
# Create new node pool
# ==========================
gcloud container node-pools create larger-pool \
  --cluster=hello-demo-cluster \
  --machine-type=e2-standard-2 \
  --num-nodes=1 \
  --zone="$ZONE"

# Cordon & drain old nodes
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=my-node-pool -o=name); do
  kubectl cordon "$node";
done

for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=my-node-pool -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node";
done

kubectl get pods -o wide

# Delete old pool
gcloud container node-pools delete my-node-pool --cluster hello-demo-cluster --zone "$ZONE" --quiet

# ==========================
# Create fresh regional cluster
# ==========================
gcloud container clusters create regional-demo --region=$REGION --num-nodes=1

# ==========================
# Enable VPC flow logs with full metadata
# ==========================
gcloud compute networks subnets update default \
  --region=$REGION \
  --enable-flow-logs \
  --logging-metadata=INCLUDE_ALL

# ==========================
# Pod 1 manifest
# ==========================
cat << EOF > pod-1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-1
  labels:
    security: demo
spec:
  containers:
  - name: container-1
    image: wbitt/network-multitool
EOF

kubectl apply -f pod-1.yaml

# ==========================
# Pod 2 manifest (fixed image)
# ==========================
cat << EOF > pod-2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-2
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - demo
        topologyKey: "kubernetes.io/hostname"
  containers:
  - name: container-2
    image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
EOF

kubectl apply -f pod-2.yaml

# ==========================
# Wait a bit & check placement
# ==========================
sleep 20
kubectl get pod pod-1 pod-2 -o wide

# ==========================
# Test traffic
# ==========================
ping -c 5 8.8.8.8
curl google.com

# ==========================
# Echo useful links
# ==========================
echo
echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo
echo -e "\033[1;33mExamine subnet + flow logs:\033[0m (you can just click the link in the next step if you don't see the flow logs)"
echo -e "\033[1;34mhttps://console.cloud.google.com/networking/networks/details/default?project=$PROJECT_ID&pageTab=SUBNETS\033[0m"
echo
echo -e "\033[1;33mBigQuery VPC Flow Logs dataset:\033[0m"
echo -e "\033[1;34mhttps://console.cloud.google.com/bigquery?project=$PROJECT_ID&ws=!1m5!1m4!4m3!1s$PROJECT_ID!2scompute_googleapis_com_vpc_flows\033[0m"
