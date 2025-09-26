# ============================================
# CPI kwartaalmutatie berekening script: Koffie & Boeken (StatLine 83131NED, 2015=100)
# - Schrijft volledige 'cpi_quarterly' naar SQLite
# - Console-output toont alléén de laatste relevante kwartaalmutatie (op basis van vandaag)
# ============================================

# Relevante packages (kan weg ge-comment worden indien al geïnstalleerd)
pkgs <- c("cbsodataR","dplyr","ggplot2","DBI","RSQLite","png","grid")
to_install <- setdiff(pkgs, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))

# Variabelen voor Statline API
TBL_ID    <- "83131NED"                           # Consumentenprijzen; prijsindex 2015=100
MEASURE   <- "CPI_1"                              # CPI (2015 = 100)
KEYS      <- c("CPI012110","CPI095100")           # 012110 is voor Koffie, 095100 is voor Boeken
DB_PATH   <- "output/cpi.sqlite"                  # SQLite-bestand als output
SHOW_PLOTS <- TRUE                                 # zet op FALSE als je plots niet live wilt tonen

# Output voor SQLite ----
dir.create(dirname(DB_PATH), recursive = TRUE, showWarnings = FALSE)

# Aanroepen metadata van CPI tabel; 'Bestedingscategorieën' bevat de product-codes en namen
cats <- cbsodataR::cbs_get_meta(TBL_ID)$Bestedingscategorieen |>
  dplyr::select(Key, Title)

# Ophalen van (CPI) maanddata
monthly <- cbsodataR::cbs_get_data(
  TBL_ID,
  select = c("Perioden","Bestedingscategorieen", MEASURE),
  typed  = FALSE
) |>
  dplyr::rename(code = Bestedingscategorieen, index = !!MEASURE) |>
  dplyr::filter(code %in% KEYS, grepl("MM\\d{2}", Perioden)) |>
  dplyr::mutate(index = as.numeric(index)) |>
  dplyr::left_join(cats, by = c("code" = "Key")) |>
  dplyr::rename(Artikel = Title)

# Indien geen match van key of het ontbreken van maanddata, stop het script
stopifnot(nrow(monthly) > 0)

# Berekenen van kwartaalmutaties met beschikbare CPI cijfers
yr  <- as.integer(substr(monthly$Perioden, 1, 4))
mm  <- as.integer(sub(".*MM(\\d{2}).*", "\\1", monthly$Perioden))
qtr <- paste0(yr, "Q", ceiling(mm/3))

quarterly <- monthly |>
  dplyr::mutate(qtr = qtr) |>
  dplyr::group_by(Artikel, qtr) |>
  dplyr::summarise(
    q_index  = mean(index, na.rm = TRUE),
    n_months = dplyr::n(),
    .groups  = "drop"
  ) |>
  dplyr::filter(n_months == 3) |>
  dplyr::arrange(Artikel, qtr) |>
  dplyr::group_by(Artikel) |>
  dplyr::mutate(qoq_pct = (q_index / dplyr::lag(q_index) - 1) * 100) |>
  dplyr::ungroup()

# Bepaal meest up-to-date kwartaal (op dag van schrijven, 24/9/2025, is dit Q2 t.o.v. Q1)
today <- Sys.Date()
y <- as.integer(format(today, "%Y"))
m <- as.integer(format(today, "%m"))
current_q <- (m - 1) %/% 3 + 1
last_year <- if (current_q == 1) y - 1 else y
last_q    <- if (current_q == 1) 4     else current_q - 1
TARGET_QTR <- paste0(last_year, "Q", last_q)

# Selecteer laatste relevante kwartaalmutatie
last_relevant <- quarterly |>
  dplyr::filter(qtr == TARGET_QTR)

# Als TARGET_QTR nog niet in de data zit, pak per artikel de allerlaatste complete
if (!nrow(last_relevant)) {
  last_relevant <- quarterly |>
    dplyr::group_by(Artikel) |>
    dplyr::slice_tail(n = 1) |>
    dplyr::ungroup()
}

# --- NIEUW: plots eerst bouwen (zodat p_last12 en p_qoq4 zeker bestaan) ---

# Voor 12-maands plot: maak Date-kolom (YYYY-MM-01) en filter laatste 12 maanden
if (!"Date" %in% names(monthly)) {
  monthly$Date <- as.Date(sprintf("%s-%s-01",
                                  substr(monthly$Perioden,1,4),
                                  sub(".*MM(\\d{2}).*", "\\1", monthly$Perioden)))
}
max_date <- max(monthly$Date, na.rm = TRUE)
min_date <- min(seq(max_date, length.out = 12, by = "-1 month"))
monthly_12m <- monthly |> dplyr::filter(Date >= min_date)

# Plot 1: CPI laatste 12 maanden
p_last12 <- ggplot2::ggplot(monthly_12m, ggplot2::aes(x = Date, y = index, color = Artikel, group = Artikel)) +
  ggplot2::geom_line() + ggplot2::geom_point() +
  ggplot2::labs(
    title = "CPI laatste 12 maanden",
    subtitle = "Basis: 2015 = 100",
    x = "Maand", y = "Index (2015 = 100)", color = "Artikel"
  ) +
  ggplot2::scale_x_date(date_breaks = "1 month", date_labels = "%Y-%m") +
  ggplot2::theme_minimal() +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

# Plot 2: laatste 4 kwartaalmutaties (QoQ)
quarterly_qoq_last4 <- quarterly |>
  dplyr::filter(!is.na(qoq_pct)) |>
  dplyr::group_by(Artikel) |>
  dplyr::slice_tail(n = 4) |>
  dplyr::ungroup()

p_qoq4 <- ggplot2::ggplot(quarterly_qoq_last4, ggplot2::aes(x = qtr, y = qoq_pct, fill = Artikel)) +
  ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.7), width = 0.6) +
  ggplot2::geom_hline(yintercept = 0, linewidth = 0.4) +
  ggplot2::labs(
    title = "Laatste 4 kwartaalmutaties (QoQ)",
    subtitle = "Basis CPI: 2015 = 100",
    x = "Kwartaal", y = "% t.o.v. vorig kwartaal", fill = "Artikel"
  ) +
  ggplot2::theme_minimal()

# Optioneel: plots live tonen in RStudio
if (SHOW_PLOTS) {
  print(p_last12)
  print(p_qoq4)
}

# SQLite en plot gedeelte

# Zorg dat DBI en RSQLite geladen zijn (al gedaan boven, maar voor de zekerheid)
if (!requireNamespace("DBI", quietly = TRUE))     install.packages("DBI")
if (!requireNamespace("RSQLite", quietly = TRUE)) install.packages("RSQLite")
library(DBI); library(RSQLite)

con <- dbConnect(SQLite(), DB_PATH)

# Schrijf MAANDdata (CPI’s) weg
#    - Date-kolom (YYYY-MM-01) staat er nu in
monthly$loaded_at <- as.character(Sys.time())
dbWriteTable(con, "cpi_monthly", monthly, overwrite = TRUE)

# Schrijf KWARTAALdata (incl. QoQ) weg
quarterly$loaded_at <- monthly$loaded_at[1]
dbWriteTable(con, "cpi_quarterly", quarterly, overwrite = TRUE)

# Sla plots op als BLOBs (PNG-bytes) in tabel 'plots'
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS plots (
    name TEXT PRIMARY KEY,
    image BLOB,
    created_at TEXT
  )
")

# Helper om ggplot naar BLOB te zetten
plot_to_blob <- function(plt, width = 10, height = 5, dpi = 150) {
  tf <- tempfile(fileext = ".png")
  ggplot2::ggsave(tf, plt, width = width, height = height, dpi = dpi)
  raw <- readBin(tf, what = "raw", n = file.info(tf)$size)
  unlink(tf)
  raw
}

# Maak PNG blobs (nu kan dit, want p_last12 en p_qoq4 bestaan)
blob_last12 <- plot_to_blob(p_last12)
blob_qoq4   <- plot_to_blob(p_qoq4)

# SQL queries om PNG-blobs in de SQLite te plaatsen
# Voorkomen van dubbele rijen in de plots tabel (delete + insert)
dbExecute(con, "DELETE FROM plots WHERE name = 'cpi_last_12_months'")
dbExecute(con, "INSERT INTO plots (name, image, created_at) VALUES (?, ?, ?)",
          params = list("cpi_last_12_months", list(blob_last12), as.character(Sys.time())))
dbExecute(con, "DELETE FROM plots WHERE name = 'cpi_qoq_last_4'")
dbExecute(con, "INSERT INTO plots (name, image, created_at) VALUES (?, ?, ?)",
          params = list("cpi_qoq_last_4", list(blob_qoq4), as.character(Sys.time())))

# Benedenstaand is om plots weer uit de SQLite te halen en in R Studio te plotten

# Haal de twee BLOBs op
res_plots <- dbGetQuery(con, "SELECT name, image FROM plots WHERE name IN ('cpi_last_12_months','cpi_qoq_last_4')")

# Sluit DB (we hebben de bytes al binnen)
dbDisconnect(con)

# helper: BLOB > tijdelijke PNG > plotten in R
show_blob_plot <- function(name, blob_raw) {
  tf <- tempfile(fileext = ".png")
  writeBin(blob_raw[[1]], tf)
  img <- png::readPNG(tf)
  grid::grid.newpage()
  grid::grid.raster(img)
  title <- switch(name,
                  "cpi_last_12_months" = "CPI laatste 12 maanden (uit SQLite BLOB)",
                  "cpi_qoq_last_4"     = "Laatste 4 kwartaalmutaties (QoQ) – uit SQLite BLOB",
                  name)
  grid::grid.text(title, x = 0.5, y = 0.96, gp = grid::gpar(fontsize = 12))
  unlink(tf)
}

# Toon beide plots uit de DB
for (i in seq_len(nrow(res_plots))) {
  show_blob_plot(res_plots$name[i], res_plots$image[i])
}

# Voor de console: alleen laatste relevante kwartaalmutatie tonen
cat("\n=== Laatste relevante kwartaalmutatie (t.o.v. vandaag) ===\n")
cat("Doel-kwartaal (target):", TARGET_QTR, "\n")
print(
  last_relevant |>
    dplyr::select(Artikel, qtr, q_index, qoq_pct)
)
cat("\nSQLite geüpdatet op: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    "\nBestand: ", normalizePath(DB_PATH), "\n", sep = "")