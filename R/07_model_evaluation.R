################################################################################
#                       MODEL EVALUATION MODULE                                #
################################################################################
# Comprehensive model comparison, cross-validation, and evaluation metrics
# Compares different metamodel types and ranks their performance
################################################################################

suppressPackageStartupMessages({
  library(data.table)
})

#' Compare test performance across all model types
#'
#' @param all_models List of all trained models (lr, nn, rf, etc.)
#' @return data.table with comparison metrics
compare_model_performance <- function(all_models) {

  cat("\n▶ Comparing model performance across all types...\n")

  model_types <- names(all_models)
  comparison_list <- list()

  for (mt in model_types) {
    cat(sprintf("  Evaluating %s...\n", mt))

    # Get all group-outcome combinations
    combinations <- names(all_models[[mt]])

    for (combo in combinations) {
      combo_result <- all_models[[mt]][[combo]]
      models <- combo_result$models

      # Calculate metrics for each person
      person_metrics <- lapply(models, function(m) {
        if (!isTRUE(m$success) || isTRUE(m$is_fallback)) {
          return(NULL)
        }

        data.table(
          model_type = mt,
          combination = combo,
          person_id = m$person_id,
          train_r2 = m$train_metrics$r_squared,
          train_rmse = m$train_metrics$rmse,
          train_mae = m$train_metrics$mae,
          test_r2 = if (!is.null(m$test_metrics)) m$test_metrics$r_squared else NA_real_,
          test_rmse = if (!is.null(m$test_metrics)) m$test_metrics$rmse else NA_real_,
          test_mae = if (!is.null(m$test_metrics)) m$test_metrics$mae else NA_real_,
          n_train = m$n_train,
          n_test = m$n_test,
          n_predictors = m$n_predictors
        )
      })

      # Remove NULLs
      person_metrics <- person_metrics[!sapply(person_metrics, is.null)]

      if (length(person_metrics) > 0) {
        comparison_list[[paste(mt, combo, sep = "_")]] <- rbindlist(person_metrics)
      }
    }
  }

  if (length(comparison_list) == 0) {
    cat("  ⚠ No valid models to compare\n")
    return(data.table())
  }

  comparison_dt <- rbindlist(comparison_list)

  cat(sprintf("✓ Comparison complete: %d model instances evaluated\n", nrow(comparison_dt)))

  return(comparison_dt)
}

#' Aggregate performance metrics by model type and combination
#'
#' @param comparison_dt data.table from compare_model_performance
#' @return data.table with aggregated metrics
aggregate_performance_metrics <- function(comparison_dt) {

  if (nrow(comparison_dt) == 0) {
    return(data.table())
  }

  aggregated <- comparison_dt[, .(
    mean_train_r2 = mean(train_r2, na.rm = TRUE),
    sd_train_r2 = sd(train_r2, na.rm = TRUE),
    mean_test_r2 = mean(test_r2, na.rm = TRUE),
    sd_test_r2 = sd(test_r2, na.rm = TRUE),
    mean_train_rmse = mean(train_rmse, na.rm = TRUE),
    sd_train_rmse = sd(train_rmse, na.rm = TRUE),
    mean_test_rmse = mean(test_rmse, na.rm = TRUE),
    sd_test_rmse = sd(test_rmse, na.rm = TRUE),
    mean_train_mae = mean(train_mae, na.rm = TRUE),
    mean_test_mae = mean(test_mae, na.rm = TRUE),
    n_models = .N,
    mean_train_samples = mean(n_train, na.rm = TRUE),
    mean_test_samples = mean(n_test, na.rm = TRUE)
  ), by = .(model_type, combination)]

  # Add ranking by test R²
  aggregated[, rank_by_test_r2 := frank(-mean_test_r2, ties.method = "min"),
            by = combination]

  return(aggregated)
}

#' Rank models by performance metric
#'
#' @param aggregated_metrics data.table from aggregate_performance_metrics
#' @param metric Metric to rank by (default "mean_test_r2")
#' @param higher_is_better Whether higher values are better (default TRUE)
#' @return data.table with rankings
rank_models <- function(aggregated_metrics, metric = "mean_test_r2",
                       higher_is_better = TRUE) {

  if (nrow(aggregated_metrics) == 0) {
    return(data.table())
  }

  # Create ranking
  if (higher_is_better) {
    aggregated_metrics[, rank := frank(-get(metric), ties.method = "min"),
                      by = combination]
  } else {
    aggregated_metrics[, rank := frank(get(metric), ties.method = "min"),
                      by = combination]
  }

  # Sort by combination and rank
  setorder(aggregated_metrics, combination, rank)

  return(aggregated_metrics)
}

#' Find best model for each combination
#'
#' @param aggregated_metrics data.table from aggregate_performance_metrics
#' @param metric Metric to optimize (default "mean_test_r2")
#' @param higher_is_better Whether higher is better (default TRUE)
#' @return data.table with best model per combination
find_best_models <- function(aggregated_metrics, metric = "mean_test_r2",
                            higher_is_better = TRUE) {

  if (nrow(aggregated_metrics) == 0) {
    return(data.table())
  }

  # Rank models
  ranked <- rank_models(aggregated_metrics, metric, higher_is_better)

  # Select best (rank = 1) for each combination
  best <- ranked[rank == 1]

  return(best)
}

#' Calculate cross-validation metrics for a single person
#'
#' @param person_data Person-specific dataset
#' @param outcome Outcome variable
#' @param model_function Function to train model (e.g., train_lr_person)
#' @param config Configuration list
#' @param k Number of folds (default 5)
#' @return List with CV metrics
cross_validate_person <- function(person_data, outcome, model_function,
                                  config, k = 5) {

  # Get full data
  full_data <- rbind(person_data$train, person_data$test)
  n <- nrow(full_data)

  if (n < k) {
    warning(sprintf("Not enough data for %d-fold CV (n=%d)", k, n))
    return(list(cv_r2 = NA_real_, cv_rmse = NA_real_))
  }

  # Create folds
  fold_indices <- sample(rep(1:k, length.out = n))

  # Cross-validation
  fold_r2 <- numeric(k)
  fold_rmse <- numeric(k)

  for (i in 1:k) {
    # Split data
    train_fold <- full_data[fold_indices != i]
    test_fold <- full_data[fold_indices == i]

    # Create temporary person data structure
    temp_person_data <- person_data
    temp_person_data$train <- train_fold
    temp_person_data$test <- test_fold
    temp_person_data$n_train <- nrow(train_fold)
    temp_person_data$n_test <- nrow(test_fold)

    # Train model
    tryCatch({
      model_result <- model_function(temp_person_data, outcome, config)

      if (!is.null(model_result$test_metrics)) {
        fold_r2[i] <- model_result$test_metrics$r_squared
        fold_rmse[i] <- model_result$test_metrics$rmse
      } else {
        fold_r2[i] <- NA_real_
        fold_rmse[i] <- NA_real_
      }

    }, error = function(e) {
      fold_r2[i] <- NA_real_
      fold_rmse[i] <- NA_real_
    })
  }

  # Average metrics
  cv_metrics <- list(
    cv_r2 = mean(fold_r2, na.rm = TRUE),
    cv_rmse = mean(fold_rmse, na.rm = TRUE),
    cv_r2_sd = sd(fold_r2, na.rm = TRUE),
    cv_rmse_sd = sd(fold_rmse, na.rm = TRUE),
    k = k
  )

  return(cv_metrics)
}

#' Export model comparison to CSV
#'
#' @param comparison_dt data.table with comparison results
#' @param output_file Output filename
#' @param config Configuration list
export_model_comparison <- function(comparison_dt, output_file, config = NULL) {

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
  fwrite(comparison_dt, filepath)

  cat(sprintf("✓ Exported model comparison to: %s\n", filepath))

  return(invisible(filepath))
}

#' Generate comprehensive evaluation report
#'
#' @param all_models List of all trained models
#' @param config Configuration list
#' @return List with all evaluation results
generate_evaluation_report <- function(all_models, config) {

  cat("\n")
  print_section_header("MODEL EVALUATION REPORT")

  # 1. Compare performance
  comparison <- compare_model_performance(all_models)

  # 2. Aggregate metrics
  aggregated <- aggregate_performance_metrics(comparison)

  # 3. Rank models
  ranked <- rank_models(aggregated, metric = "mean_test_r2", higher_is_better = TRUE)

  # 4. Find best models
  best <- find_best_models(aggregated)

  # Print summary
  cat("\n▶ Best models by combination:\n")
  for (i in 1:nrow(best)) {
    cat(sprintf("  %s: %s (test R² = %.3f)\n",
                best$combination[i],
                best$model_type[i],
                best$mean_test_r2[i]))
  }

  # 5. Export results
  if (config$modeling$export_predictions) {
    cat("\n▶ Exporting evaluation results...\n")

    export_model_comparison(comparison, "model_comparison_detailed.csv", config)
    export_model_comparison(aggregated, "model_comparison_aggregated.csv", config)
    export_model_comparison(ranked, "model_rankings.csv", config)
    export_model_comparison(best, "best_models.csv", config)
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    MODEL EVALUATION COMPLETE                                  \n")
  cat("================================================================================\n")

  results <- list(
    comparison = comparison,
    aggregated = aggregated,
    ranked = ranked,
    best = best
  )

  return(results)
}

#' Calculate prediction error metrics
#'
#' @param actual Vector of actual values
#' @param predicted Vector of predicted values
#' @return data.table with error metrics
calculate_error_metrics <- function(actual, predicted) {

  # Remove NAs
  valid_mask <- is.finite(actual) & is.finite(predicted)
  actual <- actual[valid_mask]
  predicted <- predicted[valid_mask]

  if (length(actual) == 0) {
    return(data.table(
      mae = NA_real_,
      rmse = NA_real_,
      mape = NA_real_,
      r_squared = NA_real_,
      bias = NA_real_,
      n = 0
    ))
  }

  # Calculate metrics
  errors <- actual - predicted
  abs_errors <- abs(errors)
  squared_errors <- errors^2

  mae <- mean(abs_errors)
  rmse <- sqrt(mean(squared_errors))

  # MAPE (handle zeros)
  mape <- ifelse(any(actual != 0),
                mean(abs_errors[actual != 0] / abs(actual[actual != 0])) * 100,
                NA_real_)

  # R²
  ss_res <- sum(squared_errors)
  ss_tot <- sum((actual - mean(actual))^2)
  r_squared <- 1 - (ss_res / ss_tot)

  # Bias
  bias <- mean(errors)

  metrics <- data.table(
    mae = mae,
    rmse = rmse,
    mape = mape,
    r_squared = r_squared,
    bias = bias,
    n = length(actual)
  )

  return(metrics)
}

#' Compare actual vs predicted at population level
#'
#' @param actual_values Vector of actual population-level values
#' @param population_predictions data.table with predictions from different models
#' @return data.table with comparison metrics for each model
compare_population_accuracy <- function(actual_values, population_predictions) {

  # Get prediction columns
  pred_cols <- grep("^pred_", names(population_predictions), value = TRUE)

  if (length(pred_cols) == 0) {
    stop("No prediction columns found (should start with 'pred_')")
  }

  # Calculate metrics for each model type
  results <- lapply(pred_cols, function(col) {
    model_type <- gsub("^pred_", "", col)
    predictions <- population_predictions[[col]]

    metrics <- calculate_error_metrics(actual_values, predictions)
    metrics[, model_type := model_type]

    return(metrics)
  })

  results_dt <- rbindlist(results)

  # Rank by R²
  results_dt[, rank := frank(-r_squared, ties.method = "min")]
  setorder(results_dt, rank)

  return(results_dt)
}

#' Create performance summary table
#'
#' @param all_models List of all trained models
#' @return data.table with summary statistics
create_performance_summary <- function(all_models) {

  model_types <- names(all_models)

  summary_list <- lapply(model_types, function(mt) {
    combinations <- names(all_models[[mt]])

    combo_summaries <- lapply(combinations, function(combo) {
      combo_result <- all_models[[mt]][[combo]]
      models <- combo_result$models

      # Count successful models
      n_total <- length(models)
      n_success <- sum(sapply(models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback)))
      n_fallback <- sum(sapply(models, function(m) isTRUE(m$is_fallback)))

      # Average metrics
      successful_models <- models[sapply(models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback))]

      if (length(successful_models) > 0) {
        avg_train_r2 <- mean(sapply(successful_models, function(m) m$train_metrics$r_squared), na.rm = TRUE)
        avg_test_r2 <- mean(sapply(successful_models, function(m) {
          if (!is.null(m$test_metrics)) m$test_metrics$r_squared else NA_real_
        }), na.rm = TRUE)
      } else {
        avg_train_r2 <- NA_real_
        avg_test_r2 <- NA_real_
      }

      data.table(
        model_type = mt,
        combination = combo,
        n_total = n_total,
        n_success = n_success,
        n_fallback = n_fallback,
        pct_success = 100 * n_success / n_total,
        avg_train_r2 = avg_train_r2,
        avg_test_r2 = avg_test_r2
      )
    })

    rbindlist(combo_summaries)
  })

  summary_dt <- rbindlist(summary_list)

  return(summary_dt)
}
