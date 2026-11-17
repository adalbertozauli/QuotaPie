# Validação manual complementar

Os testes automatizados não substituem estes cenários:

- [ ] Instalar Codex oficial, autenticar com assinatura e conferir percentuais/horários contra a fonte.
- [ ] Expirar ou revogar autenticação e verificar estado e ausência de credenciais nos logs.
- [ ] Configurar a status line Claude, usar normalmente uma sessão elegível e comparar as duas janelas com a página oficial de utilização.
- [ ] Confirmar quais limites adicionais do Claude Desktop são compartilhados no plano utilizado; o monitor não presume cobertura completa.
- [ ] Validar a consulta experimental Claude `/usage` em outro Mac, incluindo primeira autenticação, resets e encerramento do processo.
- [ ] Instalar pelo `.pkg`, atualizar uma instalação existente e confirmar a abertura em Aplicativos.
- [ ] Mover o ícone entre monitores e testar barra oculta automaticamente, Spaces e aplicativos em tela cheia.
- [ ] Navegar com VoiceOver e somente teclado; os rótulos estão implementados, mas não foi feita auditoria completa com leitor de tela.
- [ ] Testar aumentar contraste e reduzir transparência/movimento nos Ajustes do Sistema.
- [ ] Autorizar notificações, conferir entrega real nos três limiares e renovação confirmada; políticas foram testadas offline.
- [ ] Instalar em Aplicativos, habilitar início automático e reiniciar sessão; API foi implementada, login real não foi automatizado.
- [ ] Testar repouso/rede no hardware; o coordenador foi testado com eventos simulados.
- [ ] Executar em hardware Intel e macOS 14; compilação universal não prova execução em ambos.
- [ ] Medir energia/memória por sessão prolongada com Instruments; não foi realizado profiling prolongado.

Já exercitado por XCTest neste Mac: ícone acessível, abertura por hover, permanência ao apontar para um controle, abertura por clique, configurações, fechamento após saída, modo escuro e layout sem dados. Capturas e relatórios internos não são publicados no repositório. Repita esses cenários ao preparar uma release.
