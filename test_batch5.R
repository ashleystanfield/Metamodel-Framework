################################################################################
#                                                                              #
#                  TEST SUITE FOR BATCH 5 METAMODELS                          #
#                                                                              #
#  Tests for Support Vector Regression, Quadratic Regression, and             #
#  Cubic Regression metamodels.                                               #
#                                                                              #
#  USAGE: source("test_batch5.R")                                             #
#                                                                              #
################################################################################

cat("\n")
cat("================================================================================\n")
cat("                    BATCH 5 METAMODEL TEST SUITE                              \n")
cat("================================================================================\n")
cat("\n")

# ==============================================================================
# SETUP
# ==============================================================================

cat("▶ Setting up test environment...\n")

# Load required libraries
suppressPackageStartupMessages({
  library(data.table)
  library(e1071)
})

# Source modules
source("R/00_config_loader.R")
source("R/utils.R")
source("R/01_data_loader.R")
source("R/02_preprocessing.R")
source("R/09_metamodel_svr.R")
source("R/10_metamodel_qr.R")
source("R/11_metamodel_cr.R")

# Set random seed
set.seed(42)

# Test counter
test_count <- 0
pass_count <- 0
fail_count <- 0

#' Run a test and track results
run_test <- function(test_name, test_fn) {
  test_count <<- test_count + 1
  cat(sprintf("\n[Test %d] %s\n", test_count, test_name))

  result <- tryCatch({
    test_fn()
    TRUE
  }, error = function(e) {
    cat(sprintf("  ✗ FAILED: %s\n", e$message))
    FALSE
  })

  if (result) {
    cat("  ✓ PASSED\n")
    pass_count <<- pass_count + 1
  } else {
    fail_count <<- fail_count + 1
  }

  return(result)
}

# ==============================================================================
# CREATE TEST DATA
# ==============================================================================

cat("\n▶ Creating synthetic test data...\n")

# Create test dataset
n_persons <- 3
n_obs_per_person <- 30

test_data <- data.table()

for (person_id in 1:n_persons) {
  person_data <- data.table(
    person_id = person_id,
    x1 = runif(n_obs_per_person, 0, 10),
    x2 = runif(n_obs_per_person, 5, 15),
    x3 = runif(n_obs_per_person, -5, 5)
  )

  # Create outcome with quadratic/cubic relationships
  person_data[, outcome_quadratic := 5 + 2*x1 + 3*x2 - 0.5*x1^2 + 0.2*x2^2 +
                                      0.1*x1*x2 + rnorm(n_obs_per_person, 0, 2)]
  person_data[, outcome_cubic := 10 + x1 + 2*x2 - 0.1*x1^3 + 0.05*x2^3 +
                                  0.2*x1*x2 + rnorm(n_obs_per_person, 0, 3)]
  person_data[, outcome_linear := 8 + 1.5*x1 + 2*x2 + 0.5*x3 +
                                  rnorm(n_obs_per_person, 0, 1)]

  test_data <- rbind(test_data, person_data)
}

cat(sprintf("  Created dataset: %d persons × %d observations = %d rows\n",
           n_persons, n_obs_per_person, nrow(test_data)))
cat(sprintf("  Predictors: %s\n", paste(c("x1", "x2", "x3"), collapse = ", ")))
cat(sprintf("  Outcomes: %s\n", paste(c("outcome_linear", "outcome_quadratic", "outcome_cubic"),
                                      collapse = ", ")))

# ==============================================================================
# TEST 1: QUADRATIC REGRESSION - FEATURE EXPANSION
# ==============================================================================

run_test("Quadratic Regression - Feature Expansion", function() {
  predictors <- c("x1", "x2", "x3")
  sample_data <- test_data[person_id == 1, .(x1, x2, x3)]

  expansion <- expand_quadratic_features(sample_data, predictors, include_interactions = TRUE)

  # Check that expansion contains correct features
  stopifnot(all(c("x1", "x2", "x3") %in% expansion$expanded_cols))  # Original
  stopifnot(all(c("x1_sq", "x2_sq", "x3_sq") %in% expansion$expanded_cols))  # Squared
  stopifnot("x1_x_x2" %in% expansion$expanded_cols)  # Interactions

  cat(sprintf("    Original predictors: %d\n", length(predictors)))
  cat(sprintf("    Expanded features: %d\n", length(expansion$expanded_cols)))
  cat(sprintf("    Squared terms: %d\n", length(expansion$squared_cols)))
  cat(sprintf("    Interaction terms: %d\n", length(expansion$interaction_cols)))
})

# ==============================================================================
# TEST 2: CUBIC REGRESSION - FEATURE EXPANSION
# ==============================================================================

run_test("Cubic Regression - Feature Expansion", function() {
  predictors <- c("x1", "x2")
  sample_data <- test_data[person_id == 1, .(x1, x2)]

  expansion <- expand_cubic_features(sample_data, predictors,
                                    include_two_way = TRUE,
                                    include_three_way = FALSE)

  # Check features
  stopifnot(all(c("x1", "x2") %in% expansion$expanded_cols))  # Original
  stopifnot(all(c("x1_sq", "x2_sq") %in% expansion$expanded_cols))  # Squared
  stopifnot(all(c("x1_cube", "x2_cube") %in% expansion$expanded_cols))  # Cubic
  stopifnot("x1_sq_x_x2" %in% expansion$expanded_cols)  # Squared interactions

  cat(sprintf("    Original predictors: %d\n", length(predictors)))
  cat(sprintf("    Expanded features: %d\n", length(expansion$expanded_cols)))
  cat(sprintf("    Squared terms: %d\n", length(expansion$squared_cols)))
  cat(sprintf("    Cubic terms: %d\n", length(expansion$cubed_cols)))
  cat(sprintf("    Squared interaction terms: %d\n", length(expansion$squared_interaction_cols)))
})

# ==============================================================================
# TEST 3: QUADRATIC REGRESSION - SINGLE PERSON TRAINING
# ==============================================================================

run_test("Quadratic Regression - Single Person Training", function() {
  # Prepare person data
  person_data <- prepare_person_data(
    test_data,
    person_id = 1,
    person_id_col = "person_id",
    predictors = c("x1", "x2", "x3"),
    outcome = "outcome_quadratic",
    train_ratio = 0.8,
    seed = 42
  )

  # Create minimal config
  config <- list(
    metamodels = list(
      quadratic_regression = list(
        include_interactions = TRUE
      )
    ),
    modeling = list(
      random_seed = 42
    )
  )

  # Train QR model
  qr_model <- train_qr_person(person_data, "outcome_quadratic", config)

  # Validate results
  stopifnot(!is.null(qr_model))
  stopifnot(qr_model$person_id == 1)
  stopifnot(qr_model$outcome == "outcome_quadratic")
  stopifnot(!qr_model$is_fallback)
  stopifnot(!is.null(qr_model$model))
  stopifnot(qr_model$train_metrics$r_squared > 0)

  cat(sprintf("    Training R²: %.3f\n", qr_model$train_metrics$r_squared))
  cat(sprintf("    Test R²: %.3f\n", qr_model$test_metrics$r_squared))
  cat(sprintf("    Original predictors: %d\n", qr_model$n_predictors))
  cat(sprintf("    Expanded features: %d\n", qr_model$n_expanded_features))
})

# ==============================================================================
# TEST 4: CUBIC REGRESSION - SINGLE PERSON TRAINING
# ==============================================================================

run_test("Cubic Regression - Single Person Training", function() {
  # Prepare person data
  person_data <- prepare_person_data(
    test_data,
    person_id = 1,
    person_id_col = "person_id",
    predictors = c("x1", "x2"),
    outcome = "outcome_cubic",
    train_ratio = 0.8,
    seed = 42
  )

  # Create minimal config
  config <- list(
    metamodels = list(
      cubic_regression = list(
        include_two_way_interactions = TRUE,
        include_three_way_interactions = FALSE
      )
    ),
    modeling = list(
      random_seed = 42
    )
  )

  # Train CR model
  cr_model <- train_cr_person(person_data, "outcome_cubic", config)

  # Validate results
  stopifnot(!is.null(cr_model))
  stopifnot(cr_model$person_id == 1)
  stopifnot(!cr_model$is_fallback)
  stopifnot(!is.null(cr_model$model))
  stopifnot(cr_model$train_metrics$r_squared > 0)

  cat(sprintf("    Training R²: %.3f\n", cr_model$train_metrics$r_squared))
  cat(sprintf("    Test R²: %.3f\n", cr_model$test_metrics$r_squared))
  cat(sprintf("    Original predictors: %d\n", cr_model$n_predictors))
  cat(sprintf("    Expanded features: %d\n", cr_model$n_expanded_features))
})

# ==============================================================================
# TEST 5: SUPPORT VECTOR REGRESSION - SINGLE PERSON TRAINING
# ==============================================================================

run_test("Support Vector Regression - Single Person Training", function() {
  # Prepare person data
  person_data <- prepare_person_data(
    test_data,
    person_id = 1,
    person_id_col = "person_id",
    predictors = c("x1", "x2", "x3"),
    outcome = "outcome_linear",
    train_ratio = 0.8,
    seed = 42
  )

  # Create minimal config
  config <- list(
    metamodels = list(
      support_vector_regression = list(
        kernel = "radial",
        tune_hyperparameters = FALSE,  # Skip tuning for speed
        tune_cost_grid = c(1),
        tune_epsilon_grid = c(0.1)
      )
    ),
    modeling = list(
      random_seed = 42
    )
  )

  # Train SVR model
  svr_model <- train_svr_person(person_data, "outcome_linear", config,
                               tune_hyperparameters = FALSE)

  # Validate results
  stopifnot(!is.null(svr_model))
  stopifnot(svr_model$person_id == 1)
  stopifnot(!svr_model$is_fallback)
  stopifnot(!is.null(svr_model$model))
  stopifnot(svr_model$train_metrics$r_squared > 0)

  cat(sprintf("    Training R²: %.3f\n", svr_model$train_metrics$r_squared))
  cat(sprintf("    Test R²: %.3f\n", svr_model$test_metrics$r_squared))
  cat(sprintf("    Kernel: %s\n", svr_model$kernel))
})

# ==============================================================================
# TEST 6: QUADRATIC REGRESSION - ALL PERSONS
# ==============================================================================

run_test("Quadratic Regression - All Persons Training", function() {
  # Prepare all persons
  person_datasets <- list()
  for (pid in 1:n_persons) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2", "x3"),
      outcome = "outcome_quadratic",
      train_ratio = 0.8,
      seed = 42
    )
  }

  # Create config
  config <- list(
    metamodels = list(
      quadratic_regression = list(
        include_interactions = TRUE
      )
    ),
    modeling = list(random_seed = 42)
  )

  # Train all
  qr_result <- train_qr_all_persons(person_datasets, "outcome_quadratic", config)

  # Validate
  stopifnot(!is.null(qr_result))
  stopifnot(length(qr_result$models) == n_persons)
  stopifnot(qr_result$n_persons == n_persons)

  cat(sprintf("    Trained models: %d\n", qr_result$n_persons))
  cat(sprintf("    Fallback models: %d\n", qr_result$n_fallback))
})

# ==============================================================================
# TEST 7: CUBIC REGRESSION - ALL PERSONS
# ==============================================================================

run_test("Cubic Regression - All Persons Training", function() {
  # Prepare all persons
  person_datasets <- list()
  for (pid in 1:n_persons) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2"),
      outcome = "outcome_cubic",
      train_ratio = 0.8,
      seed = 42
    )
  }

  # Create config
  config <- list(
    metamodels = list(
      cubic_regression = list(
        include_two_way_interactions = TRUE,
        include_three_way_interactions = FALSE
      )
    ),
    modeling = list(random_seed = 42)
  )

  # Train all
  cr_result <- train_cr_all_persons(person_datasets, "outcome_cubic", config)

  # Validate
  stopifnot(!is.null(cr_result))
  stopifnot(length(cr_result$models) == n_persons)
  stopifnot(cr_result$n_persons == n_persons)

  cat(sprintf("    Trained models: %d\n", cr_result$n_persons))
  cat(sprintf("    Fallback models: %d\n", cr_result$n_fallback))
})

# ==============================================================================
# TEST 8: SVR - ALL PERSONS
# ==============================================================================

run_test("Support Vector Regression - All Persons Training", function() {
  # Prepare all persons
  person_datasets <- list()
  for (pid in 1:n_persons) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2", "x3"),
      outcome = "outcome_linear",
      train_ratio = 0.8,
      seed = 42
    )
  }

  # Create config
  config <- list(
    metamodels = list(
      support_vector_regression = list(
        kernel = "radial",
        tune_hyperparameters = FALSE,
        tune_cost_grid = c(1),
        tune_epsilon_grid = c(0.1)
      )
    ),
    modeling = list(random_seed = 42)
  )

  # Train all
  svr_result <- train_svr_all_persons(person_datasets, "outcome_linear", config)

  # Validate
  stopifnot(!is.null(svr_result))
  stopifnot(length(svr_result$models) == n_persons)
  stopifnot(svr_result$n_persons == n_persons)

  cat(sprintf("    Trained models: %d\n", svr_result$n_persons))
  cat(sprintf("    Fallback models: %d\n", svr_result$n_fallback))
})

# ==============================================================================
# TEST 9: PREDICTION - QUADRATIC REGRESSION
# ==============================================================================

run_test("Quadratic Regression - Prediction on New Data", function() {
  # Train models first
  person_datasets <- list()
  for (pid in 1:n_persons) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2", "x3"),
      outcome = "outcome_quadratic",
      train_ratio = 0.8,
      seed = 42
    )
  }

  config <- list(
    metamodels = list(
      quadratic_regression = list(include_interactions = TRUE)
    ),
    modeling = list(random_seed = 42)
  )

  qr_result <- train_qr_all_persons(person_datasets, "outcome_quadratic", config)

  # Create new data for prediction
  new_data <- data.table(
    person_id = rep(1:n_persons, each = 5),
    x1 = runif(n_persons * 5, 0, 10),
    x2 = runif(n_persons * 5, 5, 15),
    x3 = runif(n_persons * 5, -5, 5)
  )

  # Generate predictions
  predictions <- predict_qr_new_data(qr_result$models, new_data, "person_id")

  # Validate
  stopifnot(nrow(predictions) == nrow(new_data))
  stopifnot("prediction" %in% names(predictions))
  stopifnot(all(!is.na(predictions$prediction)))

  cat(sprintf("    Predicted %d scenarios\n", nrow(predictions)))
  cat(sprintf("    Mean prediction: %.2f\n", mean(predictions$prediction)))
})

# ==============================================================================
# TEST 10: PREDICTION - CUBIC REGRESSION
# ==============================================================================

run_test("Cubic Regression - Prediction on New Data", function() {
  # Train models
  person_datasets <- list()
  for (pid in 1:n_persons) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2"),
      outcome = "outcome_cubic",
      train_ratio = 0.8,
      seed = 42
    )
  }

  config <- list(
    metamodels = list(
      cubic_regression = list(
        include_two_way_interactions = TRUE,
        include_three_way_interactions = FALSE
      )
    ),
    modeling = list(random_seed = 42)
  )

  cr_result <- train_cr_all_persons(person_datasets, "outcome_cubic", config)

  # Create new data
  new_data <- data.table(
    person_id = rep(1:n_persons, each = 5),
    x1 = runif(n_persons * 5, 0, 10),
    x2 = runif(n_persons * 5, 5, 15)
  )

  # Predict
  predictions <- predict_cr_new_data(cr_result$models, new_data, "person_id")

  # Validate
  stopifnot(nrow(predictions) == nrow(new_data))
  stopifnot("prediction" %in% names(predictions))
  stopifnot(all(!is.na(predictions$prediction)))

  cat(sprintf("    Predicted %d scenarios\n", nrow(predictions)))
  cat(sprintf("    Mean prediction: %.2f\n", mean(predictions$prediction)))
})

# ==============================================================================
# TEST 11: PREDICTION - SVR
# ==============================================================================

run_test("Support Vector Regression - Prediction on New Data", function() {
  # Train models
  person_datasets <- list()
  for (pid in 1:n_persons) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2", "x3"),
      outcome = "outcome_linear",
      train_ratio = 0.8,
      seed = 42
    )
  }

  config <- list(
    metamodels = list(
      support_vector_regression = list(
        kernel = "radial",
        tune_hyperparameters = FALSE,
        tune_cost_grid = c(1),
        tune_epsilon_grid = c(0.1)
      )
    ),
    modeling = list(random_seed = 42)
  )

  svr_result <- train_svr_all_persons(person_datasets, "outcome_linear", config)

  # Create new data
  new_data <- data.table(
    person_id = rep(1:n_persons, each = 5),
    x1 = runif(n_persons * 5, 0, 10),
    x2 = runif(n_persons * 5, 5, 15),
    x3 = runif(n_persons * 5, -5, 5)
  )

  # Predict
  predictions <- predict_svr_new_data(svr_result$models, new_data, "person_id")

  # Validate
  stopifnot(nrow(predictions) == nrow(new_data))
  stopifnot("prediction" %in% names(predictions))
  stopifnot(all(!is.na(predictions$prediction)))

  cat(sprintf("    Predicted %d scenarios\n", nrow(predictions)))
  cat(sprintf("    Mean prediction: %.2f\n", mean(predictions$prediction)))
})

# ==============================================================================
# TEST 12: COEFFICIENT EXTRACTION
# ==============================================================================

run_test("Coefficient Extraction - QR and CR", function() {
  # Train QR models
  person_datasets <- list()
  for (pid in 1:2) {
    person_datasets[[pid]] <- prepare_person_data(
      test_data,
      person_id = pid,
      person_id_col = "person_id",
      predictors = c("x1", "x2"),
      outcome = "outcome_quadratic",
      train_ratio = 0.8,
      seed = 42
    )
  }

  config <- list(
    metamodels = list(
      quadratic_regression = list(include_interactions = TRUE)
    ),
    modeling = list(random_seed = 42)
  )

  qr_result <- train_qr_all_persons(person_datasets, "outcome_quadratic", config)

  # Extract coefficients
  coefs <- extract_qr_coefficients(qr_result$models)

  # Validate
  stopifnot(nrow(coefs) > 0)
  stopifnot(all(c("person_id", "term", "estimate") %in% names(coefs)))
  stopifnot(length(unique(coefs$person_id)) == 2)

  cat(sprintf("    Extracted coefficients for %d persons\n", length(unique(coefs$person_id))))
  cat(sprintf("    Total coefficients: %d\n", nrow(coefs)))
})

# ==============================================================================
# TEST SUMMARY
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("                         TEST SUMMARY                                          \n")
cat("================================================================================\n")
cat("\n")
cat(sprintf("Total tests:  %d\n", test_count))
cat(sprintf("Passed:       %d (%.1f%%)\n", pass_count, 100 * pass_count / test_count))
cat(sprintf("Failed:       %d\n", fail_count))
cat("\n")

if (fail_count == 0) {
  cat("================================================================================\n")
  cat("                   ✓ ALL TESTS PASSED                                         \n")
  cat("================================================================================\n")
} else {
  cat("================================================================================\n")
  cat("                   ✗ SOME TESTS FAILED                                        \n")
  cat("================================================================================\n")
}

cat("\n")
