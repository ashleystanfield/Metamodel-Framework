# ==============================================================================
# Quadratic Regression (QR) Metamodel Module
# ==============================================================================
#
# This module provides functions for training person-specific Quadratic
# Regression metamodels. QR extends linear regression by adding polynomial
# degree-2 terms (squared terms only - NO interactions to match original).
#
# Formula: y ~ x1 + x2 + ... + I(x1^2) + I(x2^2) + ...
#
# Author: Metamodel Generalized System
# Dependencies: data.table, stats
# ==============================================================================

library(data.table)

# ==============================================================================
# Core QR Training Functions
# ==============================================================================

#' Train Quadratic Regression Model for Single Person
#'
#' Trains a person-specific quadratic regression model using I(x^2) terms.
#' This matches the original implementation exactly - NO interaction terms.
#'
#' @param person_data List from prepare_person_data() containing train/test splits
#' @param outcome Character; name of outcome variable
#' @param config Configuration list
#'
#' @return List containing model results
train_qr_person <- function(person_data, outcome, config) {

  person_id <- person_data$person_id
  train_data <- person_data$train
  test_data <- person_data$test
  predictors_used <- person_data$predictors_used

  # Handle fallback cases
 if (isTRUE(person_data$is_fallback) || length(predictors_used) == 0) {
    # Fallback: predict mean of training outcome
    mean_outcome <- if (nrow(train_data) > 0) mean(train_data[[outcome]], na.rm = TRUE) else NA_real_

    train_pred <- rep(mean_outcome, nrow(train_data))

    # Calculate train metrics
    train_metrics <- list(r_squared = NA_real_, rmse = NA_real_, mae = NA_real_)
    if (nrow(train_data) > 0 && !is.na(mean_outcome)) {
      ss_res <- sum((train_data[[outcome]] - train_pred)^2)
      ss_tot <- sum((train_data[[outcome]] - mean(train_data[[outcome]]))^2)
      train_metrics$r_squared <- if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
      train_metrics$rmse <- sqrt(mean((train_data[[outcome]] - train_pred)^2))
      train_metrics$mae <- mean(abs(train_data[[outcome]] - train_pred))
    }

    test_metrics <- NULL
    if (!is.null(test_data) && nrow(test_data) > 0) {
      test_pred <- rep(mean_outcome, nrow(test_data))
      yact <- test_data[[outcome]]
      ss_res <- sum((yact - test_pred)^2)
      ss_tot <- sum((yact - mean(yact))^2)
      test_metrics <- list(
        r_squared = if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_,
        rmse = sqrt(mean((yact - test_pred)^2)),
        mae = mean(abs(yact - test_pred))
      )
    }

    return(list(
      model = NULL,
      person_id = person_id,
      outcome = outcome,
      predictors_used = predictors_used,
      n_predictors = length(predictors_used),
      train_metrics = train_metrics,
      test_metrics = test_metrics,
      coefficients = data.table(term = "(Intercept)", estimate = mean_outcome),
      success = TRUE,
      is_fallback = TRUE,
      fallback_reason = if (isTRUE(person_data$is_fallback)) person_data$fallback_reason else "No predictors"
    ))
  }

  # Build quadratic formula: y ~ x1 + x2 + I(x1^2) + I(x2^2)
  # NO INTERACTIONS - matches original exactly
  quad_terms <- paste0("I(", predictors_used, "^2)")
  rhs <- paste(c(predictors_used, quad_terms), collapse = " + ")
  formula_str <- paste(outcome, "~", rhs)
  formula_obj <- as.formula(formula_str)

  # Train quadratic regression model
  tryCatch({
    model <- lm(formula_obj, data = train_data)

    # Training predictions and metrics
    train_pred <- predict(model, newdata = train_data)
    train_actual <- train_data[[outcome]]
    ss_res_train <- sum((train_actual - train_pred)^2)
    ss_tot_train <- sum((train_actual - mean(train_actual))^2)
    train_metrics <- list(
      r_squared = if (ss_tot_train > 0) 1 - ss_res_train / ss_tot_train else NA_real_,
      rmse = sqrt(mean((train_actual - train_pred)^2)),
      mae = mean(abs(train_actual - train_pred))
    )

    # Test predictions and metrics
    test_metrics <- NULL
    r2_test <- NA_real_
    if (!is.null(test_data) && nrow(test_data) > 0) {
      test_pred <- predict(model, newdata = test_data)
      test_actual <- test_data[[outcome]]
      ss_res <- sum((test_actual - test_pred)^2)
      ss_tot <- sum((test_actual - mean(test_actual))^2)
      r2_test <- if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_
      test_metrics <- list(
        r_squared = r2_test,
        rmse = sqrt(mean((test_actual - test_pred)^2)),
        mae = mean(abs(test_actual - test_pred))
      )
    } else {
      # Use training R² if no test data
      r2_test <- summary(model)$r.squared
    }

    # Extract coefficients
    coefs <- as.data.table(summary(model)$coefficients, keep.rownames = TRUE)
    setnames(coefs, c("term", "estimate", "std_error", "t_value", "p_value"))

    return(list(
      model = model,
      person_id = person_id,
      outcome = outcome,
      predictors_used = predictors_used,
      n_predictors = length(predictors_used),
      r2_test = r2_test,
      n_train = nrow(train_data),
      n_test = if (!is.null(test_data)) nrow(test_data) else 0,
      train_metrics = train_metrics,
      test_metrics = test_metrics,
      coefficients = coefs,
      success = TRUE,
      is_fallback = FALSE,
      fallback_reason = NULL
    ))

  }, error = function(e) {
    # Fallback to mean prediction on error
    mean_outcome <- mean(train_data[[outcome]], na.rm = TRUE)

    train_pred <- rep(mean_outcome, nrow(train_data))
    train_metrics <- list(r_squared = NA_real_, rmse = NA_real_, mae = NA_real_)

    test_metrics <- NULL
    if (!is.null(test_data) && nrow(test_data) > 0) {
      test_pred <- rep(mean_outcome, nrow(test_data))
      yact <- test_data[[outcome]]
      ss_res <- sum((yact - test_pred)^2)
      ss_tot <- sum((yact - mean(yact))^2)
      test_metrics <- list(
        r_squared = if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_,
        rmse = sqrt(mean((yact - test_pred)^2)),
        mae = mean(abs(yact - test_pred))
      )
    }

    return(list(
      model = NULL,
      person_id = person_id,
      outcome = outcome,
      predictors_used = predictors_used,
      n_predictors = length(predictors_used),
      train_metrics = train_metrics,
      test_metrics = test_metrics,
      coefficients = data.table(term = "(Intercept)", estimate = mean_outcome),
      success = FALSE,
      is_fallback = TRUE,
      fallback_reason = paste("Training error:", e$message)
    ))
  })
}


#' Train QR Models for All Persons (Single Outcome)
#'
#' @param person_datasets List of person-specific datasets from prepare_person_data()
#' @param outcome Character; outcome variable name
#' @param config Configuration list
#'
#' @return List containing trained QR models
train_qr_all_persons <- function(person_datasets, outcome, config) {

  models <- list()
  n_fallback <- 0

  for (i in seq_along(person_datasets)) {
    person_data <- person_datasets[[i]]
    person_id <- person_data$person_id

    qr_result <- train_qr_person(person_data, outcome, config)

    if (isTRUE(qr_result$is_fallback)) {
      n_fallback <- n_fallback + 1
    }

    models[[as.character(person_id)]] <- qr_result
  }

  return(list(
    models = models,
    outcome = outcome,
    n_persons = length(models),
    n_fallback = n_fallback
  ))
}


#' Train QR for Single Group-Outcome Combination
#'
#' @param person_datasets_entry Single entry from person_datasets list
#' @param config Configuration list
#'
#' @return QR results for this group-outcome combination
train_qr_group_outcome <- function(person_datasets_entry, config) {

  group_name <- person_datasets_entry$group
  outcome <- person_datasets_entry$outcome
  person_datasets <- person_datasets_entry$datasets

  qr_result <- train_qr_all_persons(person_datasets, outcome, config)
  qr_result$group <- group_name

  return(qr_result)
}


#' Train QR Models for All Groups and Outcomes
#'
#' @param person_datasets_list List of person datasets (from Step 2)
#' @param config Configuration list
#'
#' @return Named list of QR results, one entry per group-outcome combination
train_qr_all <- function(person_datasets_list, config) {

  if (!isTRUE(config$metamodels$quadratic_regression$enabled)) {
    return(NULL)
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    QUADRATIC REGRESSION TRAINING                              \n")
  cat("================================================================================\n")

  qr_results <- list()

  for (i in seq_along(person_datasets_list)) {
    entry <- person_datasets_list[[i]]
    key <- names(person_datasets_list)[i]

    qr_result <- train_qr_group_outcome(entry, config)
    qr_results[[key]] <- qr_result

    cat(sprintf("  Completed: %s - %s (%d models, %d fallback)\n",
                qr_result$group, qr_result$outcome,
                qr_result$n_persons, qr_result$n_fallback))
  }

  # Save all models if configured
  if (isTRUE(config$modeling$save_models)) {
    save_qr_models(qr_results, config)
  }

  cat("================================================================================\n")

  return(qr_results)
}


# ==============================================================================
# Model Persistence Functions
# ==============================================================================

#' Save QR Models to Disk
#'
#' @param qr_result QR results from train_qr_all()
#' @param config Configuration list
save_qr_models <- function(qr_result, config) {

  if (!isTRUE(config$modeling$save_models)) {
    return(invisible(NULL))
  }

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "quadratic_regression")

  if (!dir.exists(models_dir)) {
    dir.create(models_dir, recursive = TRUE)
  }

  for (key in names(qr_result)) {
    result <- qr_result[[key]]
    group <- result$group
    outcome <- result$outcome

    filename <- sprintf("qr_%s_%s.rds", group, outcome)
    filepath <- file.path(models_dir, filename)

    saveRDS(result, filepath)
  }
}


#' Load QR Models from Disk
#'
#' @param group Character; group name
#' @param outcome Character; outcome name
#' @param config Configuration list
#'
#' @return QR results list
load_qr_models <- function(group, outcome, config) {

  output_dir <- config$project$output_directory
  models_dir <- file.path(output_dir, "models", "quadratic_regression")

  filename <- sprintf("qr_%s_%s.rds", group, outcome)
  filepath <- file.path(models_dir, filename)

  if (!file.exists(filepath)) {
    stop(sprintf("QR model file not found: %s", filepath))
  }

  qr_result <- readRDS(filepath)
  return(qr_result)
}


# ==============================================================================
# Prediction Functions
# ==============================================================================

#' Predict Using QR Models on New Data
#'
#' @param qr_models List of QR models from train_qr_all_persons()
#' @param new_data data.table with predictor columns
#' @param person_id_col Character; name of person ID column in new_data
#'
#' @return data.table with predictions
predict_qr_new_data <- function(qr_models, new_data, person_id_col = "person_idx") {

  if (!person_id_col %in% names(new_data)) {
    stop(sprintf("Person ID column '%s' not found in new_data", person_id_col))
  }

  predictions_list <- list()

  for (person_id in unique(new_data[[person_id_col]])) {

    person_key <- as.character(person_id)

    if (!person_key %in% names(qr_models)) {
      next
    }

    qr_model_obj <- qr_models[[person_key]]
    person_new_data <- new_data[get(person_id_col) == person_id]

    # Handle fallback models
    if (isTRUE(qr_model_obj$is_fallback)) {
      mean_pred <- qr_model_obj$coefficients$estimate[1]
      pred_values <- rep(mean_pred, nrow(person_new_data))
    } else {
      pred_values <- predict(qr_model_obj$model, newdata = person_new_data)
    }

    person_predictions <- data.table(
      person_id = person_id,
      prediction = as.numeric(pred_values),
      r2_test = qr_model_obj$r2_test
    )

    predictions_list[[person_key]] <- person_predictions
  }

  if (length(predictions_list) == 0) {
    return(data.table())
  }

  all_predictions <- rbindlist(predictions_list, use.names = TRUE, fill = TRUE)
  return(all_predictions[order(person_id)])
}


# ==============================================================================
# Summary Functions
# ==============================================================================

#' Summarize QR Training Results
#'
#' @param qr_results List of QR results from train_qr_all()
#'
#' @return data.table with summary statistics
summarize_qr_results <- function(qr_results) {

  if (is.null(qr_results) || length(qr_results) == 0) {
    return(data.table())
  }

  summary_list <- list()

  for (key in names(qr_results)) {
    result <- qr_results[[key]]
    group <- result$group
    outcome <- result$outcome
    models <- result$models

    for (person_id in names(models)) {
      model_obj <- models[[person_id]]

      test_r2 <- if (!is.null(model_obj$test_metrics)) {
        model_obj$test_metrics$r_squared
      } else {
        model_obj$r2_test
      }

      summary_list[[length(summary_list) + 1]] <- data.table(
        group = group,
        outcome = outcome,
        person_id = person_id,
        n_predictors = model_obj$n_predictors,
        r2_test = test_r2,
        is_fallback = isTRUE(model_obj$is_fallback)
      )
    }
  }

  summary_dt <- rbindlist(summary_list, use.names = TRUE, fill = TRUE)
  return(summary_dt)
}
