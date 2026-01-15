#!/bin/bash
#*************************
# Cleanup Script - Remove todos os recursos do lab
# IMPORTANTE: Execute este script para evitar custos!
#*************************

set +e  # Continue on errors during cleanup

# Determinar o diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Carregar variáveis de ambiente
if [ -f "${PROJECT_ROOT}/deployment/environmentVariables.sh" ]; then
    source "${PROJECT_ROOT}/deployment/environmentVariables.sh"
else
    # Definir cores manualmente se não conseguir carregar
    export RED=$(tput setaf 1 2>/dev/null || echo "")
    export GREEN=$(tput setaf 2 2>/dev/null || echo "")
    export YELLOW=$(tput setaf 3 2>/dev/null || echo "")
    export BLUE=$(tput setaf 4 2>/dev/null || echo "")
    export CYAN=$(tput setaf 6 2>/dev/null || echo "")
    export NC=$(tput sgr0 2>/dev/null || echo "")
    
    echo "${RED}❌ Erro ao carregar environmentVariables.sh${NC}"
    echo "${YELLOW}Continuando com valores padrão...${NC}"
    export CLUSTER_NAME="${CLUSTER_NAME:-eks-demo-scale-v2}"
    export AWS_REGION="${AWS_REGION:-us-east-1}"
    export SQS_QUEUE_NAME="${SQS_QUEUE_NAME:-keda-demo-queue.fifo}"
    export DYNAMODB_TABLE="${DYNAMODB_TABLE:-payments}"
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
fi

echo ""
echo "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${RED}║                                                            ║${NC}"
echo "${RED}║            ⚠️  SCRIPT DE LIMPEZA DE RECURSOS               ║${NC}"
echo "${RED}║                                                            ║${NC}"
echo "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${YELLOW}⚠️  Este script irá DELETAR os seguintes recursos:${NC}"
echo ""
echo "   ${RED}• Cluster EKS:${NC} ${CLUSTER_NAME}"
echo "   ${RED}• Todos os nodes EC2${NC}"
echo "   ${RED}• VPC, Subnets, NAT Gateways${NC}"
echo "   ${RED}• Fila SQS:${NC} ${SQS_QUEUE_NAME}"
echo "   ${RED}• Tabela DynamoDB:${NC} ${DYNAMODB_TABLE}"
echo "   ${RED}• IAM Roles e Policies${NC}"
echo "   ${RED}• CloudFormation Stacks${NC}"
echo ""

echo "${RED}════════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}Tem certeza que deseja continuar? (digite 'DELETE' para confirmar)${NC}"
echo -n "${CYAN}Confirmação: ${NC}"
read confirmation

if [[ "$confirmation" != "DELETE" ]]; then
    echo ""
    echo "${GREEN}✅ Limpeza cancelada. Nenhum recurso foi removido.${NC}"
    exit 0
fi

echo ""
echo "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${RED}║          INICIANDO LIMPEZA DE RECURSOS                    ║${NC}"
echo "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Contador de recursos removidos
DELETED_COUNT=0

# Função para incrementar contador
increment_deleted() {
    DELETED_COUNT=$((DELETED_COUNT + 1))
}

# Passo 1: Deletar ECR Repository
echo "${YELLOW}📦 Passo 1/7: Deletando ECR Repository...${NC}"
ECR_REPOSITORY_NAME="keda-sqs-reader"

if aws ecr describe-repositories --repository-names "${ECR_REPOSITORY_NAME}" --region "${AWS_REGION}" &> /dev/null; then
    echo "${CYAN}   Repository encontrado: ${ECR_REPOSITORY_NAME}${NC}"
    
    # Deletar todas as imagens primeiro
    IMAGE_IDS=$(aws ecr list-images --repository-name "${ECR_REPOSITORY_NAME}" --region "${AWS_REGION}" --query 'imageIds[*]' --output json 2>/dev/null)
    
    if [ -n "${IMAGE_IDS}" ] && [ "${IMAGE_IDS}" != "[]" ] && [ "${IMAGE_IDS}" != "null" ]; then
        echo "${YELLOW}   Deletando imagens...${NC}"
        aws ecr batch-delete-image \
          --repository-name "${ECR_REPOSITORY_NAME}" \
          --region "${AWS_REGION}" \
          --image-ids "${IMAGE_IDS}" > /dev/null 2>&1
    fi
    
    # Deletar repository
    echo "${YELLOW}   Deletando repository...${NC}"
    if aws ecr delete-repository \
      --repository-name "${ECR_REPOSITORY_NAME}" \
      --region "${AWS_REGION}" \
      --force > /dev/null 2>&1; then
        echo "${GREEN}✅ ECR Repository deletado${NC}"
        increment_deleted
    else
        echo "${RED}❌ Falha ao deletar ECR Repository${NC}"
    fi
else
    echo "${CYAN}   ECR Repository não encontrado, pulando...${NC}"
fi
echo ""

# Passo 2: Deletar SQS Queue
echo "${YELLOW}📝 Passo 2/7: Deletando fila SQS...${NC}"
if QUEUE_URL=$(aws sqs get-queue-url --queue-name ${SQS_QUEUE_NAME} --region ${AWS_REGION} --query 'QueueUrl' --output text 2>/dev/null); then
    aws sqs delete-queue --queue-url "${QUEUE_URL}" --region ${AWS_REGION}
    echo "${GREEN}   ✅ Fila SQS deletada: ${SQS_QUEUE_NAME}${NC}"
    increment_deleted
else
    echo "${BLUE}   ℹ️  Fila SQS não encontrada ou já deletada${NC}"
fi
echo ""

# Passo 3: Deletar DynamoDB Table
echo "${YELLOW}📝 Passo 3/7: Deletando tabela DynamoDB...${NC}"
if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} &>/dev/null; then
    aws dynamodb delete-table --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} > /dev/null
    echo "${GREEN}   ✅ Tabela DynamoDB deletada: ${DYNAMODB_TABLE}${NC}"
    echo "${CYAN}   ⏳ Aguardando exclusão completa...${NC}"
    aws dynamodb wait table-not-exists --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} 2>/dev/null || true
    increment_deleted
else
    echo "${BLUE}   ℹ️  Tabela DynamoDB não encontrada ou já deletada${NC}"
fi
echo ""

# Passo 4: Deletar Cluster EKS (inclui todos os recursos do Kubernetes)
echo "${YELLOW}📝 Passo 4/7: Deletando cluster EKS (isso pode levar 10-15 min)...${NC}"

# CRÍTICO: Terminar instâncias Karpenter ANTES de deletar o cluster
echo "${CYAN}   • Terminando instâncias EC2 criadas pelo Karpenter...${NC}"
# Karpenter v1.0+ usa tag: karpenter.sh/nodepool
KARPENTER_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=*" \
            "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

# Fallback para versão antiga (provisioner) se não encontrar nada
if [ -z "${KARPENTER_INSTANCES}" ]; then
    KARPENTER_INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=tag:karpenter.sh/provisioner-name,Values=*" \
                "Name=instance-state-name,Values=running,stopped,stopping,pending" \
      --query 'Reservations[].Instances[].InstanceId' \
      --output text \
      --region ${AWS_REGION} 2>/dev/null)
fi

# Fallback adicional: buscar por nome karpenter-*
if [ -z "${KARPENTER_INSTANCES}" ]; then
    KARPENTER_INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=karpenter-*" \
                "Name=instance-state-name,Values=running,stopped,stopping,pending" \
      --query 'Reservations[].Instances[].InstanceId' \
      --output text \
      --region ${AWS_REGION} 2>/dev/null)
fi

if [ -n "${KARPENTER_INSTANCES}" ]; then
    echo "${YELLOW}      Terminando instâncias: ${KARPENTER_INSTANCES}${NC}"
    
    # Primeiro, remover instance profiles das instâncias
    for INSTANCE_ID in ${KARPENTER_INSTANCES}; do
        PROFILE_ASSOCIATION=$(aws ec2 describe-iam-instance-profile-associations \
          --filters "Name=instance-id,Values=${INSTANCE_ID}" \
          --query 'IamInstanceProfileAssociations[0].AssociationId' \
          --output text --region ${AWS_REGION} 2>/dev/null)
        
        if [ -n "${PROFILE_ASSOCIATION}" ] && [ "${PROFILE_ASSOCIATION}" != "None" ]; then
            echo "${CYAN}      Removendo instance profile da instância ${INSTANCE_ID}...${NC}"
            aws ec2 disassociate-iam-instance-profile \
              --association-id ${PROFILE_ASSOCIATION} \
              --region ${AWS_REGION} &>/dev/null || true
        fi
    done
    
    # Terminar instâncias
    aws ec2 terminate-instances \
      --instance-ids ${KARPENTER_INSTANCES} \
      --region ${AWS_REGION} > /dev/null 2>&1
    
    echo "${CYAN}      Aguardando terminação completa das instâncias...${NC}"
    # Usar aws ec2 wait para garantir que terminaram (timeout 5 min)
    aws ec2 wait instance-terminated \
      --instance-ids ${KARPENTER_INSTANCES} \
      --region ${AWS_REGION} 2>/dev/null && \
      echo "${GREEN}      ✅ Todas as instâncias terminadas${NC}" || \
      echo "${YELLOW}      ⚠️  Timeout aguardando terminação (continuando...)${NC}"
    
    # Aguardar mais 10s para garantir que ENIs foram liberadas
    sleep 10
else
    echo "${CYAN}      Nenhuma instância do Karpenter encontrada${NC}"
fi

if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "${CYAN}   • Removendo finalizers de NodePools/Provisioners...${NC}"
    kubectl patch nodepool default -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl patch provisioner default -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    
    echo "${CYAN}   • Limpando Security Groups órfãos antes de deletar cluster...${NC}"
    VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
      --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null)
    
    if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ]; then
        echo "${CYAN}      VPC ID: ${VPC_ID}${NC}"
        
        # Buscar Security Groups (exceto default)
        SG_IDS=$(aws ec2 describe-security-groups --region ${AWS_REGION} \
          --filters "Name=vpc-id,Values=${VPC_ID}" \
          --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
          --output text 2>/dev/null)
        
        if [ -n "${SG_IDS}" ]; then
            echo "${CYAN}      Encontrados Security Groups: ${SG_IDS}${NC}"
            
            # Remover regras de ingress/egress (evita dependências circulares)
            for SG_ID in ${SG_IDS}; do
                echo "${CYAN}      Limpando regras do SG: ${SG_ID}${NC}"
                
                # Remover regras de ingress
                aws ec2 describe-security-groups --group-ids ${SG_ID} --region ${AWS_REGION} \
                  --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null | \
                  jq -c '.[]' 2>/dev/null | while read rule; do
                    aws ec2 revoke-security-group-ingress \
                      --group-id ${SG_ID} \
                      --ip-permissions "${rule}" \
                      --region ${AWS_REGION} &>/dev/null || true
                done
                
                # Remover regras de egress
                aws ec2 describe-security-groups --group-ids ${SG_ID} --region ${AWS_REGION} \
                  --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null | \
                  jq -c '.[]' 2>/dev/null | while read rule; do
                    aws ec2 revoke-security-group-egress \
                      --group-id ${SG_ID} \
                      --ip-permissions "${rule}" \
                      --region ${AWS_REGION} &>/dev/null || true
                done
                
                # Tentar deletar o Security Group
                aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION} &>/dev/null && \
                  echo "${GREEN}      ✅ SG removido: ${SG_ID}${NC}" || \
                  echo "${YELLOW}      ⚠️  SG será removido pelo CloudFormation: ${SG_ID}${NC}"
            done
        else
            echo "${CYAN}      Nenhum Security Group órfão encontrado${NC}"
        fi
    fi
    
    echo "${CYAN}   • Deletando cluster via eksctl...${NC}"
    eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --wait
    
    echo "${GREEN}   ✅ Cluster EKS deletado: ${CLUSTER_NAME}${NC}"
    increment_deleted
else
    echo "${BLUE}   ℹ️  Cluster EKS não encontrado ou já deletado${NC}"
fi
echo ""

# Passo 5: Deletar CloudFormation Stack do Karpenter
echo "${YELLOW}📝 Passo 5/7: Deletando CloudFormation Stack do Karpenter...${NC}"
KARPENTER_STACK="Karpenter-${CLUSTER_NAME}"

# Primeiro, remover instance profiles que possam bloquear a deleção
echo "${CYAN}   • Removendo instance profiles...${NC}"
INSTANCE_PROFILE_NAME="KarpenterNodeInstanceProfile-${CLUSTER_NAME}"

# Verificar se há associações ativas antes de deletar
ACTIVE_ASSOCIATIONS=$(aws ec2 describe-iam-instance-profile-associations \
  --filters "Name=iam-instance-profile.arn,Values=arn:aws:iam::${ACCOUNT_ID}:instance-profile/${INSTANCE_PROFILE_NAME}" \
  --query 'IamInstanceProfileAssociations[*].AssociationId' \
  --output text --region ${AWS_REGION} 2>/dev/null)

if [ -n "${ACTIVE_ASSOCIATIONS}" ]; then
    echo "${YELLOW}   ⚠️  Encontradas associações ativas, removendo...${NC}"
    for ASSOC_ID in ${ACTIVE_ASSOCIATIONS}; do
        aws ec2 disassociate-iam-instance-profile \
          --association-id ${ASSOC_ID} \
          --region ${AWS_REGION} &>/dev/null || true
    done
    sleep 5
fi

if aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} &>/dev/null; then
    # Remover role do instance profile
    ROLE_IN_PROFILE=$(aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} --query 'InstanceProfile.Roles[0].RoleName' --output text 2>/dev/null)
    if [ ! -z "$ROLE_IN_PROFILE" ] && [ "$ROLE_IN_PROFILE" != "None" ]; then
        aws iam remove-role-from-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} --role-name ${ROLE_IN_PROFILE} 2>/dev/null
    fi
    # Deletar instance profile
    aws iam delete-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} 2>/dev/null && \
      echo "${GREEN}   ✅ Instance profile removido: ${INSTANCE_PROFILE_NAME}${NC}" || \
      echo "${YELLOW}   ⚠️  Erro ao remover instance profile (será removido pelo CloudFormation)${NC}"
fi

# Detach de IAM policies antes de deletar stack
echo "${CYAN}   • Desanexando IAM policies dos roles...${NC}"
KARPENTER_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}"

# Verificar se a policy existe e fazer detach de todos os anexos
if aws iam get-policy --policy-arn ${KARPENTER_POLICY_ARN} &>/dev/null; then
    # Listar todas as entidades anexadas à policy
    ATTACHED_ROLES=$(aws iam list-entities-for-policy --policy-arn ${KARPENTER_POLICY_ARN} --query 'PolicyRoles[].RoleName' --output text 2>/dev/null)
    
    if [ ! -z "$ATTACHED_ROLES" ]; then
        for ROLE_NAME in $ATTACHED_ROLES; do
            echo "${CYAN}      Desanexando policy de role: ${ROLE_NAME}${NC}"
            aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn ${KARPENTER_POLICY_ARN} 2>/dev/null || true
        done
    fi
    
    # Deletar a policy manualmente (CloudFormation pode não conseguir)
    aws iam delete-policy --policy-arn ${KARPENTER_POLICY_ARN} 2>/dev/null && \
        echo "${GREEN}      ✅ Policy deletada: KarpenterControllerPolicy-${CLUSTER_NAME}${NC}" || \
        echo "${YELLOW}      ⚠️  Policy será deletada pelo CloudFormation${NC}"
fi

# Agora deletar o stack
KARPENTER_STACK_DELETED=false
if aws cloudformation describe-stacks --stack-name ${KARPENTER_STACK} --region ${AWS_REGION} &>/dev/null; then
    echo "${CYAN}   • Deletando stack CloudFormation...${NC}"
    aws cloudformation delete-stack --stack-name ${KARPENTER_STACK} --region ${AWS_REGION}
    
    echo "${CYAN}   ⏳ Aguardando exclusão da stack (timeout 8 minutos)...${NC}"
    
    # Aguardar com timeout de 8 minutos (aumentado)
    TIMEOUT=480
    ELAPSED=0
    RETRY_COUNT=0
    MAX_RETRIES=3
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        STATUS=$(aws cloudformation describe-stacks --stack-name ${KARPENTER_STACK} --region ${AWS_REGION} --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
        
        if [ "$STATUS" == "DELETED" ] || [ "$STATUS" == "DELETE_COMPLETE" ]; then
            echo "${GREEN}   ✅ CloudFormation Stack deletada: ${KARPENTER_STACK}${NC}"
            KARPENTER_STACK_DELETED=true
            increment_deleted
            break
        elif [ "$STATUS" == "DELETE_FAILED" ]; then
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -le $MAX_RETRIES ]; then
                echo "${YELLOW}   ⚠️  Falha ao deletar stack (tentativa ${RETRY_COUNT}/${MAX_RETRIES})${NC}"
                
                # Verificar motivo da falha
                FAILED_RESOURCES=$(aws cloudformation describe-stack-events --stack-name ${KARPENTER_STACK} --region ${AWS_REGION} --max-items 10 --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].LogicalResourceId' --output text 2>/dev/null)
                
                if [ ! -z "$FAILED_RESOURCES" ]; then
                    echo "${CYAN}      Recursos com falha: ${FAILED_RESOURCES}${NC}"
                    
                    # Se role falhou, tentar deletar manualmente
                    if echo "$FAILED_RESOURCES" | grep -q "KarpenterNodeRole"; then
                        echo "${CYAN}      Tentando deletar KarpenterNodeRole manualmente...${NC}"
                        # Será tratado na seção de limpeza de roles (Passo 7)
                    fi
                fi
                
                # Retry com força
                echo "${CYAN}      Tentando forçar deleção novamente...${NC}"
                aws cloudformation delete-stack --stack-name ${KARPENTER_STACK} --region ${AWS_REGION} 2>/dev/null
                sleep 20
            else
                echo "${RED}   ❌ Stack falhou após ${MAX_RETRIES} tentativas${NC}"
                echo "${YELLOW}   ⚠️  Prosseguindo com limpeza manual de recursos...${NC}"
                break
            fi
        fi
        
        sleep 15
        ELAPSED=$((ELAPSED + 15))
    done
    
    # Verificar se ainda existe após timeout
    FINAL_STATUS=$(aws cloudformation describe-stacks --stack-name ${KARPENTER_STACK} --region ${AWS_REGION} --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
    if [ "$FINAL_STATUS" != "DELETED" ] && [ "$FINAL_STATUS" != "DELETE_COMPLETE" ]; then
        echo "${YELLOW}   ⚠️  Stack ainda existe em estado: ${FINAL_STATUS}${NC}"
        echo "${CYAN}   💡 Recursos órfãos serão limpos na verificação final${NC}"
    fi
else
    echo "${BLUE}   ℹ️  CloudFormation Stack não encontrada ou já deletada${NC}"
    KARPENTER_STACK_DELETED=true
fi

# Verificar se há outras stacks órfãs
echo "${CYAN}   • Verificando stacks órfãs...${NC}"
ORPHAN_STACKS=$(aws cloudformation describe-stacks --region ${AWS_REGION} --query "Stacks[?contains(StackName, '${CLUSTER_NAME}')].StackName" --output text 2>/dev/null)
if [ ! -z "$ORPHAN_STACKS" ]; then
    for STACK in $ORPHAN_STACKS; do
        echo "${YELLOW}   ⚠️  Stack órfã encontrada: ${STACK}${NC}"
        aws cloudformation delete-stack --stack-name ${STACK} --region ${AWS_REGION} 2>/dev/null
        increment_deleted
    done
fi
echo ""

# Passo 6: Deletar IAM Policies (somente órfãs ou se stack falhou)
echo "${YELLOW}📝 Passo 6/7: Deletando IAM Policies...${NC}"

# Se stack Karpenter foi deletada com sucesso, policies devem ter sido deletadas também
if [ "$KARPENTER_STACK_DELETED" = true ]; then
    echo "${CYAN}   • Stack Karpenter deletada com sucesso, verificando policies órfãs...${NC}"
else
    echo "${CYAN}   • Stack Karpenter falhou, limpando policies manualmente...${NC}"
fi

# Lista de policies para deletar
POLICIES=(
    "KarpenterControllerPolicy-${CLUSTER_NAME}"
    "KedaSQSPolicy-${CLUSTER_NAME}"
    "KedaDynamoPolicy-${CLUSTER_NAME}"
)

for POLICY_NAME in "${POLICIES[@]}"; do
    POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text --region ${AWS_REGION})
    
    if [ ! -z "$POLICY_ARN" ]; then
        # Detach de todas as roles antes de deletar
        ATTACHED_ROLES=$(aws iam list-entities-for-policy --policy-arn ${POLICY_ARN} --query 'PolicyRoles[*].RoleName' --output text --region ${AWS_REGION})
        
        for ROLE in $ATTACHED_ROLES; do
            aws iam detach-role-policy --role-name ${ROLE} --policy-arn ${POLICY_ARN} --region ${AWS_REGION} 2>/dev/null || true
        done
        
        aws iam delete-policy --policy-arn ${POLICY_ARN} --region ${AWS_REGION} 2>/dev/null || true
        echo "${GREEN}   ✅ Policy deletada: ${POLICY_NAME}${NC}"
        increment_deleted
    else
        echo "${BLUE}   ℹ️  Policy não encontrada: ${POLICY_NAME}${NC}"
    fi
done
echo ""

# Passo 7: Deletar IAM Roles (somente órfãs ou se stack falhou)
echo "${YELLOW}📝 Passo 7/7: Deletando IAM Roles...${NC}"

# Se stack Karpenter foi deletada com sucesso, roles devem ter sido deletadas também
if [ "$KARPENTER_STACK_DELETED" = true ]; then
    echo "${CYAN}   • Stack Karpenter deletada com sucesso, verificando roles órfãs...${NC}"
else
    echo "${CYAN}   • Stack Karpenter falhou, limpando roles manualmente...${NC}"
fi

# Lista de roles para deletar
ROLES=(
    "KarpenterNodeRole-${CLUSTER_NAME}"
    "KarpenterControllerRole-${CLUSTER_NAME}"
    "KedaDemoRole-${CLUSTER_NAME}"
)
ROLES=(
    "KarpenterNodeRole-${CLUSTER_NAME}"
    "KarpenterControllerRole-${CLUSTER_NAME}"
    "KedaDemoRole-${CLUSTER_NAME}"
)

for ROLE_NAME in "${ROLES[@]}"; do
    if aws iam get-role --role-name ${ROLE_NAME} --region ${AWS_REGION} &>/dev/null; then
        echo "${CYAN}   • Limpando role: ${ROLE_NAME}${NC}"
        
        # Detach todas as policies
        ATTACHED=$(aws iam list-attached-role-policies --role-name ${ROLE_NAME} --query 'AttachedPolicies[*].PolicyArn' --output text --region ${AWS_REGION})
        for POLICY in $ATTACHED; do
            echo "${CYAN}      Desanexando policy: ${POLICY}${NC}"
            aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY} --region ${AWS_REGION} 2>/dev/null || true
        done
        
        # Deletar instance profiles associados
        INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name ${ROLE_NAME} --query 'InstanceProfiles[*].InstanceProfileName' --output text --region ${AWS_REGION})
        for PROFILE in $INSTANCE_PROFILES; do
            echo "${CYAN}      Removendo instance profile: ${PROFILE}${NC}"
            aws iam remove-role-from-instance-profile --instance-profile-name ${PROFILE} --role-name ${ROLE_NAME} --region ${AWS_REGION} 2>/dev/null || true
            aws iam delete-instance-profile --instance-profile-name ${PROFILE} --region ${AWS_REGION} 2>/dev/null || true
        done
        
        # Deletar role
        if aws iam delete-role --role-name ${ROLE_NAME} --region ${AWS_REGION} 2>/dev/null; then
            echo "${GREEN}   ✅ Role deletada: ${ROLE_NAME}${NC}"
            increment_deleted
        else
            echo "${YELLOW}   ⚠️  Não foi possível deletar role: ${ROLE_NAME}${NC}"
        fi
    else
        echo "${BLUE}   ℹ️  Role não encontrada: ${ROLE_NAME}${NC}"
    fi
done
echo ""

# Resumo final
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          ✅ LIMPEZA CONCLUÍDA!                             ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "${CYAN}📊 Resumo:${NC}"
echo "   ${GREEN}✅ Recursos deletados: ${DELETED_COUNT}${NC}"
echo ""

# Verificação final de recursos órfãos
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  Verificação Final de Recursos Órfãos${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

ORPHAN_FOUND=false

# Verificar instâncias EC2 do Karpenter
echo "${CYAN}Verificando instâncias EC2 do Karpenter...${NC}"
# Karpenter v1.0+ usa tag: karpenter.sh/nodepool
ORPHAN_INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=*" \
            "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

# Fallback para versão antiga
if [ -z "${ORPHAN_INSTANCES}" ]; then
    ORPHAN_INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=tag:karpenter.sh/provisioner-name,Values=*" \
                "Name=instance-state-name,Values=running,stopped,stopping,pending" \
      --query 'Reservations[].Instances[].InstanceId' \
      --output text \
      --region ${AWS_REGION} 2>/dev/null)
fi

# Fallback adicional: buscar por nome karpenter-*
if [ -z "${ORPHAN_INSTANCES}" ]; then
    ORPHAN_INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=karpenter-*" \
                "Name=instance-state-name,Values=running,stopped,stopping,pending" \
      --query 'Reservations[].Instances[].InstanceId' \
      --output text \
      --region ${AWS_REGION} 2>/dev/null)
fi

if [ -n "${ORPHAN_INSTANCES}" ]; then
    echo "${YELLOW}   ⚠️  Instâncias órfãs encontradas: ${ORPHAN_INSTANCES}${NC}"
    echo "${CYAN}   Terminando instâncias órfãs...${NC}"
    aws ec2 terminate-instances --instance-ids ${ORPHAN_INSTANCES} --region ${AWS_REGION} > /dev/null 2>&1
    echo "${GREEN}   ✅ Instâncias órfãs terminadas${NC}"
    ORPHAN_FOUND=true
else
    echo "${GREEN}   ✅ Nenhuma instância órfã encontrada${NC}"
fi

# Verificar stacks CloudFormation do eksctl travadas
echo ""
echo "${CYAN}Verificando stacks CloudFormation...${NC}"
EKSCTL_STACK="eksctl-${CLUSTER_NAME}-cluster"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${EKSCTL_STACK} --region ${AWS_REGION} --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${STACK_STATUS}" == "DELETE_IN_PROGRESS" ]; then
    echo "${YELLOW}   ⚠️  Stack ainda em DELETE_IN_PROGRESS: ${EKSCTL_STACK}${NC}"
    echo "${CYAN}   Isso é normal, pode levar até 15 minutos para concluir${NC}"
    echo "${CYAN}   Monitore em: https://console.aws.amazon.com/cloudformation${NC}"
    ORPHAN_FOUND=true
elif [ "${STACK_STATUS}" == "DELETE_FAILED" ]; then
    echo "${RED}   ❌ Stack em DELETE_FAILED: ${EKSCTL_STACK}${NC}"
    
    # Verificar recursos que falharam
    FAILED_RESOURCES=$(aws cloudformation describe-stack-events --stack-name ${EKSCTL_STACK} --region ${AWS_REGION} --max-items 20 --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceStatusReason]' --output text 2>/dev/null | head -5)
    
    if echo "$FAILED_RESOURCES" | grep -q "VPC"; then
        echo "${YELLOW}   ⚠️  VPC falhou ao deletar, verificando dependências...${NC}"
        
        # Obter VPC ID da stack
        VPC_ID_FROM_STACK=$(aws cloudformation describe-stack-resources --stack-name ${EKSCTL_STACK} --region ${AWS_REGION} --query 'StackResources[?ResourceType==`AWS::EC2::VPC`].PhysicalResourceId' --output text 2>/dev/null)
        
        if [ -n "${VPC_ID_FROM_STACK}" ]; then
            echo "${CYAN}   • Limpando security groups órfãos da VPC...${NC}"
            
            # Buscar security groups órfãos (exceto default)
            ORPHAN_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID_FROM_STACK}" --region ${AWS_REGION} --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null)
            
            if [ -n "${ORPHAN_SGS}" ]; then
                for SG_ID in ${ORPHAN_SGS}; do
                    echo "${CYAN}      Deletando SG: ${SG_ID}${NC}"
                    aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION} 2>/dev/null && \
                      echo "${GREEN}      ✅ SG deletado${NC}" || \
                      echo "${YELLOW}      ⚠️  SG não pôde ser deletado (em uso?)${NC}"
                done
                
                # Tentar forçar deleção da stack novamente
                echo "${CYAN}   • Tentando deletar stack novamente...${NC}"
                aws cloudformation delete-stack --stack-name ${EKSCTL_STACK} --region ${AWS_REGION} 2>/dev/null
                echo "${YELLOW}   ⏳ Stack em nova tentativa de deleção${NC}"
            fi
        fi
    fi
    
    ORPHAN_FOUND=true
elif [ "${STACK_STATUS}" != "NOT_FOUND" ] && [ "${STACK_STATUS}" != "DELETE_COMPLETE" ]; then
    echo "${YELLOW}   ⚠️  Stack em estado inesperado: ${STACK_STATUS}${NC}"
    echo "${CYAN}   Forçando deleção da stack...${NC}"
    aws cloudformation delete-stack --stack-name ${EKSCTL_STACK} --region ${AWS_REGION} 2>/dev/null || true
    ORPHAN_FOUND=true
else
    echo "${GREEN}   ✅ Nenhuma stack órfã encontrada${NC}"
fi

# Forçar deleção de TODAS as stacks relacionadas ao cluster
echo ""
echo "${CYAN}Verificando TODAS as stacks relacionadas ao cluster...${NC}"
ALL_RELATED_STACKS=$(aws cloudformation list-stacks --region ${AWS_REGION} \
  --query "StackSummaries[?contains(StackName, '${CLUSTER_NAME}') && (StackStatus=='DELETE_FAILED' || StackStatus=='CREATE_FAILED' || StackStatus=='CREATE_COMPLETE' || StackStatus=='UPDATE_COMPLETE' || StackStatus=='DELETE_IN_PROGRESS')].StackName" \
  --output text 2>/dev/null)

if [ -n "${ALL_RELATED_STACKS}" ]; then
    echo "${YELLOW}   ⚠️  Encontradas ${YELLOW}$(echo ${ALL_RELATED_STACKS} | wc -w)${YELLOW} stacks relacionadas${NC}"
    for RELATED_STACK in ${ALL_RELATED_STACKS}; do
        RELATED_STATUS=$(aws cloudformation describe-stacks --stack-name ${RELATED_STACK} --region ${AWS_REGION} --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "UNKNOWN")
        echo "${CYAN}      • ${RELATED_STACK} (${RELATED_STATUS})${NC}"
        
        if [ "${RELATED_STATUS}" == "DELETE_FAILED" ] || [ "${RELATED_STATUS}" == "CREATE_FAILED" ]; then
            echo "${YELLOW}         Forçando deleção...${NC}"
            aws cloudformation delete-stack --stack-name ${RELATED_STACK} --region ${AWS_REGION} 2>/dev/null || true
            ORPHAN_FOUND=true
        elif [ "${RELATED_STATUS}" == "DELETE_IN_PROGRESS" ]; then
            echo "${CYAN}         Já em processo de deleção${NC}"
        fi
    done
else
    echo "${GREEN}   ✅ Nenhuma stack relacionada encontrada${NC}"
fi

# Verificar ENIs (Elastic Network Interfaces) órfãs
echo ""
echo "${CYAN}Verificando ENIs (Elastic Network Interfaces) órfãs...${NC}"
if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ]; then
    ORPHAN_ENIS=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
                "Name=status,Values=available" \
      --query 'NetworkInterfaces[?Attachment==null].NetworkInterfaceId' \
      --output text \
      --region ${AWS_REGION} 2>/dev/null)
    
    if [ -n "${ORPHAN_ENIS}" ]; then
        echo "${YELLOW}   ⚠️  ENIs órfãs encontradas: ${ORPHAN_ENIS}${NC}"
        echo "${CYAN}   Deletando ENIs...${NC}"
        for ENI_ID in ${ORPHAN_ENIS}; do
            aws ec2 delete-network-interface --network-interface-id ${ENI_ID} --region ${AWS_REGION} 2>/dev/null && \
              echo "${GREEN}   ✅ ENI deletada: ${ENI_ID}${NC}" || \
              echo "${YELLOW}   ⚠️  Erro ao deletar ENI: ${ENI_ID}${NC}"
        done
        ORPHAN_FOUND=true
    else
        echo "${GREEN}   ✅ Nenhuma ENI órfã encontrada${NC}"
    fi
else
    echo "${BLUE}   ℹ️  VPC ID não disponível, pulando verificação de ENIs${NC}"
fi

echo ""
if [ "$ORPHAN_FOUND" = true ]; then
    echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo "${YELLOW}  ⚠️  ATENÇÃO: Recursos órfãos detectados${NC}"
    echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "${CYAN}Recursos órfãos foram encontrados e ações corretivas foram tomadas.${NC}"
    echo "${CYAN}Aguarde alguns minutos e verifique o AWS Console.${NC}"
    echo ""
else
    echo "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo "${GREEN}  ✅ Nenhum recurso órfão detectado${NC}"
    echo "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
fi

if [ $DELETED_COUNT -gt 0 ]; then
    echo "${GREEN}🎉 Todos os recursos foram removidos com sucesso!${NC}"
    echo "${YELLOW}💰 Você não terá mais custos relacionados a este lab.${NC}"
else
    echo "${BLUE}ℹ️  Nenhum recurso foi encontrado para deletar.${NC}"
    echo "${YELLOW}Possíveis motivos:${NC}"
    echo "   • Recursos já foram deletados anteriormente"
    echo "   • Nomes de recursos diferentes dos esperados"
    echo "   • Região AWS diferente"
fi

echo ""
echo "${CYAN}📋 Verificação recomendada:${NC}"
echo "   1. Console AWS EC2: Verificar se todos os nodes foram removidos"
echo "   2. Console AWS VPC: Verificar se VPC foi removida"
echo "   3. Console AWS IAM: Verificar roles órfãs"
echo "   4. Console AWS CloudFormation: Verificar stacks órfãs"
echo ""

echo "${YELLOW}💡 Comandos úteis para verificação manual:${NC}"
echo ""
echo "   # Verificar instâncias Karpenter:"
echo "   ${CYAN}aws ec2 describe-instances --filters \"Name=tag:Name,Values=karpenter-*\" --region ${AWS_REGION}${NC}"
echo ""
echo "   # Verificar stacks CloudFormation:"
echo "   ${CYAN}aws cloudformation list-stacks --stack-status-filter DELETE_IN_PROGRESS DELETE_FAILED --region ${AWS_REGION}${NC}"
echo ""
echo "   # Verificar ENIs órfãs:"
echo "   ${CYAN}aws ec2 describe-network-interfaces --filters \"Name=status,Values=available\" --region ${AWS_REGION}${NC}"
echo ""
echo "   # Forçar limpeza de recursos órfãos:"
echo "   ${CYAN}./scripts/force-cleanup.sh${NC}"
echo ""

echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo "${GREEN}         Script de Limpeza Finalizado!${NC}"
echo "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
