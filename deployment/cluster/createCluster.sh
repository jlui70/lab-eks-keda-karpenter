#!/bin/bash
#*************************
# Create EKS Cluster for Karpenter
# Otimizado para Karpenter v1.0+
#*************************

set -e  # Exit on error

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          CRIANDO CLUSTER EKS PARA KARPENTER               ║${NC}"
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

# Validar variáveis obrigatórias
if [ -z "$CLUSTER_NAME" ] || [ -z "$AWS_REGION" ] || [ -z "$K8S_VERSION" ]; then
    echo "${RED}❌ Erro: Variáveis obrigatórias não definidas!${NC}"
    echo "Execute: source ../environmentVariables.sh"
    exit 1
fi

echo "${CYAN}📋 Configuração do Cluster:${NC}"
echo "   • Nome: ${CLUSTER_NAME}"
echo "   • Região: ${AWS_REGION}"
echo "   • Versão K8s: ${K8S_VERSION}"
echo "   • Account ID: ${ACCOUNT_ID}"
echo ""

# Verificar se cluster já existe
echo "${YELLOW}🔍 Verificando se cluster já existe...${NC}"
CHECK_CLUSTER=$(aws eks list-clusters --region ${AWS_REGION} --query "clusters[?@=='${CLUSTER_NAME}']" --output text)

if [ ! -z "$CHECK_CLUSTER" ]; then
    echo "${BLUE}ℹ️  Cluster '${CLUSTER_NAME}' já existe!${NC}"
    echo ""
    read -p "${YELLOW}Deseja continuar mesmo assim? (y/N): ${NC}" continue_anyway
    if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
        echo "${RED}❌ Operação cancelada pelo usuário${NC}"
        exit 0
    fi
else
    echo "${GREEN}✅ Cluster não existe, prosseguindo com criação...${NC}"
fi

echo ""
echo "${YELLOW}🚀 Criando cluster EKS (isso levará ~20 minutos)...${NC}"
echo ""

# Criar arquivo de configuração do cluster
cat > /tmp/cluster-config-${CLUSTER_NAME}.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${K8S_VERSION}"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
    Environment: demo
    ManagedBy: eksctl

iam:
  withOIDC: true

managedNodeGroups:
  - name: initial-nodegroup
    instanceType: m5.large
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 30
    labels:
      role: initial
      workload: system
    tags:
      k8s.io/cluster-autoscaler/enabled: "false"
      k8s.io/cluster-autoscaler/${CLUSTER_NAME}: "owned"
      NodeGroup: initial
    iam:
      withAddonPolicies:
        autoScaler: false
        ebs: true
        efs: true
        albIngress: false
        cloudWatch: true

vpc:
  clusterEndpoints:
    publicAccess: true
    privateAccess: true
  nat:
    gateway: HighlyAvailable  # 1 NAT Gateway por AZ (produção)

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
EOF

echo "${CYAN}📄 Arquivo de configuração criado: /tmp/cluster-config-${CLUSTER_NAME}.yaml${NC}"
echo ""

# Criar cluster
eksctl create cluster -f /tmp/cluster-config-${CLUSTER_NAME}.yaml

# Verificar se criação foi bem sucedida
if [ $? -eq 0 ]; then
    echo ""
    echo "${GREEN}✅ Cluster criado com sucesso!${NC}"
    echo ""
    
    # Atualizar kubeconfig
    echo "${YELLOW}🔧 Atualizando kubeconfig...${NC}"
    aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}
    
    # Verificar conectividade
    echo ""
    echo "${YELLOW}🔍 Verificando conectividade...${NC}"
    kubectl get nodes
    
    echo ""
    echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║           CLUSTER EKS CRIADO COM SUCESSO!                 ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "${CYAN}📋 Próximos passos:${NC}"
    echo "   1. Instalar Karpenter: ./deployment/karpenter/createkarpenter.sh"
    echo "   2. Instalar KEDA: ./deployment/keda/createkeda.sh"
    echo ""
else
    echo ""
    echo "${RED}❌ Erro ao criar cluster!${NC}"
    echo "${YELLOW}Verifique os logs acima para mais detalhes${NC}"
    exit 1
fi

# Adicionar tags específicas para Karpenter discovery
echo "${YELLOW}🏷️  Adicionando tags para Karpenter discovery...${NC}"

# Obter VPC ID
VPC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
    --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Obter Subnet IDs (privadas)
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:aws:cloudformation:logical-id,Values=SubnetPrivate*" \
    --query "Subnets[*].SubnetId" --output text --region ${AWS_REGION})

# Tagear subnets
for subnet in $SUBNET_IDS; do
    echo "${CYAN}   • Tagging subnet: ${subnet}${NC}"
    aws ec2 create-tags --resources $subnet --tags \
        Key=karpenter.sh/discovery,Value=${CLUSTER_NAME} \
        --region ${AWS_REGION}
done

# Obter Security Group do Cluster
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

echo "${CYAN}   • Tagging security group: ${CLUSTER_SG}${NC}"
aws ec2 create-tags --resources ${CLUSTER_SG} --tags \
    Key=karpenter.sh/discovery,Value=${CLUSTER_NAME} \
    --region ${AWS_REGION}

echo ""
echo "${GREEN}✅ Tags adicionadas com sucesso!${NC}"
echo ""
# =============================================================================
# INSTALAR EBS CSI DRIVER (necessário para PersistentVolumes)
# =============================================================================
echo "${YELLOW}📦 Instalando AWS EBS CSI Driver...${NC}"
echo ""

# Criar IAM service account para EBS CSI Driver
echo "${CYAN}   • Criando IAM service account para EBS CSI Driver...${NC}"
eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster ${CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --role-name ${CLUSTER_NAME}-ebs-csi-driver-role \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve \
    --override-existing-serviceaccounts

# Instalar EBS CSI Driver addon
echo "${CYAN}   • Instalando EBS CSI Driver addon...${NC}"
eksctl create addon \
    --name aws-ebs-csi-driver \
    --cluster ${CLUSTER_NAME} \
    --region ${AWS_REGION} \
    --service-account-role-arn arn:aws:iam::${ACCOUNT_ID}:role/${CLUSTER_NAME}-ebs-csi-driver-role \
    --force

# Aguardar addon ficar ativo
echo "${CYAN}   • Aguardando addon ficar ativo (30s)...${NC}"
sleep 30

# Verificar instalação
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

echo ""
echo "${GREEN}✅ EBS CSI Driver instalado com sucesso!${NC}"
echo ""