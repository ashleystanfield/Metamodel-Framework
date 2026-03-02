################################################################################
#                    POPULATION-LEVEL PREDICTION MODULE                        #
################################################################################
# Aggregate person-specific predictions to population-level estimates
# Uses census/demographic weights to create representative predictions
################################################################################

suppressPackageStartupMessages({
  library(data.table)
})

#' Aggregate person-specific predictions to population level
#'
#' @param person_predictions Named vector of predictions (person_id -> prediction)
#' @param population_weights Named vector of weights (person_id -> weight)
#' @param normalize_weights Whether to normalize weights to sum to 1
#' @return Single population-level prediction (weighted average)
aggregate_to_population <- function(person_predictions, population_weights,
                                   normalize_weights = TRUE) {

  # Convert to numeric if needed
  preds <- as.numeric(person_predictions)
  weights <- as.numeric(population_weights)

  # Check lengths match
  if (length(preds) != length(weights)) {
    stop("Predictions and weights must have same length")
  }

  # Handle missing values
  valid_mask <- is.finite(preds) & is.finite(weights)

  if (!any(valid_mask)) {
    warning("No valid predictions or weights")
    return(NA_real_)
  }

  # Subset to valid
  preds_valid <- preds[valid_mask]
  weights_valid <- weights[valid_mask]

  # Normalize weights if requested
  if (normalize_weights) {
    weight_sum <- sum(weights_valid, na.rm = TRUE)

    if (!is.finite(weight_sum) || weight_sum <= 0) {
      warning("Invalid weight sum")
      return(NA_real_)
    }

    weights_valid <- weights_valid / weight_sum
  }

  # Weighted average
  population_pred <- sum(preds_valid * weights_valid, na.rm = TRUE)

  return(population_pred)
}

#' Generate population-level prediction from trained models
#'
#' @param models List of person-specific models (from train_*_all_persons)
#' @param new_data Single-row data.table with predictor values
#' @param population_weights Named list or vector (person_id -> weight)
#' @param model_type Type of model ("linear_regression", "neural_network", "random_forest")
#' @return List with population prediction and metadata
predict_population <- function(models, new_data, population_weights,
                              model_type = "linear_regression") {

  # Get person IDs from models
  person_ids <- names(models)

  if (is.null(person_ids) || length(person_ids) == 0) {
    stop("Models must be a named list with person IDs as names")
  }

  # Generate person-specific predictions
  person_preds <- numeric(length(person_ids))
  names(person_preds) <- person_ids

  for (i in seq_along(person_ids)) {
    pid <- person_ids[i]
    model_result <- models[[pid]]

    # Handle fallback models
    if (isTRUE(model_result$is_fallback)) {
      person_preds[i] <- model_result$mean_y
      next
    }

    # Predict based on model type
    tryCatch({
      if (model_type == "linear_regression") {
        person_preds[i] <- predict(model_result$model, newdata = new_data)

      } else if (model_type == "neural_network") {
        # Standardize new data
        new_data_std <- copy(new_data)
        predictors <- model_result$predictors_used

        for (pred in predictors) {
          mean_val <- model_result$standardization$means[[pred]]
          sd_val <- model_result$standardization$sds[[pred]]
          new_data_std[[pred]] <- (new_data_std[[pred]] - mean_val) / sd_val
        }

        person_preds[i] <- predict(model_result$model, newdata = new_data_std)[1]

      } else if (model_type == "random_forest") {
        person_preds[i] <- predict(model_result$model, newdata = new_data)

      } else {
        warning(sprintf("Unknown model type: %s", model_type))
        person_preds[i] <- NA_real_
      }

    }, error = function(e) {
      warning(sprintf("Prediction failed for person %s: %s", pid, e$message))
      person_preds[i] <- NA_real_
    })
  }

  # Match weights to person IDs
  weights_vec <- numeric(length(person_ids))
  names(weights_vec) <- person_ids

  for (i in seq_along(person_ids)) {
    pid <- person_ids[i]

    if (!is.null(population_weights[[pid]])) {
      weights_vec[i] <- population_weights[[pid]]
    } else {
      # Default to uniform weight if not found
      weights_vec[i] <- 1.0
    }
  }

  # Aggregate to population level
  pop_pred <- aggregate_to_population(person_preds, weights_vec,
                                     normalize_weights = TRUE)

  # Return detailed results
  result <- list(
    population_prediction = pop_pred,
    person_predictions = person_preds,
    weights = weights_vec,
    n_persons = length(person_ids),
    n_valid = sum(is.finite(person_preds)),
    model_type = model_type
  )

  return(result)
}

#' Generate population predictions for multiple scenarios
#'
#' @param models List of person-specific models
#' @param scenarios data.table with multiple rows (one per scenario)
#' @param population_weights Named list or vector
#' @param model_type Type of model
#' @return data.table with scenario data + population predictions
predict_population_scenarios <- function(models, scenarios, population_weights,
                                        model_type = "linear_regression") {

  n_scenarios <- nrow(scenarios)

  cat(sprintf("▶ Generating population predictions for %d scenarios...\n", n_scenarios))

  # Progress bar
  pb <- txtProgressBar(min = 0, max = n_scenarios, style = 3)

  # Predict each scenario
  pop_predictions <- numeric(n_scenarios)

  for (i in 1:n_scenarios) {
    scenario_row <- scenarios[i, ]

    pred_result <- predict_population(models, scenario_row, population_weights,
                                     model_type)

    pop_predictions[i] <- pred_result$population_prediction

    setTxtProgressBar(pb, i)
  }

  close(pb)

  # Combine with scenarios
  result <- copy(scenarios)
  result[, population_prediction := pop_predictions]
  result[, model_type := model_type]

  cat(sprintf("✓ Generated %d population predictions\n", n_scenarios))

  return(result)
}

#' Compare population predictions across multiple model types
#'
#' @param all_models List of lists: list(lr = lr_models, nn = nn_models, rf = rf_models)
#' @param scenarios data.table with scenarios
#' @param population_weights Named list or vector
#' @return data.table with predictions from all model types
compare_population_predictions <- function(all_models, scenarios,
                                          population_weights) {

  model_types <- names(all_models)

  cat(sprintf("\n▶ Comparing population predictions across %d model types...\n",
              length(model_types)))

  # Start with scenarios
  result <- copy(scenarios)

  # Add predictions from each model type
  for (mt in model_types) {
    cat(sprintf("  Predicting with %s...\n", mt))

    models <- all_models[[mt]]

    preds <- predict_population_scenarios(models, scenarios, population_weights,
                                          model_type = mt)

    # Add column with model type name
    col_name <- paste0("pred_", mt)
    result[[col_name]] <- preds$population_prediction
  }

  cat("✓ Population prediction comparison complete\n")

  return(result)
}

#' Export population predictions to CSV
#'
#' @param predictions data.table with predictions
#' @param output_file File path for CSV export
#' @param config Configuration list (for output directory)
export_population_predictions <- function(predictions, output_file, config = NULL) {

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
  fwrite(predictions, filepath)

  cat(sprintf("✓ Exported population predictions to: %s\n", filepath))

  return(invisible(filepath))
}

#' Generate population predictions for all trained models
#'
#' @param all_models Results from train_*_all() functions
#' @param scenarios data.table with scenarios to predict
#' @param population_weights Named list of weights
#' @param config Configuration list
#' @return List of prediction data.tables by group-outcome
generate_all_population_predictions <- function(all_models, scenarios,
                                               population_weights, config) {

  cat("\n")
  print_section_header("POPULATION-LEVEL PREDICTIONS")

  # Get all group-outcome combinations
  combinations <- names(all_models[[1]])  # Assuming all model types have same combos

  results <- list()

  for (combo in combinations) {
    cat(sprintf("\n=== %s ===\n", combo))

    # Extract models for this combination
    combo_models <- lapply(all_models, function(mt) {
      if (!is.null(mt[[combo]])) {
        mt[[combo]]$models
      } else {
        NULL
      }
    })

    # Remove NULL entries
    combo_models <- combo_models[!sapply(combo_models, is.null)]

    if (length(combo_models) == 0) {
      cat("  ⚠ No models available for this combination\n")
      next
    }

    # Generate predictions
    predictions <- compare_population_predictions(combo_models, scenarios,
                                                 population_weights)

    # Store results
    results[[combo]] <- predictions

    # Export to CSV if configured
    if (config$modeling$export_predictions) {
      filename <- sprintf("population_predictions_%s.csv", combo)
      export_population_predictions(predictions, filename, config)
    }
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                POPULATION PREDICTIONS COMPLETE                                \n")
  cat("================================================================================\n")
  cat(sprintf("Generated predictions for %d combinations\n", length(results)))
  cat("================================================================================\n")

  return(results)
}

#' Create summary statistics for population predictions
#'
#' @param population_predictions Results from generate_all_population_predictions
#' @return data.table with summary statistics
summarize_population_predictions <- function(population_predictions) {

  summary_list <- lapply(names(population_predictions), function(combo) {
    preds <- population_predictions[[combo]]

    # Get prediction columns
    pred_cols <- grep("^pred_", names(preds), value = TRUE)

    if (length(pred_cols) == 0) {
      return(NULL)
    }

    # Calculate statistics for each model type
    stats <- lapply(pred_cols, function(col) {
      values <- preds[[col]]

      data.table(
        combination = combo,
        model_type = gsub("^pred_", "", col),
        mean_prediction = mean(values, na.rm = TRUE),
        sd_prediction = sd(values, na.rm = TRUE),
        min_prediction = min(values, na.rm = TRUE),
        max_prediction = max(values, na.rm = TRUE),
        n_scenarios = length(values),
        n_valid = sum(is.finite(values))
      )
    })

    rbindlist(stats)
  })

  summary_list <- summary_list[!sapply(summary_list, is.null)]

  if (length(summary_list) == 0) {
    return(data.table())
  }

  summary_dt <- rbindlist(summary_list)

  return(summary_dt)
}

#' Calculate prediction intervals for population estimates
#'
#' @param models List of person-specific models
#' @param new_data Single-row data.table
#' @param population_weights Named list of weights
#' @param model_type Type of model
#' @param confidence_level Confidence level (default 0.95)
#' @return List with point estimate and interval
predict_population_with_interval <- function(models, new_data, population_weights,
                                            model_type = "linear_regression",
                                            confidence_level = 0.95) {

  # Get point estimate
  point_result <- predict_population(models, new_data, population_weights,
                                    model_type)

  # Calculate variance across person types (uncertainty)
  person_preds <- point_result$person_predictions
  weights <- point_result$weights

  # Normalize weights
  weights_norm <- weights / sum(weights, na.rm = TRUE)

  # Weighted variance
  weighted_mean <- point_result$population_prediction
  weighted_var <- sum(weights_norm * (person_preds - weighted_mean)^2, na.rm = TRUE)
  weighted_sd <- sqrt(weighted_var)

  # Calculate interval
  alpha <- 1 - confidence_level
  z_score <- qnorm(1 - alpha/2)

  lower <- weighted_mean - z_score * weighted_sd
  upper <- weighted_mean + z_score * weighted_sd

  result <- list(
    point_estimate = weighted_mean,
    lower_bound = lower,
    upper_bound = upper,
    std_error = weighted_sd,
    confidence_level = confidence_level,
    person_predictions = person_preds,
    weights = weights
  )

  return(result)
}

#' Generate scenario grid for sensitivity analysis
#'
#' @param predictor_ranges Named list of ranges (predictor -> c(min, max))
#' @param n_points Number of points per predictor
#' @return data.table with all combinations
generate_scenario_grid <- function(predictor_ranges, n_points = 10) {

  # Create sequences for each predictor
  sequences <- lapply(predictor_ranges, function(range) {
    seq(from = range[1], to = range[2], length.out = n_points)
  })

  # Create grid
  grid <- do.call(expand.grid, sequences)
  grid_dt <- as.data.table(grid)

  cat(sprintf("✓ Generated scenario grid: %d scenarios\n", nrow(grid_dt)))

  return(grid_dt)
}
