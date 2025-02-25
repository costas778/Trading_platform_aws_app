#!/bin/bash

# Create a timestamp for the report
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="kubernetes_diagnostic_report_${TIMESTAMP}.txt"

{
    echo "Kubernetes Diagnostic Report - $(date)"
    echo "======================================"
    echo

    echo "1. Pod Status"
    echo "-------------"
    kubectl get pods
    echo

    echo "2. Deployment Status"
    echo "-------------------"
    kubectl get deployments
    echo

    echo "3. Image References in Deployments"
    echo "--------------------------------"
    kubectl get deployments -o yaml | grep -A 2 "image:"
    echo

    echo "4. Logs from CrashLoopBackOff Pods"
    echo "---------------------------------"
    echo "Portfolio Management Pod Logs:"
    kubectl logs portfolio-management-6f8cd7d457-n5f6k
    echo
    echo "Price Feed Pod Logs:"
    kubectl logs price-feed-5f46b79fb5-54mp7
    echo

    echo "5. Pending Pod Details"
    echo "---------------------"
    echo "Portfolio Management Pending Pod:"
    kubectl describe pod portfolio-management-75d9cd8c54-q4jn8
    echo
    echo "Position Management Pending Pod:"
    kubectl describe pod position-management-6ffd47885f-th77g
    echo

    echo "6. ECR Repository Status"
    echo "-----------------------"
    echo "List of ECR Repositories:"
    aws ecr describe-repositories
    echo

    echo "7. ECR Images Status"
    echo "-------------------"
    for repo in portfolio-management position-management price-feed; do
        echo "Images in ${repo}:"
        aws ecr describe-images --repository-name ${repo} 2>/dev/null || echo "No images found or repository doesn't exist"
        echo
    done

    echo "8. Node Status"
    echo "-------------"
    kubectl get nodes
    echo
    kubectl describe nodes
    echo

    echo "9. Resource Quotas"
    echo "----------------"
    kubectl get resourcequota
    kubectl describe resourcequota
    echo

    echo "10. Events"
    echo "---------"
    kubectl get events --sort-by='.lastTimestamp'
    echo

} > "${REPORT_FILE}"

echo "Diagnostic report has been created: ${REPORT_FILE}"
echo "You can view it using: cat ${REPORT_FILE}"
