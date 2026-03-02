# ==============================================================================
# Random Forest (RF) Metamodel Module
# ==============================================================================
#
# This module provides functions for training person-specific Random Forest
# metamodels using caret with cross-validation.
#
# MATCHES ORIGINAL IMPLEMENTATION:
# - Uses caret::train with method = "rf"
# - mtry grid: 1:length(predictors) (all possible values)
# - Cross-validation for hyperparameter tuning
# - importance = TRUE
#
# Author: Metamodel Generalized System
# Dependencies: data.table, caret, randomForest
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(caret)
  library(randomForest)
})

# ==============================================================================
# Core RF Training Functions
# ==============================================================================

#' Train RF Model for Single Person
#'
#' Trains a person-specific Random Forest model using caret with CV.
#' This matches the original implementation exactly.
#'
#' @param person_data List from prepare_person_data() containing train/test splits
#' @param outcome Character; name of outcome variable
#' @param config Configuration list
#'
#' @return List containing model results
train_rf_person <- function(person_data, outcome, config) {

  person_id <- person_data$person_id
  train_data <- person_data$train
  test_data <- person_data$test
  predictors_used <- person_data$predictors_used

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
      best_mtry = NA_integer_,
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

  # Create mtry grid: 1:length(predictors) as in original
  tg <- expand.grid(mtry = 1:length(predictors_used))
  ctrl <- trainControl(method = "cv", number = folds)

  # Train RF using caret (matching original)
  fit_cv <- tryCatch({
    train(
      x = train_data[, ..predictors_used],
      y = train_data[[outcome]],
      method = "rf",
      trControl = ctrl,
      tuneGrid = tg,
      importance = TRUE
    )
  }, error = function(e) {
    NULL
  })

  # If training failed, return fallback
  if (is.null(fit_cv)) {
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
      best_mtry = NA_integer_,
      folds_used = folds,
      success = FALSE,
      is_fallback = TRUE,
      fallback_reason = "Training failed"
    ))
  }

  # Calculate training predictions and metrics
  train_pred <- predict(fit_cv, newdata = train_data[, ..predictors_used])
  train_actual <- train_data[[outcome]]
  train_metrics <- calculate_metrics(train_actual, train_pred)

  # Calculate test predictions and metrics
  test_metrics <- NULL
  if (!is.null(test_data) && nrow(test_data) > 0L) {
    test_pred <- predict(fit_cv, newdata = test_data[, ..predictors_used])
    test_actual <- test_data[[outcome]]
    test_metrics <- calculate_metrics(test_actual, test_pred)
  }

  # Get best hyperparameters
  best_mtry <- fit_cv$bestTune$mtry[1]

  return(list(
    model = fit_cv,
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
    best_mtry = best_mtry,
    folds_used = folds,
    success = TRUE,
    is_fallback = FALSE,
    fallback_reason = NULL
  ))
}


#' Train RF Models for All Persons (Single Outcome)
#'
#' @param person_datasets List of person-specific datasets from prepare_person_data()
#' @param outcome Character; outcome variable name
#' @param config Configuration list
#'
#' @return List containing trained RF models
train_rf_all_persons <- function(person_datasets, outcome, config) {

  models <- list()
  n_fallback <- 0

  for (i in seq_along(person_datasets)) {
    person_data <- person_datasets[[i]]
    person_id <- person_data$person_id

    rf_result <- train_rf_person(person_data, outcome, config)

    if (isTRUE(rf_result$is_fallback)) {
      n_fallback <- n_fallback + 1
    }

    models[[as.character(person_id)]] <- rf_result
  }

  return(list(
    models = models,
    outcome = outcome,
    n_persons = length(models),
    n_fallback = n_fallback
  ))
}


#' Train RF for Single Group-Outcome Combination
#'
#' @param person_datasets_entry Single entry from person_datasets list
#' @param config Configuration list
#'
#' @return RF results for this group-outcome combination
train_rf_group_outcome <- function(person_datasets_entry, config) {

  group_name <- person_datasets_entry$group
  outcome <- person_datasets_entry$outcome
  person_datasets <- person_datasets_entry$datasets

  rf_result <- train_rf_all_persons(person_datasets, outcome, config)
  rf_result$group <- group_name

  return(rf_result)
}


#' Train RF Models for All Groups and Outcomes
#'
#' @param person_datasets_list List of person datasets (from Step 2)
#' @param config Configuration list
#'
#' @return Named list of RF results, one entry per group-outcome combination
train_rf_all <- function(person_datasets_list, config) {

  if (!isTRUE(config$metamodels$random_forest$enabled)) {
    return(NULL)
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    RANDOM FOREST TRAINING                                      \n")
  cat("================================================================================\n")

  rf_results <- list()

  for (i in seq_along(person_datasets_list)) {
    entry <- person_datasets_list[[i]]
    key <- names(person_datasets_list)[i]

    rf_result <- train_rf_group_outcome(entry, config)
    rf_results[[key]] <- rf_result

    cat(sprintf("  Completed: %s - %s (%d models, %d fallback)\n",
                rf_result$group, rf_result$outcome,
                rf_result$n_persons, rf_result$n_fallback))
  }

  # Save all models if configured
  if (isTRUE(config$modeling$save_models)) {
    save_rf_models(rf_results, config)
  }

  cat("================================================================================\n")

  return(rf_results)
}


# ==============================================================================
# Model Persistence Functions
# ==============================================================================

#' Save RF Models to Disk
#'
#' @param rf_result RF results from train_rf_all()
#' @param config Configuration list
save_rf_models <- function(rf_result, config) {

  if (!isTRUE(config$modeling$save_models)) {
    return(invisible(NULL))
  }

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "random_forest")

  if (!dir.exists(models_dir)) {
    dir.create(models_dir, recursive = TRUE)
  }

  for (key in names(rf_result)) {
    result <- rf_result[[key]]
    group <- result$group
    outcome <- result$outcome

    filename <- sprintf("rf_%s_%s.rds", group, outcome)
    filepath <- file.path(models_dir, filename)

    saveRDS(result, filepath)
  }
}


#' Load RF Models from Disk
#'
#' @param group Character; group name
#' @param outcome Character; outcome name
#' @param config Configuration list
#'
#' @return RF results list
load_rf_models <- function(group, outcome, config) {

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "random_forest")

  filename <- sprintf("rf_%s_%s.rds", group, outcome)
  filepath <- file.path(models_dir, filename)

  if (!file.exists(filepath)) {
    stop(sprintf("RF model file not found: %s", filepath))
  }

  rf_result <- readRDS(filepath)
  return(rf_result)
}


# ==============================================================================
# Prediction Functions
# ==============================================================================

#' Predict Using RF Models on New Data
#'
#' @param rf_models List of RF models from train_rf_all_persons()
#' @param new_data data.table with predictor columns
#' @param person_id_col Character; name of person ID column in new_data
#'
#' @return data.table with predictions
predict_rf_new_data <- function(rf_models, new_data, person_id_col = "person_idx") {

  if (!person_id_col %in% names(new_data)) {
    stop(sprintf("Person ID column '%s' not found in new_data", person_id_col))
  }

  predictions_list <- list()

  for (person_id in unique(new_data[[person_id_col]])) {

    person_key <- as.character(person_id)

    if (!person_key %in% names(rf_models)) {
      next
    }

    rf_model_obj <- rf_models[[person_key]]
    person_new_data <- new_data[get(person_id_col) == person_id]
    up <- rf_model_obj$used_predictors

    # Handle fallback/mean-only models
    if (isTRUE(rf_model_obj$is_fallback) ||
        (!is.null(rf_model_obj$model$type) && rf_model_obj$model$type == "mean_only")) {
      pred_values <- rep(rf_model_obj$model$mean_y, nrow(person_new_data))
    } else if (length(up) == 0L || is.null(rf_model_obj$model)) {
      pred_values <- rep(NA_real_, nrow(person_new_data))
    } else {
      pred_values <- as.numeric(predict(rf_model_obj$model, newdata = person_new_data[, ..up]))
    }

    person_predictions <- data.table(
      person_idx = person_id,
      prediction = pred_values,
      r2_test = rf_model_obj$r2_test,
      best_mtry = rf_model_obj$best_mtry,
      folds_used = rf_model_obj$folds_used
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

#' Summarize RF Training Results
#'
#' @param rf_results List of RF results from train_rf_all()
#'
#' @return data.table with summary statistics
summarize_rf_results <- function(rf_results) {

  if (is.null(rf_results) || length(rf_results) == 0) {
    return(data.table())
  }

  summary_list <- list()

  for (key in names(rf_results)) {
    result <- rf_results[[key]]
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
        best_mtry = model_obj$best_mtry,
        is_fallback = isTRUE(model_obj$is_fallback)
      )
    }
  }

  summary_dt <- rbindlist(summary_list, use.names = TRUE, fill = TRUE)
  return(summary_dt)
}
