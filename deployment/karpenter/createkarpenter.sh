#!/bin/bash
#*************************
# Deploy Karpenter v1.0+ (API v1)
# Usa NodePool e EC2NodeClass (não mais Provisioner)
#*************************

set -e  # Exit on error

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║              INSTALANDO KARPENTER v1.0+                    ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Determinar caminho correto para environmentVariables.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../environmentVariables.sh" ]; then
    source "${SCRIPT_DIR}/../environmentVariables.sh"
elif [ -f "${SCRIPT_DIR}/environmentVariables.sh" ]; then
    source "${SCRIPT_DIR}/environmentVariables.sh"
elif [ -f "./environmentVariables.sh" ]; then
    source ./environmentVariables.sh
else
    echo "${RED}❌ Erro: environmentVariables.sh não encontrado!${NC}"
    exit 1
fi

# Validar variáveis
if [ -z "$CLUSTER_NAME" ] || [ -z "$KARPENTER_VERSION" ] || [ -z "$AWS_REGION" ] || [ -z "$ACCOUNT_ID" ]; then
    echo "${RED}❌ Erro: Variáveis obrigatórias não definidas!${NC}"
    exit 1
fi

echo "${CYAN}📋 Configuração:${NC}"
echo "   • Cluster: ${CLUSTER_NAME}"
echo "   • Versão: ${KARPENTER_VERSION}"
echo "   • Região: ${AWS_REGION}"
echo "   • Account: ${ACCOUNT_ID}"
echo ""

# Verificar se cluster está acessível
echo "${YELLOW}🔍 Verificando cluster...${NC}"
if ! kubectl cluster-info &>/dev/null; then
    echo "${RED}❌ Não foi possível conectar ao cluster!${NC}"
    echo "Execute: aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
    exit 1
fi
echo "${GREEN}✅ Cluster acessível${NC}"
echo ""

# Passo 1: Criar KarpenterNode IAM Role
echo "${YELLOW}📝 Passo 1/7: Criando KarpenterNode IAM Role...${NC}"

STACK_NAME="Karpenter-${CLUSTER_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usar CloudFormation template local
CF_TEMPLATE="${SCRIPT_DIR}/cloudformation.yaml"

if [ ! -f "${CF_TEMPLATE}" ]; then
    echo "${RED}❌ Arquivo cloudformation.yaml não encontrado!${NC}"
    exit 1
fi

# Deploy CloudFormation
aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${CF_TEMPLATE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
  --region ${AWS_REGION} || echo "${BLUE}Stack já existe, continuando...${NC}"

echo "${GREEN}✅ IAM Role para nodes criada${NC}"
echo ""

# Passo 2: Grant access to nodes
echo "${YELLOW}📝 Passo 2/7: Configurando aws-auth ConfigMap...${NC}"

# Verificar se identity mapping já existe
EXISTING_MAPPING=$(eksctl get iamidentitymapping --cluster ${CLUSTER_NAME} --region ${AWS_REGION} 2>/dev/null | grep "KarpenterNodeRole-${CLUSTER_NAME}" || true)

if [ -z "$EXISTING_MAPPING" ]; then
    eksctl create iamidentitymapping \
      --username system:node:{{EC2PrivateDNSName}} \
      --cluster ${CLUSTER_NAME} \
      --region ${AWS_REGION} \
      --arn "arn:aws:iam::${ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
      --group system:bootstrappers \
      --group system:nodes
    echo "${GREEN}✅ IAM identity mapping criado${NC}"
else
    echo "${BLUE}ℹ️  IAM identity mapping já existe${NC}"
fi

echo ""

# Passo 3: Associate OIDC Provider
echo "${YELLOW}📝 Passo 3/7: Associando OIDC Provider...${NC}"
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --region ${AWS_REGION} --approve || echo "${BLUE}OIDC já associado${NC}"
echo "${GREEN}✅ OIDC Provider configurado${NC}"
echo ""

# Passo 4: Criar Karpenter Controller IAM Role
echo "${YELLOW}📝 Passo 4/7: Criando Karpenter Controller IAM Role...${NC}"

# Criar namespace karpenter
kubectl create namespace ${KARPENTER_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Verificar se já existe
if aws iam get-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --region ${AWS_REGION} &>/dev/null; then
    echo "${BLUE}ℹ️  Role já existe, deletando para recriar...${NC}"
    
    # Detach policies primeiro
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy in $ATTACHED_POLICIES; do
        aws iam detach-role-policy --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --policy-arn $policy
    done
    
    # Delete service account annotation se existir
    kubectl delete serviceaccount karpenter -n ${KARPENTER_NAMESPACE} --ignore-not-found=true
    
    # Delete role
    aws iam delete-role --role-name "KarpenterControllerRole-${CLUSTER_NAME}" --region ${AWS_REGION} || true
fi

# Obter OIDC Provider
OIDC_PROVIDER=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

# Criar Trust Policy para a Role
cat > /tmp/karpenter-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${KARPENTER_NAMESPACE}:karpenter"
        }
      }
    }
  ]
}
EOF

# Criar IAM Role
echo "${CYAN}   Criando IAM Role manualmente (sem eksctl)...${NC}"
aws iam create-role \
  --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/karpenter-trust-policy.json \
  --region "${AWS_REGION}"

# Anexar policy
aws iam attach-role-policy \
  --role-name "KarpenterControllerRole-${CLUSTER_NAME}" \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
  --region "${AWS_REGION}"

export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}"

# Limpar arquivo temporário
rm -f /tmp/karpenter-trust-policy.json

echo "${GREEN}✅ Controller IAM Role criado: ${KARPENTER_IAM_ROLE_ARN}${NC}"
echo "${CYAN}   ⚠️  ServiceAccount será criado pelo Helm (não pelo eksctl)${NC}"
echo ""

# Passo 5: Criar Instance Profile
echo "${YELLOW}📝 Passo 5/7: Criando Instance Profile...${NC}"

if ! aws iam get-instance-profile --instance-profile-name "${KARPENTER_INSTANCE_PROFILE}" --region ${AWS_REGION} &>/dev/null; then
    aws iam create-instance-profile --instance-profile-name "${KARPENTER_INSTANCE_PROFILE}" --region ${AWS_REGION}
    aws iam add-role-to-instance-profile \
        --instance-profile-name "${KARPENTER_INSTANCE_PROFILE}" \
        --role-name "KarpenterNodeRole-${CLUSTER_NAME}" \
        --region ${AWS_REGION}
    echo "${GREEN}✅ Instance Profile criado${NC}"
else
    echo "${BLUE}ℹ️  Instance Profile já existe${NC}"
fi

echo ""

# Passo 6: Criar EC2 Spot Service-Linked Role
echo "${YELLOW}📝 Passo 6/7: Criando EC2 Spot Service-Linked Role...${NC}"
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com --region ${AWS_REGION} 2>/dev/null || echo "${BLUE}ℹ️  Spot role já existe${NC}"
echo ""

# Passo 7: Install Karpenter via Helm
echo "${YELLOW}📝 Passo 7/7: Instalando Karpenter via Helm...${NC}"

export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.endpoint" --output text)"

# Logout docker registry
docker logout public.ecr.aws 2>/dev/null || true

# Para Karpenter v1.0+, usar repositório OCI (não mais charts.karpenter.sh)
echo "${CYAN}📦 Karpenter ${KARPENTER_VERSION} usa repositório OCI (public.ecr.aws)${NC}"

echo "${CYAN}🚀 Instalando Karpenter ${KARPENTER_VERSION}...${NC}"

# Instalar/Atualizar Karpenter via OCI
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace ${KARPENTER_NAMESPACE} \
  --create-namespace \
  --version "${KARPENTER_VERSION}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait

echo "${GREEN}✅ Karpenter Helm chart instalado${NC}"
echo ""

# Aguardar pods estarem prontos
echo "${YELLOW}⏳ Aguardando pods do Karpenter ficarem prontos...${NC}"
kubectl rollout status deployment/karpenter -n ${KARPENTER_NAMESPACE} --timeout=300s

echo ""
echo "${GREEN}✅ Karpenter pods estão rodando!${NC}"
kubectl get pods -n ${KARPENTER_NAMESPACE}
echo ""

# Passo 8: Criar Provisioner e AWSNodeTemplate (API v1alpha5)
echo "${YELLOW}📝 Criando Provisioner e AWSNodeTemplate (API v1alpha5)...${NC}"
echo ""

# Obter Subnet IDs
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=tag:karpenter.sh/discovery,Values=${CLUSTER_NAME}" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region ${AWS_REGION})

if [ -z "$SUBNET_IDS" ]; then
    echo "${RED}❌ Erro: Nenhuma subnet encontrada com tag karpenter.sh/discovery=${CLUSTER_NAME}${NC}"
    exit 1
fi

echo "${CYAN}✅ Subnets encontradas: ${SUBNET_IDS}${NC}"

# Obter Security Group
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

echo "${CYAN}✅ Security Group: ${CLUSTER_SG}${NC}"
echo ""

# Criar EC2NodeClass (substitui AWSNodeTemplate na API v1)
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest  # Amazon Linux 2023 - AMI automática
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  tags:
    karpenter.sh/discovery: "${CLUSTER_NAME}"
    Name: "karpenter-node"
    Environment: "production"
    ManagedBy: "Karpenter"
  userData: |
    #!/bin/bash
    echo "EKS_CLUSTER_NAME=${CLUSTER_NAME}" >> /etc/environment
EOF

echo "${GREEN}✅ EC2NodeClass criado (API v1)${NC}"
echo ""

# Criar NodePool (substitui Provisioner na API v1)
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: ["m5.large", "m5.xlarge", "m5.2xlarge"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "100"
    memory: "200Gi"
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
    budgets:
      - nodes: "10%"
EOF

echo "${GREEN}✅ NodePool criado (API v1)${NC}"
echo ""

# Verificar recursos
echo "${YELLOW}🔍 Verificando recursos do Karpenter v1.0.1...${NC}"
echo ""
echo "${CYAN}EC2NodeClass:${NC}"
kubectl get ec2nodeclass
echo ""
echo "${CYAN}NodePool:${NC}"
kubectl get nodepool
echo ""

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║        KARPENTER INSTALADO COM SUCESSO!                    ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}📋 Próximos passos:${NC}"
echo "   1. Instalar KEDA: ./deployment/keda/createkeda.sh"
echo "   2. Verificar logs: kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f"
echo ""
