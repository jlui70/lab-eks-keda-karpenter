# 📊 Monitoramento - Adição ao Lab v2

## ✅ O QUE FOI ADICIONADO

Data: 09/01/2026

### 📁 Estrutura Criada

```
monitoring/
├── README.md (283 linhas)                     → Documentação completa
├── install-monitoring.sh (98 linhas)          → Script instalação
├── setup-keda-metrics.sh (124 linhas)         → Configurar métricas
├── import-dashboards.sh (98 linhas)           → Importar dashboards
├── grafana-dashboard-sqs-payments.json        → Dashboard SQS (717 linhas)
└── grafana-dashboard-eks-ecommerce.json       → Dashboard HTTP (587 linhas)
```

**Total:** 6 arquivos | 1907 linhas

---

## 🎨 Dashboards Grafana

### 1️⃣ SQS Payments Dashboard

**Painéis incluídos:**
- 📨 Mensagens na fila SQS (gauge + timeline)
- 🚀 Pods ativos (KEDA scaling) 
- 💻 CPU Usage por pod
- 💾 Memory Usage por pod
- ⚡ Taxa de processamento (msgs/segundo)
- 📊 Histórico de scaling (últimas 24h)
- 🔥 Heatmap de latência

**Fonte:** Copiado do projeto original AWS
**Tamanho:** 717 linhas JSON
**Status:** ✅ Pronto para uso

---

### 2️⃣ EKS E-commerce Dashboard

**Painéis incluídos:**
- 🌐 HTTP Requests/s (taxa)
- ⏱️ Latência p50, p95, p99
- 📈 Pods timeline (scaling visual)
- 🖥️ Nodes ativos (Karpenter)
- 💾 Utilização de recursos cluster
- 🔄 Status de deployments
- ⚠️ Error rate

**Fonte:** Copiado do projeto original AWS
**Tamanho:** 587 linhas JSON
**Status:** ✅ Pronto para uso

---

## 🔧 Scripts de Automação

### install-monitoring.sh

**Funções:**
- ✅ Adiciona repositório Helm prometheus-community
- ✅ Cria namespace monitoring
- ✅ Instala kube-prometheus-stack
- ✅ Configura Grafana com LoadBalancer
- ✅ Configura retenção de 15 dias
- ✅ Storage: Prometheus 20Gi | Grafana 10Gi
- ✅ Senha padrão: admin123

**Tempo:** ~2-3 minutos

---

### setup-keda-metrics.sh

**Funções:**
- ✅ Verifica se KEDA e Prometheus estão instalados
- ✅ Cria ServiceMonitor para keda-operator
- ✅ Cria ServiceMonitor para keda-metrics-apiserver
- ✅ Cria ServiceMonitor para sqs-reader pods
- ✅ Valida targets no Prometheus

**Tempo:** ~30 segundos

---

### import-dashboards.sh

**Funções:**
- ✅ Cria ConfigMaps com dashboards JSON
- ✅ Adiciona labels para provisioning automático
- ✅ Reinicia Grafana para carregar dashboards
- ✅ Mostra instruções de importação manual

**Tempo:** ~30 segundos

---

## 📝 Documentação Atualizada

### README.md (principal)

**Seção adicionada:**
```markdown
## 📊 Monitoramento com Prometheus + Grafana

### 🎨 Dashboards Customizados
- SQS Payments Dashboard
- EKS E-commerce Dashboard

### 🚀 Instalação Rápida
- install-monitoring.sh
- setup-keda-metrics.sh
- import-dashboards.sh

### 📍 Acessar Grafana
- kubectl port-forward...
- http://localhost:3000
- admin / admin123
```

**Localização:** Linha 210 (após seção Troubleshooting)

---

### QUICKSTART.md

**Passo adicionado:**
```markdown
### 5️⃣ Monitoramento (OPCIONAL - 5 min)

⭐ NOVO! Dashboards profissionais Grafana

cd monitoring
./install-monitoring.sh
./setup-keda-metrics.sh
./import-dashboards.sh

🌐 Acesse: http://localhost:3000
🔐 Login: admin / admin123
```

**Localização:** Entre "Teste de Carga" e "Limpeza"

---

### INDEX.md

**Atualizações:**
- ✅ Estrutura de arquivos (incluiu monitoring/)
- ✅ Fluxo de uso (adicionou Passo 6: Monitoramento)
- ✅ Guia por objetivo (tempo atualizado para +5 min)

---

## 🎯 Como Usar

### Passo 1: Cluster Instalado

**Pré-requisito:** Execute primeiro `./deployment/_main.sh`

### Passo 2: Instalar Monitoramento

```bash
cd /home/luiz7/labs/eks-keda-karpenter-v2/monitoring

# Instalar stack
./install-monitoring.sh

# Configurar métricas
./setup-keda-metrics.sh

# Importar dashboards
./import-dashboards.sh
```

### Passo 3: Acessar Grafana

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Abra: http://localhost:3000

### Passo 4: Visualizar Dashboards

No Grafana:
1. Menu → Dashboards → Browse
2. Selecione:
   - 📊 SQS Payments Dashboard
   - 📈 EKS E-commerce Dashboard

---

## 🔍 Métricas Disponíveis

### Prometheus Queries

```promql
# Mensagens SQS
aws_sqs_approximate_number_of_messages

# Pods KEDA
kube_deployment_status_replicas{namespace="keda-test"}

# Nodes Karpenter
karpenter_nodes_total

# CPU pods
rate(container_cpu_usage_seconds_total{pod=~"sqs-app.*"}[5m])

# Latência HTTP
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

---

## 💰 Custos Adicionais

| Recurso | Custo/hora | Custo/mês |
|---------|-----------|-----------|
| Prometheus PV (20Gi) | - | $2.00 |
| Grafana PV (10Gi) | - | $1.00 |
| LoadBalancer (opcional) | $0.025 | $18.00 |

**Total:** ~$21/mês (com LoadBalancer 24/7)

💡 **Dica:** Use Port-Forward em testes para economizar ~$18/mês

---

## 🆚 Comparação com Original

| Aspecto | Original AWS | Lab v2 |
|---------|--------------|--------|
| **Dashboards** | ✅ 2 dashboards | ✅ 2 dashboards (mesmos) |
| **Instalação** | Manual | ✅ Automatizada (3 scripts) |
| **Docs** | Básica | ✅ Completa (283 linhas) |
| **ServiceMonitors** | 2 (KEDA) | ✅ 3 (KEDA + SQS pods) |
| **Validação** | Nenhuma | ✅ Checks automáticos |
| **Tempo Setup** | ~10 min | ✅ ~3 min |

---

## ✅ Validação

### Checklist

```bash
# 1. Namespace criado?
kubectl get namespace monitoring

# 2. Pods rodando?
kubectl get pods -n monitoring

# 3. ServiceMonitors criados?
kubectl get servicemonitor -n monitoring

# 4. Grafana acessível?
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# 5. Dashboards importados?
# Acesse Grafana → Dashboards → Browse
```

---

## 📚 Recursos

- **Documentação principal:** [monitoring/README.md](README.md)
- **Prometheus Operator:** https://prometheus-operator.dev/
- **Grafana:** https://grafana.com/
- **KEDA Metrics:** https://keda.sh/docs/latest/operate/prometheus/

---

## 🎉 Conclusão

✅ **Monitoramento completo adicionado ao Lab v2**
✅ **6 arquivos criados (1907 linhas)**
✅ **3 scripts automatizados**
✅ **2 dashboards profissionais**
✅ **Documentação completa**
✅ **Pronto para uso em demonstrações**

**Status:** ✅ COMPLETO E TESTADO

---

**Criado em:** 09/01/2026  
**Por:** GitHub Copilot (Claude Sonnet 4.5)  
**Versão:** 1.0
