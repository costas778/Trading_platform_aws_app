# Add at the beginning of services.sh
echo "Cleaning up existing deployments..."
kubectl delete deployment --all
sleep 10  # Wait for cleanup

# Scale the nodegroup to 3 nodes
echo "Scaling nodegroup to 3 nodes..."
eksctl scale nodegroup --cluster=abc-trading-dev --name=abc-trading-dev-nodes --nodes=3
sleep 60  # Wait for nodes to be ready


# Define all services
all_services="api-gateway authentication authorization audit cache compliance logging market-data message-queue notification order-management portfolio-management position-management price-feed quote-service reporting risk-management settlement trade-execution user-management"

# Deploy each service
for service in $all_services; do
    echo "Deploying $service..."
    kubectl create deployment $service --image=637423471201.dkr.ecr.us-east-1.amazonaws.com/$service:latest
      # Set smaller resource requests and limits
    # kubectl set resources deployment $service \
    # --requests=cpu=50m,memory=128Mi \
    # --limits=cpu=100m,memory=256Mi
    sleep 30  # Wait for pod to stabilize
    
    # Verify pod status
    kubectl get pods -l app=$service
done

# Verify all deployments
kubectl get deployments

# Scale all deployments to 2 replicas
echo "Scaling all deployments to 2 replicas..."
kubectl scale deployment --all --replicas=2

# Verify deployments
echo "Verifying deployments..."
kubectl get deployments --all-namespaces
echo "Verifying services..."
kubectl get services --all-namespaces
echo "Verifying pods..."
kubectl get pods --all-namespaces
