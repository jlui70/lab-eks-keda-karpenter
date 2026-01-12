# 📁 Estrutura do Projeto

Este documento descreve a organização dos diretórios e arquivos do projeto EKS KEDA Karpenter v2.

## 🗂️ Estrutura de Diretórios

```
eks-keda-karpenter-v2/
│
├── README.md                      # Documentação principal do projeto
├── check-prerequisites.sh         # Script de verificação de pré-requisitos
├── .gitignore                     # Arquivos ignorados pelo Git
│
├── app/                           # Aplicação Python de teste
│   └── keda/
│       ├── Dockerfile             # Container da aplicação
│       ├── keda-mock-sqs-post.py  # Script de carga (envia mensagens)
│       ├── sqs-reader.py          # Worker que processa mensagens
│       └── requirements.txt       # Dependências Python
│
├── deployment/                    # Scripts de instalação
│   ├── _main.sh                   # ⭐ Script principal de deployment
│   ├── environmentVariables.sh    # Variáveis de configuração
│   │
│   ├── cluster/
│   │   └── createCluster.sh       # Criação do cluster EKS
│   │
│   ├── karpenter/
│   │   ├── cloudformation.yaml    # Stack de infraestrutura Karpenter
│   │   └── createkarpenter.sh     # Instalação do Karpenter
│   │
│   ├── keda/
│   │   ├── createkeda.sh          # Instalação do KEDA
│   │   ├── dynamoPolicy.json      # Policy IAM para DynamoDB
│   │   └── sqsPolicy.json         # Policy IAM para SQS
│   │
│   └── app/
│       ├── keda-python-app.yaml   # Deployment da aplicação
│       └── scaledobject.yaml      # ScaledObject (referência)
│
├── monitoring/                    # Stack de observabilidade
│   ├── install-monitoring.sh      # Instalação Prometheus + Grafana
│   ├── install-complete-monitoring.sh  # Instalação completa automatizada
│   ├── setup-keda-metrics.sh      # ServiceMonitors para KEDA
│   ├── import-dashboards.sh       # Importação de dashboards
│   ├── grafana-dashboard-eks-ecommerce.json
│   ├── grafana-dashboard-sqs-payments.json
│   └── README.md                  # Documentação do monitoring
│
├── scripts/                       # Utilitários
│   └── cleanup.sh                 # ⭐ Limpeza completa de recursos
│
└── tests/                         # Scripts de teste
    ├── run-load-test.sh           # Teste de carga (500 mensagens)
    └── force-scale-down.sh        # Reset emergencial de HPA
```

## 📋 Descrição dos Componentes

### 🎯 Scripts Principais

| Script | Descrição | Uso |
|--------|-----------|-----|
| `deployment/_main.sh` | Script principal de instalação completa | `./deployment/_main.sh` |
| `scripts/cleanup.sh` | Remove todos os recursos AWS criados | `./scripts/cleanup.sh` |
| `tests/run-load-test.sh` | Envia 500 mensagens para testar autoscaling | `./tests/run-load-test.sh` |

### 🛠️ Diretório `deployment/`

**Scripts de instalação modular:**

- **`_main.sh`**: Orquestra toda a instalação
  - Menu interativo
  - Valida pré-requisitos
  - Executa scripts na ordem correta
  - Validação pós-instalação

- **`environmentVariables.sh`**: Configuração centralizada
  - Nome do cluster
  - Região AWS
  - Versões (Karpenter, KEDA)
  - URLs de recursos (SQS, DynamoDB)

- **`cluster/createCluster.sh`**: EKS cluster
  - Cria VPC e subnets
  - Configura node groups gerenciados
  - Adiciona EBS CSI Driver

- **`karpenter/createkarpenter.sh`**: Karpenter setup
  - Stack CloudFormation (roles, policies)
  - Instalação via Helm
  - NodePool e EC2NodeClass

- **`keda/createkeda.sh`**: KEDA setup
  - Instalação via Helm
  - ServiceAccount com IRSA
  - Policies SQS e DynamoDB
  - ScaledObject automático

- **`app/`**: Deploy da aplicação
  - Deployment Kubernetes
  - Container registry no Docker Hub

### 📊 Diretório `monitoring/`

**Stack de observabilidade completa:**

- **Prometheus**: Coleta de métricas
- **Grafana**: Visualização e dashboards
- **ServiceMonitors**: Métricas do KEDA
- **Dashboards pré-configurados**:
  - SQS Payments (fila, processamento)
  - EKS E-commerce (pods, nodes, HPA)

### 🧪 Diretório `tests/`

**Scripts de validação:**

- **`run-load-test.sh`**: Teste de carga
  - Envia 500 mensagens SQS FIFO
  - Valida autoscaling (1 → 50 pods)
  - Monitora processamento

- **`force-scale-down.sh`**: Emergência
  - Purga fila SQS
  - Reseta HPA se travado
  - Garante scale-down em 15s

### 🐍 Diretório `app/keda/`

**Aplicação Python de demonstração:**

- **`sqs-reader.py`**: Worker
  - Processa mensagens da fila
  - Salva no DynamoDB
  - Simula processamento (3-7s)

- **`keda-mock-sqs-post.py`**: Load generator
  - Envia mensagens de teste
  - Modo contínuo ou batch
  - Schema completo (id, timestamp, etc)

- **`Dockerfile`**: Container
  - Python 3.11-slim
  - Boto3 para AWS SDK
  - Healthcheck incluído

## 🔐 Arquivos Ignorados (.gitignore)

**Não são versionados:**

- `docs/` - Documentação de desenvolvimento local
- `backups/` - Backups de manifestos K8s
- `app/keda/venv/` - Virtual environment Python
- Arquivos temporários (*.log, *.tmp)
- Credenciais AWS (nunca comitar!)
- Cache de IDEs (.vscode/, .idea/)

## 📝 Arquivos de Configuração

### `deployment/environmentVariables.sh`

**Variáveis principais:**

```bash
CLUSTER_NAME="eks-demo-scale-v2"
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

KARPENTER_VERSION="1.0.1"
KEDA_VERSION="2.15.1"

SQS_QUEUE_NAME="keda-demo-queue.fifo"
DYNAMODB_TABLE="payments"
```

**Todas as variáveis têm valores padrão funcionais!**

## 🚀 Fluxo de Instalação

```
1. check-prerequisites.sh
   ↓ (verifica AWS CLI, kubectl, eksctl, helm)
   
2. deployment/_main.sh
   ↓
   ├─> deployment/cluster/createCluster.sh
   │   ↓ (15-20 min)
   │   └─> EKS Cluster + VPC + Node Groups
   │
   ├─> deployment/karpenter/createkarpenter.sh
   │   ↓ (3-5 min)
   │   └─> Karpenter + NodePool + EC2NodeClass
   │
   ├─> deployment/keda/createkeda.sh
   │   ↓ (2-3 min)
   │   └─> KEDA + ScaledObject + IRSA
   │
   └─> deployment/app/keda-python-app.yaml
       ↓ (1-2 min)
       └─> Application Deployment (1 pod inicial)

3. monitoring/install-complete-monitoring.sh (OPCIONAL)
   ↓ (5-7 min)
   └─> Prometheus + Grafana + Dashboards

4. tests/run-load-test.sh
   ↓ (5-10 min)
   └─> 500 mensagens → 50 pods → 9 nodes
```

## 🧹 Limpeza de Recursos

```
scripts/cleanup.sh
│
├─> Delete KEDA resources
├─> Delete Application
├─> Delete Karpenter resources
├─> Delete EKS Cluster
├─> Delete Security Groups (órfãos)
├─> Delete CloudFormation Stack
└─> Delete SQS Queue + DynamoDB Table

⏱️ Tempo: ~10-15 minutos
```

## 📊 Tamanho dos Componentes

```
check-prerequisites.sh:    8 KB
README.md:                16 KB
tests/:                   16 KB
scripts/:                 64 KB
monitoring/:              80 KB
deployment/:             124 KB
app/:                     46 MB (por causa do venv/ - ignorado no Git)
```

**Tamanho do repositório (sem venv/docs/backups):** ~300 KB

## 🎯 Próximos Passos

1. **Clone o repositório**
2. **Execute check-prerequisites.sh**
3. **Execute deployment/_main.sh** (opção 3)
4. **(Opcional) Execute monitoring/install-complete-monitoring.sh**
5. **Execute tests/run-load-test.sh**
6. **Acesse Grafana e monitore autoscaling**
7. **Execute scripts/cleanup.sh** quando terminar

---

**Versão do Projeto:** 2.0  
**Última Atualização:** Janeiro 2026  
**Kubernetes:** 1.31  
**Karpenter:** 1.0.1  
**KEDA:** 2.15.1
