# 🤝 Contribuindo para o Projeto

Obrigado por considerar contribuir para o **EKS KEDA Karpenter v2**!

## 📋 Como Contribuir

### 🐛 Reportar Bugs

Abra uma issue com:
- Descrição clara do problema
- Passos para reproduzir
- Comportamento esperado vs atual
- Versões (AWS CLI, kubectl, eksctl, K8s)
- Logs relevantes

### ✨ Sugerir Melhorias

Abra uma issue com:
- Descrição da funcionalidade
- Justificativa (por que é útil)
- Exemplos de uso

### 🔧 Pull Requests

1. **Fork** o repositório
2. **Crie uma branch** para sua feature: `git checkout -b feature/minha-feature`
3. **Faça commits** com mensagens claras
4. **Teste** suas alterações
5. **Envie um PR** para a branch `main`

## 🧪 Testando Alterações

Antes de enviar PR:

```bash
# 1. Execute o script de verificação
./check-prerequisites.sh

# 2. Teste deployment completo
./deployment/_main.sh
# (Selecione opção 3)

# 3. Execute testes
./tests/run-load-test.sh

# 4. Valide que funciona
kubectl get pods -n keda-test
kubectl get nodes

# 5. Faça cleanup
./scripts/cleanup.sh
```

## 📝 Padrões de Código

### Scripts Bash

- Use `#!/bin/bash` no início
- Adicione comentários descritivos
- Use cores para output (veja `environmentVariables.sh`)
- Valide erros: `set -e` quando apropriado
- Use variáveis em UPPERCASE para constantes

### Python

- Python 3.8+
- PEP 8 style guide
- Type hints quando possível
- Docstrings para funções

### YAML Kubernetes

- Indentação com 2 espaços
- Use labels consistentes
- Adicione comentários para campos complexos

## 🎯 Áreas que Precisam de Ajuda

- [ ] Suporte para múltiplas regiões AWS
- [ ] Dashboards Grafana adicionais
- [ ] Testes automatizados (CI/CD)
- [ ] Suporte para outros schedulers (ex: Cluster Autoscaler)
- [ ] Documentação em inglês
- [ ] Exemplos com outros tipos de filas (Kafka, RabbitMQ)

## 📚 Recursos Úteis

- [KEDA Documentation](https://keda.sh/)
- [Karpenter Documentation](https://karpenter.sh/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

## ✅ Checklist antes de submeter PR

- [ ] Código testado em ambiente real
- [ ] Documentação atualizada (README.md)
- [ ] Variáveis sensíveis removidas
- [ ] Scripts têm permissão de execução
- [ ] Cleanup funciona corretamente
- [ ] Logs não contêm informações sensíveis

## 📧 Contato

Dúvidas? Abra uma issue ou discussão no GitHub!

---

**Obrigado por contribuir! 🚀**
