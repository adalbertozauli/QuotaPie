# Publicar no GitHub

## Repositório

O diretório local está preparado para Git. Builds, instaladores, arquivos pessoais do Xcode e relatórios internos de validação são ignorados. Os assets usados pelo aplicativo permanecem no catálogo de assets.

O projeto usa a licença MIT, registrada em `LICENSE`. Antes de publicar novos assets, confirme os direitos de distribuição. Revise `git status` e `git diff --cached`; não use `git add -f` para incluir arquivos ignorados.

O repositório é https://github.com/adalbertozauli/QuotaPie. Para configurar outro clone local sem remoto e enviar alterações:

```sh
git add .
git diff --cached --stat
git commit -m "Prepare QuotaPie for GitHub"
git remote add origin https://github.com/adalbertozauli/QuotaPie.git
git push -u origin main
```

Se `origin` já estiver configurado, não repita `git remote add`. A identidade de autoria do commit deve ser a que você deseja tornar pública; confira `git config user.name` e `git config user.email`.

## Release

1. Compile e teste conforme o README, incluindo as verificações manuais relevantes.
2. Antes de uma versão nova, atualize a versão e o número de build no Xcode.
3. Gere o Release universal e execute `./scripts/package-installer.sh`.
4. Teste o pacote em um Mac de validação, incluindo atualização de uma instalação anterior.
5. Crie uma tag para o commit correspondente e uma release no GitHub.
6. Anexe `dist/QuotaPie-Instalador.pkg` e `dist/SHA256SUMS.txt` como assets da release, não como arquivos do repositório.

Descreva a versão mínima do macOS, a versão do Xcode, os provedores suportados, o caráter experimental do Claude `/usage` e a situação real da assinatura/notarização. Não apresente builds ad-hoc como notarizados.

Para distribuição assinada, o aplicativo requer Developer ID Application, o pacote requer Developer ID Installer e o fluxo de notarização deve ser concluído e verificado antes da publicação. O script local não executa esse fluxo. Não envie certificados privados ou credenciais ao Git.

## Verificações antes de publicar

- Licença MIT incluída e documentação consistente com ela.
- Código e assets revisados; sem credenciais ou dados pessoais.
- Build e testes aprovados com contagem de testes registrada.
- Artefato corresponde à revisão publicada.
- Instalação e abertura verificadas em um ambiente de teste.
- Recursos de segurança privados do GitHub configurados pelo mantenedor.

Não há workflow de CI configurado nesta preparação: o projeto depende de uma versão beta específica do Xcode, e a disponibilidade de runner compatível ainda não foi validada.
