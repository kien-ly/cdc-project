#!/bin/bash

# CDC Project Automation Script
# This script automates the complete setup of a Change Data Capture (CDC) pipeline
# for local development and testing with AWS RDS PostgreSQL and S3

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Docker Desktop
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker Desktop."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    # Check Kubernetes
    if ! command_exists kubectl; then
        print_error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    # Check if Kubernetes is running
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Kubernetes cluster is not accessible. Please ensure Docker Desktop Kubernetes is enabled."
        exit 1
    fi
    
    # Check Helm
    if ! command_exists helm; then
        print_error "Helm is not installed. Please install Helm 3.x."
        exit 1
    fi
    
    # Check curl
    if ! command_exists curl; then
        print_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check jq
    if ! command_exists jq; then
        print_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    print_success "All prerequisites are satisfied"
}

# Function to load environment variables
load_environment() {
    print_status "Loading environment variables..."
    
    # Check if .env file exists
    if [ -f .env ]; then
        print_status "Found .env file, loading environment variables..."
        source .env
        print_success "Environment variables loaded from .env"
    else
        print_warning "No .env file found. Please create one from env.template"
        print_status "Using default values from env.template..."
        source env.template
        print_warning "Using template values. Please create .env file with your actual values."
    fi
    
    # Validate required environment variables
    local required_vars=(
        "AWS_RDS_ENDPOINT"
        "AWS_RDS_DBNAME"
        "AWS_RDS_USER"
        "AWS_RDS_PASSWORD"
        "AWS_REGION"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
        "S3_BUCKET_NAME"
        "MAC_LOCAL_IP"
        "POSTGRES_SCHEMA_TO_TRACK"
        "POSTGRES_TABLE_TO_TRACK"
        "REPLICATION_SLOT_NAME"
        "NAMESPACE"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    # Export all environment variables so they are available to child scripts
    export AWS_RDS_ENDPOINT
    export AWS_RDS_DBNAME
    export AWS_RDS_USER
    export AWS_RDS_PASSWORD
    export AWS_RDS_PORT
    export AWS_REGION
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export S3_BUCKET_NAME
    export MAC_LOCAL_IP
    export POSTGRES_SCHEMA_TO_TRACK
    export POSTGRES_TABLE_TO_TRACK
    export REPLICATION_SLOT_NAME
    export DEBEZIUM_CONNECTOR_VERSION
    export S3_SINK_CONNECTOR_VERSION
    export NAMESPACE
    export REDPANDA_REPLICAS
    export AWS_PROFILE
    
    print_success "Environment variables validated and exported"
}

# Function to setup port forwarding
setup_port_forwarding() {
    print_status "Setting up port forwarding for Kafka Connect REST API..."
    
    # Use the dedicated script for robust port-forwarding
    scripts/port-forward-kafka-connect.sh &
    local pf_pid=$!
    
    # Wait a moment for port forwarding to establish
    sleep 5
    
    # Check if port forwarding is working
    if curl -s http://localhost:8083/ >/dev/null 2>&1; then
        print_success "Port forwarding established for Kafka Connect REST API"
        echo $pf_pid > .port-forward.pid
    else
        print_error "Failed to establish port forwarding"
        kill $pf_pid 2>/dev/null || true
        exit 1
    fi
}

# Function to deploy and verify connectors
deploy_connectors() {
    print_status "Deploying and verifying CDC connectors..."

    local connectors=("debezium-postgres" "s3-sink")
    local all_successful=true

    for connector_name in "${connectors[@]}"; do
        print_status "--- Processing connector: $connector_name ---"

        # 1. Delete existing connector for a clean slate
        print_status "Attempting to delete existing connector '$connector_name'..."
        delete_response_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "http://localhost:8083/connectors/$connector_name")
        if [[ "$delete_response_code" == "204" ]]; then
            print_success "Connector '$connector_name' deleted successfully."
            sleep 3 # Give connect time to remove it
        elif [[ "$delete_response_code" == "404" ]]; then
            print_status "Connector '$connector_name' did not exist. Moving on."
        else
            print_warning "Received unexpected code $delete_response_code when trying to delete connector '$connector_name'."
        fi

        # 2. Load connector configuration from JSON file
        print_status "Loading configuration for '$connector_name'..."
        local config_file="connectors/$connector_name.json"
        if [ ! -f "$config_file" ]; then
            print_error "Configuration file $config_file not found."
            all_successful=false
            continue
        fi

        # 3. Substitute environment variables
        local config_json
        if [[ "$connector_name" == "s3-sink" ]]; then
            # S3 sink config has characters that conflict with envsubst default behavior.
            # Specify only the variables that need to be substituted.
            config_json=$(envsubst '\$AWS_REGION \$S3_BUCKET_NAME \$POSTGRES_SCHEMA_TO_TRACK \$POSTGRES_TABLE_TO_TRACK' < "$config_file")
        else
            # For other connectors, the default behavior is fine.
            config_json=$(envsubst < "$config_file")
        fi

        # 4. Deploy the connector
        print_status "Deploying connector '$connector_name'..."
        deploy_response_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "$config_json" http://localhost:8083/connectors)

        if [[ "$deploy_response_code" -ne "201" ]]; then
            print_error "Failed to deploy connector '$connector_name'. Received HTTP code: $deploy_response_code"
            print_error "Request body: $config_json"
            # Try to get more info from the API
            curl -s -X POST -H "Content-Type: application/json" --data "$config_json" http://localhost:8083/connectors
            all_successful=false
            continue
        else
            print_success "Connector '$connector_name' configuration submitted successfully."
        fi

        # 5. Verify connector and task status
        print_status "Verifying status for connector '$connector_name'..."
        for i in {1..60}; do # Wait for up to 5 minutes (60 * 5s)
            local status_json=$(curl -s "http://localhost:8083/connectors/$connector_name/status")
            local connector_state=$(echo "$status_json" | jq -r '.connector.state')
            
            if [[ "$connector_state" == "RUNNING" ]]; then
                local tasks_failed=$(echo "$status_json" | jq -r '.tasks[] | select(.state=="FAILED") | .id')
                if [ -n "$tasks_failed" ]; then
                    print_error "Connector '$connector_name' is RUNNING, but has FAILED tasks!"
                    echo "$status_json" | jq '.tasks[] | select(.state=="FAILED")'
                    all_successful=false
                    break 2 # Break both loops
                fi
                
                local tasks_running=$(echo "$status_json" | jq -r '.tasks[] | select(.state=="RUNNING") | .id')
                local task_count=$(echo "$status_json" | jq -r '.tasks | length')

                if [[ -n "$tasks_running" && "$task_count" -gt 0 ]]; then
                     print_success "Connector '$connector_name' and all its tasks are RUNNING."
                     break
                else
                     print_status "Connector '$connector_name' is RUNNING, but tasks are not yet. Waiting... ($i/60)"
                fi
            else
                print_status "Connector '$connector_name' state is '$connector_state'. Waiting... ($i/60)"
            fi
            
            if [ $i -eq 60 ]; then
                print_error "Timed out waiting for connector '$connector_name' to become healthy."
                echo "$status_json" | jq .
                all_successful=false
                break
            fi
            sleep 5
        done
    done

    if [ "$all_successful" = false ]; then
        print_error "One or more connectors failed to deploy or become healthy. Please check the logs."
        exit 1
    fi

    print_success "All connectors deployed and verified successfully!"
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying CDC deployment..."
    
    # Run verification script
    if [ -f scripts/verify-deployment.sh ]; then
        chmod +x scripts/verify-deployment.sh
        ./scripts/verify-deployment.sh
    else
        print_warning "Verification script not found, running basic checks..."
        
        # Basic verification
        kubectl get pods -n "$NAMESPACE"
        kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic list
        curl -s http://localhost:8083/connectors | jq .
    fi
}

# Function to cleanup
cleanup() {
    print_status "Cleaning up..."
    
    # Kill port forwarding
    if [ -f .port-forward.pid ]; then
        local pf_pid=$(cat .port-forward.pid)
        kill $pf_pid 2>/dev/null || true
        rm -f .port-forward.pid
    fi
    
    # Kill any remaining port forwarding processes
    pkill -f "kubectl port-forward.*kafka-connect.*8083" || true
    
    # print_success "Cleanup completed"
    print_success "not clear yet"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --verify-only       Only verify the deployment (skip setup)"
    echo "  --cleanup           Clean up the deployment"
    echo "  --no-port-forward   Skip port forwarding setup"
    echo ""
    echo "Examples:"
    echo "  $0                  # Full setup and deployment"
    echo "  $0 --verify-only    # Only verify existing deployment"
    echo "  $0 --cleanup        # Clean up deployment"
}

# Main script logic
main() {
    local verify_only=false
    local cleanup_mode=false
    local no_port_forward=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            --cleanup)
                cleanup_mode=true
                shift
                ;;
            --no-port-forward)
                no_port_forward=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up trap for cleanup on exit
    trap cleanup EXIT
    
    print_status "Starting CDC Project Automation"
    echo "======================================"
    
    if [ "$cleanup_mode" = true ]; then
        print_status "Cleanup mode enabled"
        cleanup
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Load environment variables
    load_environment
    
    if [ "$verify_only" = true ]; then
        print_status "Verify-only mode enabled"
        if [ "$no_port_forward" = false ]; then
            setup_port_forwarding
        fi
        verify_deployment
        exit 0
    fi
    
    # Make scripts executable
    chmod +x scripts/*.sh
    
    # Step 1: Deploy Redpanda
    print_status "Step 1: Deploying Redpanda cluster..."
    ./scripts/setup-redpanda.sh
    
    # Step 2: Deploy Kafka Connect
    print_status "Step 2: Deploying Kafka Connect..."
    ./scripts/setup-connect.sh
    
    # Step 3: Setup port forwarding
    if [ "$no_port_forward" = false ]; then
        print_status "Step 3: Setting up port forwarding..."
        setup_port_forwarding
    fi
    
    # Step 4: Deploy connectors
    print_status "Step 4: Deploying CDC connectors..."
    deploy_connectors
    
    # Step 5: Verify deployment
    print_status "Step 5: Verifying deployment..."
    verify_deployment
    
    print_success "CDC Project setup completed successfully!"
    echo ""
    print_status "Next steps:"
    echo "  1. Test CDC by making changes to your PostgreSQL table"
    echo "  2. Monitor data flow: RDS → Redpanda → S3"
    echo "  3. Check S3 bucket for CDC data files"
    echo "  4. Use 'kubectl logs' to monitor connector logs"
    echo ""
    print_status "Useful commands:"
    echo "  - Check connector status: curl -s http://localhost:8083/connectors | jq"
    echo "  - Monitor Redpanda topics: kubectl exec -n $NAMESPACE redpanda-0 -- rpk topic list"
    echo "  - Check S3 data: aws s3 ls s3://$S3_BUCKET_NAME --recursive"
    echo "  - View logs: kubectl logs -n $NAMESPACE -l app=kafka-connect -f"
    echo ""
    print_status "To clean up: $0 --cleanup"
}

# Run main function with all arguments
main "$@" 