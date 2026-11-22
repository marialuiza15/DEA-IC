# =============================================================================
# 01_config.R
# Parâmetros do projeto e funções auxiliares. Os outros scripts chamam este
# arquivo com source(); você só edita aqui.
#
# Pasta de trabalho: a RAIZ do repositório (onde está o README.md).
#   No RStudio: abra o arquivo DEA-IC.Rproj ou use Session > Set Working Directory.
#   No VS Code: File > Open Folder > DEA-IC.
# =============================================================================

if (!file.exists(file.path("R", "01_config.R"))) {
  stop("A pasta de trabalho não é a raiz do repositório DEA-IC. ",
       "Use setwd(\"caminho/para/DEA-IC\") antes de rodar.")
}

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(tibble)
})

# ---- 1. Período e pastas ---------------------------------------------------
ANO <- 2022
PASTA_BRUTOS     <- file.path("dados", "brutos")
ARQ_CORRESP      <- file.path("dados", "correspondencia_municipio_dsei.csv")
ARQ_BASE_DEA     <- file.path("dados", "df_final_DEA_DSEI_2022.csv")
PASTA_RESULTADOS <- "resultados"
dir.create(PASTA_RESULTADOS, showWarnings = FALSE, recursive = TRUE)

# ---- 2. Códigos (conferidos nos dicionários do CNES/CBO/SINASC/SIH) --------
TP_UNID_INDIGENA <- "72"          # CNES: Unidade de Atenção à Saúde Indígena
CBO_AIS          <- "515125"      # Agente Indígena de Saúde
CBO_AISAN        <- "515130"      # Agente Indígena de Saneamento
CBO_MEDICO       <- c("2251", "2252", "2253")   # famílias CBO (4 dígitos)
HORAS_ETI        <- 40            # 1 ETI = 40 h/semana
RACA_INDIGENA_SINASC_SIM <- "5"   # RACACOR = 5 (indígena)
RACA_INDIGENA_SIH        <- c("05", "5")
CONSULTAS_7MAIS  <- "4"           # SINASC: CONSULTAS = 4 -> 7 ou mais consultas

# ---- 3. Especificação do modelo DEA (decidida com Igor e Felipe) -----------
INSUMOS  <- c("n_estab_indigenas", "eti_total")
PRODUTOS <- c("nv_ind_7mais_consult", "internacoes_indigenas")

ORIENTACAO <- "out"   # orientado a produto, como no artigo do Felipe
N_BOOT     <- 1000    # réplicas do bootstrap (Simar & Wilson), como no artigo
ALPHA      <- 0.05    # intervalos de confiança de 95%
SEMENTE    <- 123     # mesma semente do Felipe
TOL        <- 1e-6    # escore >= 1 - TOL conta como eficiente
DSEI_DESTAQUE <- "Xingu"

# Faixas de eficiência do artigo (Oliveira et al., seção 4.1)
faixa_eficiencia <- function(e) {
  cut(e, breaks = c(-Inf, 0.25, 0.50, 0.75, 1 - TOL, Inf), right = TRUE,
      labels = c("Muito baixa (0-25%)", "Baixa (25-50%)", "Regular (50-75%)",
                 "Alta (75-99,99%)", "Eficiente (100%)"))
}

# ---- 4. Funções auxiliares -------------------------------------------------
cod6 <- function(x) substr(as.character(x), 1, 6)   # IBGE 7 díg. -> DATASUS 6
num  <- function(x) suppressWarnings(as.numeric(sub(",", ".", as.character(x), fixed = TRUE)))

ler_brutos <- function(prefixo) {
  arqs <- list.files(PASTA_BRUTOS, pattern = paste0("^", prefixo, "_.*\\.rds$"),
                     full.names = TRUE)
  if (length(arqs) == 0) stop("Nenhum arquivo ", prefixo, "_*.rds em ", PASTA_BRUTOS)
  bind_rows(lapply(arqs, readRDS))
}

# Normalização min-max (igual ao script do Felipe) + troca de 0 por 1e-16,
# porque o DEA não lida bem com valores exatamente zero.
normalizar <- function(x) (x - min(x)) / (max(x) - min(x))
normalizar_matriz <- function(M) {
  N <- apply(M, 2, normalizar)
  N[N == 0] <- 1e-16
  N
}
