################################################################################
#                         ENSEMBLE PREDICTIONS MODULE                          #
################################################################################
# Combine predictions from multiple metamodel types
# Supports simple averaging, weighted averaging, and stacking
################################################################################

suppressPackageStartupMessages({
  library(data.table)
})

#' Create ensemble prediction using simple average
#'
#' @param predictions Named vector or list of predictions (model_type -> prediction)
#' @return Single ensemble prediction
ensemble_simple_average <- function(predictions) {

  preds <- as.numeric(predictions)

  # Remove NAs
  valid_preds <- preds[is.finite(preds)]

  if (length(valid_preds) == 0) {
    return(NA_real_)
  }

  mean(valid_preds)
}

#' Create ensemble prediction using weighted average
#'
#' @param predictions Named vector of predictions
#' @param weights Named vector of weights (same names as predictions)
#' @return Single ensemble prediction
ensemble_weighted_average <- function(predictions, weights) {

  preds <- as.numeric(predictions)
  wts <- as.numeric(weights)

  # Match lengths
  if (length(preds) != length(wts)) {
    stop("Predictions and weights must have same length")
  }

  # Remove NAs
  valid_mask <- is.finite(preds) & is.finite(wts)
  preds <- preds[valid_mask]
  wts <- wts[valid_mask]

  if (length(preds) == 0) {
    return(NA_real_)
  }

  # Normalize weights
  wts <- wts / sum(wts)

  # Weighted average
  sum(preds * wts)
}

#' Create ensemble prediction using median
#'
#' @param predictions Named vector of predictions
#' @return Single ensemble prediction (median)
ensemble_median <- function(predictions) {

  preds <- as.numeric(predictions)

  # Remove NAs
  valid_preds <- preds[is.finite(preds)]

  if (length(valid_preds) == 0) {
    return(NA_real_)
  }

  median(valid_preds)
}

#' Calculate optimal ensemble weights based on past performance
#'
#' @param model_performance data.table with model performance metrics
#' @param metric Metric to optimize (default "mean_test_r2")
#' @param combination Specific combination to calculate weights for
#' @return Named vector of weights
calculate_ensemble_weights <- function(model_performance, metric = "mean_test_r2",
                                      combination = NULL) {

  # Filter to specific combination if provided
  if (!is.null(combination)) {
    perf <- model_performance[combination == combination]
  } else {
    perf <- model_performance
  }

  if (nrow(perf) == 0) {
    stop("No performance data available")
  }

  # Get metric values
  metric_values <- perf[[metric]]
  model_types <- perf$model_type

  # Handle NAs
  valid_mask <- is.finite(metric_values)
  metric_values <- metric_values[valid_mask]
  model_types <- model_types[valid_mask]

  if (length(metric_values) == 0) {
    stop("No valid metric values")
  }

  # Normalize to weights (higher metric = higher weight)
  # Handle negative values by shifting
  min_val <- min(metric_values)
  if (min_val < 0) {
    metric_values <- metric_values - min_val + 0.01
  }

  weights <- metric_values / sum(metric_values)

  # Return named vector
  names(weights) <- model_types

  return(weights)
}

#' Generate ensemble predictions for multiple models
#'
#' @param all_models List of trained models (lr, nn, rf, etc.)
#' @param new_data data.table with new data
#' @param person_id_col Name of person ID column
#' @param ensemble_method Method ("simple_average", "weighted_average", "median")
#' @param weights Optional weights for weighted_average (named vector)
#' @return data.table with individual and ensemble predictions
generate_ensemble_predictions <- function(all_models, new_data,
                                         person_id_col = "person_idx",
                                         ensemble_method = "simple_average",
                                         weights = NULL) {

  model_types <- names(all_models)

  cat(sprintf("\n▶ Generating ensemble predictions (%s)...\n", ensemble_method))
  cat(sprintf("  Model types: %s\n", paste(model_types, collapse = ", ")))

  # Get predictions from each model type
  pred_list <- list()

  for (mt in model_types) {
    cat(sprintf("  Predicting with %s...\n", mt))

    # Get models for first combination (assuming same structure across combinations)
    combo_key <- names(all_models[[mt]])[1]
    models <- all_models[[mt]][[combo_key]]$models

    # Predict based on model type
    if (mt == "linear_regression") {
      preds <- predict_lr_new_data(models, new_data, person_id_col)
    } else if (mt == "neural_network") {
      preds <- predict_nn_new_data(models, new_data, person_id_col)
    } else if (mt == "random_forest") {
      preds <- predict_rf_new_data(models, new_data, person_id_col)
    } else {
      warning(sprintf("Unknown model type: %s", mt))
      next
    }

    pred_list[[mt]] <- preds$prediction
  }

  # Combine predictions
  result <- copy(new_data)

  # Add individual model predictions
  for (mt in names(pred_list)) {
    col_name <- paste0("pred_", mt)
    result[[col_name]] <- pred_list[[mt]]
  }

  # Calculate ensemble prediction
  ensemble_preds <- numeric(nrow(result))

  for (i in 1:nrow(result)) {
    # Get predictions for this row
    row_preds <- sapply(pred_list, function(p) p[i])

    # Create ensemble
    if (ensemble_method == "simple_average") {
      ensemble_preds[i] <- ensemble_simple_average(row_preds)

    } else if (ensemble_method == "weighted_average") {
      if (is.null(weights)) {
        stop("Weights must be provided for weighted_average method")
      }
      ensemble_preds[i] <- ensemble_weighted_average(row_preds, weights)

    } else if (ensemble_method == "median") {
      ensemble_preds[i] <- ensemble_median(row_preds)

    } else {
      stop(sprintf("Unknown ensemble method: %s", ensemble_method))
    }
  }

  result[, ensemble := ensemble_preds]

  cat(sprintf("✓ Generated %d ensemble predictions\n", nrow(result)))

  return(result)
}

#' Generate population-level ensemble prediction
#'
#' @param all_models List of trained models
#' @param new_data Single-row data.table
#' @param population_weights Named list of population weights
#' @param ensemble_method Ensemble method
#' @param model_weights Optional model weights for weighted ensemble
#' @return Single population-level ensemble prediction
predict_population_ensemble <- function(all_models, new_data, population_weights,
                                       ensemble_method = "simple_average",
                                       model_weights = NULL) {

  model_types <- names(all_models)

  # Get population predictions from each model
  pop_preds <- numeric(length(model_types))
  names(pop_preds) <- model_types

  for (i in seq_along(model_types)) {
    mt <- model_types[i]

    # Get models for first combination
    combo_key <- names(all_models[[mt]])[1]
    models <- all_models[[mt]][[combo_key]]$models

    # Population prediction
    pred_result <- predict_population(models, new_data, population_weights,
                                     model_type = mt)

    pop_preds[i] <- pred_result$population_prediction
  }

  # Create ensemble
  if (ensemble_method == "simple_average") {
    ensemble_pred <- ensemble_simple_average(pop_preds)

  } else if (ensemble_method == "weighted_average") {
    if (is.null(model_weights)) {
      stop("Model weights must be provided for weighted_average")
    }
    ensemble_pred <- ensemble_weighted_average(pop_preds, model_weights)

  } else if (ensemble_method == "median") {
    ensemble_pred <- ensemble_median(pop_preds)

  } else {
    stop(sprintf("Unknown ensemble method: %s", ensemble_method))
  }

  result <- list(
    ensemble_prediction = ensemble_pred,
    individual_predictions = pop_preds,
    ensemble_method = ensemble_method
  )

  return(result)
}

#' Stacking ensemble: Train meta-learner on model predictions
#'
#' @param all_models List of trained models
#' @param person_datasets Person-specific datasets (for getting test data)
#' @param outcome Outcome variable name
#' @return List with meta-learner model
train_stacking_ensemble <- function(all_models, person_datasets, outcome) {

  cat("\n▶ Training stacking ensemble (meta-learner)...\n")

  model_types <- names(all_models)

  # Collect test predictions from all models
  # For each person, get predictions from all model types
  person_ids <- names(person_datasets)

  stacking_data_list <- list()

  for (pid in person_ids) {
    person_data <- person_datasets[[pid]]

    # Skip if no test data
    if (is.null(person_data$test) || nrow(person_data$test) == 0) {
      next
    }

    # Get actual outcomes
    test_actual <- person_data$test[[outcome]]

    # Get predictions from each model type
    test_preds <- data.table()

    for (mt in model_types) {
      # Get model for this person and model type
      combo_key <- names(all_models[[mt]])[1]
      model_result <- all_models[[mt]][[combo_key]]$models[[pid]]

      if (is.null(model_result) || !isTRUE(model_result$success)) {
        next
      }

      # Get test predictions
      if (!is.null(model_result$test_pred)) {
        if (nrow(test_preds) == 0) {
          test_preds <- data.table(actual = test_actual)
        }

        col_name <- paste0("pred_", mt)
        test_preds[[col_name]] <- model_result$test_pred
      }
    }

    if (nrow(test_preds) > 0) {
      stacking_data_list[[pid]] <- test_preds
    }
  }

  # Combine all
  if (length(stacking_data_list) == 0) {
    stop("No test predictions available for stacking")
  }

  stacking_data <- rbindlist(stacking_data_list)

  cat(sprintf("  Stacking training data: %d observations\n", nrow(stacking_data)))

  # Train meta-learner (simple linear regression)
  pred_cols <- grep("^pred_", names(stacking_data), value = TRUE)
  formula_str <- paste("actual ~", paste(pred_cols, collapse = " + "))
  formula_obj <- as.formula(formula_str)

  meta_learner <- lm(formula_obj, data = stacking_data)

  cat("  ✓ Meta-learner trained\n")
  cat(sprintf("  Meta-learner R²: %.3f\n", summary(meta_learner)$r.squared))

  result <- list(
    meta_learner = meta_learner,
    training_data = stacking_data,
    formula = formula_str,
    predictor_cols = pred_cols
  )

  return(result)
}

#' Predict using stacking ensemble
#'
#' @param stacking_model Result from train_stacking_ensemble
#' @param individual_predictions Named vector of predictions from base models
#' @return Single stacked prediction
predict_stacking <- function(stacking_model, individual_predictions) {

  # Create data.table with predictions
  pred_data <- as.data.table(as.list(individual_predictions))

  # Ensure column names match
  names(pred_data) <- paste0("pred_", names(individual_predictions))

  # Predict
  stacked_pred <- predict(stacking_model$meta_learner, newdata = pred_data)

  return(as.numeric(stacked_pred))
}

#' Compare ensemble methods
#'
#' @param all_models List of trained models
#' @param test_data data.table with test data
#' @param actual_outcomes Vector of actual outcomes
#' @param person_id_col Name of person ID column
#' @return data.table comparing ensemble methods
compare_ensemble_methods <- function(all_models, test_data, actual_outcomes,
                                    person_id_col = "person_idx") {

  ensemble_methods <- c("simple_average", "median")

  results <- list()

  for (method in ensemble_methods) {
    cat(sprintf("\n▶ Testing %s ensemble...\n", method))

    # Generate ensemble predictions
    preds <- generate_ensemble_predictions(all_models, test_data,
                                          person_id_col, method)

    # Calculate metrics
    metrics <- calculate_error_metrics(actual_outcomes, preds$ensemble)
    metrics[, method := method]

    results[[method]] <- metrics
  }

  results_dt <- rbindlist(results)

  # Rank by R²
  results_dt[, rank := frank(-r_squared, ties.method = "min")]
  setorder(results_dt, rank)

  return(results_dt)
}

#' Export ensemble predictions to CSV
#'
#' @param ensemble_predictions data.table with ensemble predictions
#' @param output_file Output filename
#' @param config Configuration list
export_ensemble_predictions <- function(ensemble_predictions, output_file,
                                       config = NULL) {

  # Determine output path
  if (!is.null(config)) {
    output_dir <- config$project$output_directory
    filepath <- file.path(output_dir, output_file)
  } else {
    filepath <- output_file
  }

  # Create directory if needed
  dir.create(dirname(filepath), recursive = TRUE, showWarnings = FALSE)

  # Write CSV
  fwrite(ensemble_predictions, filepath)

  cat(sprintf("✓ Exported ensemble predictions to: %s\n", filepath))

  return(invisible(filepath))
}
