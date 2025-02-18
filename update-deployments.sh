#!/bin/bash

# Set your environment variables
ECR_REPO_PREFIX="abc-trading-dev"
DEPLOY_ENV="dev"

# Read deployments from kubectl
deployments=$(kubectl get deployments -o custom-columns=":metadata.name" --no-headers)

# Create patch for each deployment
for deployment in $deployments; do
    cat << PATCH > "${deployment}-patch.yaml"
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: ${deployment}
        image: ${ECR_REPO_PREFIX}/${deployment}:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "${DEPLOY_ENV}"
        volumeMounts:
        - name: ssl-cert
          mountPath: /etc/ssl/certs
          readOnly: true
      volumes:
      - name: ssl-cert
        secret:
          secretName: trading-platform-certs
PATCH

    echo "Updating deployment ${deployment}"
    kubectl patch deployment ${deployment} -p "$(cat ${deployment}-patch.yaml)"
    rm "${deployment}-patch.yaml"
done

echo "All deployments updated successfully"
