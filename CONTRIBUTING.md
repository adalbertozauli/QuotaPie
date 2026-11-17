# Contribuir com o QuotaPie

Antes de propor uma alteração grande, abra uma issue descrevendo o problema e o comportamento esperado. As contribuições são disponibilizadas sob a mesma [licença MIT](LICENSE) do projeto.

## Desenvolvimento

1. Use a versão do Xcode indicada no README.
2. Abra `QuotaPie.xcodeproj` e execute o esquema compartilhado `QuotaPie`.
3. Faça alterações pequenas e relacionadas ao objetivo da contribuição.
4. Execute os testes de lógica com ⌘U. Para alterações de interface, valide também o esquema `QuotaPie-UI` e o comportamento na barra de menus.
5. Descreva no pull request o problema, a solução e a validação realizada.

Use Swift 6, indentação de quatro espaços, tipos com PascalCase e propriedades/métodos com camelCase. Prefira async/await e mantenha a consulta de provedores separada da interface. Use Swift Testing nos testes de lógica.

Não envie builds, instaladores, DerivedData, configurações pessoais do Xcode, credenciais, histórico de uso real ou capturas com dados pessoais. Fixtures devem ser sintéticas ou devidamente sanitizadas.

## Novos provedores

A interface para adicionar provedores fica para uma próxima versão. Uma proposta de conector deve identificar a modalidade monitorada (assinatura ou API), a fonte dos limites, autenticação, periodicidade, resets e limitações. Deve trazer testes offline para dados ausentes, formato inválido e falhas de autenticação. Não atribua cotas de uma modalidade a outra nem converta custos ou uso de contexto em percentual de assinatura.

## Relatos de problemas

Informe versões do app, macOS e CLI, passos para reproduzir e o resultado esperado. Remova tokens, e-mails, nomes de usuário e dados pessoais de logs e capturas. Para vulnerabilidades, siga SECURITY.md.
