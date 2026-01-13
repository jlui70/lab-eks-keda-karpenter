#!/bin/bash
#*************************
# KEDA Load Test Runner - Teste de Carga Automático
# Testa scaling de pods baseado em mensagens SQS
#*************************

set -e  # Exit on error

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          KEDA LOAD TEST - SQS SCALING                     ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Determinar diretório raiz do projeto
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Ir para diretório do projeto
cd "$PROJECT_ROOT"

echo "${CYAN}📍 Diretório do projeto: $(pwd)${NC}"
echo ""

# Verificar se script Python existe
if [[ ! -f "app/keda/keda-mock-sqs-post.py" ]]; then
    echo "${RED}❌ Arquivo de teste não encontrado!${NC}"
    echo "Procurando: app/keda/keda-mock-sqs-post.py"
    exit 1
fi

echo "${GREEN}✅ Script de teste encontrado${NC}"
echo ""

# Carregar variáveis de ambiente
if [[ ! -f "deployment/environmentVariables.sh" ]]; then
    echo "${RED}❌ Arquivo environmentVariables.sh não encontrado!${NC}"
    exit 1
fi

source deployment/environmentVariables.sh

echo "${CYAN}🔍 Verificação Pré-Teste:${NC}"
echo "═══════════════════════════"
echo "${BLUE}• Cluster:${NC} $CLUSTER_NAME"
echo "${BLUE}• SQS Queue:${NC} $SQS_QUEUE_NAME"
echo "${BLUE}• DynamoDB:${NC} $DYNAMODB_TABLE"
echo "${BLUE}• Região:${NC} $AWS_REGION"
echo ""

# Verificar conectividade com cluster
echo "${YELLOW}🔗 Verificando conectividade com cluster...${NC}"
if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
    echo "${RED}❌ Cluster não acessível!${NC}"
    echo "${YELLOW}💡 Execute: aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}${NC}"
    exit 1
fi
echo "${GREEN}✅ Cluster acessível${NC}"
echo ""

# Verificar recursos kubernetes
echo "${YELLOW}📊 Verificando recursos do Kubernetes...${NC}"

NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
echo "${BLUE}• Nodes ativos:${NC} $NODES"

KEDA_PODS=$(kubectl get pods -n keda --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "${BLUE}• KEDA pods:${NC} $KEDA_PODS/3"

APP_PODS=$(kubectl get pods -n keda-test --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "${BLUE}• App pods:${NC} $APP_PODS"

HPA_COUNT=$(kubectl get hpa -n keda-test --no-headers 2>/dev/null | wc -l)
echo "${BLUE}• HPA ativo:${NC} $HPA_COUNT"

SCALEDOBJECT=$(kubectl get scaledobject -n keda-test --no-headers 2>/dev/null | wc -l)
echo "${BLUE}• ScaledObject:${NC} $SCALEDOBJECT"

echo ""

# Validar se sistema está pronto
if [[ $NODES -eq 0 ]]; then
    echo "${RED}❌ Nenhum node encontrado!${NC}"
    exit 1
fi

if [[ $KEDA_PODS -lt 2 ]]; then
    echo "${YELLOW}⚠️  KEDA não está completamente rodando ($KEDA_PODS/3 pods)${NC}"
fi

if [[ $APP_PODS -eq 0 ]]; then
    echo "${YELLOW}⚠️  Aplicação não está rodando!${NC}"
fi

if [[ $HPA_COUNT -eq 0 ]] || [[ $SCALEDOBJECT -eq 0 ]]; then
    echo "${RED}❌ HPA ou ScaledObject não encontrado!${NC}"
    echo "${YELLOW}💡 Verifique se KEDA foi instalado corretamente${NC}"
    exit 1
fi

echo "${GREEN}✅ Sistema pronto para teste!${NC}"
echo ""

# Configurar ambiente Python
echo "${YELLOW}🐍 Configurando Ambiente Python...${NC}"
echo ""

cd app/keda

# Verificar se Python3 está instalado
if ! command -v python3 &> /dev/null; then
    echo "${RED}❌ Python3 não encontrado!${NC}"
    echo "Instale Python3: sudo apt-get install python3 python3-pip python3-venv"
    exit 1
fi

# Criar ambiente virtual se não existir
if [[ ! -d "venv" ]]; then
    echo "${CYAN}📦 Criando ambiente virtual Python...${NC}"
    python3 -m venv venv
    echo "${GREEN}✅ Ambiente virtual criado${NC}"
else
    echo "${GREEN}♻️  Usando ambiente virtual existente${NC}"
fi

# Ativar ambiente virtual
echo "${CYAN}🔌 Ativando ambiente virtual...${NC}"
source venv/bin/activate

# Verificar ativação
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "${RED}❌ Falha ao ativar ambiente virtual!${NC}"
    exit 1
fi
echo "${GREEN}✅ Ambiente virtual ativado: $VIRTUAL_ENV${NC}"
echo ""

# Instalar/atualizar dependências
echo "${CYAN}📦 Instalando dependências Python...${NC}"
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

echo "${GREEN}✅ Dependências instaladas${NC}"
echo ""

# Exportar variáveis de ambiente para Python
export SQS_QUEUE_URL="${SQS_QUEUE_URL}"
export AWS_REGION="${AWS_REGION}"
export DYNAMODB_TABLE="${DYNAMODB_TABLE}"

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          🚀 INICIANDO TESTE DE CARGA                      ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${YELLOW}💡 Dicas para monitorar:${NC}"
echo ""
echo "   ${CYAN}Terminal 1 - Pods:${NC}"
echo "   watch kubectl get pods -n keda-test"
echo ""
echo "   ${CYAN}Terminal 2 - HPA:${NC}"
echo "   watch kubectl get hpa -n keda-test"
echo ""
echo "   ${CYAN}Terminal 3 - Nodes:${NC}"
echo "   watch kubectl get nodes"
echo ""
echo "   ${CYAN}Terminal 4 - Fila SQS (vai acumular centenas de mensagens) Fila SQS:${NC}"
echo "   watch -n 5 'aws sqs get-queue-attributes --queue-url https://sqs.us-east-1.amazonaws.com/794038226274/keda-demo-queue.fifo --attribute-names ApproximateNumberOfMessages --query "Attributes.ApproximateNumberOfMessages" --output text'
#echo ""
#echo "   ${CYAN}Terminal 4 - Karpenter Logs:${NC}"
#echo "   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f"
#echo ""

sleep 3

# Executar script Python
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

python3 keda-mock-sqs-post.py

# Capturar código de saída
EXIT_CODE=$?

echo ""
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "${GREEN}✅ Teste concluído com sucesso!${NC}"
    echo ""
    echo "${YELLOW}📊 Verificando estado do sistema:${NC}"
    echo ""
    
    echo "${CYAN}Pods da aplicação:${NC}"
    kubectl get pods -n keda-test
    echo ""
    
    echo "${CYAN}HPA Status:${NC}"
    kubectl get hpa -n keda-test
    echo ""
    
    echo "${CYAN}Nodes do cluster:${NC}"
    kubectl get nodes
    echo ""
    
    echo "${YELLOW}💡 Continue monitorando até o scale-down completar${NC}"
    echo "${CYAN}   (KEDA cooldownPeriod: 30s após fila esvaziar)${NC}"
    echo ""
else
    echo "${RED}❌ Teste falhou com código: $EXIT_CODE${NC}"
fi

# Desativar ambiente virtual
deactivate

echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo "${GREEN}         Teste Finalizado!${NC}"
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
