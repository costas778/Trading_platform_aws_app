#!/bin/bash

# Read deployments from kubectl
deployments=$(kubectl get deployments -o custom-columns=":metadata.name" --no-headers)

# Create patch for each deployment
for deployment in $deployments; do
    cat << PATCH > "${deployment}-patch.yaml"
spec:
  template:
    spec:
      containers:
      - name: ${deployment}
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
        volumeMounts:
        - name: ssl-cert
          mountPath: /etc/ssl/certs
          readOnly: true
      volumes:
      - name: ssl-cert
        secret:
          secretName: trading-platform-certs
PATCH

    echo "Created patch for ${deployment}"
    
    # Apply the patch
    kubectl patch deployment ${deployment} -p "$(cat ${deployment}-patch.yaml)"
    
    # Clean up patch file
    rm "${deployment}-patch.yaml"
done

echo "All deployments patched successfully"
