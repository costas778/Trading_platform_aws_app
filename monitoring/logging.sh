#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables
if [ -z "$ENV_FILE" ]; then
    echo -e "${RED}Error: ENV_FILE not set${NC}"
    exit 1
fi

source "$ENV_FILE"

# Setup log groups for all services
setup_log_groups() {
    echo -e "${YELLOW}Setting up CloudWatch log groups...${NC}"
    
    # Create log groups for core services
    for service in ${CORE_SERVICES}; do
        aws logs create-log-group \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --tags Environment="${DEPLOY_ENV}",Service="${service}",Type="core"
        
        aws logs put-retention-policy \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --retention-in-days 30
    done
    
    # Create log groups for dependent services
    for service in ${DEPENDENT_SERVICES}; do
        aws logs create-log-group \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --tags Environment="${DEPLOY_ENV}",Service="${service}",Type="dependent"
        
        aws logs put-retention-policy \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --retention-in-days 30
    done
    
    # Create log groups for business services
    for service in ${BUSINESS_SERVICES}; do
        aws logs create-log-group \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --tags Environment="${DEPLOY_ENV}",Service="${service}",Type="business"
        
        aws logs put-retention-policy \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --retention-in-days 30
    done
}

# Configure Fluentd for all services
setup_fluentd() {
    echo -e "${YELLOW}Setting up Fluentd...${NC}"
    
    # Create Fluentd ConfigMap with service-specific configurations
    cat > fluentd-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: logging
data:
  fluent.conf: |
    # Common configurations
    <source>
      @type tail
      path /var/log/containers/*.log
      pos_file /var/log/fluentd-containers.log.pos
      tag kubernetes.*
      read_from_head true
      <parse>
        @type json
        time_format %Y-%m-%dT%H:%M:%S.%NZ
      </parse>
    </source>

    # Core services logging
    <match kubernetes.var.log.containers.**core**.log>
      @type cloudwatch_logs
      log_group_name "/${DEPLOY_ENV}/trading/#{ENV['SERVICE_NAME']}"
      log_stream_name "#{ENV['HOSTNAME']}"
      auto_create_stream true
      <buffer>
        @type memory
        flush_interval 5
        chunk_limit_size 2M
        queue_limit_length 4
        retry_max_attempts 3
      </buffer>
    </match>

    # Dependent services logging
    <match kubernetes.var.log.containers.**dependent**.log>
      @type cloudwatch_logs
      log_group_name "/${DEPLOY_ENV}/trading/#{ENV['SERVICE_NAME']}"
      log_stream_name "#{ENV['HOSTNAME']}"
      auto_create_stream true
      <buffer>
        @type memory
        flush_interval 5
        chunk_limit_size 2M
        queue_limit_length 4
        retry_max_attempts 3
      </buffer>
    </match>

    # Business services logging
    <match kubernetes.var.log.containers.**business**.log>
      @type cloudwatch_logs
      log_group_name "/${DEPLOY_ENV}/trading/#{ENV['SERVICE_NAME']}"
      log_stream_name "#{ENV['HOSTNAME']}"
      auto_create_stream true
      <buffer>
        @type memory
        flush_interval 5
        chunk_limit_size 2M
        queue_limit_length 4
        retry_max_attempts 3
      </buffer>
    </match>
EOF

    # Apply Fluentd ConfigMap
    kubectl apply -f fluentd-config.yaml
    
    # Deploy Fluentd DaemonSet
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: logging
  labels:
    k8s-app: fluentd-logging
spec:
  selector:
    matchLabels:
      name: fluentd
  template:
    metadata:
      labels:
        name: fluentd
    spec:
      serviceAccount: fluentd
      serviceAccountName: fluentd
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1-debian-cloudwatch
        env:
          - name: AWS_REGION
            value: "${AWS_REGION}"
          - name: DEPLOY_ENV
            value: "${DEPLOY_ENV}"
        resources:
          limits:
            memory: 500Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: config
          mountPath: /fluentd/etc/
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: config
        configMap:
          name: fluentd-config
EOF
}

# Setup log metrics and filters for all services
setup_log_metrics() {
    echo -e "${YELLOW}Setting up log metrics...${NC}"
    
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        # Error count metric filter
        aws logs put-metric-filter \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --filter-name "${service}-errors" \
            --filter-pattern "ERROR" \
            --metric-transformations \
                metricName="${service}Errors",\
                metricNamespace="Trading/${DEPLOY_ENV}",\
                metricValue=1
        
        # Warning count metric filter
        aws logs put-metric-filter \
            --log-group-name "/${DEPLOY_ENV}/trading/${service}" \
            --filter-name "${service}-warnings" \
            --filter-pattern "WARN" \
            --metric-transformations \
                metricName="${service}Warnings",\
                metricNamespace="Trading/${DEPLOY_ENV}",\
                metricValue=1
    done
}

# Setup log insights queries
setup_log_insights() {
    echo -e "${YELLOW}Setting up CloudWatch Logs Insights queries...${NC}"
    
    # Create saved queries for each service type
    aws cloudwatch put-dashboard \
        --dashboard-name "${DEPLOY_ENV}-logs-insights" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "log",
                    "properties": {
                        "query": "SOURCE '/${DEPLOY_ENV}/trading' | fields @timestamp, @message, @logStream, @log\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 100",
                        "region": "'${AWS_REGION}'",
                        "title": "Recent Errors Across All Services"
                    }
                },
                {
                    "type": "log",
                    "properties": {
                        "query": "SOURCE '/${DEPLOY_ENV}/trading' | stats count(*) as errorCount by service, errorType\n| sort errorCount desc",
                        "region": "'${AWS_REGION}'",
                        "title": "Error Distribution by Service"
                    }
                }
            ]
        }'
}

# Validate logging setup
validate_logging() {
    echo -e "${YELLOW}Validating logging setup...${NC}"
    
    # Check log groups
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        aws logs describe-log-groups \
            --log-group-name-prefix "/${DEPLOY_ENV}/trading/${service}" || {
            echo -e "${RED}Error: Log group not found for ${service}${NC}"
            exit 1
        }
    done
    
    # Check Fluentd status
    kubectl get ds -n logging fluentd || {
        echo -e "${RED}Error: Fluentd not running${NC}"
        exit 1
    }
    
    echo -e "${GREEN}Logging validation completed${NC}"
}

# Main execution
main() {
    setup_log_groups
    setup_fluentd
    setup_log_metrics
    setup_log_insights
    validate_logging
}

main
