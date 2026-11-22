# Próximos passos

Roteiro das etapas que faltam, na ordem sugerida. Os endereços de sites foram escritos de memória: confira antes de usar.

## Etapa 1 — Conferir a correspondência município → DSEI (urgente)

Todos os resultados dependem desta tabela, e parte dela foi preenchida como sugestão.

1. Abra `dados/correspondencia_municipio_dsei.csv` no Excel e filtre a coluna `confianca` por `baixa` (32 municípios) e depois `media`.
2. Para cada município, abra o PDSI 2024-2027 do DSEI indicado (gov.br/saude → Composição → SESAI → Planos Distritais de Saúde Indígena). Aperte Ctrl+F e busque "municípios" ou o nome do município. A lista de abrangência fica na caracterização do distrito.
3. Confirme pelo CNES: https://cnes.datasus.gov.br → Consultas → Estabelecimentos → filtre UF e município. Os estabelecimentos indígenas costumam ter "POLO BASE", "UBSI" ou "DSEI ..." no nome.
4. Se o município pertence a dois DSEIs, duplique a linha e divida o `peso` (ex.: 0,5 e 0,5, ou proporcional à população indígena de cada um). Os pesos do município precisam somar 1; o script 02 para com erro se não somarem.
5. Atualize as colunas `fonte` (ex.: "PDSI Xingu p. 12") e `confianca`.
6. Rode `source("R/rodar_tudo.R")` e compare o novo ranking com o atual.

## Etapa 2 — Reunião com o Felipe: validar a formulação

Leve a planilha `resultados/03_resultados_dea_dsei_2022.xlsx` e as figuras. Pontos para decidir:

1. **Normalização min-max:** mostrar a aba `comparacao_A_vs_B` e a figura `fig_03_comparacao_normalizacao.png`. Proposta: modelo principal sem normalização.
2. **Óbitos:** em números absolutos invertem o ranking (experimento E7, Spearman 0,12). Opções: (a) deixar fora do DEA e usar no segundo estágio; (b) usar taxa de mortalidade (óbitos / população indígena × 1.000), lembrando que misturar taxa com volume no DEA também exige cuidado.
3. **Internações:** produto desejável (acesso) ou indesejável (falha da atenção primária)? Uma alternativa é usar internações por condições sensíveis à atenção primária (ICSAP) como indesejável.
4. **Qual eficiência reportar no texto principal:** proposta de VRS corrigida pelo bootstrap, com CRS e escala de apoio, e sensibilidade no material suplementar (como combinado com o Igor).

## Etapa 3 — Experimento com orçamento

1. Gere a tabela de custos por DSEI (seu script de custos do Portal da Transparência: https://portaldatransparencia.gov.br → Despesas → filtre ação 20YP e as unidades gestoras dos DSEIs, ano 2022, valor liquidado).
2. Salve como `dados/custos_dsei_2022.csv` com as colunas `dsei` (nome idêntico ao da base) e `liquidado_saude`.
3. Rode `source("R/04_sensibilidade.R")`. O experimento E8 aparece sozinho na planilha.
4. No texto, deixe claro que o valor vem do município/unidade gestora e não cobre os convênios pagos pelo Fundo Nacional de Saúde.

## Etapa 4 — Selecionar as variáveis externas (segundo estágio)

Variáveis externas explicam a eficiência, mas não entram no DEA (clima, queimadas e saneamento não são escolhas do gestor de saúde).

1. Liste candidatas e a fonte de cada uma:
   - População indígena, % rural, saneamento, renda: Censo 2022 no SIDRA (https://sidra.ibge.gov.br) ou pelo pacote `sidrar`, como no script do Felipe.
   - Focos de queimada: INPE BDQueimadas (https://terrabrasilis.dpi.inpe.br/queimadas/bdqueimadas).
   - Desmatamento: PRODES no TerraBrasilis (https://terrabrasilis.dpi.inpe.br).
   - Uso e cobertura do solo: MapBiomas (https://brasil.mapbiomas.org).
   - Precipitação e temperatura: CHIRPS (https://www.chc.ucsb.edu/data/chirps) ou INMET.
   - Isolamento: distância até a capital ou tempo de viagem até o centro urbano mais próximo.
2. Agregue cada uma por DSEI com a mesma tabela de correspondência (soma para contagens; média ponderada pela população indígena para taxas e médias).
3. Monte uma tabela única com uma coluna `dsei` e rode a matriz de correlação de Spearman, igual à que você fez para os insumos e produtos. Retire uma de cada par com |ρ| ≥ 0,75.
4. Com 25 DSEIs, o modelo do segundo estágio comporta poucas variáveis (regra prática: no máximo 3 ou 4).

## Etapa 5 — Segundo estágio (Tobit)

1. Use a coluna `ineficiencia_tobit_vrs` (ou os arquivos `boot_resultados_*_2022.xlsx`, no formato que o script `Analise_Tobit_EffCorrigida.R` do Felipe espera).
2. Troque `COD_MUN` por `dsei` como chave de junção.
3. Com poucas DMUs, o LASSO do Felipe pode zerar tudo ou ficar instável; compare com um Tobit simples com as 3-4 variáveis escolhidas na etapa 4.
4. Discuta a literatura: Simar & Wilson (2007) recomendam regressão truncada com bootstrap duplo em vez de Tobit. Vale perguntar ao Felipe por que ele escolheu Tobit e citar a escolha.

## Etapa 6 — Análise por DSEI (o que o Igor pediu)

Para os DSEIs no fim do ranking (Altamira, Vilhena, Xingu, Alto Rio Juruá), use a aba `alvos_vrs` para mostrar quanto falta em cada produto e quais DSEIs servem de referência (`pares_vrs`). Isso é o que conversa com o gestor: onde agir e com quem aprender.
