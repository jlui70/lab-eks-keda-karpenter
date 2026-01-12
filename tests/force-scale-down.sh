#!/bin/bash
#*************************
# FORÇAR SCALE-DOWN RÁPIDO
# Use este script durante apresentação se HPA travar
#*************************

set -e

source $(dirname "$0")/../deployment/environmentVariables.sh

echo "${YELLOW}🚀 FORÇANDO SCALE-DOWN RÁPIDO...${NC}"
echo ""

# Passo 1: Purgar fila SQS
echo "${CYAN}📭 Passo 1/3: Purgando fila SQS...${NC}"
SQS_URL=$(aws sqs get-queue-url --queue-name ${SQS_QUEUE_NAME} --region ${AWS_REGION} --query 'QueueUrl' --output text)
aws sqs purge-queue --queue-url $SQS_URL --region ${AWS_REGION} 2>/dev/null || true
echo "${GREEN}   ✅ Fila purgada${NC}"
echo ""

# Passo 2: Resetar HPA (força KEDA recriar)
echo "${CYAN}🔄 Passo 2/3: Resetando HPA...${NC}"
kubectl delete hpa keda-hpa-sqs-scaledobject -n keda-test 2>/dev/null || true
echo "${YELLOW}   ⏳ Aguardando KEDA recriar HPA (15s)...${NC}"
sleep 15
echo "${GREEN}   ✅ HPA recriado${NC}"
echo ""

# Passo 3: Verificar resultado
echo "${CYAN}📊 Passo 3/3: Verificando scale-down...${NC}"
PODS=$(kubectl get pods -n keda-test 2>/dev/null | grep -c Running || echo "0")
HPA_DESIRED=$(kubectl get hpa keda-hpa-sqs-scaledobject -n keda-test -o jsonpath='{.status.desiredReplicas}' 2>/dev/null || echo "N/A")
HPA_CURRENT=$(kubectl get hpa keda-hpa-sqs-scaledobject -n keda-test -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "N/A")

echo ""
echo "${GREEN}✅ Scale-down iniciado!${NC}"
echo ""
echo "${CYAN}Status atual:${NC}"
echo "   • Pods Running: ${YELLOW}${PODS}${NC}"
echo "   • HPA Desired: ${YELLOW}${HPA_DESIRED}${NC}"
echo "   • HPA Current: ${YELLOW}${HPA_CURRENT}${NC}"
echo ""

if [ "$HPA_DESIRED" = "1" ]; then
    echo "${GREEN}🎉 Scale-down funcionando! Pods vão diminuir para 1 em ~2-3 min${NC}"
else
    echo "${YELLOW}⚠️  HPA ainda ajustando... Aguarde mais 30s e verifique novamente${NC}"
fi

echo ""
echo "${CYAN}💡 Monitore com:${NC}"
echo "   watch 'kubectl get pods -n keda-test | grep -c Running'"
echo "   watch 'kubectl get nodes'"
