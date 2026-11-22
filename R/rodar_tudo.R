# =============================================================================
# rodar_tudo.R - roda o pipeline inteiro (menos de 1 minuto)
# Pasta de trabalho: a raiz do repositório DEA-IC.
# =============================================================================
source(file.path("R", "02_montar_base_dsei.R"))
source(file.path("R", "03_dea_bootstrap.R"))
source(file.path("R", "04_sensibilidade.R"))
message("\nPronto! Abra resultados/03_resultados_dea_dsei_2022.xlsx (aba leia_me).")
