# =============================================================================
# 02_montar_base_dsei.R
# Equivale ao "Importação_Dados_Atual_2022.R" do Felipe, mas com a DMU = DSEI
# (Distrito Sanitário Especial Indígena) em vez de município.
#
# Entrada : dados/brutos/*.rds (CNES-PF, CNES-ST, SINASC, SIH, SIM, SIDRA, dez/2022)
#           dados/correspondencia_municipio_dsei.csv (município -> DSEI, com peso)
# Saída   : dados/df_final_DEA_DSEI_2022.csv (1 linha por DSEI)
#
# Como cada variável é calculada:
#   n_estab_indigenas     nº de CNES distintos com TP_UNID = 72 OU com pelo menos
#                         um AIS/AISAN vinculado. O estabelecimento vai para o
#                         DSEI do seu município (no compartilhado, o de maior peso).
#   eti_total             soma das horas semanais (HORAOUTR + HORAHOSP + HORA_AMB)
#                         de todos os vínculos desses estabelecimentos / 40.
#   nv_ind_7mais_consult  nascidos vivos com RACACOR = 5 e CONSULTAS = 4 (7+),
#                         por município de residência, levados ao DSEI com peso.
#   internacoes_indigenas AIHs do SIH-RD com RACA_COR = 05, por município de
#                         residência, levadas ao DSEI com peso.
#   (extras, só para a sensibilidade) obitos_indigenas, vinc_aisan,
#                         vinc_medicos, pop_indigena.
# =============================================================================

source(file.path("R", "01_config.R"))

# ---- 1. Correspondência município -> DSEI ---------------------------------
corr <- read_csv(ARQ_CORRESP, col_types = cols(.default = "c"),
                 locale = locale(encoding = "UTF-8")) %>%
  rename_with(~ sub("^\ufeff", "", .x)) %>%
  filter(!is.na(dsei), dsei != "") %>%
  mutate(mun6 = cod6(cod_mun_ibge), peso = coalesce(num(peso), 1))

soma_peso <- corr %>% group_by(mun6) %>% summarise(s = sum(peso), .groups = "drop")
if (any(abs(soma_peso$s - 1) > 1e-6)) {
  stop("Há municípios cujos pesos não somam 1: ",
       paste(soma_peso$mun6[abs(soma_peso$s - 1) > 1e-6], collapse = ", "))
}
message("Correspondência: ", n_distinct(corr$mun6), " municípios, ",
        n_distinct(corr$dsei), " DSEIs")

# Distribui variáveis municipais entre os DSEIs usando o peso
por_municipio <- function(df_mun) {
  df_mun %>%
    inner_join(corr %>% select(mun6, dsei, peso), by = "mun6",
               relationship = "many-to-many") %>%
    mutate(across(-c(mun6, dsei, peso), ~ .x * peso)) %>%
    select(-mun6, -peso) %>%
    group_by(dsei) %>%
    summarise(across(everything(), ~ sum(.x, na.rm = TRUE)), .groups = "drop")
}

# ---- 2. INSUMOS (CNES, competência dez/2022) -------------------------------
pf <- ler_brutos("cnes_pf")
st <- ler_brutos("cnes_st")

por_tipo <- st %>% filter(as.character(TP_UNID) %in% TP_UNID_INDIGENA) %>%
  distinct(CNES, CODUFMUN)
por_ais  <- pf %>% filter(CBO %in% c(CBO_AIS, CBO_AISAN)) %>%
  distinct(CNES, CODUFMUN)
estab <- bind_rows(por_tipo, por_ais) %>% distinct(CNES, .keep_all = TRUE) %>%
  mutate(mun6 = cod6(CODUFMUN))

dsei_principal <- corr %>% group_by(mun6) %>%
  slice_max(peso, n = 1, with_ties = FALSE) %>% ungroup() %>% select(mun6, dsei)
estab <- estab %>% left_join(dsei_principal, by = "mun6")
message("Estabelecimentos indígenas identificados: ", nrow(estab),
        " | sem DSEI (município fora da correspondência): ", sum(is.na(estab$dsei)))
estab <- estab %>% filter(!is.na(dsei))

insumos <- pf %>%
  inner_join(estab %>% select(CNES, dsei), by = "CNES") %>%
  mutate(horas = coalesce(num(HORAOUTR), 0) + coalesce(num(HORAHOSP), 0) +
                 coalesce(num(HORA_AMB), 0)) %>%
  group_by(dsei) %>%
  summarise(n_estab_indigenas = n_distinct(CNES),
            eti_total         = sum(horas) / HORAS_ETI,
            vinc_aisan        = sum(CBO == CBO_AISAN),
            vinc_medicos      = sum(substr(CBO, 1, 4) %in% CBO_MEDICO),
            .groups = "drop")

# ---- 3. PRODUTOS (por município de residência) ----------------------------
nv <- ler_brutos("sinasc") %>%
  mutate(mun6 = cod6(CODMUNRES)) %>%
  group_by(mun6) %>%
  summarise(nv_ind_7mais_consult = sum(RACACOR %in% RACA_INDIGENA_SINASC_SIM &
                                       CONSULTAS %in% CONSULTAS_7MAIS),
            .groups = "drop") %>%
  por_municipio()

intern <- ler_brutos("sih") %>%
  mutate(mun6 = cod6(MUNIC_RES)) %>%
  group_by(mun6) %>%
  summarise(internacoes_indigenas = sum(RACA_COR %in% RACA_INDIGENA_SIH), .groups = "drop") %>%
  por_municipio()

obitos <- ler_brutos("sim") %>%
  mutate(mun6 = cod6(CODMUNRES)) %>%
  group_by(mun6) %>%
  summarise(obitos_indigenas = sum(RACACOR %in% RACA_INDIGENA_SINASC_SIM), .groups = "drop") %>%
  por_municipio()

# ---- 4. População indígena (Censo 2022) - só para contexto ----------------
censo <- ler_brutos("sidra_censo2022_raca")
col_mun  <- grep("^Munic.*\\(C", names(censo), value = TRUE)[1]
col_raca <- grep("^Cor ou ra.a$", names(censo), value = TRUE)[1]   # coluna do nome, não do código
pop <- censo %>%
  transmute(mun6 = cod6(.data[[col_mun]]), raca = .data[[col_raca]], valor = num(Valor)) %>%
  group_by(mun6) %>%
  summarise(pop_indigena = sum(valor[grepl("^Ind", raca)], na.rm = TRUE), .groups = "drop") %>%
  por_municipio()

# ---- 5. Base final (mesma lógica do df_final_DEA do Felipe) ----------------
base <- insumos %>%
  full_join(nv, by = "dsei") %>%
  full_join(intern, by = "dsei") %>%
  full_join(obitos, by = "dsei") %>%
  full_join(pop, by = "dsei") %>%
  select(dsei, all_of(INSUMOS), all_of(PRODUTOS),
         obitos_indigenas, vinc_aisan, vinc_medicos, pop_indigena) %>%
  arrange(dsei)

faltando <- base %>% filter(if_any(all_of(c(INSUMOS, PRODUTOS)), is.na))
if (nrow(faltando) > 0) {
  stop("DSEIs com NA em variáveis do modelo (o DEA não aceita NA): ",
       paste(faltando$dsei, collapse = ", "))
}

write_csv(base, ARQ_BASE_DEA)
message("\nBase salva em ", ARQ_BASE_DEA, " (", nrow(base), " DSEIs)")
print(as.data.frame(base %>% mutate(across(where(is.numeric), ~ round(.x, 1)))))
