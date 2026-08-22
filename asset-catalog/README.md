# asset-catalog

Arquivos editáveis:

- `aliases.csv`: sinônimos, traduções e correções.
- `fallbacks.csv`: fallback global e por categoria.
- `settings.json`: comportamento do resolver.

Arquivos gerados:

- `assets-index.json`: índice completo da pasta de imagens.
- `catalog-build-report.json`: relatório de colisões, aliases inválidos e estatísticas.

Não edite `assets-index.json` manualmente. Corrija nomes de arquivos, aliases ou fallbacks e execute `ATUALIZAR_CATALOGO.bat`.
