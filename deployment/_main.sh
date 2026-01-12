#!/bin/bash
#*************************
# Main Deployment Script - KEDA & Karpenter Lab v2
# Deployment automatizado completo
#*************************

set -e  # Exit on first error

# Carregar variáveis de ambiente PRIMEIRO
source ./environmentVariables.sh

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║                                                            ║${NC}"
echo "${GREEN}║    EKS Autoscaling Lab - KEDA & Karpenter v2              ║${NC}"
echo "${GREEN}║    Deployment Automatizado                                 ║${NC}"
echo "${GREEN}║                                                            ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo ""
echo "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║          VERIFICAÇÃO DE CONFIGURAÇÃO                      ║${NC}"
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

# Menu de seleção
echo ""
echo "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${BLUE}║          SELEÇÃO DE MÓDULOS DE IMPLANTAÇÃO                ║${NC}"
echo "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}Escolha uma opção:${NC}"
echo ""
echo "   ${GREEN}1)${NC} Implantar apenas o Cluster EKS"
echo "   ${GREEN}2)${NC} Implantar Cluster EKS + Karpenter"
echo "   ${GREEN}3)${NC} Implantar COMPLETO: Cluster + Karpenter + KEDA + AWS Services ${YELLOW}(Recomendado)${NC}"
echo ""
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -n "${CYAN}Digite sua escolha (1, 2 ou 3): ${NC}"
read deployment_option

case $deployment_option in
    1)
        echo ""
        echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo "${GREEN}║              OPÇÃO 1: CLUSTER EKS                         ║${NC}"
        echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        chmod +x ./cluster/createCluster.sh
        ./cluster/createCluster.sh
        
        echo ""
        echo "${GREEN}✅ Opção 1 concluída!${NC}"
        ;;
        
    2)
        echo ""
        echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo "${GREEN}║          OPÇÃO 2: CLUSTER EKS + KARPENTER                 ║${NC}"
        echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        echo "${YELLOW}🚀 Etapa 1/2: Implantando Cluster EKS...${NC}"
        chmod +x ./cluster/createCluster.sh
        ./cluster/createCluster.sh
        
        echo ""
        echo "${YELLOW}🚀 Etapa 2/2: Implantando Karpenter...${NC}"
        chmod +x ./karpenter/createkarpenter.sh
        ./karpenter/createkarpenter.sh
        
        echo ""
        echo "${GREEN}✅ Opção 2 concluída!${NC}"
        ;;
        
    3)
        echo ""
        echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo "${GREEN}║       OPÇÃO 3: DEPLOYMENT COMPLETO                       ║${NC}"
        echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        echo "${YELLOW}🚀 Etapa 1/4: Implantando Cluster EKS (20-25 min)...${NC}"
        chmod +x ./cluster/createCluster.sh
        ./cluster/createCluster.sh
        
        echo ""
        echo "${YELLOW}🚀 Etapa 2/5: Implantando Karpenter (5-7 min)...${NC}"
        chmod +x ./karpenter/createkarpenter.sh
        ./karpenter/createkarpenter.sh
        
        echo ""
        echo "${YELLOW}🚀 Etapa 3/5: Criando recursos AWS (SQS e DynamoDB)...${NC}"
        chmod +x ./services/awsService.sh 
        ./services/awsService.sh
        
        echo ""
        echo "${YELLOW}🚀 Etapa 4/5: Build & Push Docker Image para ECR (2-3 min)...${NC}"
        chmod +x ./app/buildDockerImage.sh
        ./app/buildDockerImage.sh
        
        echo ""
        echo "${YELLOW}🚀 Etapa 5/5: Implantando KEDA (3-5 min)...${NC}"
        chmod +x ./keda/createkeda.sh
        ./keda/createkeda.sh
        
        echo ""
        echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo "${GREEN}║          ✅ DEPLOYMENT COMPLETO CONCLUÍDO!                 ║${NC}"
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
        
        echo "${CYAN}7. NodePool do Karpenter:${NC}"
        kubectl get nodepool
        echo ""
        
        echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
        echo "${CYAN}🎉 Todos os componentes implantados e validados!${NC}"
        echo ""
        echo "${YELLOW}📋 Próximos passos:${NC}"
        echo ""
        echo "   ${GREEN}1. Validar ambiente:${NC}"
        echo "      • Verificar logs KEDA: kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=50"
        echo "      • Verificar logs Karpenter: kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50"
        echo ""
        echo "   ${GREEN}2. Executar teste de carga SQS:${NC}"
        echo "      cd tests && ./run-load-test.sh"
        echo ""
        echo "   ${GREEN}3. Monitorar scaling:${NC}"
        echo "      • Pods: watch kubectl get pods -n keda-test"
        echo "      • HPA: watch kubectl get hpa -n keda-test"
        echo "      • Nodes: watch kubectl get nodes"
        echo ""
        echo "${YELLOW}💰 Lembre-se:${NC} Após os testes, execute ./scripts/cleanup.sh para remover recursos e evitar custos!"
        echo ""
        ;;
        
    *)
        echo ""
        echo "${RED}❌ Opção inválida! Escolha 1, 2 ou 3.${NC}"
        exit 1
        ;;
esac

echo ""
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo "${GREEN}            Deployment Script Finalizado!${NC}"
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
