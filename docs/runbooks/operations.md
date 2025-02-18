# Operations Runbook

## Common Operations
1. Deploying Updates
   ./deploy.sh --environment [dev|staging|prod]

2. Scaling Services
   kubectl scale deployment frontend --replicas=3

3. Database Backup
   ./backup.sh --database trading

## Monitoring
1. Accessing Grafana
   - URL: https://grafana.${DOMAIN_NAME}
   - Default credentials in AWS Secrets Manager

2. Checking Logs
   - CloudWatch Logs
   - Kibana Dashboard

## Troubleshooting
1. Pod Crashes
   - Check logs: kubectl logs [pod-name]
   - Check events: kubectl describe pod [pod-name]

2. Database Issues
   - Check connectivity
   - Check RDS metrics
   - Review slow query logs
