# ==============================================================================
# Neural Network (NN) Metamodel Module
# ==============================================================================
#
# This module provides functions for training person-specific Neural Network
# metamodels using caret with cross-validation.
#
# MATCHES ORIGINAL IMPLEMENTATION:
# - Uses caret::train with method = "nnet"
# - size_grid: c(1, 3, 5, 10)
# - decay_grid: c(0, 1e-4, 1e-3, 1e-2)
# - maxit = 500
# - MaxNWts = 20000
# - preProcess = c("center", "scale")
# - linout = TRUE (regression)
#
# Author: Metamodel Generalized System
# Dependencies: data.table, caret, nnet
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(caret)
  library(nnet)
})

# ==============================================================================
# Default Grid Parameters (matching original)
# ==============================================================================

NN_SIZE_GRID  <- c(1, 3, 5, 10)
NN_DECAY_GRID <- c(0, 1e-4, 1e-3, 1e-2)
NN_MAXIT      <- 500
NN_MAXNWTS    <- 20000

# ==============================================================================
# Core NN Training Functions
# ==============================================================================

#' Train NN Model for Single Person
#'
#' Trains a person-specific Neural Network model using caret with CV.
#' This matches the original implementation exactly.
#'
#' @param person_data List from prepare_person_data() containing train/test splits
#' @param outcome Character; name of outcome variable
#' @param config Configuration list
#'
#' @return List containing model results
train_nn_person <- function(person_data, outcome, config) {

  person_id <- person_data$person_id
  train_data <- person_data$train
  test_data <- person_data$test
  predictors_used <- person_data$predictors_used

  # Get grid parameters from config or use defaults
  nn_config <- config$metamodels$neural_network
  size_grid <- nn_config$size_grid %||% NN_SIZE_GRID
  decay_grid <- nn_config$decay_grid %||% NN_DECAY_GRID
  maxit_nn <- nn_config$maxit %||% NN_MAXIT
  maxnwts_nn <- nn_config$maxnwts %||% NN_MAXNWTS

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
      best_size = NA_integer_,
      best_decay = NA_real_,
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

  # Create tune grid: size x decay (matching original)
  tg <- expand.grid(size = size_grid, decay = decay_grid)
  ctrl <- trainControl(method = "cv", number = folds)

  # Train NN using caret (matching original)
  fit_cv <- tryCatch({
    train(
      x = train_data[, ..predictors_used],
      y = train_data[[outcome]],
      method = "nnet",
      preProcess = c("center", "scale"),
      trControl = ctrl,
      tuneGrid = tg,
      linout = TRUE,
      trace = FALSE,
      MaxNWts = maxnwts_nn,
      maxit = maxit_nn
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
      best_size = NA_integer_,
      best_decay = NA_real_,
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
  best_size <- fit_cv$bestTune$size[1]
  best_decay <- fit_cv$bestTune$decay[1]

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
    best_size = best_size,
    best_decay = best_decay,
    folds_used = folds,
    success = TRUE,
    is_fallback = FALSE,
    fallback_reason = NULL
  ))
}


#' Train NN Models for All Persons (Single Outcome)
#'
#' @param person_datasets List of person-specific datasets from prepare_person_data()
#' @param outcome Character; outcome variable name
#' @param config Configuration list
#'
#' @return List containing trained NN models
train_nn_all_persons <- function(person_datasets, outcome, config) {

  models <- list()
  n_fallback <- 0

  for (i in seq_along(person_datasets)) {
    person_data <- person_datasets[[i]]
    person_id <- person_data$person_id

    nn_result <- train_nn_person(person_data, outcome, config)

    if (isTRUE(nn_result$is_fallback)) {
      n_fallback <- n_fallback + 1
    }

    models[[as.character(person_id)]] <- nn_result
  }

  return(list(
    models = models,
    outcome = outcome,
    n_persons = length(models),
    n_fallback = n_fallback
  ))
}


#' Train NN for Single Group-Outcome Combination
#'
#' @param person_datasets_entry Single entry from person_datasets list
#' @param config Configuration list
#'
#' @return NN results for this group-outcome combination
train_nn_group_outcome <- function(person_datasets_entry, config) {

  group_name <- person_datasets_entry$group
  outcome <- person_datasets_entry$outcome
  person_datasets <- person_datasets_entry$datasets

  nn_result <- train_nn_all_persons(person_datasets, outcome, config)
  nn_result$group <- group_name

  return(nn_result)
}


#' Train NN Models for All Groups and Outcomes
#'
#' @param person_datasets_list List of person datasets (from Step 2)
#' @param config Configuration list
#'
#' @return Named list of NN results, one entry per group-outcome combination
train_nn_all <- function(person_datasets_list, config) {

  if (!isTRUE(config$metamodels$neural_network$enabled)) {
    return(NULL)
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    NEURAL NETWORK TRAINING                                     \n")
  cat("================================================================================\n")

  nn_results <- list()

  for (i in seq_along(person_datasets_list)) {
    entry <- person_datasets_list[[i]]
    key <- names(person_datasets_list)[i]

    nn_result <- train_nn_group_outcome(entry, config)
    nn_results[[key]] <- nn_result

    cat(sprintf("  Completed: %s - %s (%d models, %d fallback)\n",
                nn_result$group, nn_result$outcome,
                nn_result$n_persons, nn_result$n_fallback))
  }

  # Save all models if configured
  if (isTRUE(config$modeling$save_models)) {
    save_nn_models(nn_results, config)
  }

  cat("================================================================================\n")

  return(nn_results)
}


# ==============================================================================
# Model Persistence Functions
# ==============================================================================

#' Save NN Models to Disk
#'
#' @param nn_result NN results from train_nn_all()
#' @param config Configuration list
save_nn_models <- function(nn_result, config) {

  if (!isTRUE(config$modeling$save_models)) {
    return(invisible(NULL))
  }

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "neural_network")

  if (!dir.exists(models_dir)) {
    dir.create(models_dir, recursive = TRUE)
  }

  for (key in names(nn_result)) {
    result <- nn_result[[key]]
    group <- result$group
    outcome <- result$outcome

    filename <- sprintf("nn_%s_%s.rds", group, outcome)
    filepath <- file.path(models_dir, filename)

    saveRDS(result, filepath)
  }
}


#' Load NN Models from Disk
#'
#' @param group Character; group name
#' @param outcome Character; outcome name
#' @param config Configuration list
#'
#' @return NN results list
load_nn_models <- function(group, outcome, config) {

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "neural_network")

  filename <- sprintf("nn_%s_%s.rds", group, outcome)
  filepath <- file.path(models_dir, filename)

  if (!file.exists(filepath)) {
    stop(sprintf("NN model file not found: %s", filepath))
  }

  nn_result <- readRDS(filepath)
  return(nn_result)
}


# ==============================================================================
# Prediction Functions
# ==============================================================================

#' Predict Using NN Models on New Data
#'
#' @param nn_models List of NN models from train_nn_all_persons()
#' @param new_data data.table with predictor columns
#' @param person_id_col Character; name of person ID column in new_data
#'
#' @return data.table with predictions
predict_nn_new_data <- function(nn_models, new_data, person_id_col = "person_idx") {

  if (!person_id_col %in% names(new_data)) {
    stop(sprintf("Person ID column '%s' not found in new_data", person_id_col))
  }

  predictions_list <- list()

  for (person_id in unique(new_data[[person_id_col]])) {

    person_key <- as.character(person_id)

    if (!person_key %in% names(nn_models)) {
      next
    }

    nn_model_obj <- nn_models[[person_key]]
    person_new_data <- new_data[get(person_id_col) == person_id]
    up <- nn_model_obj$used_predictors

    # Handle fallback/mean-only models
    if (isTRUE(nn_model_obj$is_fallback) ||
        (!is.null(nn_model_obj$model$type) && nn_model_obj$model$type == "mean_only")) {
      pred_values <- rep(nn_model_obj$model$mean_y, nrow(person_new_data))
    } else if (length(up) == 0L || is.null(nn_model_obj$model)) {
      pred_values <- rep(NA_real_, nrow(person_new_data))
    } else {
      pred_values <- as.numeric(predict(nn_model_obj$model, newdata = person_new_data[, ..up]))
    }

    person_predictions <- data.table(
      person_idx = person_id,
      prediction = pred_values,
      r2_test = nn_model_obj$r2_test,
      best_size = nn_model_obj$best_size,
      best_decay = nn_model_obj$best_decay,
      folds_used = nn_model_obj$folds_used
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

#' Summarize NN Training Results
#'
#' @param nn_results List of NN results from train_nn_all()
#'
#' @return data.table with summary statistics
summarize_nn_results <- function(nn_results) {

  if (is.null(nn_results) || length(nn_results) == 0) {
    return(data.table())
  }

  summary_list <- list()

  for (key in names(nn_results)) {
    result <- nn_results[[key]]
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
        best_size = model_obj$best_size,
        best_decay = model_obj$best_decay,
        is_fallback = isTRUE(model_obj$is_fallback)
      )
    }
  }

  summary_dt <- rbindlist(summary_list, use.names = TRUE, fill = TRUE)
  return(summary_dt)
}
