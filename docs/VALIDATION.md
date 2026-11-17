# Validação para preparação do GitHub

Data: 17/11/2026.

- Build pelo Xcode, incluindo targets de teste: aprovado.
- Esquema compartilhado `QuotaPie`: 73 casos de teste passaram, zero falhas e zero ignorados (inclui casos parametrizados).
- Script `package-installer.sh`: sintaxe conferida e empacotamento executado com o Release universal gerado nesta sessão.
- Checksum SHA-256 do instalador gerado e conferido.
- Revisão dos arquivos candidatos ao Git: sem correspondências para os padrões pesquisados de chaves privadas, tokens e caminhos pessoais. Essa verificação não equivale a uma auditoria completa de segurança.
- Builds, instaladores, dados do usuário do Xcode e relatórios internos ficam fora do Git.

Testes de interface não foram repetidos nesta preparação documental e de empacotamento. O esquema `QuotaPie-UI` está compartilhado para execução manual. Não foi realizada instalação do pacote em um segundo Mac, notarização ou validação em Intel/macOS 14.

Consulte também o checklist em [MANUAL_VALIDATION.md](MANUAL_VALIDATION.md).
