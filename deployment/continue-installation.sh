#!/bin/bash
#*************************
# Continuar Instalação - Executar apenas o que falta
#*************************

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Importar variáveis de ambiente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source ./environmentVariables.sh

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║        CONTINUAR INSTALAÇÃO DE ONDE PAROU                 ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verificar estado atual
echo "${CYAN}🔍 Verificando o que já está instalado...${NC}"
echo ""

NEEDS_DYNAMO=false
NEEDS_ECR=false
NEEDS_APP=false

# 1. Verificar Cluster
echo -n "${YELLOW}1. Cluster EKS: ${NC}"
if kubectl cluster-info &>/dev/null; then
    echo "${GREEN}✅ OK${NC}"
else
    echo "${RED}❌ ERRO - Cluster não acessível!${NC}"
    exit 1
fi

# 2. Verificar Karpenter
echo -n "${YELLOW}2. Karpenter: ${NC}"
if kubectl get pods -n karpenter 2>/dev/null | grep -q Running; then
    echo "${GREEN}✅ OK${NC}"
else
    echo "${RED}❌ ERRO - Karpenter não está rodando!${NC}"
    exit 1
fi

# 3. Verificar KEDA
echo -n "${YELLOW}3. KEDA: ${NC}"
if kubectl get pods -n keda 2>/dev/null | grep -q Running; then
    echo "${GREEN}✅ OK${NC}"
else
    echo "${RED}❌ ERRO - KEDA não está rodando!${NC}"
    exit 1
fi

# 4. Verificar SQS
echo -n "${YELLOW}4. SQS Queue: ${NC}"
if aws sqs get-queue-url --queue-name ${SQS_QUEUE_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "${GREEN}✅ OK${NC}"
else
    echo "${YELLOW}⚠️  Não existe (será criado)${NC}"
fi

# 5. Verificar DynamoDB
echo -n "${YELLOW}5. DynamoDB Table: ${NC}"
if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} &>/dev/null; then
    echo "${GREEN}✅ OK${NC}"
else
    echo "${YELLOW}⚠️  Não existe (será criado)${NC}"
    NEEDS_DYNAMO=true
fi

# 6. Verificar ECR
echo -n "${YELLOW}6. ECR Repository: ${NC}"
if aws ecr describe-repositories --repository-names keda-sqs-reader --region ${AWS_REGION} &>/dev/null; then
    echo "${GREEN}✅ OK${NC}"
else
    echo "${YELLOW}⚠️  Não existe (será criado)${NC}"
    NEEDS_ECR=true
fi

# 7. Verificar Aplicação
echo -n "${YELLOW}7. Aplicação (pods): ${NC}"
if kubectl get deployment -n ${APP_NAMESPACE} ${APP_DEPLOYMENT_NAME} &>/dev/null; then
    POD_COUNT=$(kubectl get pods -n ${APP_NAMESPACE} -l app=sqs-reader --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
        echo "${GREEN}✅ OK ($POD_COUNT pods)${NC}"
    else
        echo "${YELLOW}⚠️  Deployment existe mas sem pods (será corrigido)${NC}"
        NEEDS_APP=true
    fi
else
    echo "${YELLOW}⚠️  Não existe (será criado)${NC}"
    NEEDS_APP=true
fi

echo ""
echo "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo "${CYAN}  ETAPAS NECESSÁRIAS${NC}"
echo "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL_STEPS=0

if [ "$NEEDS_DYNAMO" = true ]; then
    echo "${YELLOW}→ Criar DynamoDB Table${NC}"
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

if [ "$NEEDS_ECR" = true ]; then
    echo "${YELLOW}→ Criar ECR Repository e Build Docker Image${NC}"
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

if [ "$NEEDS_APP" = true ]; then
    echo "${YELLOW}→ Deploy da Aplicação${NC}"
    TOTAL_STEPS=$((TOTAL_STEPS + 1))
fi

if [ $TOTAL_STEPS -eq 0 ]; then
    echo "${GREEN}✅ Tudo já está instalado!${NC}"
    echo ""
    echo "${CYAN}📊 Status dos recursos:${NC}"
    echo ""
    kubectl get nodes
    echo ""
    kubectl get pods -n karpenter
    echo ""
    kubectl get pods -n keda
    echo ""
    kubectl get pods -n ${APP_NAMESPACE}
    echo ""
    kubectl get scaledobject -n ${APP_NAMESPACE}
    echo ""
    exit 0
fi

echo ""
echo "${CYAN}Total de etapas: ${TOTAL_STEPS}${NC}"
echo ""

# Confirmar execução
echo "${YELLOW}Deseja continuar com as etapas acima? (s/n)${NC}"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo "${RED}Cancelado pelo usuário.${NC}"
    exit 0
fi

echo ""
CURRENT_STEP=0

# Executar etapas necessárias
if [ "$NEEDS_DYNAMO" = true ]; then
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║  Etapa ${CURRENT_STEP}/${TOTAL_STEPS}: Criando DynamoDB Table                      ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "${CYAN}Criando tabela ${DYNAMODB_TABLE}...${NC}"
    aws dynamodb create-table \
        --table-name ${DYNAMODB_TABLE} \
        --attribute-definitions AttributeName=id,AttributeType=S \
        --key-schema AttributeName=id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region ${AWS_REGION} > /dev/null
    
    echo "${YELLOW}Aguardando tabela ficar ativa...${NC}"
    aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION}
    
    echo "${GREEN}✅ DynamoDB Table criada!${NC}"
    echo ""
fi

if [ "$NEEDS_ECR" = true ]; then
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║  Etapa ${CURRENT_STEP}/${TOTAL_STEPS}: Build & Push Docker Image                   ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    chmod +x ./app/buildDockerImage.sh
    ./app/buildDockerImage.sh
    
    echo ""
fi

if [ "$NEEDS_APP" = true ]; then
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║  Etapa ${CURRENT_STEP}/${TOTAL_STEPS}: Deploy da Aplicação                         ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo "${CYAN}Aplicando deployment da aplicação...${NC}"
    kubectl apply -f ./app/keda-python-app.yaml
    
    echo "${CYAN}Aplicando ScaledObject...${NC}"
    kubectl apply -f ./app/scaledobject.yaml
    
    echo ""
    echo "${YELLOW}⏳ Aguardando deployment estar pronto...${NC}"
    kubectl rollout status deployment/${APP_DEPLOYMENT_NAME} -n ${APP_NAMESPACE} --timeout=180s
    
    echo "${GREEN}✅ Aplicação deployada!${NC}"
    echo ""
fi

# Validação Final
echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          ✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!             ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${CYAN}📊 Status Final:${NC}"
echo ""

echo "${YELLOW}Nodes:${NC}"
kubectl get nodes
echo ""

echo "${YELLOW}Pods Karpenter:${NC}"
kubectl get pods -n karpenter
echo ""

echo "${YELLOW}Pods KEDA:${NC}"
kubectl get pods -n keda
echo ""

echo "${YELLOW}Pods Aplicação:${NC}"
kubectl get pods -n ${APP_NAMESPACE}
echo ""

echo "${YELLOW}ScaledObject:${NC}"
kubectl get scaledobject -n ${APP_NAMESPACE}
echo ""

echo "${YELLOW}HPA:${NC}"
kubectl get hpa -n ${APP_NAMESPACE}
echo ""

echo "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo "${CYAN}  PRÓXIMOS PASSOS${NC}"
echo "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "${GREEN}1. Executar teste de carga:${NC}"
echo "   cd ../tests"
echo "   ./run-load-test.sh"
echo ""
echo "${GREEN}2. Monitorar scaling:${NC}"
echo "   • Pods: watch kubectl get pods -n ${APP_NAMESPACE}"
echo "   • HPA: watch kubectl get hpa -n ${APP_NAMESPACE}"
echo "   • Nodes: watch kubectl get nodes"
echo ""
echo "${YELLOW}💰 Após testes: ./scripts/cleanup.sh${NC}"
echo ""
