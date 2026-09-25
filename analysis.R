#!/usr/bin/env Rscript
# Reproduce the Motor Risk Lab analysis with base R.
# Run from this project directory: Rscript analysis.R
# Source: Dutang & Charpentier, CASdatasets, DOI 10.57745/P0KHAG.

dir.create("data", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

sources <- c(
  freq = "https://raw.githubusercontent.com/dutangc/CASdatasets/227fb56b8734bdb7c0327a41180e01d2ddaeaf26/data/freMTPLfreq.rda",
  sev  = "https://raw.githubusercontent.com/dutangc/CASdatasets/227fb56b8734bdb7c0327a41180e01d2ddaeaf26/data/freMTPLsev.rda"
)
for (name in names(sources)) {
  path <- file.path("data", paste0("freMTPL", name, ".rda"))
  if (!file.exists(path)) download.file(sources[[name]], path, mode = "wb", quiet = TRUE)
  load(path)
}

stopifnot(nrow(freMTPLfreq) == 413169, nrow(freMTPLsev) == 16181)
stopifnot(!anyNA(freMTPLfreq), !anyNA(freMTPLsev))
stopifnot(all(freMTPLfreq$Exposure > 0), all(freMTPLsev$ClaimAmount > 0))
stopifnot(length(unique(freMTPLfreq$PolicyID)) == nrow(freMTPLfreq))
stopifnot(all(freMTPLsev$PolicyID %in% as.integer(as.character(freMTPLfreq$PolicyID))))
stopifnot(sum(freMTPLfreq$ClaimNb) == nrow(freMTPLsev))

freq <- freMTPLfreq
sev <- freMTPLsev
rm(freMTPLfreq, freMTPLsev)
freq$PolicyID <- as.integer(as.character(freq$PolicyID))
claim_count <- tabulate(match(sev$PolicyID, freq$PolicyID), nbins = nrow(freq))
stopifnot(all(claim_count == freq$ClaimNb))

band_driver <- function(x) cut(x, c(-Inf, 25, 35, 55, 70, Inf),
  labels = c("18–25", "26–35", "36–55", "56–70", "71+"))
band_car <- function(x) cut(x, c(-Inf, 2, 7, 15, Inf),
  labels = c("0–2", "3–7", "8–15", "16+"))
band_power <- function(x) cut(match(as.character(x), letters[4:15]),
  c(-Inf, 3, 7, Inf), labels = c("d–f", "g–j", "k–o"))

freq$DriverBand <- band_driver(freq$DriverAge)
freq$CarBand <- band_car(freq$CarAge)
freq$PowerBand <- band_power(freq$Power)
freq$LogDensity <- log1p(freq$Density)
stopifnot(!anyNA(freq$DriverBand), !anyNA(freq$CarBand), !anyNA(freq$PowerBand))

# Split at policy level before attaching claims. A fixed seed makes the test repeatable.
set.seed(20260925)
perm <- sample.int(nrow(freq))
freq$split <- "test"
freq$split[perm[seq_len(floor(.70 * nrow(freq)))]] <- "train"
freq$split[perm[(floor(.70 * nrow(freq)) + 1):floor(.85 * nrow(freq))]] <- "validation"
sev$policy_row <- match(sev$PolicyID, freq$PolicyID)
sev$split <- freq$split[sev$policy_row]
features <- c("DriverBand", "CarBand", "PowerBand", "Gas", "Region", "LogDensity")
for (name in features) sev[[name]] <- freq[[name]][sev$policy_row]

train <- freq$split == "train"
validation <- freq$split == "validation"
test <- freq$split == "test"
sev_train <- sev$split == "train"
sev_validation <- sev$split == "validation"
sev_test <- sev$split == "test"

frequency <- glm(ClaimNb ~ DriverBand + CarBand + PowerBand + Gas +
  Region + LogDensity + offset(log(Exposure)),
  family = poisson(link = "log"), data = freq[train, ])
severity <- glm(ClaimAmount ~ DriverBand + CarBand + PowerBand + Gas + Region,
  family = Gamma(link = "log"), data = sev[sev_train, ])

freq_rate_base <- sum(freq$ClaimNb[train]) / sum(freq$Exposure[train])
sev_mean_base <- mean(sev$ClaimAmount[sev_train])
freq$glm_count <- as.numeric(predict(frequency, newdata = freq, type = "response"))
freq$gamma_severity <- as.numeric(predict(severity, newdata = freq, type = "response"))
freq$base_count <- freq$Exposure * freq_rate_base
freq$base_cost <- freq$base_count * sev_mean_base
sev$gamma_severity <- as.numeric(predict(severity, newdata = sev, type = "response"))

actual_cost <- numeric(nrow(freq))
claim_sums <- rowsum(sev$ClaimAmount, sev$policy_row, reorder = FALSE)
actual_cost[as.integer(rownames(claim_sums))] <- claim_sums[, 1]
freq$actual_cost <- actual_cost

poisson_dev <- function(y, mu) 2 * sum(ifelse(y == 0, mu, y * log(y / mu) - y + mu))
gamma_dev <- function(y, mu) 2 * sum((y - mu) / mu - log(y / mu))

# Choose each component with validation data only. Keep test untouched until now.
valid_freq_model <- poisson_dev(freq$ClaimNb[validation], freq$glm_count[validation])
valid_freq_base <- poisson_dev(freq$ClaimNb[validation], freq$base_count[validation])
valid_sev_model <- gamma_dev(sev$ClaimAmount[sev_validation], sev$gamma_severity[sev_validation])
valid_sev_base <- gamma_dev(sev$ClaimAmount[sev_validation], rep(sev_mean_base, sum(sev_validation)))
use_frequency_model <- valid_freq_model < valid_freq_base
use_severity_model <- valid_sev_model < valid_sev_base
freq$pred_count <- if (use_frequency_model) freq$glm_count else freq$base_count
freq$pred_severity <- if (use_severity_model) freq$gamma_severity else sev_mean_base
freq$pred_cost <- freq$pred_count * freq$pred_severity

metrics <- data.frame(
  key = c("policies", "claims", "exposure_years", "train_policies", "validation_policies",
    "test_policies", "test_claims", "claim_rate", "mean_severity", "train_frequency_rate",
    "train_mean_severity", "use_frequency_model", "use_severity_model",
    "validation_poisson_deviance_model", "validation_poisson_deviance_baseline",
    "validation_gamma_deviance_model", "validation_gamma_deviance_baseline",
    "test_poisson_deviance_model",
    "test_poisson_deviance_baseline", "test_gamma_deviance_model", "test_gamma_deviance_baseline",
    "test_freq_oe", "test_sev_oe", "test_cost_oe", "test_expected_cost",
    "test_actual_cost", "test_cost_oe_baseline", "train_pearson_dispersion",
    "test_mae_cost_model", "test_mae_cost_baseline", "train_claim_mean_severity",
    "validation_claim_mean_severity", "test_claim_mean_severity"),
  value = c(nrow(freq), nrow(sev), sum(freq$Exposure), sum(train),
    sum(freq$split == "validation"), sum(test), sum(sev_test),
    sum(freq$ClaimNb) / sum(freq$Exposure), mean(sev$ClaimAmount),
    freq_rate_base, sev_mean_base, as.integer(use_frequency_model), as.integer(use_severity_model),
    valid_freq_model / sum(validation), valid_freq_base / sum(validation),
    valid_sev_model / sum(sev_validation), valid_sev_base / sum(sev_validation),
    poisson_dev(freq$ClaimNb[test], freq$glm_count[test]) / sum(test),
    poisson_dev(freq$ClaimNb[test], freq$base_count[test]) / sum(test),
    gamma_dev(sev$ClaimAmount[sev_test], sev$gamma_severity[sev_test]) / sum(sev_test),
    gamma_dev(sev$ClaimAmount[sev_test], rep(sev_mean_base, sum(sev_test))) / sum(sev_test),
    sum(freq$ClaimNb[test]) / sum(freq$pred_count[test]),
    sum(sev$ClaimAmount[sev_test]) / sum(if (use_severity_model) sev$gamma_severity[sev_test] else rep(sev_mean_base, sum(sev_test))),
    sum(freq$actual_cost[test]) / sum(freq$pred_cost[test]),
    sum(freq$pred_cost[test]), sum(freq$actual_cost[test]),
    sum(freq$actual_cost[test]) / sum(freq$base_cost[test]),
    sum(residuals(frequency, type = "pearson")^2) / frequency$df.residual,
    mean(abs(freq$actual_cost[test] - freq$pred_cost[test])),
    mean(abs(freq$actual_cost[test] - freq$base_cost[test])),
    mean(sev$ClaimAmount[sev_train]), mean(sev$ClaimAmount[sev_validation]),
    mean(sev$ClaimAmount[sev_test])
  )
)

# Policy bootstrap of held-out observed / expected total cost (model fixed).
set.seed(20260926)
test_rows <- which(test)
ratios <- replicate(400, {
  idx <- sample(test_rows, length(test_rows), replace = TRUE)
  sum(freq$actual_cost[idx]) / sum(freq$pred_cost[idx])
})
metrics <- rbind(metrics, data.frame(key = c("test_cost_oe_ci_low", "test_cost_oe_ci_high"),
  value = as.numeric(quantile(ratios, c(.025, .975)))))

# Calibrate observed and expected counts/costs across test-set predicted risk deciles.
risk <- freq$pred_cost[test] / freq$Exposure[test]
breaks <- unique(quantile(risk, seq(0, 1, .1)))
decile <- cut(risk, breaks = breaks, include.lowest = TRUE, labels = FALSE)
test_frame <- freq[test, ]
test_frame$decile <- decile
calibration <- do.call(rbind, lapply(split(test_frame, test_frame$decile), function(x)
  data.frame(decile = x$decile[1], policies = nrow(x), exposure = sum(x$Exposure),
    actual_claims = sum(x$ClaimNb), expected_claims = sum(x$pred_count),
    actual_cost = sum(x$actual_cost), expected_cost = sum(x$pred_cost))))
row.names(calibration) <- NULL

# Coefficients make the underwriting desk a real evaluation of the fitted models.
coefficient_table <- rbind(
  data.frame(model = "frequency", term = names(coef(frequency)), estimate = unname(coef(frequency))),
  data.frame(model = "severity", term = names(coef(severity)), estimate = unname(coef(severity)))
)

# Aggregate empirical layer costs. These are descriptive, not a treaty quote.
attachments <- c(1000, 5000, 10000, 25000, 50000)
limits <- c(5000, 10000, 25000, 50000, 100000)
layer <- expand.grid(attachment = attachments, limit = limits)
layer$claim_count_above_attachment <- sapply(layer$attachment,
  function(a) sum(sev$ClaimAmount > a))
layer$mean_ceded_per_claim <- mapply(function(a, l)
  mean(pmin(pmax(sev$ClaimAmount - a, 0), l)), layer$attachment, layer$limit)
layer$ceded_per_exposure <- layer$mean_ceded_per_claim *
  (sum(freq$ClaimNb) / sum(freq$Exposure))
layer$loss_share_ceded <- layer$mean_ceded_per_claim / mean(sev$ClaimAmount)

severity_breaks <- c(0, 500, 1000, 2500, 5000, 10000, 25000, 50000, Inf)
severity_labels <- c("0–500", "500–1k", "1k–2.5k", "2.5k–5k", "5k–10k",
  "10k–25k", "25k–50k", "50k+")
sev$amount_band <- cut(sev$ClaimAmount, severity_breaks,
  labels = severity_labels, include.lowest = TRUE, right = FALSE)
severity_bands <- do.call(rbind, lapply(severity_labels, function(label) {
  x <- sev$ClaimAmount[sev$amount_band == label]
  data.frame(band = label, claims = length(x), claim_share = length(x) / nrow(sev),
    amount = sum(x), loss_share = sum(x) / sum(sev$ClaimAmount))
}))

write.csv(metrics, "results/metrics.csv", row.names = FALSE)
write.csv(calibration, "results/calibration.csv", row.names = FALSE)
write.csv(coefficient_table, "results/coefficients.csv", row.names = FALSE)
write.csv(layer, "results/layers.csv", row.names = FALSE)
write.csv(severity_bands, "results/severity_bands.csv", row.names = FALSE)
write.csv(data.frame(split = c("train", "validation", "test"),
  policies = as.integer(table(factor(freq$split, levels = c("train", "validation", "test")))),
  claims = c(sum(freq$ClaimNb[train]), sum(freq$ClaimNb[freq$split == "validation"]),
    sum(freq$ClaimNb[test]))), "results/splits.csv", row.names = FALSE)
cat("Finished. Test O/E cost:", round(metrics$value[metrics$key == "test_cost_oe"], 3), "\n")
