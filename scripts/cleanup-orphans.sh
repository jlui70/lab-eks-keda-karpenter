#!/bin/bash
#*************************
# Cleanup Orphan Resources - Limpa recursos órfãos deixados após cleanup
#*************************

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Importar variáveis de ambiente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../deployment/environmentVariables.sh"

echo ""
echo "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${YELLOW}║        LIMPEZA DE RECURSOS ÓRFÃOS                         ║${NC}"
echo "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

CLEANED=0

# 1. Limpar instâncias EC2 do Karpenter
echo "${CYAN}1. Verificando instâncias EC2 do Karpenter...${NC}"
KARPENTER_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/provisioner-name,Values=*" \
            "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value | [0]]' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

if [ -n "${KARPENTER_INSTANCES}" ]; then
    echo "${YELLOW}   Encontradas instâncias órfãs:${NC}"
    echo "${KARPENTER_INSTANCES}" | while read line; do
        echo "      $line"
    done
    
    INSTANCE_IDS=$(echo "${KARPENTER_INSTANCES}" | awk '{print $1}')
    echo ""
    echo "${YELLOW}   Terminando instâncias...${NC}"
    aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS} --region ${AWS_REGION} > /dev/null 2>&1
    echo "${GREEN}   ✅ Instâncias terminadas${NC}"
    CLEANED=$((CLEANED + 1))
else
    echo "${GREEN}   ✅ Nenhuma instância órfã encontrada${NC}"
fi
echo ""

# 2. Verificar ENIs órfãos
echo "${CYAN}2. Verificando ENIs (interfaces de rede) órfãos...${NC}"
ORPHAN_ENIS=$(aws ec2 describe-network-interfaces \
  --filters "Name=description,Values=*karpenter*" \
            "Name=status,Values=available" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

if [ -n "${ORPHAN_ENIS}" ]; then
    echo "${YELLOW}   Encontrados ENIs órfãos: ${ORPHAN_ENIS}${NC}"
    echo "${YELLOW}   Deletando ENIs...${NC}"
    for ENI in ${ORPHAN_ENIS}; do
        aws ec2 delete-network-interface --network-interface-id ${ENI} --region ${AWS_REGION} 2>/dev/null || true
    done
    echo "${GREEN}   ✅ ENIs deletados${NC}"
    CLEANED=$((CLEANED + 1))
else
    echo "${GREEN}   ✅ Nenhum ENI órfão encontrado${NC}"
fi
echo ""

# 3. Verificar Security Groups órfãos
echo "${CYAN}3. Verificando Security Groups do cluster...${NC}"
CLUSTER_SGS=$(aws ec2 describe-security-groups \
  --filters "Name=tag:aws:eks:cluster-name,Values=${CLUSTER_NAME}" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

if [ -n "${CLUSTER_SGS}" ]; then
    echo "${YELLOW}   Encontrados Security Groups órfãos:${NC}"
    echo "${CLUSTER_SGS}" | while read line; do
        echo "      $line"
    done
    echo ""
    echo "${CYAN}   Nota: Security Groups serão deletados automaticamente quando${NC}"
    echo "${CYAN}   a stack CloudFormation terminar de deletar.${NC}"
else
    echo "${GREEN}   ✅ Nenhum Security Group órfão encontrado${NC}"
fi
echo ""

# 4. Verificar stacks CloudFormation travadas
echo "${CYAN}4. Verificando stacks CloudFormation...${NC}"
EKSCTL_STACK="eksctl-${CLUSTER_NAME}-cluster"
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name ${EKSCTL_STACK} \
  --region ${AWS_REGION} \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${STACK_STATUS}" == "DELETE_IN_PROGRESS" ]; then
    echo "${YELLOW}   Stack em DELETE_IN_PROGRESS: ${EKSCTL_STACK}${NC}"
    echo ""
    echo "${CYAN}   Verificando recursos travados na stack...${NC}"
    
    STUCK_RESOURCES=$(aws cloudformation list-stack-resources \
      --stack-name ${EKSCTL_STACK} \
      --region ${AWS_REGION} \
      --query 'StackResourceSummaries[?ResourceStatus==`DELETE_IN_PROGRESS`].[ResourceType,LogicalResourceId]' \
      --output text 2>/dev/null)
    
    if [ -n "${STUCK_RESOURCES}" ]; then
        echo "${YELLOW}   Recursos ainda sendo deletados:${NC}"
        echo "${STUCK_RESOURCES}" | while read line; do
            echo "      $line"
        done
    fi
    
    echo ""
    echo "${CYAN}   Aguardando conclusão da stack (pode levar 5-10 min)...${NC}"
    echo "${CYAN}   Monitore em: https://console.aws.amazon.com/cloudformation${NC}"
    
elif [ "${STACK_STATUS}" == "DELETE_FAILED" ]; then
    echo "${RED}   ❌ Stack em DELETE_FAILED: ${EKSCTL_STACK}${NC}"
    echo ""
    echo "${YELLOW}   Tentando forçar deleção...${NC}"
    aws cloudformation delete-stack --stack-name ${EKSCTL_STACK} --region ${AWS_REGION} 2>/dev/null
    echo "${GREEN}   ✅ Comando de deleção reenviado${NC}"
    CLEANED=$((CLEANED + 1))
    
elif [ "${STACK_STATUS}" != "NOT_FOUND" ] && [ "${STACK_STATUS}" != "DELETE_COMPLETE" ]; then
    echo "${YELLOW}   Stack em estado: ${STACK_STATUS}${NC}"
    
else
    echo "${GREEN}   ✅ Nenhuma stack órfã encontrada${NC}"
fi
echo ""

# 5. Verificar Volumes EBS órfãos
echo "${CYAN}5. Verificando volumes EBS órfãos...${NC}"
ORPHAN_VOLUMES=$(aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
            "Name=status,Values=available" \
  --query 'Volumes[].[VolumeId,Size,State]' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

if [ -n "${ORPHAN_VOLUMES}" ]; then
    echo "${YELLOW}   Encontrados volumes órfãos:${NC}"
    echo "${ORPHAN_VOLUMES}" | while read line; do
        echo "      $line"
    done
    
    VOLUME_IDS=$(echo "${ORPHAN_VOLUMES}" | awk '{print $1}')
    echo ""
    echo "${YELLOW}   Deletando volumes...${NC}"
    for VOL in ${VOLUME_IDS}; do
        aws ec2 delete-volume --volume-id ${VOL} --region ${AWS_REGION} 2>/dev/null || true
    done
    echo "${GREEN}   ✅ Volumes deletados${NC}"
    CLEANED=$((CLEANED + 1))
else
    echo "${GREEN}   ✅ Nenhum volume órfão encontrado${NC}"
fi
echo ""

# Resumo
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          ✅ LIMPEZA DE ÓRFÃOS CONCLUÍDA                    ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $CLEANED -gt 0 ]; then
    echo "${GREEN}✅ ${CLEANED} tipo(s) de recursos órfãos foram limpos${NC}"
    echo ""
    echo "${YELLOW}💡 Recomendação:${NC}"
    echo "   Aguarde 5-10 minutos e execute este script novamente para"
    echo "   verificar se todos os recursos foram completamente removidos."
else
    echo "${GREEN}✅ Nenhum recurso órfão encontrado!${NC}"
    echo "   Todos os recursos foram limpos corretamente."
fi
echo ""
echo "${CYAN}📋 Para verificar custos:${NC}"
echo "   https://console.aws.amazon.com/billing/home#/bills${NC}"
echo ""
