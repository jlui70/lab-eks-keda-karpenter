# 📊 Monitoramento com Prometheus + Grafana

Stack completa de monitoramento para visualização de métricas KEDA e Karpenter.

## 🎯 Componentes

- **Prometheus**: Coleta de métricas do cluster
- **Grafana**: Visualização e dashboards
- **ServiceMonitors**: Integração com KEDA
- **Dashboards Customizados**: SQS Payments e EKS E-commerce

## 🚀 Instalação

### ⚡ Instalação AUTOMÁTICA (Recomendado para Avaliadores)

**Execute UM ÚNICO comando** para instalar tudo:

```bash
cd monitoring
./install-complete-monitoring.sh
```

**O que faz automaticamente:**
1. ✅ Instala Prometheus + Grafana (Helm)
2. ✅ Configura ServiceMonitors para KEDA
3. ✅ Importa 2 dashboards customizados
4. ✅ Valida instalação completa

**Tempo total**: 3-5 minutos

---

### 📋 Instalação Manual (Passo a Passo)

Se preferir executar individualmente:

**Passo 1: Instalar Stack Prometheus + Grafana**

```bash
cd monitoring
chmod +x *.sh
./install-monitoring.sh
```

**Tempo estimado**: 2-3 minutos

**Passo 2: Configurar Métricas KEDA**

```bash
./setup-keda-metrics.sh
```

Isso cria ServiceMonitors para:
- KEDA Operator
- KEDA Metrics Server
- SQS Reader Pods

**Passo 3: Importar Dashboards Customizados**

```bash
./import-dashboards.sh
```

## 📈 Dashboards Disponíveis

### 1️⃣ SQS Payments Dashboard

**Métricas incluídas:**
- 📨 Mensagens na fila SQS (approximate messages)
- 🚀 Número de pods ativos (scaling KEDA)
- 💻 CPU e Memória dos pods
- ⚡ Taxa de processamento (msgs/segundo)
- 📊 Histórico de scaling

**Queries Prometheus principais:**
```promql
# Mensagens na fila
aws_sqs_approximate_number_of_messages

# Pods ativos
kube_deployment_status_replicas{deployment="sqs-app"}

# CPU usage
rate(container_cpu_usage_seconds_total{pod=~"sqs-app.*"}[5m])
```

### 2️⃣ EKS E-commerce Dashboard

**Métricas incluídas:**
- 🌐 HTTP requests por segundo
- ⏱️ Latência de resposta (p50, p95, p99)
- 📈 Pods scaling timeline
- 🖥️ Nodes provisionados pelo Karpenter
- 💾 Utilização de recursos

**Queries Prometheus principais:**
```promql
# HTTP requests
rate(nginx_ingress_controller_requests[5m])

# Latência
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Nodes ativos
kube_node_info{node=~".*karpenter.*"}
```

## 🔑 Acesso ao Grafana

### Opção 1: LoadBalancer (Recomendado)

```bash
# Obter URL do LoadBalancer
kubectl get svc -n monitoring monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Acesse: `http://<LOADBALANCER-URL>`

### Opção 2: Port-Forward (Local)

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Acesse: `http://localhost:3000`

### 🔐 Credenciais Padrão

```
Usuário: admin
Senha: admin123
```

**⚠️ IMPORTANTE**: Altere a senha padrão em produção!

```bash
# Alterar senha via CLI
kubectl exec -it -n monitoring deployment/monitoring-grafana -- grafana-cli admin reset-admin-password NoVaSenha123
```

## 🎨 Importação Manual de Dashboards

Se o script automático falhar:

1. **Acesse o Grafana** (http://localhost:3000)
2. **Login**: admin / admin123
3. **Menu**: [+] Create → Import
4. **Upload JSON**:
   - `monitoring/grafana-dashboard-sqs-payments.json`
   - `monitoring/grafana-dashboard-eks-ecommerce.json`
5. **Selecione Data Source**: `monitoring-kube-prometheus-prometheus`
6. **Import**

## 📊 Verificar Métricas no Prometheus

### Acesso ao Prometheus

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Acesse: `http://localhost:9090`

### Queries Úteis

```promql
# Verificar se KEDA está exportando métricas
up{job="keda-operator"}

# Ver ScaledObjects ativos
keda_scaledobject_paused

# Mensagens SQS
aws_sqs_approximate_number_of_messages

# Pods KEDA
kube_deployment_status_replicas{namespace="keda-test"}

# Nodes Karpenter
karpenter_nodes_total
```

## 🔍 Troubleshooting

### Problema: Grafana não carrega

```bash
# Verificar status
kubectl get pods -n monitoring

# Logs do Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Reiniciar Grafana
kubectl rollout restart deployment monitoring-grafana -n monitoring
```

### Problema: Métricas não aparecem

```bash
# Verificar ServiceMonitors
kubectl get servicemonitor -n monitoring

# Verificar Targets no Prometheus
# Acesse: http://localhost:9090/targets
# Procure por: keda-operator, keda-metrics-apiserver

# Verificar se KEDA está expondo métricas
kubectl get svc -n keda
```

### Problema: Dashboards vazios

1. **Verifique Data Source**:
   - Grafana → Configuration → Data Sources
   - Deve existir: `monitoring-kube-prometheus-prometheus`
   - Status: ✅ Working

2. **Verifique Prometheus**:
   ```bash
   kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
   ```
   - Execute queries manualmente em http://localhost:9090

3. **Reimporte Dashboard**:
   - Delete dashboard antigo
   - Reimporte JSON
   - Selecione Data Source correto

## 🧹 Desinstalar Monitoramento

```bash
# Remover stack completa
helm uninstall monitoring -n monitoring

# Remover namespace (CUIDADO: remove PVCs!)
kubectl delete namespace monitoring

# Remover ServiceMonitors
kubectl delete servicemonitor -n monitoring keda-operator keda-metrics-apiserver sqs-reader-pods
```

## 📝 Customização

### Adicionar Novo Dashboard

1. Crie dashboard no Grafana
2. Export JSON: Dashboard → Share → Export → Save to file
3. Coloque em `monitoring/custom-dashboard.json`
4. Crie ConfigMap:
   ```bash
   kubectl create configmap custom-dashboard \
     --from-file=dashboard.json=monitoring/custom-dashboard.json \
     -n monitoring
   
   kubectl label configmap custom-dashboard grafana_dashboard=1 -n monitoring
   ```

### Adicionar Alertas

Edite `monitoring/install-monitoring.sh` e adicione:

```yaml
--set alertmanager.enabled=true \
--set alertmanager.service.type=LoadBalancer
```

## 📚 Recursos

- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [KEDA Metrics](https://keda.sh/docs/latest/operate/prometheus/)
- [Karpenter Metrics](https://karpenter.sh/docs/concepts/metrics/)

## ✅ Checklist de Validação

```bash
# 1. Prometheus está rodando?
kubectl get pods -n monitoring | grep prometheus

# 2. Grafana está rodando?
kubectl get pods -n monitoring | grep grafana

# 3. ServiceMonitors criados?
kubectl get servicemonitor -n monitoring

# 4. Métricas KEDA disponíveis?
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# Acesse: http://localhost:9090 e busque por "keda"

# 5. Dashboards importados?
# Acesse Grafana e vá em Dashboards → Browse
```

## 💰 Custos

**EBS Volumes criados:**
- Prometheus: 20Gi (~$2.00/mês)
- Grafana: 10Gi (~$1.00/mês)

**LoadBalancer (se habilitado):**
- ~$0.025/hora (~$18/mês)

**Total estimado**: ~$21/mês (se manter rodando 24/7)

⚠️ **Para ambientes de teste**: Use Port-Forward ao invés de LoadBalancer!
