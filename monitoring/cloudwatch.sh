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

# Setup CloudWatch agent for all services
setup_cloudwatch_agent() {
    echo -e "${YELLOW}Setting up CloudWatch agent...${NC}"
    
    # Create CloudWatch agent configuration for trading services
    cat > cwagent-trading-config.json <<EOF
{
    "agent": {
        "metrics_collection_interval": 60
    },
    "metrics": {
        "metrics_collected": {
            "kubernetes": {
                "cluster_name": "${CLUSTER_NAME}",
                "metrics_collection_interval": 60
            },
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"]
            },
            "memory": {
                "measurement": ["mem_used_percent"]
            },
            "disk": {
                "measurement": ["disk_used_percent"],
                "resources": ["/"]
            }
        },
        "append_dimensions": {
            "InstanceId": "\${aws:InstanceId}",
            "Environment": "${DEPLOY_ENV}",
            "ClusterName": "${CLUSTER_NAME}"
        }
    }
}
EOF

    # Store CloudWatch agent configuration in SSM
    aws ssm put-parameter \
        --name "/${DEPLOY_ENV}/cloudwatch/trading-agent-config" \
        --type String \
        --value file://cwagent-trading-config.json \
        --overwrite
}

# Setup CloudWatch alarms for all services
setup_alarms() {
    echo -e "${YELLOW}Setting up CloudWatch alarms...${NC}"
    
    # Setup alarms for Core Services
    for service in ${CORE_SERVICES}; do
        # CPU utilization alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${DEPLOY_ENV}-${service}-high-cpu" \
            --alarm-description "CPU utilization exceeded 80% for ${service}" \
            --namespace "Trading/${DEPLOY_ENV}" \
            --metric-name CPUUtilization \
            --dimensions Name=ServiceName,Value=${service} \
            --statistic Average \
            --period 300 \
            --threshold 80 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "${SNS_TOPIC_ARN}"

        # Memory utilization alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${DEPLOY_ENV}-${service}-high-memory" \
            --alarm-description "Memory utilization exceeded 80% for ${service}" \
            --namespace "Trading/${DEPLOY_ENV}" \
            --metric-name MemoryUtilization \
            --dimensions Name=ServiceName,Value=${service} \
            --statistic Average \
            --period 300 \
            --threshold 80 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "${SNS_TOPIC_ARN}"

        # Error rate alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${DEPLOY_ENV}-${service}-error-rate" \
            --alarm-description "Error rate exceeded 5% for ${service}" \
            --namespace "Trading/${DEPLOY_ENV}" \
            --metric-name ErrorRate \
            --dimensions Name=ServiceName,Value=${service} \
            --statistic Average \
            --period 300 \
            --threshold 5 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "${SNS_TOPIC_ARN}"
    done

    # Setup Business Service specific alarms
    for service in ${BUSINESS_SERVICES}; do
        # Service latency alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${DEPLOY_ENV}-${service}-high-latency" \
            --alarm-description "Service latency exceeded threshold for ${service}" \
            --namespace "Trading/${DEPLOY_ENV}" \
            --metric-name ServiceLatency \
            --dimensions Name=ServiceName,Value=${service} \
            --statistic Average \
            --period 300 \
            --threshold 1000 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "${SNS_TOPIC_ARN}"

        # Transaction failure rate alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${DEPLOY_ENV}-${service}-transaction-failures" \
            --alarm-description "Transaction failure rate exceeded threshold for ${service}" \
            --namespace "Trading/${DEPLOY_ENV}" \
            --metric-name TransactionFailureRate \
            --dimensions Name=ServiceName,Value=${service} \
            --statistic Average \
            --period 300 \
            --threshold 1 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "${SNS_TOPIC_ARN}"
    done
}

# Setup service-specific dashboards
setup_dashboards() {
    echo -e "${YELLOW}Setting up CloudWatch dashboards...${NC}"
    
    # Create main trading dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DEPLOY_ENV}-trading-overview" \
        --dashboard-body file://monitoring/dashboards/trading-overview.json

    # Create service-specific dashboards
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        # Generate dashboard configuration
        cat > "dashboard-${service}.json" <<EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["Trading/${DEPLOY_ENV}", "CPUUtilization", "ServiceName", "${service}"],
                    [".", "MemoryUtilization", ".", "."],
                    [".", "ErrorRate", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "${service} Metrics"
            }
        }
    ]
}
EOF

        # Create dashboard
        aws cloudwatch put-dashboard \
            --dashboard-name "${DEPLOY_ENV}-${service}" \
            --dashboard-body file://dashboard-${service}.json
    done
}

# Setup Container Insights
setup_container_insights() {
    echo -e "${YELLOW}Setting up Container Insights...${NC}"
    
    # Enable Container Insights for the cluster
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: amazon-cloudwatch
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cloudwatch-agent
  namespace: amazon-cloudwatch
spec:
  selector:
    matchLabels:
      name: cloudwatch-agent
  template:
    metadata:
      labels:
        name: cloudwatch-agent
    spec:
      containers:
        - name: cloudwatch-agent
          image: amazon/cloudwatch-agent:latest
          env:
            - name: CLUSTER_NAME
              value: ${CLUSTER_NAME}
            - name: HOST_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
          volumeMounts:
            - name: cwagentconfig
              mountPath: /etc/cwagentconfig
      volumes:
        - name: cwagentconfig
          configMap:
            name: cwagent-trading-config
EOF
}

# Validate monitoring setup
validate_monitoring() {
    echo -e "${YELLOW}Validating monitoring setup...${NC}"
    
    # Check CloudWatch agent status
    kubectl get daemonset cloudwatch-agent -n amazon-cloudwatch || {
        echo -e "${RED}Error: CloudWatch agent not running${NC}"
        exit 1
    }
    
    # Check if metrics are being collected
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        aws cloudwatch list-metrics \
            --namespace "Trading/${DEPLOY_ENV}" \
            --dimensions Name=ServiceName,Value=${service} || {
            echo -e "${RED}Error: Metrics not found for ${service}${NC}"
            exit 1
        }
    done
    
    echo -e "${GREEN}Monitoring validation completed${NC}"
}

# Main execution
main() {
    setup_cloudwatch_agent
    setup_alarms
    setup_dashboards
    setup_container_insights
    validate_monitoring
}

main
