# ==============================================================================
# Support Vector Regression (SVR) Metamodel Module
# ==============================================================================
#
# This module provides functions for training person-specific Support Vector
# Regression metamodels using caret and kernlab packages.
#
# MATCHES ORIGINAL IMPLEMENTATION:
# - Uses caret::train with method = "svmRadial"
# - Grid: sigma = c(0.01, 0.1, 1), C = c(0.1, 1, 10)
# - Loops over epsilon = c(0.01, 0.1, 0.5)
# - Preprocessing: center and scale
#
# Author: Metamodel Generalized System
# Dependencies: data.table, caret, kernlab
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(caret)
  library(kernlab)
})

# ==============================================================================
# Default Grid Parameters (matching original)
# ==============================================================================

SVR_SIGMA_GRID   <- c(0.01, 0.1, 1)
SVR_C_GRID       <- c(0.1, 1, 10)
SVR_EPSILON_GRID <- c(0.01, 0.1, 0.5)

# ==============================================================================
# Core SVR Training Functions
# ==============================================================================

#' Train SVR Model for Single Person
#'
#' Trains a person-specific SVR model using caret with svmRadial.
#' This matches the original implementation exactly - loops over epsilon values.
#'
#' @param person_data List from prepare_person_data() containing train/test splits
#' @param outcome Character; name of outcome variable
#' @param config Configuration list
#'
#' @return List containing model results
train_svr_person <- function(person_data, outcome, config) {

  person_id <- person_data$person_id
  train_data <- person_data$train
  test_data <- person_data$test
  predictors_used <- person_data$predictors_used

  # Get grid parameters from config or use defaults
  svr_config <- config$metamodels$support_vector_regression
  sigma_grid <- svr_config$sigma_grid %||% SVR_SIGMA_GRID
  C_grid <- svr_config$C_grid %||% SVR_C_GRID
  epsilon_grid <- svr_config$epsilon_grid %||% SVR_EPSILON_GRID

  # Determine number of CV folds
  folds <- min(5L, nrow(train_data))
  deg_y <- length(unique(train_data[[outcome]])) < 2
  too_small <- folds < 2L || nrow(train_data) < 2L || length(predictors_used) == 0L

  # Handle fallback cases
  if (isTRUE(person_data$is_fallback) || too_small || deg_y) {
    ybar <- if (nrow(train_data) > 0L) mean(train_data[[outcome]], na.rm = TRUE) else NA_real_

    # Calculate fallback metrics
    train_metrics <- NULL
    test_metrics <- NULL

    if (nrow(train_data) > 0L) {
      train_pred <- rep(ybar, nrow(train_data))
      train_actual <- train_data[[outcome]]
      train_metrics <- calculate_metrics(train_actual, train_pred)
    }

    if (!is.null(test_data) && nrow(test_data) > 0L) {
      test_pred <- rep(ybar, nrow(test_data))
      test_actual <- test_data[[outcome]]
      test_metrics <- calculate_metrics(test_actual, test_pred)
    }

    return(list(
      model = list(type = "mean_only", mean_y = ybar),
      person_id = person_id,
      group = person_data$group %||% NA_character_,
      outcome = outcome,
      predictors_used = predictors_used,
      n_predictors = length(predictors_used),
      train_metrics = train_metrics,
      test_metrics = test_metrics,
      n_train = nrow(train_data),
      n_test = if (!is.null(test_data)) nrow(test_data) else 0L,
      dropped_constants = person_data$dropped_constants %||% character(0),
      best_sigma = NA_real_,
      best_C = NA_real_,
      best_epsilon = NA_real_,
      folds_used = folds,
      success = TRUE,
      is_fallback = TRUE,
      fallback_reason = if (isTRUE(person_data$is_fallback)) {
        person_data$fallback_reason
      } else if (too_small) {
        "Insufficient data"
      } else {
        "Constant outcome"
      }
    ))
  }

  # Grid search over epsilon values (matching original)
  best <- NULL
  best_rmse <- Inf
  best_eps <- NA_real_

  for (eps in epsilon_grid) {
    # Create grid for sigma and C
    tg <- expand.grid(C = C_grid, sigma = sigma_grid)
    ctrl <- trainControl(method = "cv", number = folds)

    # Train SVR using caret with svmRadial (kernlab backend)
    fit_cv <- tryCatch({
      train(
        x = train_data[, ..predictors_used],
        y = train_data[[outcome]],
        method = "svmRadial",
        preProcess = c("center", "scale"),
        trControl = ctrl,
        tuneGrid = tg,
        epsilon = eps
      )
    }, error = function(e) {
      NULL
    })

    if (!is.null(fit_cv)) {
      # Get RMSE for best tune
      bt <- fit_cv$bestTune
      rmse_row <- fit_cv$results[fit_cv$results$C == bt$C &
                                   fit_cv$results$sigma == bt$sigma, ]
      rmse_val <- rmse_row$RMSE[1]

      if (!is.na(rmse_val) && rmse_val < best_rmse) {
        best <- fit_cv
        best_rmse <- rmse_val
        best_eps <- eps
      }
    }
  }

  # If training failed, return fallback
  if (is.null(best)) {
    ybar <- mean(train_data[[outcome]], na.rm = TRUE)

    train_pred <- rep(ybar, nrow(train_data))
    train_actual <- train_data[[outcome]]
    train_metrics <- calculate_metrics(train_actual, train_pred)

    test_metrics <- NULL
    if (!is.null(test_data) && nrow(test_data) > 0L) {
      test_pred <- rep(ybar, nrow(test_data))
      test_actual <- test_data[[outcome]]
      test_metrics <- calculate_metrics(test_actual, test_pred)
    }

    return(list(
      model = list(type = "mean_only", mean_y = ybar),
      person_id = person_id,
      group = person_data$group %||% NA_character_,
      outcome = outcome,
      predictors_used = predictors_used,
      n_predictors = length(predictors_used),
      train_metrics = train_metrics,
      test_metrics = test_metrics,
      n_train = nrow(train_data),
      n_test = if (!is.null(test_data)) nrow(test_data) else 0L,
      dropped_constants = person_data$dropped_constants %||% character(0),
      best_sigma = NA_real_,
      best_C = NA_real_,
      best_epsilon = NA_real_,
      folds_used = folds,
      success = FALSE,
      is_fallback = TRUE,
      fallback_reason = "Training failed"
    ))
  }

  # Calculate training predictions and metrics
  train_pred <- predict(best, newdata = train_data[, ..predictors_used])
  train_actual <- train_data[[outcome]]
  train_metrics <- calculate_metrics(train_actual, train_pred)

  # Calculate test predictions and metrics
  test_metrics <- NULL
  if (!is.null(test_data) && nrow(test_data) > 0L) {
    test_pred <- predict(best, newdata = test_data[, ..predictors_used])
    test_actual <- test_data[[outcome]]
    test_metrics <- calculate_metrics(test_actual, test_pred)
  }

  # Get best hyperparameters
  bt <- best$bestTune

  return(list(
    model = best,
    person_id = person_id,
    group = person_data$group %||% NA_character_,
    outcome = outcome,
    predictors_used = predictors_used,
    n_predictors = length(predictors_used),
    train_metrics = train_metrics,
    test_metrics = test_metrics,
    n_train = nrow(train_data),
    n_test = if (!is.null(test_data)) nrow(test_data) else 0L,
    dropped_constants = person_data$dropped_constants %||% character(0),
    best_sigma = bt$sigma[1],
    best_C = bt$C[1],
    best_epsilon = best_eps,
    folds_used = folds,
    success = TRUE,
    is_fallback = FALSE,
    fallback_reason = NULL
  ))
}


#' Train SVR Models for All Persons (Single Outcome)
#'
#' @param person_datasets List of person-specific datasets from prepare_person_data()
#' @param outcome Character; outcome variable name
#' @param config Configuration list
#'
#' @return List containing trained SVR models
train_svr_all_persons <- function(person_datasets, outcome, config) {

  models <- list()
  n_fallback <- 0

  for (i in seq_along(person_datasets)) {
    person_data <- person_datasets[[i]]
    person_id <- person_data$person_id

    svr_result <- train_svr_person(person_data, outcome, config)

    if (isTRUE(svr_result$is_fallback)) {
      n_fallback <- n_fallback + 1
    }

    models[[as.character(person_id)]] <- svr_result
  }

  return(list(
    models = models,
    outcome = outcome,
    n_persons = length(models),
    n_fallback = n_fallback
  ))
}


#' Train SVR for Single Group-Outcome Combination
#'
#' @param person_datasets_entry Single entry from person_datasets list
#' @param config Configuration list
#'
#' @return SVR results for this group-outcome combination
train_svr_group_outcome <- function(person_datasets_entry, config) {

  group_name <- person_datasets_entry$group
  outcome <- person_datasets_entry$outcome
  person_datasets <- person_datasets_entry$datasets

  svr_result <- train_svr_all_persons(person_datasets, outcome, config)
  svr_result$group <- group_name

  return(svr_result)
}


#' Train SVR Models for All Groups and Outcomes
#'
#' @param person_datasets_list List of person datasets (from Step 2)
#' @param config Configuration list
#'
#' @return Named list of SVR results, one entry per group-outcome combination
train_svr_all <- function(person_datasets_list, config) {

  if (!isTRUE(config$metamodels$support_vector_regression$enabled)) {
    return(NULL)
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    SUPPORT VECTOR REGRESSION TRAINING                         \n")
  cat("================================================================================\n")

  svr_results <- list()

  for (i in seq_along(person_datasets_list)) {
    entry <- person_datasets_list[[i]]
    key <- names(person_datasets_list)[i]

    svr_result <- train_svr_group_outcome(entry, config)
    svr_results[[key]] <- svr_result

    cat(sprintf("  Completed: %s - %s (%d models, %d fallback)\n",
                svr_result$group, svr_result$outcome,
                svr_result$n_persons, svr_result$n_fallback))
  }

  # Save all models if configured
  if (isTRUE(config$modeling$save_models)) {
    save_svr_models(svr_results, config)
  }

  cat("================================================================================\n")

  return(svr_results)
}


# ==============================================================================
# Model Persistence Functions
# ==============================================================================

#' Save SVR Models to Disk
#'
#' @param svr_result SVR results from train_svr_all()
#' @param config Configuration list
save_svr_models <- function(svr_result, config) {

  if (!isTRUE(config$modeling$save_models)) {
    return(invisible(NULL))
  }

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "svr")

  if (!dir.exists(models_dir)) {
    dir.create(models_dir, recursive = TRUE)
  }

  for (key in names(svr_result)) {
    result <- svr_result[[key]]
    group <- result$group
    outcome <- result$outcome

    filename <- sprintf("svr_%s_%s.rds", group, outcome)
    filepath <- file.path(models_dir, filename)

    saveRDS(result, filepath)
  }
}


#' Load SVR Models from Disk
#'
#' @param group Character; group name
#' @param outcome Character; outcome name
#' @param config Configuration list
#'
#' @return SVR results list
load_svr_models <- function(group, outcome, config) {

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "svr")

  filename <- sprintf("svr_%s_%s.rds", group, outcome)
  filepath <- file.path(models_dir, filename)

  if (!file.exists(filepath)) {
    stop(sprintf("SVR model file not found: %s", filepath))
  }

  svr_result <- readRDS(filepath)
  return(svr_result)
}


# ==============================================================================
# Prediction Functions
# ==============================================================================

#' Predict Using SVR Models on New Data
#'
#' @param svr_models List of SVR models from train_svr_all_persons()
#' @param new_data data.table with predictor columns
#' @param person_id_col Character; name of person ID column in new_data
#'
#' @return data.table with predictions
predict_svr_new_data <- function(svr_models, new_data, person_id_col = "person_idx") {

  if (!person_id_col %in% names(new_data)) {
    stop(sprintf("Person ID column '%s' not found in new_data", person_id_col))
  }

  predictions_list <- list()

  for (person_id in unique(new_data[[person_id_col]])) {

    person_key <- as.character(person_id)

    if (!person_key %in% names(svr_models)) {
      next
    }

    svr_model_obj <- svr_models[[person_key]]
    person_new_data <- new_data[get(person_id_col) == person_id]
    up <- svr_model_obj$used_predictors

    # Handle fallback/mean-only models
    if (isTRUE(svr_model_obj$is_fallback) ||
        (!is.null(svr_model_obj$model$type) && svr_model_obj$model$type == "mean_only")) {
      pred_values <- rep(svr_model_obj$model$mean_y, nrow(person_new_data))
    } else if (length(up) == 0L || is.null(svr_model_obj$model)) {
      pred_values <- rep(NA_real_, nrow(person_new_data))
    } else {
      pred_values <- as.numeric(predict(svr_model_obj$model, newdata = person_new_data[, ..up]))
    }

    person_predictions <- data.table(
      person_idx = person_id,
      prediction = pred_values,
      r2_test = svr_model_obj$r2_test,
      best_sigma = svr_model_obj$best_sigma,
      best_C = svr_model_obj$best_C,
      best_epsilon = svr_model_obj$best_epsilon,
      folds_used = svr_model_obj$folds_used
    )

    predictions_list[[person_key]] <- person_predictions
  }

  if (length(predictions_list) == 0) {
    return(data.table())
  }

  all_predictions <- rbindlist(predictions_list, use.names = TRUE, fill = TRUE)
  return(all_predictions[order(person_idx)])
}


# ==============================================================================
# Summary Functions
# ==============================================================================

#' Summarize SVR Training Results
#'
#' @param svr_results List of SVR results from train_svr_all()
#'
#' @return data.table with summary statistics
summarize_svr_results <- function(svr_results) {

  if (is.null(svr_results) || length(svr_results) == 0) {
    return(data.table())
  }

  summary_list <- list()

  for (key in names(svr_results)) {
    result <- svr_results[[key]]
    group <- result$group
    outcome <- result$outcome
    models <- result$models

    for (person_id in names(models)) {
      model_obj <- models[[person_id]]

      summary_list[[length(summary_list) + 1]] <- data.table(
        group = group,
        outcome = outcome,
        person_idx = as.integer(person_id),
        folds_used = model_obj$folds_used,
        r2_test = model_obj$r2_test,
        n_train = model_obj$n_train,
        n_test = model_obj$n_test,
        best_sigma = model_obj$best_sigma,
        best_C = model_obj$best_C,
        best_epsilon = model_obj$best_epsilon,
        is_fallback = isTRUE(model_obj$is_fallback)
      )
    }
  }

  summary_dt <- rbindlist(summary_list, use.names = TRUE, fill = TRUE)
  return(summary_dt)
}
