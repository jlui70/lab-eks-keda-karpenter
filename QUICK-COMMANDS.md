# ⚡ Comandos Rápidos

Este arquivo contém os comandos mais utilizados do projeto para referência rápida.

## 🚀 Instalação

```bash
# Verificar pré-requisitos
./check-prerequisites.sh

# Instalação completa (25 min)
./deployment/_main.sh
# Selecionar opção: 3 (Deploy completo)

# Instalar monitoring (opcional - 7 min)
./monitoring/install-complete-monitoring.sh
```

## 🧪 Testes

```bash
# Teste de carga (500 mensagens)
./tests/run-load-test.sh

# Forçar scale-down (emergência)
./tests/force-scale-down.sh
```

## 📊 Monitoramento

```bash
# Acessar Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Abrir: http://localhost:3000
# User: admin | Pass: kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d

# Ver pods
watch -n 2 'kubectl get pods -n keda-test'

# Ver nodes
watch -n 2 'kubectl get nodes'

# Ver HPA
watch -n 2 'kubectl get hpa -n keda-test'

# Ver fila SQS
SQS_URL=$(aws sqs get-queue-url --queue-name keda-demo-queue.fifo --query 'QueueUrl' --output text)
watch -n 2 "aws sqs get-queue-attributes --queue-url $SQS_URL --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text"
```

## 🔍 Diagnóstico

```bash
# Status completo
kubectl get all -n keda-test
kubectl get nodes
kubectl get scaledobject -n keda-test

# Logs da aplicação
kubectl logs -n keda-test -l app=sqs-app --tail=50 -f

# Logs do KEDA
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator --tail=50 -f

# Logs do Karpenter
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50 -f

# Eventos do cluster
kubectl get events -n keda-test --sort-by='.lastTimestamp'

# Descrever HPA
kubectl describe hpa -n keda-test

# Descrever ScaledObject
kubectl describe scaledobject sqs-scaledobject -n keda-test
```

## ⚙️ Ajustes Rápidos

```bash
# Ajustar cooldown para demo (scale-down mais rápido)
kubectl patch scaledobject sqs-scaledobject -n keda-test \
  --type='merge' -p '{"spec":{"cooldownPeriod":10,"pollingInterval":5}}'

# Ajustar ttl do Karpenter (remove nodes mais rápido)
kubectl patch nodepool default --type='merge' \
  -p '{"spec":{"disruption":{"consolidationPolicy":"WhenEmpty","consolidateAfter":"10s"}}}'

# Reverter para produção
kubectl patch scaledobject sqs-scaledobject -n keda-test \
  --type='merge' -p '{"spec":{"cooldownPeriod":30,"pollingInterval":10}}'
```

## 🛠️ Troubleshooting

```bash
# HPA travado? Resetar:
kubectl delete hpa keda-hpa-sqs-scaledobject -n keda-test
# KEDA recria automaticamente em ~10s

# Purgar fila SQS
SQS_URL=$(aws sqs get-queue-url --queue-name keda-demo-queue.fifo --query 'QueueUrl' --output text)
aws sqs purge-queue --queue-url $SQS_URL

# Reiniciar deployment
kubectl rollout restart deployment sqs-app -n keda-test

# Ver recursos usados pelos pods
kubectl top pods -n keda-test
kubectl top nodes
```

## 🧹 Limpeza

```bash
# Limpeza completa (10-15 min)
./scripts/cleanup.sh

# Limpeza parcial (apenas app)
kubectl delete namespace keda-test
```

## 📦 Git

```bash
# Inicializar repositório
git init
git add .
git commit -m "Initial commit: EKS KEDA Karpenter Lab v2"

# Adicionar remote
git remote add origin <seu-repo-url>
git branch -M main
git push -u origin main
```

## 🔐 AWS

```bash
# Verificar credenciais
aws sts get-caller-identity

# Listar clusters
aws eks list-clusters --region us-east-1

# Update kubeconfig
aws eks update-kubeconfig --name eks-demo-scale-v2 --region us-east-1

# Verificar custos (importante!)
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter file://<(echo '{"Tags":{"Key":"Project","Values":["eks-keda-karpenter"]}}')
```

## 📊 Métricas Úteis

```bash
# Quantos pods rodando
kubectl get pods -n keda-test --field-selector=status.phase=Running --no-headers | wc -l

# Quantos nodes no cluster
kubectl get nodes --no-headers | wc -l

# Mensagens na fila
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name keda-demo-queue.fifo --query 'QueueUrl' --output text) \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text

# Items no DynamoDB
aws dynamodb scan --table-name payments --select COUNT --query 'Count' --output text
```

## 🎯 Atalhos para Apresentação

```bash
# Terminal 1: Fila SQS
SQS_URL=$(aws sqs get-queue-url --queue-name keda-demo-queue.fifo --query 'QueueUrl' --output text)
watch -n 2 "aws sqs get-queue-attributes --queue-url $SQS_URL --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text"

# Terminal 2: Pods
watch -n 2 'kubectl get pods -n keda-test --no-headers | wc -l'

# Terminal 3: Nodes
watch -n 2 'kubectl get nodes --no-headers | wc -l'

# Terminal 4: HPA
watch -n 2 'kubectl get hpa -n keda-test'

# Terminal 5: Enviar mensagens
./tests/run-load-test.sh
```

---

**💡 Dica**: Salve este arquivo nos seus favoritos para acesso rápido!
