#!/bin/bash
#*************************
# Environment Variables - KEDA & Karpenter Lab v2
# Atualizado com versões compatíveis - Janeiro 2026
#*************************

echo "🔧 Carregando variáveis de ambiente..."

# AWS Configuration
export AWS_REGION="${AWS_REGION:-us-east-1}"
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
export TEMPOUT=$(mktemp)

# Validar que temos ACCOUNT_ID
if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Erro: Não foi possível obter ACCOUNT_ID. Verifique suas credenciais AWS."
    echo "Execute: aws configure"
    exit 1
fi

# Cluster Configuration
export CLUSTER_NAME="${CLUSTER_NAME:-eks-demo-scale-v2}"
export K8S_VERSION="${K8S_VERSION:-1.31}"

# Karpenter Configuration - VERSÃO ATUALIZADA!
export KARPENTER_VERSION="${KARPENTER_VERSION:-0.16.3}"  # Compatível com EKS 1.31
export KARPENTER_NAMESPACE="karpenter"

# KEDA Configuration
export KEDA_VERSION="${KEDA_VERSION:-2.15.1}"  # Versão estável atual
export KEDA_NAMESPACE="keda"
export KEDA_SERVICE_ACCOUNT="keda-operator"
export KEDA_APP_SERVICE_ACCOUNT="keda-service-account"

# Application Configuration
export APP_NAMESPACE="keda-test"
export APP_DEPLOYMENT_NAME="sqs-app"

# IAM Roles and Policies
export KARPENTER_NODE_ROLE="KarpenterNodeRole-${CLUSTER_NAME}"
export KARPENTER_CONTROLLER_ROLE="KarpenterControllerRole-${CLUSTER_NAME}"
export KARPENTER_CONTROLLER_POLICY="KarpenterControllerPolicy-${CLUSTER_NAME}"
export KEDA_ROLE="KedaDemoRole-${CLUSTER_NAME}"
export KEDA_SQS_POLICY="KedaSQSPolicy-${CLUSTER_NAME}"
export KEDA_DYNAMO_POLICY="KedaDynamoPolicy-${CLUSTER_NAME}"

# AWS Services
export SQS_QUEUE_NAME="${SQS_QUEUE_NAME:-keda-demo-queue.fifo}"
export SQS_QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${ACCOUNT_ID}/${SQS_QUEUE_NAME}"
export DYNAMODB_TABLE="${DYNAMODB_TABLE:-payments}"

# Instance Profile
export KARPENTER_INSTANCE_PROFILE="KarpenterNodeInstanceProfile-${CLUSTER_NAME}"

# Colors for output
export RED=$(tput setaf 1)
export GREEN=$(tput setaf 2)
export YELLOW=$(tput setaf 3)
export BLUE=$(tput setaf 4)
export CYAN=$(tput setaf 6)
export MAGENTA=$(tput setaf 5)
export NC=$(tput sgr0)  # No Color

# Validação de variáveis críticas
echo ""
echo "${GREEN}✅ Variáveis carregadas com sucesso:${NC}"
echo "${CYAN}   • AWS Region:${NC} ${AWS_REGION}"
echo "${CYAN}   • Account ID:${NC} ${ACCOUNT_ID}"
echo "${CYAN}   • Cluster Name:${NC} ${CLUSTER_NAME}"
echo "${CYAN}   • Kubernetes:${NC} ${K8S_VERSION}"
echo "${CYAN}   • Karpenter:${NC} ${KARPENTER_VERSION}"
echo "${CYAN}   • KEDA:${NC} ${KEDA_VERSION}"
echo ""
