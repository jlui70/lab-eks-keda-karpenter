# 📊 Monitoramento com Prometheus + Grafana

Stack completa de monitoramento para visualização de métricas KEDA e Karpenter.

## 🎯 Componentes

- **Prometheus**: Coleta de métricas do cluster
- **Grafana**: Visualização e dashboards
- **Dashboards Customizados**: SQS Payments para monitoramento do teste de scaling

## 🚀 Instalação

### ⚡ Instalação AUTOMÁTICA (Recomendado)

A stack de monitoramento é **instalada automaticamente** durante o deployment completo:

```bash
# A partir da raiz do projeto
./deployment/_main.sh
```

## 📈 Dashboard Disponível

### 📊 SQS Payments Dashboard

**Métricas incluídas:**
- 📨 Mensagens na fila SQS (approximate messages)
- 🚀 Número de pods ativos (scaling KEDA)
- 💻 CPU e Memória dos pods
- ⚡ Taxa de processamento (msgs/segundo)
- 📊 Histórico de scaling
- 🖥️ Nodes provisionados pelo Karpenter

**Queries Prometheus principais:**
```promql
# Mensagens na fila
aws_sqs_approximate_number_of_messages

# Pods ativos
kube_deployment_status_replicas{deployment="sqs-app"}

# CPU usage
rate(container_cpu_usage_seconds_total{pod=~"sqs-app.*"}[5m])

# Nodes Karpenter
count(kube_node_info)
```

## 🔑 Acesso ao Grafana

### Port-Forward (Recomendado)

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

## 🎨 Visualizando o Dashboard

Após acessar o Grafana:

1. **Login**: admin / admin123
2. **Menu**: Dashboards → Browse
3. **Selecione**: "SQS Payments Dashboard"

O dashboard mostra em tempo real:
- Mensagens processadas
- Pods escalando conforme carga
- Nodes sendo provisionados pelo Karpenter
- CPU/Memory usage

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

### Problema: Dashboard vazio ou sem dados

1. **Verifique Data Source**:
   - Grafana → Configuration → Data Sources
   - Deve existir: `monitoring-kube-prometheus-prometheus`
   - Status: ✅ Working

2. **Verifique Prometheus**:
   ```bash
   kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
   ```
   - Execute queries manualmente em http://localhost:9090

3. **Verifique se os pods estão rodando**:
   ```bash
   kubectl get pods -n keda-test
   kubectl get pods -n monitoring
   ```

## ✅ Validação Rápida

```bash
# 1. Prometheus rodando?
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# 2. Grafana rodando?
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# 3. Dashboard importado?
# Acesse Grafana → Dashboards → Browse
# Deve aparecer: "SQS Payments Dashboard"

# 4. Métricas disponíveis?
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# Acesse: http://localhost:9090
# Execute query: kube_deployment_status_replicas{namespace="keda-test"}
```

## 💰 Custos

**EBS Volumes criados pelo Prometheus/Grafana:**
- ~$2-3/mês se mantido 24/7
- Removido automaticamente com o cleanup do lab

---

## 📚 Recursos

- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [KEDA Metrics](https://keda.sh/docs/latest/operate/prometheus/)
- [Karpenter Metrics](https://karpenter.sh/docs/concepts/metrics/)

**LoadBalancer (se habilitado):**
- ~$0.025/hora (~$18/mês)

**Total estimado**: ~$21/mês (se manter rodando 24/7)

⚠️ **Para ambientes de teste**: Use Port-Forward ao invés de LoadBalancer!
