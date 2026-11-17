# QuotaPie

Monitor de cotas de **Codex e Claude Code** na barra de menus do macOS. Exibe utilização, horários de renovação, histórico e alertas opcionais em uma interface nativa SwiftUI/AppKit.

Projeto independente, sem afiliação com OpenAI ou Anthropic. A interface também usa o nome **AI Usage Monitor**.

## Requisitos

- Para executar: macOS 14 ou posterior. Builds universais incluem Apple Silicon e Intel; execução em Intel e macOS 14 ainda precisa de validação em hardware real.
- Para compilar: **Xcode beta 27.2**, usado nesta revisão, com Swift 6. O projeto usa o formato `project.xcproj`; compatibilidade com versões anteriores do Xcode não foi validada.
- CLI do provedor instalado e autenticado pelo próprio usuário. O QuotaPie não fornece uma assinatura de IA.

## Instalação

Quando houver uma versão publicada, abra a seção [Releases](https://github.com/adalbertozauli/QuotaPie/releases) deste repositório e baixe `QuotaPie-Instalador.pkg`.

1. Feche o QuotaPie, caso esteja aberto.
2. Dê duplo-clique no pacote e confirme a instalação pelo Instalador do macOS. Ele pode solicitar autenticação de administrador.
3. Abra **Aplicativos → QuotaPie**. O ícone aparece na barra de menus; não há janela principal nem ícone permanente no Dock.
4. Clique no ícone e abra a engrenagem para configurar os provedores.

O instalador local atual não tem assinatura Developer ID nem notarização. O macOS pode bloquear um pacote baixado da internet. A alternativa é compilar o código localmente; este projeto não orienta desativar as proteções do sistema. Não há atualizador automático nesta versão.

## Provedores

| Provedor | Fonte | Limitações |
| --- | --- | --- |
| Codex | App Server do CLI autenticado | Requer conta compatível com as cotas de assinatura. Uma chave de API não representa cotas do ChatGPT. |
| Claude Code | Status line local ou consulta experimental de `/usage` | A status line depende dos campos emitidos e da atividade no CLI. A consulta experimental depende do formato textual do Claude Code. |

**Codex:** instale e autentique o CLI oficial com `codex login`. O app procura instalações comuns, incluindo `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` e Codex.app. Se necessário, informe o caminho do executável em **Configurações → Provedores** e use **Verificar conexões**.

**Claude:** siga o [guia de configuração](docs/CLAUDE_SETUP.md). A consulta experimental de `/usage` é opcional e vem desativada. A autenticação permanece no CLI.

ChatGPT convencional e outros provedores não são oferecidos nesta versão. A inclusão de novos provedores está no [roadmap](ROADMAP.md). Dados ausentes nunca são substituídos automaticamente por cotas fictícias.

## Recursos e privacidade

- Atualização configurável, estados de conexão e indicação de leituras antigas.
- Percentuais e horários de renovação por janela, respeitando o fuso local.
- Histórico local, aparência clara/escura, abertura por clique ou hover.
- Alertas e início com o macOS opcionais.
- Sem telemetria, servidor próprio ou coleta de cookies pelo QuotaPie.
- Os CLIs dos provedores fazem suas próprias conexões e gerenciam suas credenciais. O monitor não armazena tokens próprios.

Preferências usam UserDefaults. Histórico e leitura da ponte ficam em `~/Library/Application Support/AIUsageMonitor/`. O histórico pode ser apagado nas configurações. Para remover o app, desative o início automático, remova a ponte da status line se configurada e exclua o aplicativo de Aplicativos. Para apagar os dados locais, remova também a pasta acima e as preferências do bundle `zauli.med.QuotaPie`.

App Sandbox está desativado para permitir o uso dos CLIs externos. O projeto solicita Hardened Runtime; o Xcode pode desativá-lo em builds ad-hoc. Builds de distribuição precisam de verificação própria de assinatura e runtime.

## Compilar e testar

Abra `QuotaPie.xcodeproj`, selecione **QuotaPie**, destino **My Mac**, e execute com ⌘R. O esquema compartilhado inclui os testes de lógica; use ⌘U para executá-los.

No Terminal, com o Xcode compatível selecionado:

```sh
xcodebuild -project QuotaPie.xcodeproj -scheme QuotaPie   -configuration Debug -destination 'platform=macOS' test
```

O esquema **QuotaPie-UI** executa os testes de interface em uma sessão gráfica. Eles podem precisar de autorização de automação do macOS. Os testes usam fixtures; não é necessário autenticar contas para os testes offline. Uma execução com zero testes não conta como validação.

Para gerar o aplicativo universal:

```sh
xcodebuild -project QuotaPie.xcodeproj -scheme QuotaPie   -configuration Release -derivedDataPath build   CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=   ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
```

Para gerar o instalador e seu checksum a partir desse build:

```sh
./scripts/package-installer.sh
```

Os arquivos ficam em `dist/`, fora do controle de versão. O script gera um pacote local sem assinatura; não realiza notarização. Consulte o [guia de publicação](docs/GITHUB_RELEASE.md).

Validação desta preparação: build aprovado e **73 casos de teste passaram**. Veja [limitações da validação](docs/VALIDATION.md).

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `QuotaPie/` | Aplicativo, provedores, modelos, persistência e interface |
| `QuotaPieTests/` | Testes Swift Testing de domínio, parsers e transporte |
| `QuotaPieUITests/` | Testes de interface |
| `scripts/` | Geração do ícone e empacotamento |
| `docs/` | Configuração, publicação e validação manual |

## Contribuições e licença

Veja [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). Projeto open source sob a [licença MIT](LICENSE), com copyright de Adalberto Zauli. Não foi incorporado código dos projetos consultados como referência.
