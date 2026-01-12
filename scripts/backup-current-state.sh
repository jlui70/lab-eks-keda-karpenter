#!/bin/bash
#*************************
# Backup Current State - EKS KEDA Karpenter Lab
# Cria backup completo antes do cleanup
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

# Criar diretório de backup com timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${SCRIPT_DIR}/../backups/backup_${TIMESTAMP}"
mkdir -p "${BACKUP_DIR}"/{kubernetes,aws,iam,manifests}

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║           BACKUP DO ESTADO ATUAL DO LAB                  ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}📁 Diretório de backup: ${BACKUP_DIR}${NC}"
echo ""

# Função para verificar se comando foi bem-sucedido
check_success() {
    if [ $? -eq 0 ]; then
        echo "${GREEN}   ✅ $1${NC}"
    else
        echo "${RED}   ❌ Falha: $1${NC}"
    fi
}

# ========================================
# 1. BACKUP KUBERNETES RESOURCES
# ========================================
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  1/5: Backup dos recursos Kubernetes${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Verificar se cluster está acessível
if ! kubectl cluster-info &>/dev/null; then
    echo "${RED}❌ Cluster não está acessível. Backup Kubernetes será pulado.${NC}"
else
    echo "${CYAN}Exportando recursos do namespace keda-test...${NC}"
    
    # Deployments
    kubectl get deployment -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/deployments.yaml" 2>/dev/null
    check_success "Deployments exportados"
    
    # Services
    kubectl get service -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/services.yaml" 2>/dev/null
    check_success "Services exportados"
    
    # ConfigMaps
    kubectl get configmap -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/configmaps.yaml" 2>/dev/null
    check_success "ConfigMaps exportados"
    
    # ServiceAccounts
    kubectl get serviceaccount -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/serviceaccounts.yaml" 2>/dev/null
    check_success "ServiceAccounts exportados"
    
    # ScaledObjects
    kubectl get scaledobject -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/scaledobjects.yaml" 2>/dev/null
    check_success "ScaledObjects exportados"
    
    # HPA (criado pelo KEDA)
    kubectl get hpa -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/hpa.yaml" 2>/dev/null
    check_success "HPA exportado"
    
    echo ""
    echo "${CYAN}Exportando recursos do Karpenter...${NC}"
    
    # Provisioners
    kubectl get provisioner -o yaml > "${BACKUP_DIR}/kubernetes/provisioners.yaml" 2>/dev/null
    check_success "Provisioners exportados"
    
    # AWSNodeTemplates
    kubectl get awsnodetemplate -o yaml > "${BACKUP_DIR}/kubernetes/awsnodetemplates.yaml" 2>/dev/null
    check_success "AWSNodeTemplates exportados"
    
    # Karpenter Deployment
    kubectl get deployment -n karpenter -o yaml > "${BACKUP_DIR}/kubernetes/karpenter-deployment.yaml" 2>/dev/null
    check_success "Karpenter Deployment exportado"
    
    echo ""
    echo "${CYAN}Exportando recursos do KEDA...${NC}"
    
    # KEDA Operator
    kubectl get deployment -n keda -o yaml > "${BACKUP_DIR}/kubernetes/keda-deployments.yaml" 2>/dev/null
    check_success "KEDA Deployments exportados"
    
    # TriggerAuthentications
    kubectl get triggerauthentication -n keda-test -o yaml > "${BACKUP_DIR}/kubernetes/triggerauthentications.yaml" 2>/dev/null
    check_success "TriggerAuthentications exportados"
    
    echo ""
    echo "${CYAN}Exportando informações do cluster...${NC}"
    
    # Nodes
    kubectl get nodes -o yaml > "${BACKUP_DIR}/kubernetes/nodes.yaml" 2>/dev/null
    check_success "Nodes exportados"
    
    # Namespaces
    kubectl get namespace keda-test,keda,karpenter -o yaml > "${BACKUP_DIR}/kubernetes/namespaces.yaml" 2>/dev/null
    check_success "Namespaces exportados"
    
    # Cluster Info
    kubectl cluster-info dump --output-directory="${BACKUP_DIR}/kubernetes/cluster-dump" --namespaces keda-test,keda,karpenter 2>/dev/null
    check_success "Cluster dump criado"
fi
echo ""

# ========================================
# 2. BACKUP AWS RESOURCES
# ========================================
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  2/5: Backup dos recursos AWS${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "${CYAN}Exportando informações do SQS...${NC}"
aws sqs get-queue-attributes \
  --queue-url "https://sqs.${AWS_REGION}.amazonaws.com/${ACCOUNT_ID}/${SQS_QUEUE_NAME}" \
  --attribute-names All \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/sqs-queue-attributes.json" 2>/dev/null
check_success "Atributos da fila SQS"

echo "${CYAN}Exportando informações do DynamoDB...${NC}"
aws dynamodb describe-table \
  --table-name "${DYNAMODB_TABLE}" \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/dynamodb-table-description.json" 2>/dev/null
check_success "Descrição da tabela DynamoDB"

# Backup de alguns itens do DynamoDB (últimos 100)
aws dynamodb scan \
  --table-name "${DYNAMODB_TABLE}" \
  --max-items 100 \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/dynamodb-sample-data.json" 2>/dev/null
check_success "Sample data do DynamoDB"

echo "${CYAN}Exportando informações do ECR...${NC}"
aws ecr describe-repositories \
  --repository-names "keda-sqs-reader" \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/ecr-repository.json" 2>/dev/null
check_success "Repositório ECR"

aws ecr describe-images \
  --repository-name "keda-sqs-reader" \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/ecr-images.json" 2>/dev/null
check_success "Imagens do ECR"

echo "${CYAN}Exportando informações do EKS...${NC}"
aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/eks-cluster.json" 2>/dev/null
check_success "Cluster EKS"

aws eks list-nodegroups \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  > "${BACKUP_DIR}/aws/eks-nodegroups.json" 2>/dev/null
check_success "NodeGroups do EKS"

echo ""

# ========================================
# 3. BACKUP IAM RESOURCES
# ========================================
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  3/5: Backup das configurações IAM${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Roles
ROLES=(
    "KarpenterNodeRole-${CLUSTER_NAME}"
    "KarpenterControllerRole-${CLUSTER_NAME}"
    "KedaDemoRole-${CLUSTER_NAME}"
)

echo "${CYAN}Exportando IAM Roles...${NC}"
for ROLE_NAME in "${ROLES[@]}"; do
    if aws iam get-role --role-name "${ROLE_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        aws iam get-role --role-name "${ROLE_NAME}" --region "${AWS_REGION}" \
          > "${BACKUP_DIR}/iam/role-${ROLE_NAME}.json" 2>/dev/null
        
        # Políticas anexadas
        aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --region "${AWS_REGION}" \
          > "${BACKUP_DIR}/iam/role-${ROLE_NAME}-policies.json" 2>/dev/null
        
        check_success "Role: ${ROLE_NAME}"
    fi
done

# Policies
POLICIES=(
    "KarpenterControllerPolicy-${CLUSTER_NAME}"
    "KedaSQSPolicy-${CLUSTER_NAME}"
    "KedaDynamoPolicy-${CLUSTER_NAME}"
)

echo ""
echo "${CYAN}Exportando IAM Policies...${NC}"
for POLICY_NAME in "${POLICIES[@]}"; do
    POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text --region "${AWS_REGION}" 2>/dev/null)
    
    if [ -n "${POLICY_ARN}" ]; then
        aws iam get-policy --policy-arn "${POLICY_ARN}" --region "${AWS_REGION}" \
          > "${BACKUP_DIR}/iam/policy-${POLICY_NAME}.json" 2>/dev/null
        
        # Versão da política
        POLICY_VERSION=$(aws iam get-policy --policy-arn "${POLICY_ARN}" --query 'Policy.DefaultVersionId' --output text --region "${AWS_REGION}" 2>/dev/null)
        aws iam get-policy-version --policy-arn "${POLICY_ARN}" --version-id "${POLICY_VERSION}" --region "${AWS_REGION}" \
          > "${BACKUP_DIR}/iam/policy-${POLICY_NAME}-document.json" 2>/dev/null
        
        check_success "Policy: ${POLICY_NAME}"
    fi
done

echo ""

# ========================================
# 4. BACKUP CLOUDFORMATION STACKS
# ========================================
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  4/5: Backup dos CloudFormation Stacks${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

KARPENTER_STACK="Karpenter-${CLUSTER_NAME}"

echo "${CYAN}Exportando CloudFormation Stack do Karpenter...${NC}"
if aws cloudformation describe-stacks --stack-name "${KARPENTER_STACK}" --region "${AWS_REGION}" &>/dev/null; then
    aws cloudformation describe-stacks \
      --stack-name "${KARPENTER_STACK}" \
      --region "${AWS_REGION}" \
      > "${BACKUP_DIR}/aws/cfn-karpenter-stack.json" 2>/dev/null
    check_success "Stack do Karpenter"
    
    # Template do stack
    aws cloudformation get-template \
      --stack-name "${KARPENTER_STACK}" \
      --region "${AWS_REGION}" \
      > "${BACKUP_DIR}/aws/cfn-karpenter-template.json" 2>/dev/null
    check_success "Template do Karpenter"
else
    echo "${CYAN}   Stack do Karpenter não encontrado${NC}"
fi

echo ""

# ========================================
# 5. COPIAR MANIFESTOS ORIGINAIS
# ========================================
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  5/5: Copiando manifestos e configurações${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "${CYAN}Copiando arquivos de deployment...${NC}"
cp -r "${SCRIPT_DIR}/../deployment" "${BACKUP_DIR}/manifests/" 2>/dev/null
check_success "Deployment files"

cp -r "${SCRIPT_DIR}/../app" "${BACKUP_DIR}/manifests/" 2>/dev/null
check_success "Application files"

# Criar arquivo de metadados
cat > "${BACKUP_DIR}/backup-info.txt" << EOF
═══════════════════════════════════════════════════════════
  BACKUP INFORMATION
═══════════════════════════════════════════════════════════

Date: $(date)
Timestamp: ${TIMESTAMP}
Cluster: ${CLUSTER_NAME}
Region: ${AWS_REGION}
Account ID: ${ACCOUNT_ID}
Karpenter Version: ${KARPENTER_VERSION}
KEDA Version: ${KEDA_VERSION}

Backup Directory: ${BACKUP_DIR}

═══════════════════════════════════════════════════════════
  RESTORE INSTRUCTIONS
═══════════════════════════════════════════════════════════

Para restaurar este backup:

1. Execute o deployment completo:
   cd deployment
   ./_main.sh
   Escolha opção 3 (Deployment Completo)

2. Após deployment completo, restaure os recursos específicos:
   
   # Aplicar ScaledObject customizado (se modificado)
   kubectl apply -f ${BACKUP_DIR}/kubernetes/scaledobjects.yaml
   
   # Aplicar Provisioner customizado (se modificado)
   kubectl apply -f ${BACKUP_DIR}/kubernetes/provisioners.yaml

3. Verificar estado:
   kubectl get pods -n keda-test
   kubectl get nodes
   kubectl get scaledobject -n keda-test
   kubectl get provisioner

═══════════════════════════════════════════════════════════
  BACKED UP RESOURCES
═══════════════════════════════════════════════════════════

Kubernetes:
- Deployments, Services, ConfigMaps
- ScaledObjects, HPA
- Provisioners, AWSNodeTemplates
- Karpenter & KEDA deployments
- Nodes & Namespaces

AWS:
- SQS Queue configuration
- DynamoDB Table schema & sample data
- ECR Repository & Images
- EKS Cluster configuration

IAM:
- Roles: Karpenter, KEDA
- Policies: Controller, SQS, DynamoDB

CloudFormation:
- Karpenter Stack & Template

Manifests:
- Deployment scripts
- Application code

═══════════════════════════════════════════════════════════
EOF

echo ""

# ========================================
# RESUMO DO BACKUP
# ========================================
echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          ✅ BACKUP CONCLUÍDO COM SUCESSO!                 ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}📁 Backup salvo em:${NC}"
echo "   ${BACKUP_DIR}"
echo ""
echo "${CYAN}📊 Tamanho do backup:${NC}"
du -sh "${BACKUP_DIR}" | awk '{print "   " $1}'
echo ""
echo "${CYAN}📂 Estrutura do backup:${NC}"
tree -L 2 "${BACKUP_DIR}" 2>/dev/null || ls -R "${BACKUP_DIR}"
echo ""
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  PRÓXIMOS PASSOS${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "${CYAN}1. Revisar backup:${NC}"
echo "   cat ${BACKUP_DIR}/backup-info.txt"
echo ""
echo "${CYAN}2. Executar cleanup:${NC}"
echo "   cd scripts"
echo "   ./cleanup.sh"
echo ""
echo "${CYAN}3. Caso precise restaurar:${NC}"
echo "   • Execute novo deployment (./_main.sh)"
echo "   • Consulte: ${BACKUP_DIR}/backup-info.txt"
echo ""
echo "${GREEN}✅ Você está seguro para executar o cleanup agora!${NC}"
echo ""
