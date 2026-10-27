# Prumo

App pessoal (PWA para iPhone) para ler todo dia o que sai de novo em arquitetura: projetos e obras, urbanismo, habitação, paisagismo, interiores, patrimônio, materiais, concursos e pesquisa acadêmica, do Brasil e de fora, com meta diária de leitura. Feito de presente para o Milton, a partir do [Atualiz.IA](https://github.com/oiyuriv/atualizia).

**Abrir:** https://oiyuriv.github.io/prumo/ no Safari → Compartilhar → *Adicionar à Tela de Início*.

## Como funciona

- `tools/sources.json`: as fontes (revistas, portais, conselhos e periódicos acadêmicos de arquitetura e urbanismo). Para incluir ou tirar uma fonte, é só editar esta lista.
- `tools/build-feed.ps1`: busca os feeds, traduz títulos e resumos de fora para o português, marca os temas (o título manda no tema principal) e grava `data/feed.json`.
- `.github/workflows/feed.yml`: roda o coletor a cada 2 horas no GitHub Actions e publica o site.
- `index.html`: o app inteiro. Nome, notas, guardados, metas, gráficos do perfil e o que o feed aprendeu ficam só no aparelho (localStorage). Na primeira abertura aparece uma tela de boas-vindas para escolher o nome, os temas favoritos e a meta diária.
- `make-icons.ps1`: gera os ícones (o prumo roxo sobre fundo preto).

Para testar no Windows: `powershell -File tools/build-feed.ps1` e depois `powershell -File serve.ps1` (porta 8132).
