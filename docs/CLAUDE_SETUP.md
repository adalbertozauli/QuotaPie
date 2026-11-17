# Conectar Claude com status line oficial

## Alternativa experimental: consulta interativa

Na versão de 16/11/2026, abra **Configurações → Provedores → Claude** e ative **Consultar /usage pelo Claude Code (experimental)**. A opção é desativada por padrão e substitui a fonte status line enquanto estiver ativa; não combina leituras das duas fontes.

Requer Claude Code 2.1.311 ou versão compatível, instalado em `~/.local/bin`, `/opt/homebrew/bin` ou `/usr/local/bin`, já autenticado pelo próprio CLI. A consulta abre um pseudoterminal de 160 × 200, usa `/usage`, desativa ferramentas, hooks, MCP e customizações e encerra o processo ao concluir, cancelar ou atingir o limite de 16 segundos. Não envia prompts ao modelo.

A pasta própria `~/Library/Application Support/AIUsageMonitor/ClaudeProbe` deve estar vazia, pertencer ao usuário e não passar por symlinks. Somente essa pasta pode ter o diálogo de confiança confirmado pela consulta. O CLI pode manter seus próprios metadados de sessão/confiança; o monitor não lê nem exporta essas informações.

O parser considera somente seções `Current session` e `Current week`, incluindo modelos adicionais. Percentuais de insights, custo e contexto não são cotas. Datas sem fuso explícito ou com formato desconhecido permanecem indisponíveis. O formato da tela é instável; a interface sinaliza esse mecanismo como experimental.

**Validação registrada em 16/11/2026:** a consulta no aplicativo instalado retornou janelas reais de sessão e semana; 61 testes automatizados passaram naquela revisão. Isso não garante compatibilidade com outras versões do CLI ou com a primeira configuração em outro Mac. A integração continua experimental. No executor restrito do Xcode, a criação de PTY pode ser bloqueada; valide a conexão no aplicativo instalado.

Para voltar à ponte anterior, desative a opção experimental. Não é necessário remover a configuração de status line.

## Ponte da status line

Requer Claude Code com suporte a `rate_limits` na status line e assinatura elegível. Não exige Claude Desktop instalado. Não lê tokens ou cookies. O app deve estar instalado em um caminho estável (ex.: `/Applications/QuotaPie.app`).

Em `~/.claude/settings.json`, configure manualmente, preservando as demais opções:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Applications/QuotaPie.app/Contents/MacOS/QuotaPie\" --claude-statusline"
  }
}
```

O executável funciona como filtro nativo: recebe JSON pelo stdin e grava apenas `capturedAt`, `rate_limits.five_hour` e `rate_limits.seven_day` em `~/Library/Application Support/AIUsageMonitor/claude-usage.json` com permissão 0600. Nenhuma conversa, identidade, custo ou credencial é armazenada. Não precisa Python, jq ou servidor.

Se você já usa outra status line, integre explicitamente os dois comandos em seu script, fornecendo a mesma entrada a ambos; não substitua sua configuração sem guardar uma cópia. O monitor não modifica essa configuração automaticamente.

Após a primeira resposta de uma sessão Claude Code, abra o painel e atualize. Campos ausentes permanecem desconhecidos. Não inicie uma conversa paga apenas para testar o aplicativo: os testes offline usam fixtures. A ponte não consulta a conta em segundo plano. Sem atividade recente, o painel mostra dados antigos. Quando uma janela some após reset, nenhum saldo é inferido. Não representa automaticamente todas as modalidades do Claude Desktop.

Para desconectar, remova o comando de status line e apague `claude-usage.json`. Histórico pode ser apagado em Configurações.

Fonte: https://code.claude.com/docs/en/statusline

Se aparecer “Ponte conectada, mas o Claude Code não forneceu cotas”, a captura está funcionando, porém a entrada não contém janelas de utilização. Login ou uso apenas do Desktop não garante esses campos. Aguarde uma resposta em sua sessão normal do Claude Code e atualize o painel. O monitor mantém os percentuais indisponíveis até receber métricas reais.
