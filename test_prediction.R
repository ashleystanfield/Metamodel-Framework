################################################################################
#             TEST SCRIPT FOR PREDICTION & EVALUATION (BATCH 4)               #
################################################################################
# This script tests population prediction, evaluation, and ensemble modules
# Run this to verify Batch 4 is working correctly
################################################################################

# Clear workspace
rm(list = ls())

# Set working directory
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

cat("\n")
cat("================================================================================\n")
cat("         TESTING PREDICTION & EVALUATION (BATCH 4)                            \n")
cat("================================================================================\n")
cat("\n")

# Load all modules
source("R/00_config_loader.R")
source("R/utils.R")
source("R/01_data_loader.R")
source("R/02_preprocessing.R")
source("R/03_metamodel_lr.R")
source("R/04_metamodel_nn.R")
source("R/05_metamodel_rf.R")
source("R/06_population_prediction.R")
source("R/07_model_evaluation.R")
source("R/08_ensemble.R")

# Suppress package startup messages
suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
  library(nnet)
  library(randomForest)
})

# ------------------------------------------------------------------------------
# SETUP: Create Dummy Data and Train Models
# ------------------------------------------------------------------------------

cat("SETUP: Creating dummy data and training models...\n")
cat("-----------------------------------\n")

set.seed(42)

# Create dummy data
n_persons <- 3
samples_per_person <- 20

dummy_data <- data.table(
  person_idx = rep(1:n_persons, each = samples_per_person),
  x1 = rnorm(n_persons * samples_per_person, mean = 5, sd = 2),
  x2 = rnorm(n_persons * samples_per_person, mean = 10, sd = 3),
  y = rnorm(n_persons * samples_per_person, mean = 20, sd = 5)
)

dummy_data[, y := 2 * x1 + 0.5 * x2 + rnorm(.N, sd = 2)]

# Load config
config <- load_config("config.yaml")
config$data$person_id_column <- "person_idx"
config$variables$predictors <- c("x1", "x2")
config$variables$outcomes <- c("y")

# Prepare person datasets
person_datasets <- prepare_all_persons(dummy_data, config, "y")

# Train LR models
config$metamodels$linear_regression$enabled <- TRUE
config$metamodels$neural_network$enabled <- TRUE
config$metamodels$neural_network$tune_hyperparameters <- FALSE
config$metamodels$random_forest$enabled <- TRUE
config$metamodels$random_forest$tune_hyperparameters <- FALSE

lr_models <- train_lr_all_persons(person_datasets, "y", config)
nn_models <- train_nn_all_persons(person_datasets, "y", config)
rf_models <- train_rf_all_persons(person_datasets, "y", config)

cat("\n✓ SETUP COMPLETE\n\n")

# ------------------------------------------------------------------------------
# TEST 1: Population Prediction Aggregation
# ------------------------------------------------------------------------------

cat("TEST 1: Population prediction aggregation\n")
cat("-----------------------------------\n")

# Create uniform weights
pop_weights <- list("1" = 0.4, "2" = 0.35, "3" = 0.25)

# Create scenario
scenario <- data.table(x1 = 5.0, x2 = 10.0)

# Predict
pop_pred_lr <- predict_population(lr_models, scenario, pop_weights, "linear_regression")
pop_pred_nn <- predict_population(nn_models, scenario, pop_weights, "neural_network")
pop_pred_rf <- predict_population(rf_models, scenario, pop_weights, "random_forest")

cat(sprintf("  LR population prediction: %.3f\n", pop_pred_lr$population_prediction))
cat(sprintf("  NN population prediction: %.3f\n", pop_pred_nn$population_prediction))
cat(sprintf("  RF population prediction: %.3f\n", pop_pred_rf$population_prediction))

if (is.finite(pop_pred_lr$population_prediction) &&
    is.finite(pop_pred_nn$population_prediction) &&
    is.finite(pop_pred_rf$population_prediction)) {
  cat("\n✓ TEST 1 PASSED\n\n")
} else {
  cat("\n✗ TEST 1 FAILED: Invalid predictions\n\n")
}

# ------------------------------------------------------------------------------
# TEST 2: Model Performance Comparison
# ------------------------------------------------------------------------------

cat("TEST 2: Model performance comparison\n")
cat("-----------------------------------\n")

# Create all_models structure
all_models <- list(
  linear_regression = list(test_y = list(models = lr_models)),
  neural_network = list(test_y = list(models = nn_models)),
  random_forest = list(test_y = list(models = rf_models))
)

comparison <- compare_model_performance(all_models)

cat(sprintf("  Comparison rows: %d\n", nrow(comparison)))
cat(sprintf("  Model types: %s\n", paste(unique(comparison$model_type), collapse = ", ")))

if (nrow(comparison) > 0) {
  cat("\n✓ TEST 2 PASSED\n\n")
} else {
  cat("\n✗ TEST 2 FAILED: No comparison data\n\n")
}

# ------------------------------------------------------------------------------
# TEST 3: Aggregate Performance Metrics
# ------------------------------------------------------------------------------

cat("TEST 3: Aggregate performance metrics\n")
cat("-----------------------------------\n")

aggregated <- aggregate_performance_metrics(comparison)

cat(sprintf("  Aggregated rows: %d\n", nrow(aggregated)))
cat("\n  Summary:\n")
print(aggregated[, .(model_type, mean_train_r2, mean_test_r2)])

if (nrow(aggregated) > 0) {
  cat("\n✓ TEST 3 PASSED\n\n")
} else {
  cat("\n✗ TEST 3 FAILED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 4: Find Best Models
# ------------------------------------------------------------------------------

cat("TEST 4: Find best models\n")
cat("-----------------------------------\n")

best <- find_best_models(aggregated)

cat(sprintf("  Best model: %s (test R² = %.3f)\n",
            best$model_type[1], best$mean_test_r2[1]))

if (nrow(best) > 0) {
  cat("\n✓ TEST 4 PASSED\n\n")
} else {
  cat("\n✗ TEST 4 FAILED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 5: Ensemble Prediction - Simple Average
# ------------------------------------------------------------------------------

cat("TEST 5: Ensemble prediction (simple average)\n")
cat("-----------------------------------\n")

# Create ensemble from person predictions
person_1_preds <- c(
  linear_regression = lr_models[[1]]$train_pred[1],
  neural_network = nn_models[[1]]$train_pred[1],
  random_forest = rf_models[[1]]$train_pred[1]
)

ensemble_avg <- ensemble_simple_average(person_1_preds)

cat(sprintf("  LR: %.3f\n", person_1_preds[1]))
cat(sprintf("  NN: %.3f\n", person_1_preds[2]))
cat(sprintf("  RF: %.3f\n", person_1_preds[3]))
cat(sprintf("  Ensemble (avg): %.3f\n", ensemble_avg))

expected_avg <- mean(person_1_preds)
if (abs(ensemble_avg - expected_avg) < 0.001) {
  cat("\n✓ TEST 5 PASSED\n\n")
} else {
  cat("\n✗ TEST 5 FAILED: Ensemble != average\n\n")
}

# ------------------------------------------------------------------------------
# TEST 6: Ensemble Prediction - Weighted Average
# ------------------------------------------------------------------------------

cat("TEST 6: Ensemble prediction (weighted average)\n")
cat("-----------------------------------\n")

weights <- c(linear_regression = 0.5, neural_network = 0.3, random_forest = 0.2)

ensemble_weighted <- ensemble_weighted_average(person_1_preds, weights)

cat(sprintf("  Weights: LR=%.1f, NN=%.1f, RF=%.1f\n",
            weights[1], weights[2], weights[3]))
cat(sprintf("  Ensemble (weighted): %.3f\n", ensemble_weighted))

expected_weighted <- sum(person_1_preds * weights)
if (abs(ensemble_weighted - expected_weighted) < 0.001) {
  cat("\n✓ TEST 6 PASSED\n\n")
} else {
  cat("\n✗ TEST 6 FAILED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 7: Ensemble Prediction - Median
# ------------------------------------------------------------------------------

cat("TEST 7: Ensemble prediction (median)\n")
cat("-----------------------------------\n")

ensemble_med <- ensemble_median(person_1_preds)

cat(sprintf("  Ensemble (median): %.3f\n", ensemble_med))

expected_median <- median(person_1_preds)
if (abs(ensemble_med - expected_median) < 0.001) {
  cat("\n✓ TEST 7 PASSED\n\n")
} else {
  cat("\n✗ TEST 7 FAILED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 8: Calculate Ensemble Weights from Performance
# ------------------------------------------------------------------------------

cat("TEST 8: Calculate ensemble weights from performance\n")
cat("-----------------------------------\n")

ensemble_weights <- calculate_ensemble_weights(aggregated, "mean_test_r2", "test_y")

cat("  Calculated weights:\n")
for (i in seq_along(ensemble_weights)) {
  cat(sprintf("    %s: %.3f\n", names(ensemble_weights)[i], ensemble_weights[i]))
}

if (abs(sum(ensemble_weights) - 1.0) < 0.001) {
  cat("\n✓ TEST 8 PASSED\n\n")
} else {
  cat("\n✗ TEST 8 FAILED: Weights don't sum to 1\n\n")
}

# ------------------------------------------------------------------------------
# TEST 9: Error Metrics Calculation
# ------------------------------------------------------------------------------

cat("TEST 9: Error metrics calculation\n")
cat("-----------------------------------\n")

actual <- dummy_data$y[1:10]
predicted <- actual + rnorm(10, sd = 0.5)

metrics <- calculate_error_metrics(actual, predicted)

cat("  Calculated metrics:\n")
cat(sprintf("    MAE: %.3f\n", metrics$mae))
cat(sprintf("    RMSE: %.3f\n", metrics$rmse))
cat(sprintf("    R²: %.3f\n", metrics$r_squared))

if (metrics$r_squared > 0.5 && is.finite(metrics$rmse)) {
  cat("\n✓ TEST 9 PASSED\n\n")
} else {
  cat("\n✗ TEST 9 FAILED\n\n")
}

# ------------------------------------------------------------------------------
# TEST 10: Scenario Grid Generation
# ------------------------------------------------------------------------------

cat("TEST 10: Scenario grid generation\n")
cat("-----------------------------------\n")

predictor_ranges <- list(
  x1 = c(0, 10),
  x2 = c(5, 15)
)

scenario_grid <- generate_scenario_grid(predictor_ranges, n_points = 5)

cat(sprintf("  Generated %d scenarios\n", nrow(scenario_grid)))
cat("  Sample scenarios:\n")
print(head(scenario_grid, 3))

if (nrow(scenario_grid) == 25) {  # 5 x 5 grid
  cat("\n✓ TEST 10 PASSED\n\n")
} else {
  cat("\n✗ TEST 10 FAILED: Wrong number of scenarios\n\n")
}

# ------------------------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------------------------

cat("================================================================================\n")
cat("                            TEST SUMMARY                                       \n")
cat("================================================================================\n")
cat("\n")

cat("All Batch 4 tests completed!\n")
cat("\n")
cat("Modules tested:\n")
cat("  ✓ Population Prediction (R/06_population_prediction.R)\n")
cat("  ✓ Model Evaluation (R/07_model_evaluation.R)\n")
cat("  ✓ Ensemble Methods (R/08_ensemble.R)\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
