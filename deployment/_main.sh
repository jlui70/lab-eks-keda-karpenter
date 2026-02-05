#!/bin/bash
#*************************
# Main Deployment Script - KEDA & Karpenter Lab v2
# Deployment automatizado completo
#*************************

set -e  # Exit on first error

# Determinar o diretório do script e do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar variáveis de ambiente PRIMEIRO
source "${SCRIPT_DIR}/environmentVariables.sh"

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║                                                            ║${NC}"
echo "${GREEN}║    EKS Autoscaling Lab - KEDA & Karpenter v2               ║${NC}"
echo "${GREEN}║    Deployment Automatizado                                 ║${NC}"
echo "${GREEN}║                                                            ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo ""
echo "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║          VERIFICAÇÃO DE CONFIGURAÇÃO                       ║${NC}"
echo "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}📋 Detalhes da implantação:${NC}"
echo "   ${BLUE}• AWS Account:${NC} ${ACCOUNT_ID}"
echo "   ${BLUE}• AWS Region:${NC} ${AWS_REGION}"
echo "   ${BLUE}• Cluster Name:${NC} ${CLUSTER_NAME}"
echo "   ${BLUE}• Kubernetes:${NC} ${K8S_VERSION}"
echo "   ${BLUE}• Karpenter:${NC} ${KARPENTER_VERSION}"
echo "   ${BLUE}• KEDA:${NC} ${KEDA_VERSION}"
echo ""

echo "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "   ${RED}• Este processo levará aproximadamente 25-30 minutos${NC}"
echo "   ${RED}• Certifique-se de ter as permissões IAM necessárias${NC}"
echo "   ${RED}• Custos estimados: ~$1-2 para teste de 2-3 horas${NC}"
echo ""

# Validar pré-requisitos
echo "${YELLOW}🔍 Validando pré-requisitos...${NC}"

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo "${RED}❌ AWS CLI não encontrado!${NC}"
    echo "Instale: https://aws.amazon.com/cli/"
    exit 1
fi
echo "${GREEN}   ✅ AWS CLI: $(aws --version | cut -d' ' -f1)${NC}"

# Verificar kubectl
if ! command -v kubectl &> /dev/null; then
    echo "${RED}❌ kubectl não encontrado!${NC}"
    echo "Instale: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
echo "${GREEN}   ✅ kubectl: $(kubectl version --client --short 2>/dev/null | head -1)${NC}"

# Verificar eksctl
if ! command -v eksctl &> /dev/null; then
    echo "${RED}❌ eksctl não encontrado!${NC}"
    echo "Instale: https://eksctl.io/"
    exit 1
fi
echo "${GREEN}   ✅ eksctl: $(eksctl version)${NC}"

# Verificar helm
if ! command -v helm &> /dev/null; then
    echo "${RED}❌ Helm não encontrado!${NC}"
    echo "Instale: https://helm.sh/"
    exit 1
fi
echo "${GREEN}   ✅ Helm: $(helm version --short)${NC}"

# Verificar credenciais AWS
if ! aws sts get-caller-identity &> /dev/null; then
    echo "${RED}❌ Credenciais AWS inválidas!${NC}"
    echo "Execute: aws configure"
    exit 1
fi
echo "${GREEN}   ✅ Credenciais AWS: OK${NC}"

echo ""
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}⚠️  Este script irá instalar AUTOMATICAMENTE:${NC}"
echo "   ${CYAN}• Cluster EKS (15-20 min)${NC}"
echo "   ${CYAN}• Karpenter (3-5 min)${NC}"
echo "   ${CYAN}• AWS Services - SQS + DynamoDB (1 min)${NC}"
echo "   ${CYAN}• Application Container (2-3 min)${NC}"
echo "   ${CYAN}• KEDA (3-5 min)${NC}"
echo "   ${CYAN}• Monitoring Stack - Prometheus + Grafana (3-5 min)${NC}"
echo ""
echo "${YELLOW}📊 Tempo total estimado: ~30-35 minutos${NC}"
echo ""
echo "${BLUE}Deseja continuar? ${YELLOW}(Digite Y para prosseguir ou N para cancelar)${NC}"
echo -n "${CYAN}Resposta: ${NC}"
read user_input

if [[ "$user_input" != "Y" && "$user_input" != "y" ]]; then
    echo ""
    echo "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${RED}║               ❌ IMPLANTAÇÃO CANCELADA                     ║${NC}"
    echo "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
fi

# Iniciar deployment completo automaticamente
echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          LAB EKS + KEDA + KARPENTER + MONITORING           ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
        echo ""
        echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo "${GREEN}║                DEPLOYMENT AUTOMATIZADO                     ║${NC}"
        echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
echo "${YELLOW}🚀 Etapa 1/6: Implantando Cluster EKS (20-25 min)...${NC}"
chmod +x "${SCRIPT_DIR}/cluster/createCluster.sh"
"${SCRIPT_DIR}/cluster/createCluster.sh"

echo ""
echo "${YELLOW}🚀 Etapa 2/6: Implantando Karpenter (5-7 min)...${NC}"
chmod +x "${SCRIPT_DIR}/karpenter/createkarpenter.sh"
"${SCRIPT_DIR}/karpenter/createkarpenter.sh"

echo ""
echo "${YELLOW}🚀 Etapa 3/6: Criando recursos AWS (SQS e DynamoDB)...${NC}"
chmod +x "${SCRIPT_DIR}/services/awsService.sh"
"${SCRIPT_DIR}/services/awsService.sh"

echo ""
echo "${YELLOW}🚀 Etapa 4/6: Build & Push Docker Image para ECR (2-3 min)...${NC}"
chmod +x "${SCRIPT_DIR}/app/buildDockerImage.sh"
"${SCRIPT_DIR}/app/buildDockerImage.sh"

echo ""
echo "${YELLOW}🚀 Etapa 5/6: Implantando KEDA (3-5 min)...${NC}"
chmod +x "${SCRIPT_DIR}/keda/createkeda.sh"
"${SCRIPT_DIR}/keda/createkeda.sh"

echo ""
echo "${YELLOW}🚀 Etapa 6/6: Instalando Monitoring Stack (3-5 min)...${NC}"
chmod +x "$(dirname "${SCRIPT_DIR}")/monitoring/install-complete-monitoring.sh"
"$(dirname "${SCRIPT_DIR}")/monitoring/install-complete-monitoring.sh"

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║    ✅ DEPLOYMENT COMPLETO + MONITORING CONCLUÍDO!          ║${NC}"
        echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Validação Final
        echo "${YELLOW}🔍 Executando validação final...${NC}"
        echo ""
        
        echo "${CYAN}1. Nodes do cluster:${NC}"
        kubectl get nodes
        echo ""
        
        echo "${CYAN}2. Pods do Karpenter:${NC}"
        kubectl get pods -n karpenter
        echo ""
        
        echo "${CYAN}3. Pods do KEDA:${NC}"
        kubectl get pods -n keda
        echo ""
        
        echo "${CYAN}4. Pods da aplicação:${NC}"
        kubectl get pods -n keda-test
        echo ""
        
        echo "${CYAN}5. ScaledObject:${NC}"
        kubectl get scaledobject -n keda-test
        echo ""
        
        echo "${CYAN}6. HPA (criado pelo KEDA):${NC}"
        kubectl get hpa -n keda-test
        echo ""
        
        echo "${CYAN}7. NodePool do Karpenter (API v1):${NC}"
        kubectl get nodepool
        echo ""
        
        echo "${CYAN}8. EC2NodeClass do Karpenter (API v1):${NC}"
        kubectl get ec2nodeclass
        echo ""
        
        echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo "${CYAN}🎉 Todos os componentes implantados e validados!${NC}"
        echo ""
        echo "${YELLOW}📋 Próximos passos:${NC}"
        echo ""
        echo "   ${GREEN}1. Validar ambiente:${NC}"
        echo "      • Verificar logs KEDA: kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=50"
        echo "      • Verificar logs Karpenter: kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50"
        echo "      • Verificar monitoring: kubectl get pods -n monitoring"
        echo ""
        echo "   ${GREEN}2. Acessar Grafana:${NC}"
        echo "      kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
        echo "      Acesse: http://localhost:3000 (admin/admin123)"
        echo ""
        echo "   ${GREEN}3. Executar teste de carga SQS:${NC}"
        echo "      cd tests && ./run-load-test.sh"
        echo ""
        echo "   ${GREEN}4. Monitorar scaling (4 terminais):${NC}"
        echo "      • Terminal 1 - HPA: watch -n 2 'kubectl get hpa -n keda-test'"
        echo "      • Terminal 2 - Pods: watch -n 2 'kubectl get pods -n keda-test'"
        echo "      • Terminal 3 - Nodes: watch -n 2 'kubectl get nodes'"
        echo "      • Terminal 4 - Fila SQS: watch -n 5 'aws sqs get-queue-attributes --queue-url https://sqs.us-east-1.amazonaws.com/794038226274/keda-demo-queue.fifo --attribute-names ApproximateNumberOfMessages --query \"Attributes.ApproximateNumberOfMessages\" --output text'"

        echo ""
        echo "${YELLOW}💰 Lembre-se:${NC} Após os testes, execute ./scripts/cleanup.sh para remover recursos e evitar custos!"
        echo ""

echo ""
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo "${GREEN}            Deployment Script Finalizado!${NC}"
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
