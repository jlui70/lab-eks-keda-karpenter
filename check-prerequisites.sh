#!/bin/bash
#*************************
# Script de Verificação Rápida
# Valida se o ambiente está pronto para o lab
#*************************

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         VERIFICAÇÃO DE PRÉ-REQUISITOS                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ERRORS=0

# Função para verificar comando
check_command() {
    local cmd=$1
    local name=$2
    local min_version=$3
    
    if command -v $cmd &> /dev/null; then
        version=$($cmd --version 2>&1 | head -1)
        echo -e "${GREEN}✅ ${name}:${NC} ${version}"
    else
        echo -e "${RED}❌ ${name}: NÃO INSTALADO${NC}"
        ERRORS=$((ERRORS + 1))
    fi
}

# Verificar ferramentas
echo -e "${CYAN}📦 Ferramentas Necessárias:${NC}"
echo ""

check_command "aws" "AWS CLI"
check_command "kubectl" "kubectl"
check_command "eksctl" "eksctl"
check_command "helm" "Helm"
check_command "python3" "Python3"

echo ""

# Verificar credenciais AWS
echo -e "${CYAN}🔐 Credenciais AWS:${NC}"
echo ""

if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
    AWS_REGION=$(aws configure get region)
    
    echo -e "${GREEN}✅ Credenciais válidas${NC}"
    echo -e "   Account ID: ${ACCOUNT_ID}"
    echo -e "   User/Role: ${AWS_USER}"
    echo -e "   Region: ${AWS_REGION}"
else
    echo -e "${RED}❌ Credenciais AWS inválidas ou não configuradas${NC}"
    echo -e "${YELLOW}Execute: aws configure${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Verificar quotas AWS (opcional)
echo -e "${CYAN}📊 Verificando quotas AWS (opcional):${NC}"
echo ""

# VPC Quota
VPC_QUOTA=$(aws service-quotas get-service-quota \
    --service-code vpc \
    --quota-code L-F678F1CE \
    --query 'Quota.Value' \
    --output text 2>/dev/null || echo "N/A")

if [ "$VPC_QUOTA" != "N/A" ]; then
    echo -e "${GREEN}✅ VPCs disponíveis:${NC} ${VPC_QUOTA}"
else
    echo -e "${YELLOW}⚠️  Não foi possível verificar quota de VPCs${NC}"
fi

# EIP Quota
EIP_QUOTA=$(aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-0263D0A3 \
    --query 'Quota.Value' \
    --output text 2>/dev/null || echo "N/A")

if [ "$EIP_QUOTA" != "N/A" ]; then
    echo -e "${GREEN}✅ Elastic IPs disponíveis:${NC} ${EIP_QUOTA}"
else
    echo -e "${YELLOW}⚠️  Não foi possível verificar quota de EIPs${NC}"
fi

echo ""

# Verificar se já existe cluster
echo -e "${CYAN}🔍 Verificando clusters existentes:${NC}"
echo ""

EXISTING_CLUSTERS=$(aws eks list-clusters --query "clusters[]" --output text 2>/dev/null)

if [ ! -z "$EXISTING_CLUSTERS" ]; then
    echo -e "${YELLOW}⚠️  Clusters existentes encontrados:${NC}"
    for cluster in $EXISTING_CLUSTERS; do
        echo "   • $cluster"
    done
    echo ""
    echo -e "${YELLOW}💡 Considere deletar clusters não utilizados para evitar custos${NC}"
else
    echo -e "${GREEN}✅ Nenhum cluster EKS encontrado${NC}"
fi

echo ""

# Verificar Docker (opcional)
echo -e "${CYAN}🐳 Docker (opcional):${NC}"
echo ""

if command -v docker &> /dev/null; then
    if docker ps &> /dev/null; then
        echo -e "${GREEN}✅ Docker instalado e rodando${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker instalado mas não está rodando${NC}"
        echo -e "   Inicie com: sudo systemctl start docker"
    fi
else
    echo -e "${YELLOW}⚠️  Docker não instalado (não obrigatório para este lab)${NC}"
fi

echo ""

# Resumo final
echo "╔════════════════════════════════════════════════════════════╗"
if [ $ERRORS -eq 0 ]; then
    echo -e "║         ${GREEN}✅ AMBIENTE PRONTO PARA O LAB!${NC}                    ║"
else
    echo -e "║         ${RED}❌ ENCONTRADOS ${ERRORS} ERRO(S)${NC}                         ║"
fi
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}🚀 Próximos passos:${NC}"
    echo ""
    echo "   1. Revisar configurações (opcional):"
    echo "      nano deployment/environmentVariables.sh"
    echo ""
    echo "   2. Executar deployment:"
    echo "      ./deployment/_main.sh"
    echo ""
    echo "   3. Escolher opção 3 (Deployment Completo)"
    echo ""
    echo -e "${YELLOW}⏱️  Tempo estimado: 25 minutos${NC}"
    echo -e "${YELLOW}💰 Custo estimado: $1-2 para 2-3 horas de teste${NC}"
    echo ""
else
    echo -e "${RED}❌ Corrija os erros acima antes de prosseguir${NC}"
    echo ""
    echo -e "${YELLOW}📚 Documentação de ajuda:${NC}"
    echo "   • AWS CLI: https://aws.amazon.com/cli/"
    echo "   • kubectl: https://kubernetes.io/docs/tasks/tools/"
    echo "   • eksctl: https://eksctl.io/"
    echo "   • Helm: https://helm.sh/"
    echo ""
fi

exit $ERRORS
