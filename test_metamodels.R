################################################################################
#                   TEST SCRIPT FOR METAMODEL TRAINING (BATCH 3)               #
################################################################################
# This script tests the metamodel training modules (LR, NN, RF)
# Run this to verify Batch 3 is working correctly
################################################################################

# Clear workspace
rm(list = ls())

# Set working directory
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

cat("\n")
cat("================================================================================\n")
cat("              TESTING METAMODEL TRAINING (BATCH 3)                            \n")
cat("================================================================================\n")
cat("\n")

# Load modules
source("R/00_config_loader.R")
source("R/utils.R")
source("R/01_data_loader.R")
source("R/02_preprocessing.R")
source("R/03_metamodel_lr.R")
source("R/04_metamodel_nn.R")
source("R/05_metamodel_rf.R")

# Suppress package startup messages
suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
  library(nnet)
  library(randomForest)
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
# TEST 2: Create Dummy Data for Testing
# ------------------------------------------------------------------------------

cat("TEST 2: Creating dummy data for testing\n")
cat("-----------------------------------\n")

set.seed(42)

# Create dummy data with 3 person types, each with 20 samples
n_persons <- 3
samples_per_person <- 20

dummy_data <- data.table(
  person_idx = rep(1:n_persons, each = samples_per_person),
  x1 = rnorm(n_persons * samples_per_person, mean = 5, sd = 2),
  x2 = rnorm(n_persons * samples_per_person, mean = 10, sd = 3),
  x3 = rnorm(n_persons * samples_per_person, mean = 15, sd = 4),
  y = rnorm(n_persons * samples_per_person, mean = 20, sd = 5)
)

# Add some relationship between predictors and outcome
dummy_data[, y := 2 * x1 + 0.5 * x2 - 0.3 * x3 + rnorm(.N, sd = 2)]

cat(sprintf("  Created dummy dataset: %d rows, %d persons\n",
            nrow(dummy_data), n_persons))
cat(sprintf("  Predictors: x1, x2, x3\n"))
cat(sprintf("  Outcome: y\n"))

cat("\n✓ TEST 2 PASSED\n\n")

# ------------------------------------------------------------------------------
# TEST 3: Prepare Person-Specific Datasets
# ------------------------------------------------------------------------------

cat("TEST 3: Preparing person-specific datasets\n")
cat("-----------------------------------\n")

# Update config to match dummy data
config$data$person_id_column <- "person_idx"
config$variables$predictors <- c("x1", "x2", "x3")
config$variables$outcomes <- c("y")

person_datasets <- prepare_all_persons(dummy_data, config, "y")

cat(sprintf("\n  Prepared %d person datasets\n", length(person_datasets)))
cat(sprintf("  Avg training samples: %.1f\n",
            mean(sapply(person_datasets, function(x) x$n_train))))

cat("\n✓ TEST 3 PASSED\n\n")

# ------------------------------------------------------------------------------
# TEST 4: Train Linear Regression
# ------------------------------------------------------------------------------

cat("TEST 4: Training Linear Regression models\n")
cat("-----------------------------------\n")

lr_models <- train_lr_all_persons(person_datasets, "y", config)

# Check results
n_success <- sum(sapply(lr_models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback)))
cat(sprintf("\n  Successful LR models: %d/%d\n", n_success, length(lr_models)))

# Check that we have predictions
first_model <- lr_models[[1]]
if (!is.null(first_model$train_pred) && !is.null(first_model$train_metrics)) {
  cat(sprintf("  First model training R²: %.3f\n", first_model$train_metrics$r_squared))
  cat(sprintf("  First model training RMSE: %.3f\n", first_model$train_metrics$rmse))
}

if (n_success == length(lr_models)) {
  cat("\n✓ TEST 4 PASSED\n\n")
} else {
  cat("\n✗ TEST 4 FAILED: Not all models trained successfully\n\n")
}

# ------------------------------------------------------------------------------
# TEST 5: Train Neural Network
# ------------------------------------------------------------------------------

cat("TEST 5: Training Neural Network models\n")
cat("-----------------------------------\n")

# Disable tuning for faster testing
config$metamodels$neural_network$tune_hyperparameters <- FALSE
config$metamodels$neural_network$size <- 5
config$metamodels$neural_network$decay <- 0.01

nn_models <- train_nn_all_persons(person_datasets, "y", config)

# Check results
n_success_nn <- sum(sapply(nn_models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback)))
cat(sprintf("\n  Successful NN models: %d/%d\n", n_success_nn, length(nn_models)))

# Check that we have predictions
first_nn_model <- nn_models[[1]]
if (!is.null(first_nn_model$train_pred) && !is.null(first_nn_model$train_metrics)) {
  cat(sprintf("  First model training R²: %.3f\n", first_nn_model$train_metrics$r_squared))
  cat(sprintf("  First model training RMSE: %.3f\n", first_nn_model$train_metrics$rmse))
  cat(sprintf("  Hidden layer size: %d\n", first_nn_model$size))
  cat(sprintf("  Decay: %.4f\n", first_nn_model$decay))
}

if (n_success_nn == length(nn_models)) {
  cat("\n✓ TEST 5 PASSED\n\n")
} else {
  cat("\n✗ TEST 5 FAILED: Not all models trained successfully\n\n")
}

# ------------------------------------------------------------------------------
# TEST 6: Train Random Forest
# ------------------------------------------------------------------------------

cat("TEST 6: Training Random Forest models\n")
cat("-----------------------------------\n")

# Disable tuning for faster testing
config$metamodels$random_forest$tune_hyperparameters <- FALSE
config$metamodels$random_forest$ntree <- 100  # Fewer trees for testing
config$metamodels$random_forest$mtry <- 2

rf_models <- train_rf_all_persons(person_datasets, "y", config)

# Check results
n_success_rf <- sum(sapply(rf_models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback)))
cat(sprintf("\n  Successful RF models: %d/%d\n", n_success_rf, length(rf_models)))

# Check that we have predictions
first_rf_model <- rf_models[[1]]
if (!is.null(first_rf_model$train_pred) && !is.null(first_rf_model$train_metrics)) {
  cat(sprintf("  First model training R²: %.3f\n", first_rf_model$train_metrics$r_squared))
  cat(sprintf("  First model training RMSE: %.3f\n", first_rf_model$train_metrics$rmse))
  cat(sprintf("  Number of trees: %d\n", first_rf_model$ntree))
  cat(sprintf("  mtry: %d\n", first_rf_model$mtry))
}

if (n_success_rf == length(rf_models)) {
  cat("\n✓ TEST 6 PASSED\n\n")
} else {
  cat("\n✗ TEST 6 FAILED: Not all models trained successfully\n\n")
}

# ------------------------------------------------------------------------------
# TEST 7: Extract Coefficients (LR)
# ------------------------------------------------------------------------------

cat("TEST 7: Extracting LR coefficients\n")
cat("-----------------------------------\n")

lr_coefs <- extract_lr_coefficients(lr_models)

cat(sprintf("  Extracted coefficients: %d rows\n", nrow(lr_coefs)))
cat(sprintf("  Unique terms: %d\n", uniqueN(lr_coefs$term)))
cat("\n  Sample coefficients:\n")
print(head(lr_coefs))

if (nrow(lr_coefs) > 0) {
  cat("\n✓ TEST 7 PASSED\n\n")
} else {
  cat("\n✗ TEST 7 FAILED: No coefficients extracted\n\n")
}

# ------------------------------------------------------------------------------
# TEST 8: Extract Variable Importance (RF)
# ------------------------------------------------------------------------------

cat("TEST 8: Extracting RF variable importance\n")
cat("-----------------------------------\n")

rf_importance <- extract_rf_importance(rf_models)

cat(sprintf("  Extracted importance: %d rows\n", nrow(rf_importance)))
cat(sprintf("  Unique variables: %d\n", uniqueN(rf_importance$variable)))

if (nrow(rf_importance) > 0) {
  importance_summary <- summarize_rf_importance(rf_importance)
  cat("\n  Average variable importance:\n")
  print(importance_summary)
}

if (nrow(rf_importance) > 0) {
  cat("\n✓ TEST 8 PASSED\n\n")
} else {
  cat("\n✗ TEST 8 FAILED: No importance extracted\n\n")
}

# ------------------------------------------------------------------------------
# TEST 9: Make Predictions on New Data
# ------------------------------------------------------------------------------

cat("TEST 9: Making predictions on new data\n")
cat("-----------------------------------\n")

# Create new test data
new_data <- data.table(
  person_idx = rep(1:n_persons, each = 5),
  x1 = rnorm(n_persons * 5, mean = 5, sd = 2),
  x2 = rnorm(n_persons * 5, mean = 10, sd = 3),
  x3 = rnorm(n_persons * 5, mean = 15, sd = 4)
)

# Predict with LR
lr_pred <- predict_lr_new_data(lr_models, new_data, person_id_col = "person_idx")
cat(sprintf("  LR predictions: %d rows\n", nrow(lr_pred)))

# Predict with NN
nn_pred <- predict_nn_new_data(nn_models, new_data, person_id_col = "person_idx")
cat(sprintf("  NN predictions: %d rows\n", nrow(nn_pred)))

# Predict with RF
rf_pred <- predict_rf_new_data(rf_models, new_data, person_id_col = "person_idx")
cat(sprintf("  RF predictions: %d rows\n", nrow(rf_pred)))

if (nrow(lr_pred) > 0 && nrow(nn_pred) > 0 && nrow(rf_pred) > 0) {
  cat("\n✓ TEST 9 PASSED\n\n")
} else {
  cat("\n✗ TEST 9 FAILED: Prediction failed for one or more models\n\n")
}

# ------------------------------------------------------------------------------
# TEST 10: Model Saving and Loading
# ------------------------------------------------------------------------------

cat("TEST 10: Saving and loading models\n")
cat("-----------------------------------\n")

# Create test group-outcome structure
test_result <- list(
  group = "test_group",
  outcome = "y",
  models = lr_models,
  n_models = length(lr_models),
  n_success = n_success,
  n_fallback = 0
)

# Test LR save/load
tryCatch({
  save_lr_models(test_result, config)
  loaded_lr <- load_lr_models("test_group", "y", config)

  cat(sprintf("  Saved and loaded LR models: %d models\n", loaded_lr$n_models))

  cat("\n✓ TEST 10a (LR) PASSED\n")
}, error = function(e) {
  cat(sprintf("\n✗ TEST 10a (LR) FAILED: %s\n", e$message))
})

# Test NN save/load
test_result_nn <- list(
  group = "test_group",
  outcome = "y",
  models = nn_models,
  n_models = length(nn_models),
  n_success = n_success_nn,
  n_fallback = 0
)

tryCatch({
  save_nn_models(test_result_nn, config)
  loaded_nn <- load_nn_models("test_group", "y", config)

  cat(sprintf("  Saved and loaded NN models: %d models\n", loaded_nn$n_models))

  cat("\n✓ TEST 10b (NN) PASSED\n")
}, error = function(e) {
  cat(sprintf("\n✗ TEST 10b (NN) FAILED: %s\n", e$message))
})

# Test RF save/load
test_result_rf <- list(
  group = "test_group",
  outcome = "y",
  models = rf_models,
  n_models = length(rf_models),
  n_success = n_success_rf,
  n_fallback = 0
)

tryCatch({
  save_rf_models(test_result_rf, config)
  loaded_rf <- load_rf_models("test_group", "y", config)

  cat(sprintf("  Saved and loaded RF models: %d models\n", loaded_rf$n_models))

  cat("\n✓ TEST 10c (RF) PASSED\n\n")
}, error = function(e) {
  cat(sprintf("\n✗ TEST 10c (RF) FAILED: %s\n\n", e$message))
})

# ------------------------------------------------------------------------------
# TEST 11: Summary Reports
# ------------------------------------------------------------------------------

cat("TEST 11: Creating summary reports\n")
cat("-----------------------------------\n")

# Create dummy results structure for all three models
all_results <- list(
  test_group_y = test_result
)

all_results_nn <- list(
  test_group_y = test_result_nn
)

all_results_rf <- list(
  test_group_y = test_result_rf
)

# Test LR summary
lr_summary <- summarize_lr_results(all_results)
cat("\n  LR Summary:\n")
print(lr_summary)

# Test NN summary
nn_summary <- summarize_nn_results(all_results_nn)
cat("\n  NN Summary:\n")
print(nn_summary)

# Test RF summary
rf_summary <- summarize_rf_results(all_results_rf)
cat("\n  RF Summary:\n")
print(rf_summary)

if (nrow(lr_summary) > 0 && nrow(nn_summary) > 0 && nrow(rf_summary) > 0) {
  cat("\n✓ TEST 11 PASSED\n\n")
} else {
  cat("\n✗ TEST 11 FAILED: Summary creation failed\n\n")
}

# ------------------------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------------------------

cat("================================================================================\n")
cat("                            TEST SUMMARY                                       \n")
cat("================================================================================\n")
cat("\n")

cat("All Batch 3 tests completed!\n")
cat("\n")
cat("Modules tested:\n")
cat("  ✓ Linear Regression (R/03_metamodel_lr.R)\n")
cat("  ✓ Neural Network (R/04_metamodel_nn.R)\n")
cat("  ✓ Random Forest (R/05_metamodel_rf.R)\n")
cat("\n")
cat("Next steps:\n")
cat("  1. If all tests passed, Batch 3 is working correctly\n")
cat("  2. You can now train metamodels on your real data\n")
cat("  3. Ready for Batch 4 (prediction & evaluation)\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
