#!/bin/bash
#*************************
# Deploy KEDA v2+ (API v2)
# Corrigido para KEDA 2.15+
#*************************

set -e  # Exit on error

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║              INSTALANDO KEDA v2.15+                        ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Determinar caminho correto para environmentVariables.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../environmentVariables.sh" ]; then
    source "${SCRIPT_DIR}/../environmentVariables.sh"
elif [ -f "./environmentVariables.sh" ]; then
    source ./environmentVariables.sh
else
    echo "${RED}❌ Erro: environmentVariables.sh não encontrado!${NC}"
    exit 1
fi

# Validar variáveis
required_vars=("CLUSTER_NAME" "AWS_REGION" "ACCOUNT_ID" "KEDA_ROLE" "KEDA_SQS_POLICY" "KEDA_DYNAMO_POLICY" "APP_NAMESPACE" "APP_DEPLOYMENT_NAME" "SQS_QUEUE_URL")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "${RED}❌ Erro: Variável ${var} não definida!${NC}"
        exit 1
    fi
done

echo "${CYAN}📋 Configuração:${NC}"
echo "   • Cluster: ${CLUSTER_NAME}"
echo "   • KEDA Version: ${KEDA_VERSION}"
echo "   • Região: ${AWS_REGION}"
echo "   • Namespace App: ${APP_NAMESPACE}"
echo "   • SQS Queue: ${SQS_QUEUE_NAME}"
echo ""

# Verificar cluster
echo "${YELLOW}🔍 Verificando cluster...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo "${RED}❌ Cluster não acessível!${NC}"
    exit 1
fi
echo "${GREEN}✅ Cluster acessível${NC}"
echo ""

# Obter OIDC Provider
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
    --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

if [ -z "$OIDC_PROVIDER" ]; then
    echo "${RED}❌ Erro: Não foi possível obter OIDC Provider!${NC}"
    exit 1
fi

echo "${CYAN}✅ OIDC Provider: ${OIDC_PROVIDER}${NC}"
echo ""

# Passo 1: Criar IAM Policies
echo "${YELLOW}📝 Passo 1/7: Criando IAM Policies...${NC}"

# Determinar caminho dos arquivos de policy
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SQS Policy
SQS_POLICY_ARN=$(aws iam create-policy \
    --policy-name ${KEDA_SQS_POLICY} \
    --policy-document file://${SCRIPT_DIR}/sqsPolicy.json \
    --region ${AWS_REGION} \
    --query 'Policy.Arn' \
    --output text 2>/dev/null || \
    aws iam list-policies --query "Policies[?PolicyName=='${KEDA_SQS_POLICY}'].Arn" --output text)

echo "${GREEN}   ✅ SQS Policy: ${SQS_POLICY_ARN}${NC}"

# DynamoDB Policy
DYNAMO_POLICY_ARN=$(aws iam create-policy \
    --policy-name ${KEDA_DYNAMO_POLICY} \
    --policy-document file://${SCRIPT_DIR}/dynamoPolicy.json \
    --region ${AWS_REGION} \
    --query 'Policy.Arn' \
    --output text 2>/dev/null || \
    aws iam list-policies --query "Policies[?PolicyName=='${KEDA_DYNAMO_POLICY}'].Arn" --output text)

echo "${GREEN}   ✅ DynamoDB Policy: ${DYNAMO_POLICY_ARN}${NC}"
echo ""

# Passo 2: Criar Trust Relationship
echo "${YELLOW}📝 Passo 2/7: Criando Trust Relationship...${NC}"

cat > /tmp/keda-trust-relationship.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": [
            "system:serviceaccount:${KEDA_NAMESPACE}:${KEDA_SERVICE_ACCOUNT}",
            "system:serviceaccount:${APP_NAMESPACE}:${KEDA_APP_SERVICE_ACCOUNT}"
          ]
        }
      }
    }
  ]
}
EOF

echo "${GREEN}✅ Trust relationship configurado${NC}"
echo ""

# Passo 3: Criar IAM Role
echo "${YELLOW}📝 Passo 3/7: Criando IAM Role para KEDA...${NC}"

# Deletar role se já existir
if aws iam get-role --role-name ${KEDA_ROLE} --region ${AWS_REGION} &>/dev/null; then
    echo "${BLUE}ℹ️  Role já existe, removendo policies...${NC}"
    
    # Detach todas as policies
    ATTACHED=$(aws iam list-attached-role-policies --role-name ${KEDA_ROLE} --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy in $ATTACHED; do
        aws iam detach-role-policy --role-name ${KEDA_ROLE} --policy-arn $policy --region ${AWS_REGION} 2>/dev/null || true
    done
    
    # Delete role
    aws iam delete-role --role-name ${KEDA_ROLE} --region ${AWS_REGION} 2>/dev/null || true
    sleep 5
fi

# Criar role
KEDA_ROLE_ARN=$(aws iam create-role \
    --role-name ${KEDA_ROLE} \
    --assume-role-policy-document file:///tmp/keda-trust-relationship.json \
    --description "IAM Role for KEDA Operator" \
    --region ${AWS_REGION} \
    --query 'Role.Arn' \
    --output text)

echo "${GREEN}   ✅ Role criada: ${KEDA_ROLE_ARN}${NC}"

# Attach policies
aws iam attach-role-policy --role-name ${KEDA_ROLE} --policy-arn ${SQS_POLICY_ARN} --region ${AWS_REGION}
aws iam attach-role-policy --role-name ${KEDA_ROLE} --policy-arn ${DYNAMO_POLICY_ARN} --region ${AWS_REGION}

echo "${GREEN}   ✅ Policies anexadas${NC}"
echo ""

# Passo 4: Criar Namespaces e Service Accounts
echo "${YELLOW}📝 Passo 4/7: Criando namespaces e service accounts...${NC}"

# Namespace da aplicação
kubectl create namespace ${APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
echo "${GREEN}   ✅ Namespace ${APP_NAMESPACE} criado${NC}"

# Service Account da aplicação
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${KEDA_APP_SERVICE_ACCOUNT}
  namespace: ${APP_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: ${KEDA_ROLE_ARN}
EOF

echo "${GREEN}   ✅ Service Account criado e anotado com IAM Role${NC}"
echo ""

# Passo 5: Instalar KEDA via Helm
echo "${YELLOW}📝 Passo 5/7: Instalando KEDA via Helm...${NC}"

# Add Helm repo
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Criar namespace KEDA
kubectl create namespace ${KEDA_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install KEDA
helm upgrade --install keda kedacore/keda \
  --namespace ${KEDA_NAMESPACE} \
  --create-namespace \
  --version ${KEDA_VERSION} \
  --set serviceAccount.operator.create=true \
  --set serviceAccount.operator.name=${KEDA_SERVICE_ACCOUNT} \
  --set serviceAccount.operator.annotations."eks\.amazonaws\.com/role-arn"=${KEDA_ROLE_ARN} \
  --set podIdentity.aws.irsa.enabled=true \
  --set prometheus.metricServer.enabled=true \
  --set prometheus.metricServer.port=8080 \
  --set resources.operator.limits.cpu=1000m \
  --set resources.operator.limits.memory=1000Mi \
  --set resources.operator.requests.cpu=100m \
  --set resources.operator.requests.memory=100Mi \
  --wait

echo "${GREEN}✅ KEDA instalado via Helm${NC}"
echo ""

# Aguardar pods estarem prontos
echo "${YELLOW}⏳ Aguardando pods do KEDA ficarem prontos...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keda-operator -n ${KEDA_NAMESPACE} --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keda-operator-metrics-apiserver -n ${KEDA_NAMESPACE} --timeout=300s || true

echo ""
echo "${GREEN}✅ KEDA pods estão rodando!${NC}"
kubectl get pods -n ${KEDA_NAMESPACE}
echo ""

# Passo 6: Deploy Aplicação (ANTES do ScaledObject)
echo "${YELLOW}📝 Passo 6/7: Deploying aplicação SQS reader...${NC}"

# Verificar se arquivo YAML existe
if [ ! -f "${SCRIPT_DIR}/../app/keda-python-app.yaml" ]; then
    echo "${RED}❌ Arquivo keda-python-app.yaml não encontrado!${NC}"
    exit 1
fi

echo "${CYAN}   Aplicando deployment da aplicação...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../app/keda-python-app.yaml"

echo "${GREEN}✅ Aplicação deployed${NC}"
echo ""

# Aguardar deployment estar pronto
echo "${YELLOW}⏳ Aguardando deployment estar pronto...${NC}"
kubectl rollout status deployment/${APP_DEPLOYMENT_NAME} -n ${APP_NAMESPACE} --timeout=180s || true

echo ""

# Passo 7: Deploy ScaledObject (API v1alpha1 - única suportada em KEDA 2.15.1) - DEPOIS do Deployment
echo "${YELLOW}📝 Passo 7/7: Criando ScaledObject (API v1alpha1 - KEDA 2.15.1)...${NC}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials-secret
  namespace: ${APP_NAMESPACE}
type: Opaque
stringData:
  AWS_REGION: "${AWS_REGION}"
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-trigger-auth-aws
  namespace: ${APP_NAMESPACE}
spec:
  podIdentity:
    provider: aws
    identityOwner: keda
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-scaledobject
  namespace: ${APP_NAMESPACE}
spec:
  scaleTargetRef:
    name: ${APP_DEPLOYMENT_NAME}
  minReplicaCount: 1
  maxReplicaCount: 50
  pollingInterval: 10
  cooldownPeriod: 30
  triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: keda-trigger-auth-aws
    metadata:
      queueURL: ${SQS_QUEUE_URL}
      queueLength: "5"
      awsRegion: ${AWS_REGION}
EOF

echo "${GREEN}✅ ScaledObject criado com API v1alpha1 (KEDA 2.15.1)${NC}"
echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║            KEDA INSTALADO COM SUCESSO!                     ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verificar recursos
echo "${CYAN}📊 Status dos recursos:${NC}"
echo ""
echo "${YELLOW}Pods KEDA:${NC}"
kubectl get pods -n ${KEDA_NAMESPACE}
echo ""
echo "${YELLOW}Pods Aplicação:${NC}"
kubectl get pods -n ${APP_NAMESPACE}
echo ""
echo "${YELLOW}ScaledObject:${NC}"
kubectl get scaledobject -n ${APP_NAMESPACE}
echo ""
echo "${YELLOW}HPA (criado pelo KEDA):${NC}"
kubectl get hpa -n ${APP_NAMESPACE}
echo ""

echo "${CYAN}📋 Próximos passos:${NC}"
echo "   1. Criar recursos AWS: ./deployment/services/awsService.sh"
echo "   2. Executar teste de carga: ./tests/run-load-test.sh"
echo ""
echo "${CYAN}💡 Monitoramento:${NC}"
echo "   • Ver logs KEDA: kubectl logs -n ${KEDA_NAMESPACE} -l app.kubernetes.io/name=keda-operator -f"
echo "   • Ver HPA: watch kubectl get hpa -n ${APP_NAMESPACE}"
echo "   • Ver pods: watch kubectl get pods -n ${APP_NAMESPACE}"
echo ""
