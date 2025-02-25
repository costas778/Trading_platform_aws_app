#!/bin/bash

# Deploy all services
for service in api-gateway audit authentication authorization cache compliance logging market-data \
              message-queue notification order-management portfolio-management position-management \
              price-feed quote-service reporting risk-management settlement trade-execution user-management; do
    echo "Deploying $service..."
    kubectl apply -f "k8s/base/trading-services/$service/deployment.yaml"
    kubectl apply -f "k8s/base/trading-services/$service/service.yaml"
done


