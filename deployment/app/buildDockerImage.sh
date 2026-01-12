#!/bin/bash
#*************************
# Build and Push Docker Image to ECR
#*************************

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Importar variáveis de ambiente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../environmentVariables.sh"

# Variáveis
ECR_REPOSITORY_NAME="keda-sqs-reader"
IMAGE_TAG="latest"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
APP_DIR="${SCRIPT_DIR}/../../app/keda"

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║         BUILD & PUSH DOCKER IMAGE TO ECR                 ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Passo 1: Verificar se Docker está instalado
echo "${YELLOW}🔍 Verificando Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo "${RED}❌ Docker não está instalado!${NC}"
    echo "   Instale: https://docs.docker.com/engine/install/"
    exit 1
fi
echo "${GREEN}✅ Docker instalado${NC}"
echo ""

# Passo 2: Criar ECR Repository (se não existir)
echo "${YELLOW}📦 Criando ECR Repository (se não existir)...${NC}"
aws ecr describe-repositories \
  --repository-names "${ECR_REPOSITORY_NAME}" \
  --region "${AWS_REGION}" &> /dev/null

if [ $? -ne 0 ]; then
    echo "   Repository não existe, criando..."
    aws ecr create-repository \
      --repository-name "${ECR_REPOSITORY_NAME}" \
      --region "${AWS_REGION}" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 > /dev/null
    
    if [ $? -eq 0 ]; then
        echo "${GREEN}✅ ECR Repository criado: ${ECR_REPOSITORY_NAME}${NC}"
    else
        echo "${RED}❌ Falha ao criar ECR Repository${NC}"
        exit 1
    fi
else
    echo "${CYAN}   Repository já existe${NC}"
    echo "${GREEN}✅ ECR Repository verificado${NC}"
fi
echo ""

# Passo 3: Login no ECR
echo "${YELLOW}🔐 Fazendo login no ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "${GREEN}✅ Login no ECR realizado${NC}"
else
    echo "${RED}❌ Falha no login do ECR${NC}"
    exit 1
fi
echo ""

# Passo 4: Build da imagem Docker
echo "${YELLOW}🔨 Fazendo build da imagem Docker...${NC}"
echo "   Dockerfile: ${APP_DIR}/Dockerfile"
echo "   Image: ${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
echo ""

cd "${APP_DIR}"
docker build -t "${ECR_REPOSITORY_NAME}:${IMAGE_TAG}" . 2>&1 | grep -E "Step|Successfully|ERROR"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "${GREEN}✅ Build concluído${NC}"
else
    echo ""
    echo "${RED}❌ Falha no build da imagem${NC}"
    exit 1
fi
echo ""

# Passo 5: Tag da imagem
echo "${YELLOW}🏷️  Criando tag da imagem...${NC}"
docker tag "${ECR_REPOSITORY_NAME}:${IMAGE_TAG}" "${ECR_URI}"
echo "${GREEN}✅ Tag criada: ${ECR_URI}${NC}"
echo ""

# Passo 6: Push da imagem para ECR
echo "${YELLOW}📤 Fazendo push para ECR...${NC}"
echo "   Isso pode levar alguns minutos..."
echo ""

docker push "${ECR_URI}" 2>&1 | grep -E "Pushing|Pushed|digest|ERROR"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "${GREEN}✅ Push concluído${NC}"
else
    echo ""
    echo "${RED}❌ Falha no push da imagem${NC}"
    exit 1
fi
echo ""

# Passo 7: Verificar imagem no ECR
echo "${YELLOW}🔍 Verificando imagem no ECR...${NC}"
IMAGE_DIGEST=$(aws ecr describe-images \
  --repository-name "${ECR_REPOSITORY_NAME}" \
  --region "${AWS_REGION}" \
  --query 'imageDetails[?imageTags[?contains(@, `latest`)]] | [0].imagePushDate' \
  --output text)

if [ -n "${IMAGE_DIGEST}" ]; then
    echo "${GREEN}✅ Imagem disponível no ECR${NC}"
    echo "   URI: ${ECR_URI}"
    echo "   Push date: ${IMAGE_DIGEST}"
else
    echo "${RED}❌ Imagem não encontrada no ECR${NC}"
    exit 1
fi
echo ""

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          ✅ BUILD & PUSH CONCLUÍDO COM SUCESSO!           ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
