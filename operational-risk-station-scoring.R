# ============================================================
# Project: Environmental Data Quality Framework for Operational Risk Mitigation
#
# End-to-end workflow for:
#   - Data ingestion
#   - Data validation
#   - Monthly aggregation with completeness threshold
#   - Station filtering based on coverage rules
#   - Quality scoring (5 metrics + total score STRS)
#   - Classification into reliability tiers (5 levels)
#   - Geographic visualization of tiers
#
# Author: Santino Adduca
# ============================================================

# ============================================================
# 1. LIBRARIES
# ============================================================
library(tidyverse)
library(lubridate)
library(maps)
library(patchwork)

# ============================================================
# 2. CONFIGURATION
# ============================================================

# File paths
PATH_METADATA <- "data/raw/PP_PMETobs_v11_metadata.csv"
PATH_DAILY    <- "data/raw/PP_PMETobs_1950_2020_v11d.csv"

# Completeness threshold for considering a month as "complete"
# Used in Seasonal Depth (SD) calculation: a month is "good" if its mean completeness > this threshold
COMPLETENESS_THRESHOLD <- 0.90   # 90% of days in month must have data

# Minimum number of valid years required for a station to be considered? 
# (Not directly used in current scoring, but could be used for filtering)
MIN_VALID_YEARS        <- 10

# Recent activity window: only stations with data in the last N months are kept
ACTIVE_WINDOW_MONTHS   <- 12     # keep stations active in the last 12 months

# Tau parameter for Temporal Depth (TD) score
# Controls how quickly the exponential reward saturates with number of complete years
# TD = 1 - exp(-L / TAU_TD). Higher TAU means slower saturation (more years needed to reach high score)
TAU_TD                 <- 15      # tau for Temporal Depth

# Weights for total score (should sum to 1)
# These determine the relative importance of each quality metric
w_TC <- 0.30   # Total Coverage weight
w_MC <- 0.25   # Mean Completeness weight
w_SD <- 0.15   # Seasonal Depth weight
w_SS <- 0.10   # Seasonal Stability weight
w_TD <- 0.20   # Temporal Depth weight

# Thresholds for reliability tiers (five levels)
TIER_VERY_LOW  <- 0.20   # below this: very low
TIER_LOW       <- 0.40   # 0.20 to <0.40: low
TIER_MODERATE  <- 0.60   # 0.40 to <0.60: moderate
TIER_GOOD      <- 0.80   # 0.60 to <0.80: good
# above TIER_GOOD: very good

OUTPUT_DIR  <- "outputs"
SAVE_OUTPUT <- TRUE    # set to TRUE to export CSV and plots

# ============================================================
# 3. HELPER FUNCTIONS
# ============================================================
# Simple print without timestamp
print_msg <- function(msg) {
  cat(msg, "\n")
}

format_latitude  <- function(x) paste0(abs(x), "°S")
format_longitude <- function(x) paste0(abs(x), "°W")

# ============================================================
# 4. DATA INGESTION
# ============================================================
print_msg("Loading metadata...")
metadata <- read.csv(PATH_METADATA, stringsAsFactors = FALSE)

print_msg("Loading daily precipitation data...")
daily_data <- read.csv(PATH_DAILY, stringsAsFactors = FALSE)
daily_data$Date <- as.Date(daily_data$Date)

world_map <- map_data("world")

# ============================================================
# 5. BASIC VALIDATION
# ============================================================
has_negative_values <- any(daily_data[, -1] < 0, na.rm = TRUE)
max_observed_value  <- max(daily_data[, -1], na.rm = TRUE)

print_msg(paste("Negative values detected:", has_negative_values))
print_msg(paste("Maximum observed value:", round(max_observed_value,2), "mm"))

# ============================================================
# 6. RESHAPE TO LONG FORMAT
# ============================================================
data_long <- daily_data %>%
  pivot_longer(
    cols = -Date,
    names_to = "station_id",
    values_to = "precip"
  )

# ============================================================
# 7. FILTER ACTIVE STATIONS (RECENT ACTIVITY WINDOW)
# ============================================================
max_date    <- max(data_long$Date, na.rm = TRUE)
cutoff_date <- max_date %m-% months(ACTIVE_WINDOW_MONTHS)

active_station_ids <- data_long %>%
  filter(Date >= cutoff_date, !is.na(precip)) %>%
  distinct(station_id) %>%
  pull(station_id)

data_long <- data_long %>%
  filter(station_id %in% active_station_ids)

print_msg(paste("Active stations:", length(active_station_ids), "of", nrow(metadata)))

# ============================================================
# 8. PREPARE SCORING DATASET
# ============================================================
data_scoring <- data_long %>%
  mutate(
    year  = year(Date),
    month = month(Date)
  )

# ============================================================
# 9. TC — TOTAL COVERAGE
# Description: Proportion of days with valid data over the entire station period.
# ============================================================
TC_df <- data_scoring %>%
  group_by(station_id) %>%
  summarise(
    total_days_calendar = as.numeric(max(Date) - min(Date)) + 1,
    total_days_valid    = sum(!is.na(precip)),
    TC = total_days_valid / total_days_calendar,
    .groups = "drop"
  )

# ============================================================
# 10. MONTHLY COMPLETENESS BASE
# ============================================================
monthly_completeness <- data_scoring %>%
  group_by(station_id, year, month) %>%
  summarise(
    n_days_valid  = sum(!is.na(precip)),
    days_in_month = days_in_month(min(Date)),
    completeness  = n_days_valid / days_in_month,
    .groups = "drop"
  )

# ============================================================
# 11. MC — MEAN COMPLETENESS
# Description: Average monthly completeness across all months.
# ============================================================
MC_df <- monthly_completeness %>%
  group_by(station_id) %>%
  summarise(
    MC = mean(completeness, na.rm = TRUE),
    .groups = "drop"
  )

# ============================================================
# 12. SD — SEASONAL DEPTH
# Description: Proportion of months (by calendar month) where mean completeness exceeds the threshold.
# ============================================================
SD_df <- monthly_completeness %>%
  group_by(station_id, month) %>%
  summarise(
    mean_month_comp = mean(completeness, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(station_id) %>%
  summarise(
    SD = mean(mean_month_comp > COMPLETENESS_THRESHOLD),
    .groups = "drop"
  )

# ============================================================
# 13. SS — SEASONAL STABILITY
# Description: Consistency of completeness across months (1 minus standard deviation of monthly means).
# ============================================================
SS_df <- monthly_completeness %>%
  group_by(station_id, month) %>%
  summarise(
    mean_month_comp = mean(completeness, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(station_id) %>%
  summarise(
    SS = 1 - sd(mean_month_comp, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(SS = pmax(pmin(SS, 1), 0))

# ============================================================
# 14. TD — TEMPORAL DEPTH
# Description: Reward for having many complete years, using an exponential saturation function.
# ============================================================
annual_full <- data_scoring %>%
  group_by(station_id, year) %>%
  summarise(
    n_days_valid = sum(!is.na(precip)),
    days_in_year = ifelse(leap_year(year), 366, 365),
    full_year    = n_days_valid == days_in_year,
    .groups = "drop"
  )

TD_df <- annual_full %>%
  group_by(station_id) %>%
  summarise(
    L  = sum(full_year),
    TD = 1 - exp(-L / TAU_TD),
    .groups = "drop"
  )

# ============================================================
# 15. INTEGRATE METRICS
# ============================================================
all_stations <- data_scoring %>%
  distinct(station_id)

scores <- all_stations %>%
  left_join(TC_df, by = "station_id") %>%
  left_join(MC_df, by = "station_id") %>%
  left_join(SD_df, by = "station_id") %>%
  left_join(SS_df, by = "station_id") %>%
  left_join(TD_df, by = "station_id")

# Replace NAs with 0 (stations with no data at all)
scores <- scores %>%
  mutate(across(c(TC, MC, SD, SS, TD), ~replace_na(., 0)))

# ============================================================
# 16. TOTAL SCORE (STRS)
# ============================================================
scores <- scores %>%
  mutate(
    STRS = w_TC * TC +
      w_MC * MC +
      w_SD * SD +
      w_SS * SS +
      w_TD * TD
  )

# ============================================================
# 17. BUSINESS SEGMENTATION FLAGS (RELIABILITY TIERS - 5 LEVELS)
# ============================================================
scores <- scores %>%
  mutate(
    reliability = case_when(
      STRS >= TIER_GOOD      ~ "Very Good",
      STRS >= TIER_MODERATE  ~ "Good",
      STRS >= TIER_LOW       ~ "Moderate",
      STRS >= TIER_VERY_LOW  ~ "Low",
      TRUE                   ~ "Very Low"
    ),
  ) %>%
  mutate(reliability = factor(reliability, 
                              levels = c("Very Good", "Good", "Moderate", "Low", "Very Low"),
                              ordered = TRUE))

# ============================================================
# 18. ATTACH METADATA
# ============================================================
# Adjust join key if metadata column is different (here assumed "gauge_id")
scores_final <- scores %>%
  left_join(metadata, by = c("station_id" = "gauge_id"))

# ============================================================
# 19. EXECUTIVE DIAGNOSTICS
# ============================================================
print_msg("Final STRS summary:")
print(summary(scores_final$STRS))

print_msg("Reliability tier distribution:")
print(table(scores_final$reliability))

# ============================================================
# 20. CREATE PLOTS: HISTOGRAM, DONUT CHART, AND MAP
# ============================================================

# Define color palette (red -> orange -> yellow -> lightgreen -> darkgreen)
reliability_colors <- c(
  "Very Low"  = "darkred",
  "Low"       = "orange3",
  "Moderate"  = "gold",
  "Good"      = "lightgreen",
  "Very Good" = "darkgreen"
)

# --- Histogram of STRS ---
hist_plot <- ggplot(scores_final, aes(x = STRS)) +
  geom_histogram(binwidth = 0.05, fill = "grey", color = "black", alpha = 0.8) +
  labs(title = "Score distribution", x = "STRS", y = "Count") +
  theme_bw() +
  theme(legend.position = "none")  # no legend needed

# --- Donut chart of reliability tiers ---
tier_counts <- scores_final %>%
  count(reliability) %>%
  mutate(
    proportion = n / sum(n),
    percentage = paste0(round(proportion * 100, 1), "%"),
    label = paste0(reliability, "\n", percentage)
  )

donut_plot <- ggplot(tier_counts, aes(x = 2, y = n, fill = reliability)) +
  geom_bar(stat = "identity", width = 1, color = "black") +
  geom_text(aes(label = percentage),
            position = position_stack(vjust = 0.5),
            color = "black", size = 4, fontface = "bold") +
  coord_polar(theta = "y") +
  scale_fill_manual(values = reliability_colors) +
  xlim(0.5, 2.5) +  # creates the hole
  labs(title = "Distribution of categories") +
  theme_void() +
  theme(legend.position = "none")

# --- Map of stations colored by reliability ---
# Ensure we have latitude and longitude columns in metadata
if (!all(c("gauge_lat", "gauge_lon") %in% colnames(scores_final))) {
  stop("Metadata must contain 'gauge_lat' and 'gauge_lon' columns for mapping.")
}

map_plot <- ggplot() +
  geom_polygon(data = world_map, aes(x = long, y = lat, group = group),
               fill = "gray90", color = "gray50", linewidth = 0.2) +
  geom_point(data = scores_final, 
             aes(x = gauge_lon, y = gauge_lat, fill = reliability),
             size = 2.5, alpha = 0.9, 
             shape = 21,           # circle with border and fill
             stroke = 0.3,         # border thickness
             color = "black") +    # border color
  scale_fill_manual(values = reliability_colors,
                    name = "Reliability",
                    breaks = c("Very Good", "Good", "Moderate", "Low", "Very Low")) +
  coord_quickmap(xlim = range(scores_final$gauge_lon, na.rm = TRUE),
                 ylim = range(scores_final$gauge_lat, na.rm = TRUE)) +
  labs(title = "Geographic distribution",
       x = "Longitude", y = "Latitude") +
  theme_bw() +
  theme(
    panel.grid = element_blank(),
    legend.position = "right"
  )

# --- Combine all three plots into one figure ---
combined_plot <- ((hist_plot / donut_plot) | map_plot) +
  plot_annotation(
    title = "Station Reliability Assessment for Operational Risk Mitigation",
    theme = theme(
      plot.title = element_text(size = 18, face = "bold", hjust = 0.5)
    )
  )

# ============================================================
# 21. EXPORT FOR BI DASHBOARD AND PLOTS
# ============================================================
if (SAVE_OUTPUT) {
  if (!dir.exists(OUTPUT_DIR)) {
    dir.create(OUTPUT_DIR, recursive = TRUE)
  }
  
  # Save scores: BI dataset
  scores_export <- scores_final %>%
    select(
      station_id,
      gauge_name,
      institution,
      gauge_lat,
      gauge_lon,
      gauge_alt,
      total_days_calendar,
      total_days_valid,
      TC, MC, SD, SS, TD,
      STRS,
      reliability
    )
  
  write.csv(scores_export,
            file.path(OUTPUT_DIR, "station_quality_scores.csv"),
            row.names = FALSE)
  
  # Save combined figure
  ggsave(file.path(OUTPUT_DIR, "diagnostic_oprational_risk_dashboard.png"),
         combined_plot, width = 9, height = 9, dpi = 600, bg='white')
  
  print_msg("BI dataset and combined plot exported successfully.")
}

print_msg("Workflow completed.")