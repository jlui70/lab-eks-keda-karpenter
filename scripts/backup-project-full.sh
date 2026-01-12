#!/bin/bash
#*************************
# Full Project Backup - Cria ZIP do projeto completo
# Salva em local externo para proteção contra deleção acidental
#*************************

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurações
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PROJECT_DIR="/home/luiz7/labs/eks-keda-karpenter-v2"
PROJECT_NAME="eks-keda-karpenter-v2"
BACKUP_BASE_DIR="$HOME/project-backups"
BACKUP_FILENAME="${PROJECT_NAME}_backup_${TIMESTAMP}.tar.gz"
BACKUP_PATH="${BACKUP_BASE_DIR}/${BACKUP_FILENAME}"

echo ""
echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║         BACKUP COMPLETO DO PROJETO                       ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Criar diretório de backups se não existir
mkdir -p "${BACKUP_BASE_DIR}"

echo "${CYAN}📁 Projeto: ${PROJECT_NAME}${NC}"
echo "${CYAN}📂 Origem: ${PROJECT_DIR}${NC}"
echo "${CYAN}💾 Destino: ${BACKUP_PATH}${NC}"
echo ""

# Verificar se projeto existe
if [ ! -d "${PROJECT_DIR}" ]; then
    echo "${RED}❌ Erro: Diretório do projeto não encontrado!${NC}"
    echo "   ${PROJECT_DIR}"
    exit 1
fi

# Ir para o diretório pai do projeto
cd "$(dirname "${PROJECT_DIR}")" || exit 1

echo "${YELLOW}📦 Criando arquivo compactado...${NC}"
echo "${CYAN}   Isso pode levar alguns minutos...${NC}"
echo ""

# Criar tar.gz excluindo arquivos desnecessários
tar -czf "${BACKUP_PATH}" \
  --exclude='node_modules' \
  --exclude='.git' \
  --exclude='*.pyc' \
  --exclude='__pycache__' \
  --exclude='.DS_Store' \
  --exclude='*.log' \
  --exclude='.vscode' \
  --exclude='.idea' \
  "${PROJECT_NAME}" 2>&1 | grep -v "Removing leading"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "${GREEN}✅ Backup criado com sucesso!${NC}"
else
    echo "${RED}❌ Erro ao criar backup!${NC}"
    exit 1
fi

echo ""
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  INFORMAÇÕES DO BACKUP${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Informações do arquivo
BACKUP_SIZE=$(du -h "${BACKUP_PATH}" | awk '{print $1}')
BACKUP_SIZE_BYTES=$(stat -c%s "${BACKUP_PATH}" 2>/dev/null || stat -f%z "${BACKUP_PATH}" 2>/dev/null)

echo "${CYAN}📦 Arquivo: ${BACKUP_FILENAME}${NC}"
echo "${CYAN}📊 Tamanho: ${BACKUP_SIZE}${NC}"
echo "${CYAN}📁 Localização: ${BACKUP_PATH}${NC}"
echo ""

# Listar conteúdo do backup (primeiros níveis)
echo "${CYAN}📂 Conteúdo do backup:${NC}"
tar -tzf "${BACKUP_PATH}" | head -30
if [ $(tar -tzf "${BACKUP_PATH}" | wc -l) -gt 30 ]; then
    echo "${CYAN}   ... e mais $(( $(tar -tzf "${BACKUP_PATH}" | wc -l) - 30 )) arquivos${NC}"
fi
echo ""

# Criar arquivo de metadados
METADATA_FILE="${BACKUP_BASE_DIR}/${PROJECT_NAME}_backup_${TIMESTAMP}_info.txt"
cat > "${METADATA_FILE}" << EOF
═══════════════════════════════════════════════════════════
  BACKUP COMPLETO DO PROJETO
═══════════════════════════════════════════════════════════

Data do Backup: $(date)
Timestamp: ${TIMESTAMP}
Hostname: $(hostname)
User: $(whoami)

Projeto: ${PROJECT_NAME}
Diretório Original: ${PROJECT_DIR}

Arquivo Backup: ${BACKUP_FILENAME}
Localização: ${BACKUP_PATH}
Tamanho: ${BACKUP_SIZE} (${BACKUP_SIZE_BYTES} bytes)

═══════════════════════════════════════════════════════════
  INSTRUÇÕES DE RESTAURAÇÃO
═══════════════════════════════════════════════════════════

1. Para restaurar o projeto completo:

   cd /home/luiz7/labs
   tar -xzf ${BACKUP_PATH}
   cd ${PROJECT_NAME}

2. Para restaurar em outro local:

   mkdir -p /caminho/desejado
   cd /caminho/desejado
   tar -xzf ${BACKUP_PATH}

3. Para visualizar conteúdo sem extrair:

   tar -tzf ${BACKUP_PATH} | less

4. Para extrair apenas um arquivo específico:

   tar -xzf ${BACKUP_PATH} ${PROJECT_NAME}/deployment/_main.sh

═══════════════════════════════════════════════════════════
  VERIFICAÇÃO DE INTEGRIDADE
═══════════════════════════════════════════════════════════

MD5 Checksum:
$(md5sum "${BACKUP_PATH}" 2>/dev/null || md5 "${BACKUP_PATH}" 2>/dev/null)

SHA256 Checksum:
$(sha256sum "${BACKUP_PATH}" 2>/dev/null || shasum -a 256 "${BACKUP_PATH}" 2>/dev/null)

Para verificar integridade após transferência:
  md5sum -c <(echo "$(md5sum "${BACKUP_PATH}" | awk '{print $1}')  nome_do_arquivo")

═══════════════════════════════════════════════════════════
  CONTEÚDO DO BACKUP
═══════════════════════════════════════════════════════════

Total de arquivos: $(tar -tzf "${BACKUP_PATH}" | wc -l)

Estrutura principal:
$(tar -tzf "${BACKUP_PATH}" | head -50)

═══════════════════════════════════════════════════════════
EOF

echo "${GREEN}✅ Arquivo de metadados criado: ${METADATA_FILE}${NC}"
echo ""

# Listar backups anteriores
PREVIOUS_BACKUPS=$(ls -1 "${BACKUP_BASE_DIR}"/${PROJECT_NAME}_backup_*.tar.gz 2>/dev/null | wc -l)
if [ ${PREVIOUS_BACKUPS} -gt 1 ]; then
    echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo "${YELLOW}  BACKUPS ANTERIORES ENCONTRADOS${NC}"
    echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "${CYAN}Total de backups: ${PREVIOUS_BACKUPS}${NC}"
    echo ""
    ls -lht "${BACKUP_BASE_DIR}"/${PROJECT_NAME}_backup_*.tar.gz | head -5 | while read line; do
        echo "   $line"
    done
    echo ""
    
    # Calcular espaço total usado
    TOTAL_SIZE=$(du -sh "${BACKUP_BASE_DIR}" | awk '{print $1}')
    echo "${CYAN}📊 Espaço total usado por backups: ${TOTAL_SIZE}${NC}"
    echo ""
    echo "${YELLOW}💡 Para limpar backups antigos:${NC}"
    echo "   cd ${BACKUP_BASE_DIR}"
    echo "   ls -lt ${PROJECT_NAME}_backup_*.tar.gz  # Ver backups"
    echo "   rm ${PROJECT_NAME}_backup_YYYYMMDD_*.tar.gz  # Remover específico"
    echo ""
fi

echo "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║          ✅ BACKUP COMPLETO FINALIZADO!                   ║${NC}"
echo "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${CYAN}🔐 Seu projeto está seguro em:${NC}"
echo "   ${BACKUP_PATH}"
echo ""
echo "${CYAN}📄 Instruções de restauração em:${NC}"
echo "   ${METADATA_FILE}"
echo ""
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}  COMANDOS RÁPIDOS${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "${CYAN}• Ver conteúdo do backup:${NC}"
echo "  tar -tzf ${BACKUP_PATH} | less"
echo ""
echo "${CYAN}• Restaurar projeto:${NC}"
echo "  cd /home/luiz7/labs && tar -xzf ${BACKUP_PATH}"
echo ""
echo "${CYAN}• Copiar backup para USB/Externo:${NC}"
echo "  cp ${BACKUP_PATH} /media/usb/"
echo ""
echo "${CYAN}• Transferir para outro servidor:${NC}"
echo "  scp ${BACKUP_PATH} user@server:/backup/"
echo ""
echo "${GREEN}✅ Agora você pode executar o cleanup com total segurança!${NC}"
echo ""
