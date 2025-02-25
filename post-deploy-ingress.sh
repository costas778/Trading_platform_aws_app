#!/bin/bash

# Set error handling
set -e

# Color codes for output (using printf for better compatibility)
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
NC=$(printf '\033[0m')

# Base directory
BASE_DIR="/home/costas778/abc/trading-platform/k8s/base/ingress"

# Logging functions with timestamp
log() {
    printf "${GREEN}[%s] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
    printf "${YELLOW}[%s] WARNING: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

error() {
    printf "${RED}[%s] ERROR: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Create directory and ingress.yaml if needed
setup_ingress_config() {
    # Create directory if it doesn't exist
    if [ ! -d "$BASE_DIR" ]; then
        log "Creating directory structure..."
        mkdir -p "$BASE_DIR"
    fi

    # Create or update ingress.yaml
    log "Creating/updating ingress.yaml..."
    cat << 'EOFINGRESS' > "$BASE_DIR/ingress.yaml"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: trading-platform-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  ingressClassName: alb
  tls:
  - hosts:
    - "*.abc-trading-dev.com"
    secretName: trading-platform-certs
  rules:
  - host: api.abc-trading-dev.com
    http:
      paths:
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: authentication
            port:
              number: 8080
      - path: /users
        pathType: Prefix
        backend:
          service:
            name: user-management
            port:
              number: 8080
      - path: /trading
        pathType: Prefix
        backend:
          service:
            name: trade-execution
            port:
              number: 8080
      - path: /market
        pathType: Prefix
        backend:
          service:
            name: market-data
            port:
              number: 8080
  - host: app.abc-trading-dev.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 80
  - host: axon.abc-trading-dev.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: message-queue
            port:
              number: 8024
EOFINGRESS
}

# Check if secret exists
check_secret() {
    kubectl get secret trading-platform-certs -n default &>/dev/null
}

# Check if ingress exists
check_ingress() {
    kubectl get ingress trading-platform-ingress &>/dev/null
}

# Main execution
main() {
    log "Starting ingress setup and deployment..."

    # 1. Setup/update ingress configuration
    setup_ingress_config

    # 2. Generate self-signed certificate if needed
    if ! check_secret; then
        log "Generating new self-signed certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout tls.key -out tls.crt \
            -subj "/C=US/ST=State/L=City/O=ABC Trading/OU=DevOps/CN=*.abc-trading-dev.com"

        log "Creating Kubernetes TLS secret..."
        kubectl create secret tls trading-platform-certs \
            --cert=tls.crt \
            --key=tls.key \
            --namespace=default

        rm -f tls.key tls.crt
    else
        warn "TLS secret 'trading-platform-certs' already exists"
    fi

    # 3. Apply ingress configuration
    log "Applying ingress configuration..."
    if ! check_ingress; then
        kubectl apply -f "$BASE_DIR/ingress.yaml"
    else
        warn "Ingress already exists, updating configuration..."
        kubectl delete ingress trading-platform-ingress
        kubectl apply -f "$BASE_DIR/ingress.yaml"
    fi

    # 4. Verify and wait for ALB
    log "Verifying ingress configuration..."
    kubectl get ingress trading-platform-ingress

    log "Waiting for ALB provisioning (may take up to 3 minutes)..."
    for i in {1..36}; do
        ALB_HOSTNAME=$(kubectl get ingress trading-platform-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        if [ -n "$ALB_HOSTNAME" ]; then
            log "ALB Hostname: $ALB_HOSTNAME"
            break
        fi
        printf "."
        sleep 5
    done
    echo ""

    # Final check for ALB hostname
    ALB_HOSTNAME=$(kubectl get ingress trading-platform-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -n "$ALB_HOSTNAME" ]; then
        log "ALB Hostname: $ALB_HOSTNAME"
    else
        warn "ALB hostname not yet available. Please check status manually with:"
        echo "kubectl get ingress trading-platform-ingress -o wide"
        echo "kubectl describe ingress trading-platform-ingress"
    fi

    log "Setup and deployment completed!"
}

# Execute main function
main "$@"
