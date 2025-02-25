#!/bin/bash

# First generate and create the SSL certificates secret
echo "Generating SSL certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt \
    -subj "/CN=*.your-domain.com"

echo "Creating Kubernetes secret for SSL certificates..."
kubectl create secret tls trading-platform-certs \
    --cert=tls.crt \
    --key=tls.key \
    --dry-run=client -o yaml | kubectl apply -f -

# Clean up certificate files
rm tls.key tls.crt

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
