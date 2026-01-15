#!/bin/bash
#*************************
# Pre-Installation Check Script
# Remove stacks órfãs antes de instalar
#*************************

set -e

# Cores
export RED=$(tput setaf 1 2>/dev/null || echo "")
export GREEN=$(tput setaf 2 2>/dev/null || echo "")
export YELLOW=$(tput setaf 3 2>/dev/null || echo "")
export CYAN=$(tput setaf 6 2>/dev/null || echo "")
export NC=$(tput sgr0 2>/dev/null || echo "")

# Carregar variáveis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

if [ -f "${PROJECT_ROOT}/deployment/environmentVariables.sh" ]; then
    source "${PROJECT_ROOT}/deployment/environmentVariables.sh"
else
    export CLUSTER_NAME="${CLUSTER_NAME:-eks-demo-scale-v2}"
    export AWS_REGION="${AWS_REGION:-us-east-1}"
fi

echo ""
echo "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║    PRÉ-VERIFICAÇÃO ANTES DA INSTALAÇÃO                    ║${NC}"
echo "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${YELLOW}🔍 Verificando recursos órfãos do projeto anterior...${NC}"
echo ""

# Verificar se cluster já existe
echo "${CYAN}1️⃣ Verificando se cluster EKS existe...${NC}"
if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "${RED}   ❌ Cluster '${CLUSTER_NAME}' JÁ EXISTE!${NC}"
    echo ""
    echo "${YELLOW}   ⚠️  Você deve deletar o cluster existente antes de instalar novamente.${NC}"
    echo "${CYAN}   Execute: ${NC}cd scripts && ./cleanup.sh"
    echo ""
    exit 1
else
    echo "${GREEN}   ✅ Cluster não existe${NC}"
fi

# Verificar CloudFormation Stacks órfãs
echo ""
echo "${CYAN}2️⃣ Verificando CloudFormation Stacks órfãs...${NC}"

ORPHAN_STACKS=$(aws cloudformation list-stacks --region ${AWS_REGION} \
    --query "StackSummaries[?contains(StackName, '${CLUSTER_NAME}') && (StackStatus=='DELETE_FAILED' || StackStatus=='CREATE_FAILED' || StackStatus=='CREATE_COMPLETE' || StackStatus=='UPDATE_COMPLETE')].StackName" \
    --output text 2>/dev/null)

if [ -n "${ORPHAN_STACKS}" ]; then
    echo "${YELLOW}   ⚠️  Stacks órfãs encontradas:${NC}"
    for STACK in ${ORPHAN_STACKS}; do
        STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK} --region ${AWS_REGION} --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
        echo "${YELLOW}      • ${STACK} (${STACK_STATUS})${NC}"
    done
    
    echo ""
    echo "${CYAN}   🧹 Limpando stacks órfãs...${NC}"
    
    for STACK in ${ORPHAN_STACKS}; do
        echo "${CYAN}      Deletando stack: ${STACK}${NC}"
        aws cloudformation delete-stack --stack-name ${STACK} --region ${AWS_REGION} 2>/dev/null || true
    done
    
    echo ""
    echo "${CYAN}   ⏳ Aguardando deleção das stacks (timeout: 2 minutos)...${NC}"
    
    TIMEOUT=120
    ELAPSED=0
    ALL_DELETED=false
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        REMAINING_STACKS=""
        
        for STACK in ${ORPHAN_STACKS}; do
            STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK} --region ${AWS_REGION} --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
            
            if [ "$STATUS" != "DELETED" ] && [ "$STATUS" != "DELETE_COMPLETE" ]; then
                REMAINING_STACKS="${REMAINING_STACKS} ${STACK}"
            fi
        done
        
        if [ -z "${REMAINING_STACKS}" ]; then
            ALL_DELETED=true
            break
        fi
        
        sleep 10
        ELAPSED=$((ELAPSED + 10))
        echo "${CYAN}      Aguardando... (${ELAPSED}s)${NC}"
    done
    
    if [ "$ALL_DELETED" = true ]; then
        echo "${GREEN}   ✅ Todas as stacks órfãs foram deletadas${NC}"
    else
        echo "${YELLOW}   ⚠️  Algumas stacks ainda estão sendo deletadas${NC}"
        echo "${CYAN}   💡 Aguarde mais alguns minutos e tente novamente${NC}"
        echo ""
        exit 1
    fi
else
    echo "${GREEN}   ✅ Nenhuma stack órfã encontrada${NC}"
fi

# Verificar VPC órfã
echo ""
echo "${CYAN}3️⃣ Verificando VPC órfã...${NC}"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" --region ${AWS_REGION} --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ]; then
    echo "${YELLOW}   ⚠️  VPC órfã encontrada: ${VPC_ID}${NC}"
    echo "${CYAN}   🧹 Tentando limpar VPC...${NC}"
    
    # Remover Internet Gateways
    IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --region ${AWS_REGION} --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null)
    for IGW_ID in ${IGW_IDS}; do
        echo "${CYAN}      Removendo Internet Gateway: ${IGW_ID}${NC}"
        aws ec2 detach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID} --region ${AWS_REGION} 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id ${IGW_ID} --region ${AWS_REGION} 2>/dev/null || true
    done
    
    # Remover Security Groups (exceto default)
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" --region ${AWS_REGION} --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null)
    for SG_ID in ${SG_IDS}; do
        echo "${CYAN}      Removendo Security Group: ${SG_ID}${NC}"
        aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION} 2>/dev/null || true
    done
    
    # Tentar deletar VPC
    echo "${CYAN}      Deletando VPC: ${VPC_ID}${NC}"
    if aws ec2 delete-vpc --vpc-id ${VPC_ID} --region ${AWS_REGION} 2>/dev/null; then
        echo "${GREEN}   ✅ VPC deletada com sucesso${NC}"
    else
        echo "${YELLOW}   ⚠️  VPC ainda tem dependências (será limpa pelo eksctl)${NC}"
    fi
else
    echo "${GREEN}   ✅ Nenhuma VPC órfã encontrada${NC}"
fi

# Verificar IAM Roles órfãs
echo ""
echo "${CYAN}4️⃣ Verificando IAM Roles órfãs...${NC}"

ORPHAN_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, '${CLUSTER_NAME}')].RoleName" --output text 2>/dev/null)

if [ -n "${ORPHAN_ROLES}" ]; then
    echo "${YELLOW}   ⚠️  IAM Roles órfãs encontradas:${NC}"
    for ROLE in ${ORPHAN_ROLES}; do
        echo "${YELLOW}      • ${ROLE}${NC}"
        
        # Detach policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name ${ROLE} --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
        for POLICY_ARN in ${ATTACHED_POLICIES}; do
            aws iam detach-role-policy --role-name ${ROLE} --policy-arn ${POLICY_ARN} 2>/dev/null || true
        done
        
        # Remove inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name ${ROLE} --query 'PolicyNames[*]' --output text 2>/dev/null)
        for POLICY_NAME in ${INLINE_POLICIES}; do
            aws iam delete-role-policy --role-name ${ROLE} --policy-name ${POLICY_NAME} 2>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role --role-name ${ROLE} 2>/dev/null && \
            echo "${GREEN}      ✅ Role deletada: ${ROLE}${NC}" || \
            echo "${YELLOW}      ⚠️  Erro ao deletar role: ${ROLE}${NC}"
    done
else
    echo "${GREEN}   ✅ Nenhuma IAM Role órfã encontrada${NC}"
fi

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║    ✅ PRÉ-VERIFICAÇÃO CONCLUÍDA COM SUCESSO!              ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}💡 Você pode prosseguir com a instalação:${NC}"
echo "${CYAN}   ./deployment/_main.sh${NC}"
echo ""
