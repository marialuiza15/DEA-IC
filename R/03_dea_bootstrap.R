# =============================================================================
# 03_dea_bootstrap.R
# Primeiro estágio do artigo do Felipe (Oliveira et al.), aplicado aos DSEIs:
#   DEA orientado a produto, CRS e VRS, + bootstrap de Simar & Wilson (1000
#   réplicas) -> eficiências corrigidas pelo viés e intervalos de confiança.
# Segue o script "Analise_DEA_Bootstrap_Completo.R" (pacote Benchmarking).
#
# Duas especificações, lado a lado:
#   A_replica_felipe : dados com normalização min-max e 0 -> 1e-16 (como no artigo)
#   B_unidades_orig  : dados nas unidades originais (MODELO PRINCIPAL recomendado)
#   Motivo: o DEA já é invariante à unidade de medida, então não precisa de
#   normalização. A min-max desloca a origem (x - min), e o CRS não é invariante
#   a deslocamento: o DSEI com o menor valor vira 1e-16 e o escore muda muito.
#   Com 25 DMUs, o bootstrap CRS nem chega a rodar com os dados normalizados.
#
# Leitura do escore (Benchmarking, orientação "out"):
#   F  = eficiência de Farrell (>= 1): quanto os produtos poderiam ser
#        multiplicados com os mesmos insumos. F = 1,25 -> +25% de produto.
#   TE = 1/F (entre 0 e 1, em %): é o escore usado nas faixas do artigo.
#   Escala = TE_CRS / TE_VRS.  Ineficiência para o Tobit = F - 1 (como o Felipe).
#
# Entrada : dados/df_final_DEA_DSEI_2022.csv (script 02)
# Saídas  : resultados/03_resultados_dea_dsei_2022.xlsx (planilha principal)
#           resultados/eficiencia_dea_2022.xlsx, boot_resultados_crs_2022.xlsx,
#           boot_resultados_vrs_2022.xlsx (mesmo formato do Felipe -> Tobit)
#           resultados/fig_03_*.png
# =============================================================================

source(file.path("R", "01_config.R"))
suppressPackageStartupMessages({ library(Benchmarking); library(writexl); library(ggplot2) })

base <- read_csv(ARQ_BASE_DEA, show_col_types = FALSE)
X <- as.matrix(base[, INSUMOS]);  rownames(X) <- base$dsei
Y <- as.matrix(base[, PRODUTOS]); rownames(Y) <- base$dsei
n <- nrow(base); m <- length(INSUMOS); s <- length(PRODUTOS)

# Regra prática de graus de liberdade (Cooper et al.): n >= max(m*s, 3*(m+s))
minimo_dmus <- max(m * s, 3 * (m + s))
message(sprintf("DMUs: %d | insumos: %d | produtos: %d | mínimo recomendado: %d -> %s",
                n, m, s, minimo_dmus, ifelse(n >= minimo_dmus, "OK", "ATENÇÃO")))

# ---- 1. Função que roda uma especificação completa -------------------------
rodar_dea <- function(X, Y, nome) {
  e_crs  <- dea(X, Y, RTS = "crs", ORIENTATION = ORIENTACAO)
  e_vrs  <- dea(X, Y, RTS = "vrs", ORIENTATION = ORIENTACAO)
  e_nirs <- dea(X, Y, RTS = "drs", ORIENTATION = ORIENTACAO)  # "drs" = não crescentes

  boot <- function(rts) {
    set.seed(SEMENTE)
    tryCatch(dea.boot(X, Y, NREP = N_BOOT, RTS = rts, ORIENTATION = ORIENTACAO, alpha = ALPHA),
             error = function(err) {
               message("  [", nome, "] bootstrap ", toupper(rts), " falhou: ", conditionMessage(err))
               NULL
             })
  }
  list(nome = nome, X = X, Y = Y,
       crs = e_crs, vrs = e_vrs, nirs = e_nirs,
       boot_crs = boot("crs"), boot_vrs = boot("vrs"))
}

message("\nRodando A (réplica do Felipe, min-max)...")
res_A <- rodar_dea(normalizar_matriz(X), normalizar_matriz(Y), "A_replica_felipe")
message("Rodando B (unidades originais, modelo principal)...")
res_B <- rodar_dea(X, Y, "B_unidades_orig")

# ---- 2. Tabela de resultados de uma especificação --------------------------
tabela_resultados <- function(r) {
  F_crs <- eff(r$crs); F_vrs <- eff(r$vrs); F_nirs <- eff(r$nirs)
  ret <- case_when(abs(F_crs - F_vrs) < TOL  ~ "Constante (CRS)",
                   abs(F_nirs - F_vrs) < TOL ~ "Decrescente (DRS)",
                   TRUE                      ~ "Crescente (IRS)")
  out <- tibble(
    dsei       = base$dsei,
    te_crs     = 1 / F_crs,             # eficiência produtiva
    te_vrs     = 1 / F_vrs,             # eficiência técnica
    te_escala  = F_vrs / F_crs,         # = te_crs / te_vrs
    retorno_escala = ret)
  if (!is.null(r$boot_vrs)) {
    out <- out %>% mutate(
      te_vrs_bc  = 1 / r$boot_vrs$eff.bc,
      ic_inf_vrs = 1 / r$boot_vrs$conf.int[, 2],  # inverter troca os limites
      ic_sup_vrs = 1 / r$boot_vrs$conf.int[, 1])
  }
  if (!is.null(r$boot_crs)) {
    out <- out %>% mutate(
      te_crs_bc  = 1 / r$boot_crs$eff.bc,
      ic_inf_crs = 1 / r$boot_crs$conf.int[, 2],
      ic_sup_crs = 1 / r$boot_crs$conf.int[, 1])
  }
  if (!is.null(r$boot_vrs) && !is.null(r$boot_crs)) {
    out <- out %>% mutate(te_escala_bc = te_crs_bc / te_vrs_bc)
  }
  out
}

tab_A <- tabela_resultados(res_A)
tab_B <- tabela_resultados(res_B)

# ---- 3. Resultado principal (B) com ranking, faixas e pares ----------------
pares_txt <- function(e) {
  L <- lambda(e)
  apply(L, 1, function(l) {
    l <- l[l > 1e-6]
    nm  <- sub("^L_?", "", names(l))        # "L3" (índice) ou "L_Xingu" (nome)
    idx <- suppressWarnings(as.integer(nm))
    nomes <- ifelse(is.na(idx), nm, base$dsei[idx])
    paste0(nomes, " (", format(round(l, 2), decimal.mark = ","), ")", collapse = "; ")
  })
}

principal <- tab_B %>%
  mutate(
    ranking_vrs_bc   = rank(-te_vrs_bc, ties.method = "min"),
    faixa_vrs        = faixa_eficiencia(te_vrs),
    faixa_vrs_bc     = faixa_eficiencia(te_vrs_bc),
    faixa_crs_bc     = faixa_eficiencia(te_crs_bc),
    faixa_escala_bc  = faixa_eficiencia(te_escala_bc),
    fronteira_vrs    = te_vrs >= 1 - TOL,
    expansao_vrs_pct = 100 * (eff(res_B$vrs) - 1),
    pares_vrs        = ifelse(fronteira_vrs, "(está na fronteira)", pares_txt(res_B$vrs)),
    ineficiencia_tobit_vrs = res_B$boot_vrs$eff.bc - 1,   # como no script Tobit do Felipe
    ineficiencia_tobit_crs = res_B$boot_crs$eff.bc - 1
  ) %>%
  relocate(ranking_vrs_bc, dsei) %>%
  arrange(ranking_vrs_bc)

# Alvos: quanto cada DSEI deveria produzir para chegar na fronteira VRS
# (expansão radial F x produto observado + folgas de produto)
folgas <- slack(X, Y, res_B$vrs)
alvo <- sweep(Y, 1, eff(res_B$vrs), `*`) + folgas$sy
alvos <- tibble(dsei = base$dsei,
                nv7_obs = Y[, 1], nv7_alvo = round(alvo[, 1]),
                intern_obs = Y[, 2], intern_alvo = round(alvo[, 2]),
                folga_estab = round(folgas$sx[, 1], 1),
                folga_eti   = round(folgas$sx[, 2], 1)) %>%
  mutate(nv7_falta = nv7_alvo - nv7_obs, intern_falta = intern_alvo - intern_obs) %>%
  left_join(principal %>% select(dsei, ranking_vrs_bc, te_vrs), by = "dsei") %>%
  mutate(te_vrs = round(te_vrs, 4)) %>%
  relocate(ranking_vrs_bc, dsei, te_vrs) %>% arrange(ranking_vrs_bc)

# ---- 4. Tabelas no formato do artigo (Tabelas 5 e 6) -----------------------
contagem_faixas <- principal %>%
  select(`TE VRS (DEA)` = faixa_vrs, `TE VRS (bootstrap)` = faixa_vrs_bc,
         `TE CRS (bootstrap)` = faixa_crs_bc, `Escala (bootstrap)` = faixa_escala_bc) %>%
  pivot_longer(everything(), names_to = "medida", values_to = "faixa") %>%
  count(medida, faixa, .drop = FALSE) %>%
  pivot_wider(names_from = medida, values_from = n, values_fill = 0)

descr <- function(x) c(media = mean(x), dp = sd(x), min = min(x), mediana = median(x), max = max(x))
descritivas <- bind_rows(
  lapply(list(
    `Produtiva - CRS (DEA)`       = principal$te_crs,
    `Produtiva - CRS (bootstrap)` = principal$te_crs_bc,
    `Técnica - VRS (DEA)`         = principal$te_vrs,
    `Técnica - VRS (bootstrap)`   = principal$te_vrs_bc,
    `Escala (DEA)`                = principal$te_escala,
    `Escala (bootstrap)`          = principal$te_escala_bc),
    function(x) as_tibble_row(round(descr(x), 4))), .id = "eficiencia")

# ---- 5. Comparação A x B (efeito da normalização min-max) ------------------
comparacao <- tab_B %>% select(dsei, B_te_crs = te_crs, B_te_vrs = te_vrs) %>%
  left_join(tab_A %>% select(dsei, A_te_crs = te_crs, A_te_vrs = te_vrs), by = "dsei") %>%
  mutate(dif_crs = A_te_crs - B_te_crs, dif_vrs = A_te_vrs - B_te_vrs) %>%
  arrange(dif_crs)
spearman_AB <- c(
  crs = cor(comparacao$A_te_crs, comparacao$B_te_crs, method = "spearman"),
  vrs = cor(comparacao$A_te_vrs, comparacao$B_te_vrs, method = "spearman"))

# ---- 6. Exportar ------------------------------------------------------------
r4 <- function(df) df %>% mutate(across(where(is.numeric), ~ round(.x, 4)))

leia_me <- tibble(item = c(
  "Modelo", "DMU", "Insumos", "Produtos", "Orientação", "Retornos de escala",
  "Bootstrap", "Escore", "Escala", "Escala corrigida > 1", "Alvos", "Faixas",
  "Ranking", "Graus de liberdade",
  "Especificação A", "Especificação B", "Spearman A x B",
  "Bootstrap da especificação A"),
  descricao = c(
  "DEA + bootstrap de Simar & Wilson, como no artigo de Oliveira et al. (Benchmarking::dea e dea.boot)",
  paste0("DSEI (", n, " distritos da Amazônia Legal), ano ", ANO),
  paste(INSUMOS, collapse = " + "),
  paste(PRODUTOS, collapse = " + "),
  "Produto (output): o gestor não escolhe o tamanho da rede, então o objetivo é produzir mais com o que já tem",
  "CRS (eficiência produtiva), VRS (técnica) e NIRS (só para classificar o retorno de escala)",
  paste0(N_BOOT, " réplicas, alfa = ", ALPHA, ", semente = ", SEMENTE),
  "te = 1/F, entre 0 e 1. te = 0,80 -> o DSEI poderia produzir 1/0,80 = 25% a mais com os mesmos insumos. Sufixo _bc = corrigido pelo viés",
  "te_escala = te_crs / te_vrs. Retorno crescente (IRS) = DSEI pequeno demais; decrescente (DRS) = grande demais",
  "te_escala_bc pode passar de 1 porque CRS e VRS são corrigidos em bootstraps separados (aconteceu no artigo também). Leia > 1 como 'sem ineficiência de escala'",
  "Aba alvos_vrs: produção que o DSEI teria na fronteira VRS (expansão radial + folgas). folga_* = insumo que sobraria mesmo na fronteira",
  "Iguais ao artigo: muito baixa 0-25%, baixa 25-50%, regular 50-75%, alta 75-99,99%, eficiente 100%",
  "Pela eficiência VRS corrigida (bootstrap), que desempata os DSEIs que estão todos em 1 no DEA",
  sprintf("n = %d >= max(m*s, 3(m+s)) = %d", n, minimo_dmus),
  "Réplica exata do Felipe: min-max + 0 -> 1e-16",
  "MODELO PRINCIPAL: unidades originais (o DEA não precisa de normalização)",
  sprintf("CRS = %.2f | VRS = %.2f", spearman_AB["crs"], spearman_AB["vrs"]),
  ifelse(is.null(res_A$boot_crs), "CRS falhou (LP não otimiza com valores 1e-16); VRS rodou", "rodou")))

write_xlsx(list(
  leia_me              = leia_me,
  dados_modelo         = base %>% select(dsei, all_of(INSUMOS), all_of(PRODUTOS)),
  resultado_principal  = r4(principal),
  alvos_vrs            = alvos,
  faixas_tabela5       = contagem_faixas,
  descritivas_tabela6  = descritivas,
  comparacao_A_vs_B    = r4(comparacao),
  replica_felipe_A     = r4(tab_A)
), file.path(PASTA_RESULTADOS, "03_resultados_dea_dsei_2022.xlsx"))

# Arquivos no MESMO formato do Felipe (para reaproveitar o script Tobit).
# Atenção: aqui os valores ficam na escala de Farrell (>= 1), como no original.
write_xlsx(tibble(DMU = base$dsei, eff_crs_22 = eff(res_B$crs), eff_vrs_22 = eff(res_B$vrs),
                  eff_scl_22 = eff(res_B$vrs) / eff(res_B$crs)),
           file.path(PASTA_RESULTADOS, "eficiencia_dea_2022.xlsx"))
salvar_boot_felipe <- function(b, rts) {
  write_xlsx(list(
    Eff_Original    = setNames(tibble(base$dsei, b$eff),    c("DMU", paste0("eff_original_", rts, "_22"))),
    Eff_Corrigida   = setNames(tibble(base$dsei, b$eff.bc), c("DMU", paste0("eff_corrigido_", rts, "_22"))),
    Bias            = setNames(tibble(base$dsei, b$bias),   c("DMU", paste0("bias_", rts, "_22"))),
    Intervalos_Conf = setNames(tibble(base$dsei, b$conf.int[, 1], b$conf.int[, 2]),
                               c("DMU", paste0("ci_low_", rts, "_22"), paste0("ci_up_", rts, "_22")))),
    file.path(PASTA_RESULTADOS, paste0("boot_resultados_", rts, "_2022.xlsx")))
}
salvar_boot_felipe(res_B$boot_crs, "crs")
salvar_boot_felipe(res_B$boot_vrs, "vrs")

# ---- 7. Figuras -------------------------------------------------------------
g1 <- principal %>%
  mutate(dsei = reorder(dsei, te_vrs_bc), destaque = dsei == DSEI_DESTAQUE) %>%
  ggplot(aes(y = dsei)) +
  geom_errorbarh(aes(xmin = ic_inf_vrs, xmax = ic_sup_vrs), height = 0.3, colour = "grey55") +
  geom_point(aes(x = te_vrs, shape = "DEA (original)"), colour = "grey40", size = 2) +
  geom_point(aes(x = te_vrs_bc, colour = destaque, shape = "Bootstrap (corrigida)"), size = 2.6) +
  scale_colour_manual(values = c(`FALSE` = "#2b6a99", `TRUE` = "#d1495b"), guide = "none") +
  scale_shape_manual(values = c(`DEA (original)` = 1, `Bootstrap (corrigida)` = 16), name = NULL) +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1.05)) +
  labs(x = "Eficiência técnica (VRS, orientação produto)", y = NULL,
       title = "Eficiência técnica dos DSEIs, 2022",
       subtitle = paste0("Barras = IC 95% do bootstrap (", N_BOOT, " réplicas). Em vermelho: DSEI ", DSEI_DESTAQUE)) +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(PASTA_RESULTADOS, "fig_03_eficiencia_vrs_bootstrap.png"), g1, width = 8, height = 7.5, dpi = 200)

g2 <- comparacao %>%
  pivot_longer(c(A_te_crs, B_te_crs, A_te_vrs, B_te_vrs),
               names_to = c("esp", "modelo"), names_pattern = "(A|B)_te_(crs|vrs)") %>%
  pivot_wider(names_from = esp, values_from = value) %>%
  mutate(modelo = toupper(modelo)) %>%
  ggplot(aes(B, A)) +
  geom_abline(linetype = 2, colour = "grey60") +
  geom_point(colour = "#2b6a99", size = 2.2) +
  facet_wrap(~ modelo) +
  coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(x = "B: unidades originais", y = "A: min-max (réplica do Felipe)",
       title = "Efeito da normalização min-max no escore",
       subtitle = "Pontos fora da diagonal = DSEIs cujo escore muda só por causa da normalização") +
  theme_minimal(base_size = 11)
ggsave(file.path(PASTA_RESULTADOS, "fig_03_comparacao_normalizacao.png"), g2, width = 8, height = 4.5, dpi = 200)

# ---- 8. Resumo no console ---------------------------------------------------
message("\n== MODELO PRINCIPAL (B) ==")
message("Na fronteira VRS (DEA): ", sum(principal$fronteira_vrs), " de ", n,
        " | na fronteira CRS: ", sum(principal$te_crs >= 1 - TOL))
print(as.data.frame(principal %>% select(ranking_vrs_bc, dsei, te_crs, te_vrs, te_escala,
                                         te_vrs_bc, ic_inf_vrs, ic_sup_vrs, retorno_escala) %>% r4()))
message(sprintf("\nSpearman A x B: CRS = %.2f | VRS = %.2f", spearman_AB["crs"], spearman_AB["vrs"]))
message("Arquivos salvos em ", PASTA_RESULTADOS, "/")
