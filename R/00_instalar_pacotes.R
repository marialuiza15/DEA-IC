# =============================================================================
# 00_instalar_pacotes.R
# Rode UMA vez só. Instala os pacotes usados pelos scripts 01 a 04.
# Os mesmos pacotes do Felipe (Benchmarking, dplyr, tidyr, writexl) + ggplot2.
# =============================================================================

pacotes <- c("Benchmarking",  # DEA e bootstrap de Simar & Wilson (dea, dea.boot)
             "dplyr", "tidyr", "readr", "tibble",
             "writexl",       # exportar Excel
             "ggplot2")       # figuras

faltando <- setdiff(pacotes, rownames(installed.packages()))
if (length(faltando) > 0) install.packages(faltando)

invisible(lapply(pacotes, library, character.only = TRUE))
message("OK! Pacotes instalados. Versão do Benchmarking: ",
        as.character(packageVersion("Benchmarking")))
