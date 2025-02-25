#!/bin/bash

# Set error handling
set -e

# Color codes for output
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
NC=$(printf '\033[0m')

# Configuration
AWS_REGION="us-east-1"
BASE_DIR="/home/costas778/abc/trading-platform"
ECR_REPOSITORY_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

# Services configuration with ports
declare -A SERVICES=(
    ["api-gateway"]="8097"
    ["audit"]="8080"
    ["authentication"]="8080"
    ["authorization"]="8080"
    ["cache"]="8080"
    ["compliance"]="8080"
    ["logging"]="8080"
    ["market-data"]="8080"
    ["message-queue"]="8024"
    ["notification"]="8080"
    ["order-management"]="8080"
    ["portfolio-management"]="8080"
    ["position-management"]="8080"
    ["price-feed"]="8080"
    ["quote-service"]="8080"
    ["reporting"]="8080"
    ["risk-management"]="8080"
    ["settlement"]="8080"
    ["trade-execution"]="8080"
    ["user-management"]="8080"
)

# Logging functions
log() {
    printf "${GREEN}[%s] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
    printf "${YELLOW}[%s] WARNING: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

error() {
    printf "${RED}[%s] ERROR: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    exit 1
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    for service in "${!SERVICES[@]}"; do
        SERVICE_DIR="$BASE_DIR/$service"
        log "Setting up $service in $SERVICE_DIR"
        
        # Create service directory
        mkdir -p "$SERVICE_DIR"
        
        # Create Dockerfile
        cat << EOF > "$SERVICE_DIR/Dockerfile"
FROM openjdk:17-slim

WORKDIR /app

COPY target/*.jar app.jar

EXPOSE ${SERVICES[$service]}

ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
        
        # Create Maven project structure
        mkdir -p "$SERVICE_DIR/src/main/java"
        mkdir -p "$SERVICE_DIR/src/main/resources"
        mkdir -p "$SERVICE_DIR/src/test/java"
        
        # Create pom.xml
        cat << EOF > "$SERVICE_DIR/pom.xml"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.abc.trading</groupId>
    <artifactId>${service}</artifactId>
    <version>1.0-SNAPSHOT</version>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
    </parent>

    <properties>
        <java.version>17</java.version>
        <spring-cloud.version>2023.0.0</spring-cloud.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF

        # Create Application class
        mkdir -p "$SERVICE_DIR/src/main/java/com/abc/trading/${service//-/}"
        cat << EOF > "$SERVICE_DIR/src/main/java/com/abc/trading/${service//-/}/Application.java"
package com.abc.trading.${service//-/};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
EOF

        # Create application.properties
        cat << EOF > "$SERVICE_DIR/src/main/resources/application.properties"
server.port=${SERVICES[$service]}
spring.application.name=${service}
EOF
    done
}

# Setup Java environment
setup_java_environment() {
    log "Setting up Java environment..."
    
    if ! command -v java &> /dev/null; then
        error "Java is not installed"
    fi

    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    elif [ -d "/usr/lib/jvm/java-17-openjdk" ]; then
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
    else
        log "Java 17 not found. Attempting to install..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y openjdk-17-jdk
            export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
        elif command -v yum &> /dev/null; then
            sudo yum install -y java-17-openjdk-devel
            export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
        else
            error "Could not install Java 17. Please install it manually."
        fi
    fi

    if command -v update-alternatives &> /dev/null; then
        log "Configuring Java alternatives..."
        sudo update-alternatives --install /usr/bin/java java "${JAVA_HOME}/bin/java" 1
        sudo update-alternatives --install /usr/bin/javac javac "${JAVA_HOME}/bin/javac" 1
        sudo update-alternatives --set java "${JAVA_HOME}/bin/java"
        sudo update-alternatives --set javac "${JAVA_HOME}/bin/javac"
    fi

    export JAVA_HOME
    export PATH="${JAVA_HOME}/bin:$PATH"

    java_version=$("${JAVA_HOME}/bin/java" -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)
    if [ "$java_version" != "17" ]; then
        error "Java 17 is required but version $java_version was found. JAVA_HOME=${JAVA_HOME}"
    fi

    log "Using Java 17 from: $JAVA_HOME"
    log "Java version: $("${JAVA_HOME}/bin/java" -version 2>&1)"
}

# Build Maven projects
build_maven_projects() {
    log "Building Maven projects..."
    for service in "${!SERVICES[@]}"; do
        SERVICE_DIR="$BASE_DIR/$service"
        if [ -f "$SERVICE_DIR/pom.xml" ]; then
            log "Building $service..."
            (cd "$SERVICE_DIR" && \
             JAVA_HOME="$JAVA_HOME" \
             "${JAVA_HOME}/bin/java" -version && \
             mvn clean package -DskipTests \
                -Dmaven.compiler.source=17 \
                -Dmaven.compiler.target=17 \
                -Dmaven.compiler.release=17 \
                -Djava.home="$JAVA_HOME")
        else
            warn "No pom.xml found for $service, skipping build..."
        fi
    done
}

# Create ECR repositories
create_ecr_repositories() {
    log "Creating ECR repositories..."
    for service in "${!SERVICES[@]}"; do
        if aws ecr describe-repositories --repository-names "$service" 2>/dev/null; then
            warn "Repository $service already exists, skipping..."
        else
            log "Creating repository for $service..."
            aws ecr create-repository \
                --repository-name "$service" \
                --image-scanning-configuration scanOnPush=true \
                --encryption-configuration encryptionType=AES256
        fi
    done
}

# Get ECR login token
ecr_login() {
    log "Logging into ECR..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com"
}

# Build and push Docker images
build_and_push_images() {
    log "Building and pushing Docker images..."
    
    for service in "${!SERVICES[@]}"; do
        SERVICE_DIR="$BASE_DIR/$service"
        if [ -f "$SERVICE_DIR/Dockerfile" ]; then
            log "Building Docker image for $service..."
            (cd "$SERVICE_DIR" && docker build -t "$service" .)
            
            REPO_URI="${ECR_REPOSITORY_PREFIX}/$service"
            
            log "Tagging $service..."
            docker tag "$service:latest" "$REPO_URI:latest"
            
            log "Pushing $service to ECR..."
            docker push "$REPO_URI:latest" || {
                error "Failed to push image for $service"
            }
            log "Successfully pushed image for $service"
        else
            warn "No Dockerfile found for $service, skipping..."
        fi
    done
}

# Update Kubernetes deployments
update_k8s_deployments() {
    log "Updating Kubernetes deployments..."
    
    for service in "${!SERVICES[@]}"; do
        REPO_URI="${ECR_REPOSITORY_PREFIX}/$service:latest"
        
        log "Updating deployment for $service..."
        if kubectl get deployment "$service" &>/dev/null; then
            kubectl patch deployment "$service" -p \
                '{"spec":{"template":{"spec":{"containers":[{"name":"'"$service"'","image":"'"$REPO_URI"'"}]}}}}' || {
                error "Failed to update deployment for $service"
            }
            log "Successfully updated deployment for $service"
        else
            warn "Deployment $service does not exist, skipping..."
        fi
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
    fi
    
    if ! command -v mvn &> /dev/null; then
        error "Maven is not installed"
    fi
    
    if ! command -v java &> /dev/null; then
        error "Java is not installed"
    fi
}

# Main execution
main() {
    log "Starting complete setup process..."
    
    check_prerequisites
    setup_java_environment
    create_project_structure
    build_maven_projects
    create_ecr_repositories
    ecr_login
    build_and_push_images
    update_k8s_deployments
    
    log "Setup completed successfully!"
}

# Execute main function
main
