#!/bin/bash
#*************************
# Deploy AWS Services (SQS & DynamoDB)
#*************************

set -e  # Exit on error

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          CRIANDO RECURSOS AWS (SQS & DYNAMODB)             ║${NC}"
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
if [ -z "$DYNAMODB_TABLE" ] || [ -z "$SQS_QUEUE_NAME" ] || [ -z "$AWS_REGION" ]; then
    echo "${RED}❌ Erro: Variáveis obrigatórias não definidas!${NC}"
    exit 1
fi

echo "${CYAN}📋 Recursos a serem criados:${NC}"
echo "   • DynamoDB Table: ${DYNAMODB_TABLE}"
echo "   • SQS Queue: ${SQS_QUEUE_NAME}"
echo "   • Região: ${AWS_REGION}"
echo ""

# Criar DynamoDB Table
echo "${YELLOW}📝 Passo 1/2: Criando tabela DynamoDB...${NC}"

# Verificar se já existe
if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} &>/dev/null; then
    echo "${BLUE}ℹ️  Tabela DynamoDB '${DYNAMODB_TABLE}' já existe${NC}"
else
    echo "${CYAN}Criando tabela com PAY_PER_REQUEST billing mode...${NC}"
    
    aws dynamodb create-table \
        --table-name ${DYNAMODB_TABLE} \
        --region ${AWS_REGION} \
        --attribute-definitions \
            AttributeName=id,AttributeType=S \
            AttributeName=messageProcessingTime,AttributeType=S \
        --key-schema \
            AttributeName=id,KeyType=HASH \
            AttributeName=messageProcessingTime,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags \
            Key=Environment,Value=demo \
            Key=ManagedBy,Value=script \
        --output text > /dev/null
    
    echo "${GREEN}✅ Tabela DynamoDB criada com sucesso!${NC}"
    
    # Aguardar tabela estar ativa
    echo "${YELLOW}⏳ Aguardando tabela ficar ativa...${NC}"
    aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION}
    echo "${GREEN}✅ Tabela está ativa${NC}"
fi

# Obter detalhes da tabela
TABLE_ARN=$(aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} --query 'Table.TableArn' --output text)
echo "${CYAN}   Table ARN: ${TABLE_ARN}${NC}"
echo ""

# Criar SQS FIFO Queue
echo "${YELLOW}📝 Passo 2/2: Criando fila SQS FIFO...${NC}"

# Verificar se já existe
if aws sqs get-queue-url --queue-name ${SQS_QUEUE_NAME} --region ${AWS_REGION} &>/dev/null; then
    QUEUE_URL=$(aws sqs get-queue-url --queue-name ${SQS_QUEUE_NAME} --region ${AWS_REGION} --query 'QueueUrl' --output text)
    echo "${BLUE}ℹ️  Fila SQS '${SQS_QUEUE_NAME}' já existe${NC}"
    echo "${CYAN}   Queue URL: ${QUEUE_URL}${NC}"
else
    echo "${CYAN}Criando fila FIFO com as seguintes configurações:${NC}"
    echo "   • FIFO Queue: true"
    echo "   • Content-Based Deduplication: true"
    echo "   • Visibility Timeout: 60 segundos"
    echo "   • Message Retention: 4 dias"
    echo ""
    
    QUEUE_URL=$(aws sqs create-queue \
        --queue-name ${SQS_QUEUE_NAME} \
        --region ${AWS_REGION} \
        --attributes '{
            "FifoQueue": "true",
            "ContentBasedDeduplication": "true",
            "VisibilityTimeout": "60",
            "MessageRetentionPeriod": "345600",
            "ReceiveMessageWaitTimeSeconds": "10"
        }' \
        --tags Environment=demo,ManagedBy=script \
        --query 'QueueUrl' \
        --output text)
    
    echo "${GREEN}✅ Fila SQS criada com sucesso!${NC}"
    echo "${CYAN}   Queue URL: ${QUEUE_URL}${NC}"
fi

# Obter Queue ARN
QUEUE_ARN=$(aws sqs get-queue-attributes \
    --queue-url ${QUEUE_URL} \
    --attribute-names QueueArn \
    --region ${AWS_REGION} \
    --query 'Attributes.QueueArn' \
    --output text)

echo "${CYAN}   Queue ARN: ${QUEUE_ARN}${NC}"
echo ""

# Salvar informações em arquivo
echo "${YELLOW}📄 Salvando informações dos recursos...${NC}"

cat > /tmp/aws-resources-info.txt <<EOF
AWS Resources Created
=====================

DynamoDB Table:
  Name: ${DYNAMODB_TABLE}
  ARN: ${TABLE_ARN}
  Region: ${AWS_REGION}
  Billing Mode: PAY_PER_REQUEST

SQS Queue:
  Name: ${SQS_QUEUE_NAME}
  URL: ${QUEUE_URL}
  ARN: ${QUEUE_ARN}
  Type: FIFO
  Region: ${AWS_REGION}

Environment Variables:
  export SQS_QUEUE_URL="${QUEUE_URL}"
  export DYNAMODB_TABLE="${DYNAMODB_TABLE}"
  export AWS_REGION="${AWS_REGION}"
EOF

cat /tmp/aws-resources-info.txt

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║        RECURSOS AWS CRIADOS COM SUCESSO!                   ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${CYAN}📋 Informações salvas em: /tmp/aws-resources-info.txt${NC}"
echo ""
echo "${CYAN}✅ Recursos prontos para uso!${NC}"
echo ""
echo "${YELLOW}💡 Próximos passos:${NC}"
echo "   1. Verificar ScaledObject: kubectl get scaledobject -n ${APP_NAMESPACE}"
echo "   2. Executar teste: ./tests/run-load-test.sh"
echo ""
