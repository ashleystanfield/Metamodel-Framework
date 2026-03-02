################################################################################
#                   TEST SCRIPT FOR DATA LOADING (BATCH 2)                    #
################################################################################
# This script tests the data loading and preprocessing modules
# Run this to verify Batch 2 is working correctly
################################################################################

# Clear workspace
rm(list = ls())

# Set working directory
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

cat("\n")
cat("================================================================================\n")
cat("              TESTING DATA LOADING & PREPROCESSING (BATCH 2)                  \n")
cat("================================================================================\n")
cat("\n")

# Load modules
source("R/00_config_loader.R")
source("R/utils.R")
source("R/01_data_loader.R")
source("R/02_preprocessing.R")

# Suppress package startup messages
suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
})

# ------------------------------------------------------------------------------
# TEST 1: Load Configuration
# ------------------------------------------------------------------------------

cat("TEST 1: Loading configuration\n")
cat("-----------------------------------\n")

config <- load_config("config.yaml")
print_config_summary(config)

cat("\n✓ TEST 1 PASSED\n\n")

# ------------------------------------------------------------------------------
# TEST 2: Get Enabled Files
# ------------------------------------------------------------------------------

cat("TEST 2: Getting enabled input files\n")
cat("-----------------------------------\n")

enabled_files <- get_enabled_input_files(config)
cat(sprintf("Found %d enabled file(s):\n", length(enabled_files)))
for (name in names(enabled_files)) {
  cat(sprintf("  • %s: %s\n", name, enabled_files[[name]]))
  cat(sprintf("    Exists: %s\n", file.exists(enabled_files[[name]])))
}

cat("\n✓ TEST 2 PASSED\n\n")

# ------------------------------------------------------------------------------
# TEST 3: Load Data (if files exist)
# ------------------------------------------------------------------------------

cat("TEST 3: Loading data files\n")
cat("-----------------------------------\n")

if (length(enabled_files) > 0 && any(file.exists(unlist(enabled_files)))) {

  tryCatch({
    data_list <- load_all_data(config)

    cat("\nData loading summary:\n")
    for (name in names(data_list)) {
      cat(sprintf("  %s: %d rows × %d columns\n",
                  name, nrow(data_list[[name]]), ncol(data_list[[name]])))
    }

    cat("\n✓ TEST 3 PASSED\n\n")

  }, error = function(e) {
    cat(sprintf("\n✗ TEST 3 FAILED: %s\n\n", e$message))
    cat("  This is OK if your data files aren't set up yet.\n\n")
  })

} else {
  cat("  No data files found (this is OK for initial testing)\n")
  cat("  Update config.yaml with valid file paths to test data loading\n")
  cat("\n⏭ TEST 3 SKIPPED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 4: Data Quality Check (if data loaded)
# ------------------------------------------------------------------------------

cat("TEST 4: Data quality check\n")
cat("-----------------------------------\n")

if (exists("data_list") && length(data_list) > 0) {

  tryCatch({
    # Check quality of first dataset
    first_data <- data_list[[1]]

    quality <- check_data_quality(first_data, config)

    cat("\nQuality metrics:\n")
    cat(sprintf("  Rows: %d\n", quality$n_rows))
    cat(sprintf("  Columns: %d\n", quality$n_cols))
    cat(sprintf("  Person types: %d\n", quality$n_persons))
    cat(sprintf("  Missing values: %d (%.2f%%)\n",
                quality$missing_total, quality$missing_pct))

    cat("\n✓ TEST 4 PASSED\n\n")

  }, error = function(e) {
    cat(sprintf("\n✗ TEST 4 FAILED: %s\n\n", e$message))
  })

} else {
  cat("  No data available for quality check\n")
  cat("\n⏭ TEST 4 SKIPPED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 5: Train/Test Split
# ------------------------------------------------------------------------------

cat("TEST 5: Train/test splitting\n")
cat("-----------------------------------\n")

# Create dummy data
dummy_data <- data.table(
  person_idx = rep(1:3, each = 10),
  x1 = rnorm(30),
  x2 = rnorm(30),
  y = rnorm(30)
)

split <- split_train_test(dummy_data, train_ratio = 0.8, seed = 42)

cat(sprintf("  Original data: %d rows\n", nrow(dummy_data)))
cat(sprintf("  Training set: %d rows\n", nrow(split$train)))
cat(sprintf("  Test set: %d rows\n", nrow(split$test)))
cat(sprintf("  Ratio: %.1f%%/%.1f%%\n",
            100 * nrow(split$train) / nrow(dummy_data),
            100 * nrow(split$test) / nrow(dummy_data)))

if (nrow(split$train) + nrow(split$test) == nrow(dummy_data)) {
  cat("\n✓ TEST 5 PASSED\n\n")
} else {
  cat("\n✗ TEST 5 FAILED: Row counts don't match\n\n")
}

# ------------------------------------------------------------------------------
# TEST 6: Constant Predictor Detection
# ------------------------------------------------------------------------------

cat("TEST 6: Constant predictor detection\n")
cat("-----------------------------------\n")

# Create data with one constant predictor
test_data <- data.table(
  x1 = rep(5, 20),      # Constant
  x2 = rnorm(20),       # Variable
  x3 = rep(NA, 20),     # All NA (should be constant)
  y = rnorm(20)
)

const_preds <- detect_constant_predictors(test_data, c("x1", "x2", "x3"))

cat(sprintf("  Constant predictors found: %s\n",
            ifelse(length(const_preds) > 0, paste(const_preds, collapse = ", "), "none")))

expected_const <- c("x1", "x3")
if (all(expected_const %in% const_preds)) {
  cat("\n✓ TEST 6 PASSED\n\n")
} else {
  cat("\n✗ TEST 6 FAILED: Expected x1 and x3 to be constant\n\n")
}

# ------------------------------------------------------------------------------
# TEST 7: Person-Specific Data Preparation
# ------------------------------------------------------------------------------

cat("TEST 7: Person-specific data preparation\n")
cat("-----------------------------------\n")

# Use dummy data from TEST 5
person_data <- prepare_person_data(
  data = dummy_data,
  person_id = 1,
  person_id_col = "person_idx",
  predictors = c("x1", "x2"),
  outcome = "y",
  train_ratio = 0.8,
  seed = 42,
  drop_constants = TRUE
)

cat(sprintf("  Person ID: %d\n", person_data$person_id))
cat(sprintf("  Total samples: %d\n", person_data$n_total))
cat(sprintf("  Training samples: %d\n", person_data$n_train))
cat(sprintf("  Test samples: %d\n", person_data$n_test))
cat(sprintf("  Predictors used: %d\n", person_data$n_predictors))
cat(sprintf("  Constant predictors: %d\n", person_data$n_constant))

if (person_data$n_total == 10 && person_data$n_train == 8) {
  cat("\n✓ TEST 7 PASSED\n\n")
} else {
  cat("\n✗ TEST 7 FAILED: Unexpected sample counts\n\n")
}

# ------------------------------------------------------------------------------
# TEST 8: Dataset Validation
# ------------------------------------------------------------------------------

cat("TEST 8: Dataset validation\n")
cat("-----------------------------------\n")

validation <- validate_person_dataset(person_data, min_samples = 2)

cat(sprintf("  Is valid: %s\n", validation$is_valid))
cat(sprintf("  Reason: %s\n", validation$reason))

if (validation$is_valid) {
  cat("\n✓ TEST 8 PASSED\n\n")
} else {
  cat(sprintf("\n✗ TEST 8 FAILED: %s\n\n", validation$reason))
}

# ------------------------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------------------------

cat("================================================================================\n")
cat("                            TEST SUMMARY                                       \n")
cat("================================================================================\n")
cat("\n")

cat("All basic tests completed!\n")
cat("\n")
cat("Next steps:\n")
cat("  1. Update config.yaml with your actual data file paths\n")
cat("  2. Run this script again to test with real data\n")
cat("  3. If all tests pass, you're ready for Batch 3 (metamodel training)\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
