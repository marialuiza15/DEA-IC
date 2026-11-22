# =============================================================================
# 04_sensibilidade.R
# Análise de sensibilidade combinada na reunião com o Igor: mudar a lista de
# variáveis e ver se a FRONTEIRA e o RANKING mudam (ou só o valor do escore).
# Todos os experimentos: VRS, orientação produto, unidades originais,
# bootstrap com as mesmas configurações do script 03.
#
#   E0 base                     estab + ETI  ->  NV 7+ consultas + internações
#   E1 sem estabelecimentos     tira um insumo de cada vez (leave-one-out)
#   E2 sem ETI
#   E3 sem NV 7+ consultas      tira um produto de cada vez
#   E4 sem internações
#   E5 + VINC AISAN             volta com variáveis que tinham saído
#   E6 + VINC médicos
#   E7 + óbitos indígenas       produto indesejável, transformado como no
#                               artigo (Seiford & Zhu): max(óbitos) - óbitos + 1
#   E8 + liquidado saúde        só roda se existir dados/custos_dsei_2022.csv
#                               (colunas: dsei, liquidado_saude)
#
# Entrada : dados/df_final_DEA_DSEI_2022.csv
# Saídas  : resultados/04_sensibilidade_dea_2022.xlsx
#           resultados/fig_04_sensibilidade_ranking.png
# =============================================================================

source(file.path("R", "01_config.R"))
suppressPackageStartupMessages({ library(Benchmarking); library(writexl); library(ggplot2) })

base <- read_csv(ARQ_BASE_DEA, show_col_types = FALSE) %>%
  mutate(obitos_T = max(obitos_indigenas) - obitos_indigenas + 1)

arq_custos <- file.path("dados", "custos_dsei_2022.csv")
tem_custos <- file.exists(arq_custos)
if (tem_custos) {
  base <- base %>% left_join(read_csv(arq_custos, show_col_types = FALSE) %>%
                               select(dsei, liquidado_saude), by = "dsei")
}

EXP <- list(
  E0_base              = list(ins = INSUMOS, prod = PRODUTOS),
  E1_sem_estab         = list(ins = "eti_total", prod = PRODUTOS),
  E2_sem_eti           = list(ins = "n_estab_indigenas", prod = PRODUTOS),
  E3_sem_nv7           = list(ins = INSUMOS, prod = "internacoes_indigenas"),
  E4_sem_internacoes   = list(ins = INSUMOS, prod = "nv_ind_7mais_consult"),
  E5_mais_vinc_aisan   = list(ins = c(INSUMOS, "vinc_aisan"), prod = PRODUTOS),
  E6_mais_vinc_medicos = list(ins = c(INSUMOS, "vinc_medicos"), prod = PRODUTOS),
  E7_mais_obitos       = list(ins = INSUMOS, prod = c(PRODUTOS, "obitos_T"))
)
if (tem_custos) EXP$E8_mais_liquidado <- list(ins = c(INSUMOS, "liquidado_saude"), prod = PRODUTOS)

# Variáveis com zero em insumo atrapalham o DEA: avisar
for (e in names(EXP)) {
  z <- sapply(EXP[[e]]$ins, function(v) sum(base[[v]] == 0))
  if (any(z > 0)) message("Aviso ", e, ": insumos com zero -> ",
                          paste0(names(z)[z > 0], " (", z[z > 0], " DSEIs)", collapse = ", "))
}

rodar <- function(cfg) {
  X <- as.matrix(base[, cfg$ins]); Y <- as.matrix(base[, cfg$prod])
  e <- dea(X, Y, RTS = "vrs", ORIENTATION = ORIENTACAO)
  set.seed(SEMENTE)
  b <- dea.boot(X, Y, NREP = N_BOOT, RTS = "vrs", ORIENTATION = ORIENTACAO, alpha = ALPHA)
  tibble(dsei = base$dsei, te_vrs = 1 / eff(e), te_vrs_bc = 1 / b$eff.bc)
}

res <- bind_rows(lapply(names(EXP), function(nm) {
  message("Rodando ", nm, " ...")
  rodar(EXP[[nm]]) %>% mutate(experimento = nm)
})) %>%
  group_by(experimento) %>%
  mutate(ranking = rank(-te_vrs_bc, ties.method = "min"),
         fronteira = te_vrs >= 1 - TOL) %>% ungroup()

ref <- res %>% filter(experimento == "E0_base") %>%
  select(dsei, te0 = te_vrs, bc0 = te_vrs_bc, rk0 = ranking, fr0 = fronteira)

resumo <- res %>% left_join(ref, by = "dsei") %>%
  group_by(experimento) %>%
  summarise(
    insumos  = paste(EXP[[first(experimento)]]$ins, collapse = " + "),
    produtos = paste(EXP[[first(experimento)]]$prod, collapse = " + "),
    n_fronteira_vrs   = sum(fronteira),
    media_te_vrs      = mean(te_vrs),
    media_te_vrs_bc   = mean(te_vrs_bc),
    spearman_dea_vs_base = cor(te_vrs, te0, method = "spearman"),
    spearman_bc_vs_base  = cor(te_vrs_bc, bc0, method = "spearman"),
    maior_mudanca_posicoes = max(abs(ranking - rk0)),
    quem_mais_mudou   = ifelse(max(abs(ranking - rk0)) == 0, "-",
                               paste(dsei[abs(ranking - rk0) == max(abs(ranking - rk0))], collapse = "; ")),
    entraram_fronteira = paste(dsei[fronteira & !fr0], collapse = "; "),
    sairam_fronteira   = paste(dsei[!fronteira & fr0], collapse = "; "),
    posicao_destaque   = ranking[dsei == DSEI_DESTAQUE],
    te_vrs_bc_destaque = te_vrs_bc[dsei == DSEI_DESTAQUE],
    .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)),
         across(c(entraram_fronteira, sairam_fronteira), ~ ifelse(.x == "", "-", .x)))
names(resumo)[names(resumo) == "posicao_destaque"]   <- paste0("posicao_", DSEI_DESTAQUE)
names(resumo)[names(resumo) == "te_vrs_bc_destaque"] <- paste0("te_vrs_bc_", DSEI_DESTAQUE)

largo <- function(col) res %>% select(dsei, experimento, all_of(col)) %>%
  pivot_wider(names_from = experimento, values_from = all_of(col)) %>%
  left_join(ref %>% select(dsei, rk0), by = "dsei") %>% arrange(rk0) %>% select(-rk0)

write_xlsx(list(
  resumo        = resumo,
  escore_vrs    = largo("te_vrs") %>% mutate(across(where(is.numeric), ~ round(.x, 4))),
  escore_vrs_bc = largo("te_vrs_bc") %>% mutate(across(where(is.numeric), ~ round(.x, 4))),
  ranking_bc    = largo("ranking")
), file.path(PASTA_RESULTADOS, "04_sensibilidade_dea_2022.xlsx"))

# Figura: posição de cada DSEI em cada experimento
g <- res %>% left_join(ref %>% select(dsei, rk0), by = "dsei") %>%
  mutate(dsei = reorder(dsei, -rk0),
         experimento = factor(experimento, levels = names(EXP))) %>%
  ggplot(aes(experimento, dsei, fill = ranking)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = ranking), size = 3) +
  scale_fill_gradient(low = "#2b6a99", high = "#f2f2f2", name = "Posição") +
  labs(x = NULL, y = NULL, title = "Ranking dos DSEIs em cada experimento (VRS corrigida pelo bootstrap)",
       subtitle = "Linhas ordenadas pelo modelo base (E0). Cor parecida na linha = ranking estável") +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1), panel.grid = element_blank())
ggsave(file.path(PASTA_RESULTADOS, "fig_04_sensibilidade_ranking.png"), g, width = 9.5, height = 7.5, dpi = 200)

message("\n== RESUMO DA SENSIBILIDADE ==")
print(as.data.frame(resumo %>% select(experimento, n_fronteira_vrs, spearman_bc_vs_base,
                                      maior_mudanca_posicoes, quem_mais_mudou)))
if (!tem_custos) message("\n(E8 com liquidado_saude não rodou: falta dados/custos_dsei_2022.csv)")
