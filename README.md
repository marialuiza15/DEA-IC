# DEA-IC: Eficiência dos Distritos Sanitários Especiais Indígenas (DSEI)

Iniciação Científica, Departamento de Engenharia Industrial (PUC-Rio), Projeto Conexão Saúde Alto Xingu.

Este repositório aplica aos DSEIs da Amazônia Legal o mesmo primeiro estágio do artigo de Oliveira et al. (DEA + bootstrap de Simar & Wilson), que no original usava municípios como DMU. O segundo estágio (Tobit com variáveis externas) é o próximo passo do projeto (ver `docs/PROXIMOS_PASSOS.md`).

## Modelo

| Item | Escolha |
|---|---|
| DMU | DSEI (25 distritos da Amazônia Legal), ano 2022 |
| Insumos | `n_estab_indigenas` (estrutura física), `eti_total` (força de trabalho em equivalente tempo integral) |
| Produtos | `nv_ind_7mais_consult` (nascidos vivos indígenas com 7+ consultas de pré-natal), `internacoes_indigenas` |
| Orientação | Produto, como no artigo |
| Retornos de escala | CRS (eficiência produtiva), VRS (técnica) e escala = CRS/VRS |
| Bootstrap | 1000 réplicas, IC 95%, semente 123 (`Benchmarking::dea.boot`) |
| Graus de liberdade | 25 DMUs ≥ max(m×s, 3(m+s)) = 12 |

As variáveis foram escolhidas na reunião de seleção com o orientador e o Luis Felipe (correlação de Spearman, limite |ρ| ≥ 0,75).

## Como rodar

Pré-requisitos: R (https://cran.r-project.org) e, se quiser, RStudio (https://posit.co/download/rstudio-desktop/) ou VS Code com a extensão R.

```r
setwd("C:/caminho/para/DEA-IC")          # a pasta deste repositório
source("R/00_instalar_pacotes.R")        # só na primeira vez
source("R/rodar_tudo.R")                 # roda 02, 03 e 04 (menos de 1 minuto)
```

Ou um por vez:

```r
source("R/02_montar_base_dsei.R")        # dados brutos -> 1 linha por DSEI
source("R/03_dea_bootstrap.R")           # DEA + bootstrap (modelo principal)
source("R/04_sensibilidade.R")           # experimentos de sensibilidade
```

## Estrutura

```
R/
  00_instalar_pacotes.R   pacotes (Benchmarking, dplyr, tidyr, readr, writexl, ggplot2)
  01_config.R             parâmetros: códigos, variáveis do modelo, bootstrap, faixas
  02_montar_base_dsei.R   equivale ao "Importação_Dados_Atual_2022.R" do Felipe
  03_dea_bootstrap.R      equivale ao "Analise_DEA_Bootstrap_Completo.R" do Felipe
  04_sensibilidade.R      tira/acrescenta variáveis e compara fronteira e ranking
  rodar_tudo.R            roda 02, 03 e 04 em sequência
dados/
  brutos/                 microdados já filtrados (CNES dez/2022, SIH, SIM, SINASC, Censo 2022)
  correspondencia_municipio_dsei.csv   município -> DSEI (com peso)
  df_final_DEA_DSEI_2022.csv           base do modelo (gerada pelo 02)
resultados/
  03_resultados_dea_dsei_2022.xlsx     planilha principal (comece pela aba leia_me)
  04_sensibilidade_dea_2022.xlsx
  eficiencia_dea_2022.xlsx, boot_resultados_crs_2022.xlsx, boot_resultados_vrs_2022.xlsx
                                       mesmo formato do Felipe, para o script Tobit dele
  fig_03_*.png, fig_04_*.png
docs/
  PROXIMOS_PASSOS.md      roteiro detalhado das próximas etapas
```

## Como cada variável é calculada

| Variável | Cálculo | Fonte |
|---|---|---|
| `n_estab_indigenas` | Nº de CNES distintos com `TP_UNID = 72` ou com pelo menos um AIS (CBO 515125) ou AISAN (515130). O estabelecimento vai para o DSEI do seu município | CNES-ST + CNES-PF, dez/2022 |
| `eti_total` | (HORAOUTR + HORAHOSP + HORA_AMB de todos os vínculos desses estabelecimentos) / 40 | CNES-PF, dez/2022 |
| `nv_ind_7mais_consult` | Nascidos vivos com `RACACOR = 5` e `CONSULTAS = 4` (7 ou mais), por município de residência | SINASC 2022 |
| `internacoes_indigenas` | AIHs com `RACA_COR = 05`, por município de residência | SIH-RD 2022 |

Variáveis municipais vão para o DSEI pela tabela de correspondência; município compartilhado entre dois DSEIs é dividido pelo `peso`.

## Como ler o escore

- **F** (Farrell, ≥ 1) é o que o pacote Benchmarking devolve na orientação a produto: quanto os produtos poderiam ser multiplicados com os mesmos insumos.
- **te = 1/F** (entre 0 e 1) é o escore apresentado nas planilhas e usado nas faixas do artigo. Exemplo: te = 0,80 → o DSEI poderia produzir 1/0,80 = 25% a mais com os mesmos insumos.
- Sufixo `_bc` = corrigido pelo viés no bootstrap. O IC 95% é do escore corrigido e normalmente não contém o escore original do DEA (isso é esperado: o DEA superestima a eficiência).
- `te_escala_bc` pode passar de 1 porque CRS e VRS são corrigidos em bootstraps separados; leia > 1 como "sem ineficiência de escala".
- `ineficiencia_tobit_*` = F corrigido − 1, a variável dependente usada no script Tobit do Felipe.

## Diferenças em relação ao script do Felipe (e por quê)

1. **Sem normalização min-max no modelo principal.** O DEA já é invariante à unidade de medida, então a normalização não é necessária. A min-max também desloca a origem (x − min), e o modelo CRS não é invariante a esse deslocamento: o DSEI com o menor valor de uma variável vira 1e-16 e seu escore muda muito. Nos nossos dados, a correlação de Spearman entre os escores CRS com e sem min-max é só 0,51 (Kaiapó do Mato Grosso cai de 0,63 para 0,00), e o bootstrap CRS com os dados normalizados não roda ("Model has not been optimized"). No VRS orientado a produto a diferença é pequena (Spearman = 1,00). A réplica exata com min-max continua no script (especificação A, aba `replica_felipe_A`, figura `fig_03_comparacao_normalizacao.png`). **Decisão a validar com o Felipe.**
2. **Uma competência do CNES (dez/2022)** em vez de somar 12 meses, para não contar cada profissional 12 vezes.
3. **Escore apresentado como 1/F**, que é o que o artigo usa nas faixas. Os arquivos no formato do Felipe mantêm F.

## Principais resultados (2022)

- **Fronteira:** 8 dos 25 DSEIs têm eficiência técnica (VRS) igual a 1 no DEA; 3 têm eficiência produtiva (CRS) igual a 1 (Alto Rio Solimões, Médio Rio Solimões e Afluentes, Yanomami).
- **Médias:** eficiência técnica de 68,5% no DEA e 55,7% corrigida pelo bootstrap; produtiva de 60,1% e 50,6%; escala de 89,2% e 91,6%. A maior parte da ineficiência é técnica (uso dos recursos), não de escala.
- **O bootstrap desempata a fronteira:** os 8 DSEIs com escore 1 no DEA passam a ter escores corrigidos entre 72% e 85%, com Kaiapó do Pará, Médio Rio Solimões e Afluentes e Xavante no topo.
- **DSEI Xingu:** 23º de 25, eficiência técnica de 34,3% (30,0% corrigida, IC 95% de 26,8% a 33,5%). Os DSEIs de referência (Alto Rio Negro, Kaiapó do Pará e Yanomami) indicam que, com os mesmos insumos, ele poderia ter cerca de 236 nascidos vivos com 7+ consultas (observado: 81) e 1.313 internações (observado: 450). Retorno de escala decrescente.
- **Sensibilidade** (Spearman do ranking corrigido com o modelo base): estável sem estabelecimentos (0,99), com VINC AISAN (0,99) e com VINC médicos (0,99). Muda muito sem um dos produtos (0,50 a 0,71), o que mostra que cada produto mede uma dimensão diferente. Incluir óbitos em números absolutos inverte o ranking (0,12): DSEIs pequenos têm poucos óbitos por serem pequenos, então a variável mede tamanho, não desempenho. Se óbitos entrarem, precisam ser uma taxa.

## Limitações conhecidas

- **A correspondência município → DSEI ainda precisa ser conferida nos PDSIs.** A coluna `confianca` do CSV marca 32 municípios com confiança baixa. Os resultados dependem dela.
- Os produtos vêm de bases por município de residência e raça/cor, então incluem indígenas em área urbana que não são atendidos pelo subsistema, e dependem da qualidade do preenchimento de raça/cor.
- A produção da atenção primária nas aldeias fica no SIASI, que não é público.
- Internação como produto desejável é discutível: pode indicar acesso, mas também falha da atenção primária.
- O orçamento (`liquidado_saude`) não está nestes dados. O script 04 roda o experimento E8 automaticamente se existir `dados/custos_dsei_2022.csv` (colunas `dsei`, `liquidado_saude`).

## Referência

Oliveira, L. F. A. et al. (2025). *Socio-Economic Planning Sciences* (arquivo `1-s2.0-S0038012125001065-main.pdf`). Confira a referência completa no PDF antes de citar.
