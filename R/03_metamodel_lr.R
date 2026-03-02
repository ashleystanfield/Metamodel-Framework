################################################################################
#                    LINEAR REGRESSION METAMODEL MODULE                        #
################################################################################
# Person-specific linear regression training for metamodeling
# Handles model fitting, prediction, evaluation, and persistence
################################################################################

suppressPackageStartupMessages({
  library(data.table)
})

#' Train linear regression model for a single person
#'
#' @param person_data List from prepare_person_data()
#' @param outcome Name of outcome variable
#' @param config Configuration list
#' @return List with model, predictions, and metrics
train_lr_person <- function(person_data, outcome, config) {

  # Check if dataset is valid
  validation <- validate_person_dataset(person_data,
                                       min_samples = config$validation$minimum_sample_size %||% 2)

  # If invalid, return fallback model
  if (!validation$is_valid) {
    return(create_fallback_model(person_data, outcome))
  }

  # Check for constant outcome
  if (isTRUE(person_data$outcome_is_constant)) {
    return(create_fallback_model(person_data, outcome))
  }

  # Get training data
  train_data <- person_data$train
  test_data <- person_data$test
  predictors_used <- person_data$predictors_used

  # Check if we have predictors
  if (length(predictors_used) == 0) {
    return(create_fallback_model(person_data, outcome))
  }

  # Build formula
  formula_str <- paste(outcome, "~", paste(predictors_used, collapse = " + "))
  formula_obj <- as.formula(formula_str)

  # Fit model
  tryCatch({
    model <- lm(formula_obj, data = train_data)

    # Training predictions
    train_pred <- predict(model, newdata = train_data)
    train_actual <- train_data[[outcome]]

    # Test predictions (if test data available)
    test_pred <- NULL
    test_actual <- NULL
    test_metrics <- NULL

    if (!is.null(test_data) && nrow(test_data) > 0) {
      test_pred <- predict(model, newdata = test_data)
      test_actual <- test_data[[outcome]]
      test_metrics <- calculate_metrics(test_actual, test_pred)
    }

    # Training metrics
    train_metrics <- calculate_metrics(train_actual, train_pred)

    # Return results
    result <- list(
      person_id = person_data$person_id,
      model_type = "linear_regression",
      model = model,
      formula = formula_str,
      predictors_used = predictors_used,
      n_predictors = length(predictors_used),

      # Training results
      train_actual = train_actual,
      train_pred = train_pred,
      train_metrics = train_metrics,

      # Test results
      test_actual = test_actual,
      test_pred = test_pred,
      test_metrics = test_metrics,

      # Metadata
      n_train = nrow(train_data),
      n_test = if (!is.null(test_data)) nrow(test_data) else 0,

      # Success flag
      success = TRUE,
      is_fallback = FALSE,
      error = NULL
    )

    return(result)

  }, error = function(e) {
    # If model fitting fails, return fallback
    warning(sprintf("LR failed for person %s: %s", person_data$person_id, e$message))
    fallback <- create_fallback_model(person_data, outcome)
    fallback$error <- e$message
    return(fallback)
  })
}

#' Train linear regression for all persons
#'
#' @param person_datasets List of person-specific datasets
#' @param outcome Outcome variable name
#' @param config Configuration list
#' @return List of trained models
train_lr_all_persons <- function(person_datasets, outcome, config) {

  n_persons <- length(person_datasets)

  cat(sprintf("\n▶ Training Linear Regression models for %d persons (outcome: %s)...\n",
              n_persons, outcome))

  # Progress bar
  pb <- create_progress_bar(n_persons, config = config)

  # Train each person
  models <- vector("list", n_persons)
  names(models) <- names(person_datasets)

  for (i in seq_along(person_datasets)) {
    person_data <- person_datasets[[i]]

    models[[i]] <- train_lr_person(person_data, outcome, config)

    tick_progress(pb)
  }

  # Summary statistics
  n_success <- sum(sapply(models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback)))
  n_fallback <- sum(sapply(models, function(m) isTRUE(m$is_fallback)))

  # Calculate average metrics for successful models
  successful_models <- models[sapply(models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback))]

  if (length(successful_models) > 0) {
    avg_train_r2 <- mean(sapply(successful_models, function(m) m$train_metrics$r_squared), na.rm = TRUE)
    avg_train_rmse <- mean(sapply(successful_models, function(m) m$train_metrics$rmse), na.rm = TRUE)

    test_r2_values <- sapply(successful_models, function(m) {
      if (!is.null(m$test_metrics)) m$test_metrics$r_squared else NA
    })
    avg_test_r2 <- mean(test_r2_values, na.rm = TRUE)

    cat(sprintf("\n  Successfully trained: %d/%d models\n", n_success, n_persons))
    cat(sprintf("  Fallback models: %d\n", n_fallback))
    cat(sprintf("  Avg training R²: %.3f\n", avg_train_r2))
    cat(sprintf("  Avg training RMSE: %.4f\n", avg_train_rmse))
    if (!is.na(avg_test_r2)) {
      cat(sprintf("  Avg test R²: %.3f\n", avg_test_r2))
    }
  } else {
    cat(sprintf("\n  ⚠ No successful models (all %d are fallback)\n", n_fallback))
  }

  return(models)
}

#' Train linear regression for a group-outcome combination
#'
#' @param person_datasets_entry Entry from results$person_datasets
#' @param config Configuration list
#' @return List with models and summary
train_lr_group_outcome <- function(person_datasets_entry, config) {

  group <- person_datasets_entry$group
  outcome <- person_datasets_entry$outcome
  datasets <- person_datasets_entry$datasets

  cat(sprintf("\n=== Training LR for %s - %s ===\n", group, outcome))

  # Train all persons
  models <- train_lr_all_persons(datasets, outcome, config)

  result <- list(
    group = group,
    outcome = outcome,
    models = models,
    n_models = length(models),
    n_success = sum(sapply(models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback))),
    n_fallback = sum(sapply(models, function(m) isTRUE(m$is_fallback)))
  )

  return(result)
}

#' Train linear regression for all groups and outcomes
#'
#' @param person_datasets_list Full results$person_datasets from pipeline
#' @param config Configuration list
#' @return List of all trained models organized by group and outcome
train_lr_all <- function(person_datasets_list, config) {

  cat("\n")
  print_section_header("LINEAR REGRESSION TRAINING")

  n_combinations <- length(person_datasets_list)
  cat(sprintf("Training LR for %d group-outcome combinations\n", n_combinations))

  # Train each combination
  all_results <- list()

  for (key in names(person_datasets_list)) {
    entry <- person_datasets_list[[key]]

    result <- train_lr_group_outcome(entry, config)
    all_results[[key]] <- result

    # Save models if configured
    if (config$modeling$save_models) {
      save_lr_models(result, config)
    }
  }

  # Overall summary
  total_models <- sum(sapply(all_results, function(r) r$n_models))
  total_success <- sum(sapply(all_results, function(r) r$n_success))
  total_fallback <- sum(sapply(all_results, function(r) r$n_fallback))

  cat("\n")
  cat("================================================================================\n")
  cat("                    LINEAR REGRESSION TRAINING COMPLETE                        \n")
  cat("================================================================================\n")
  cat(sprintf("Total models trained: %d\n", total_models))
  cat(sprintf("Successful models: %d (%.1f%%)\n", total_success, 100 * total_success / total_models))
  cat(sprintf("Fallback models: %d (%.1f%%)\n", total_fallback, 100 * total_fallback / total_models))
  cat("================================================================================\n")

  return(all_results)
}

#' Save linear regression models to disk
#'
#' @param lr_result Result from train_lr_group_outcome()
#' @param config Configuration list
save_lr_models <- function(lr_result, config) {

  group <- lr_result$group
  outcome <- lr_result$outcome

  # Create models directory
  models_dir <- file.path(config$project$output_directory, "models", "linear_regression")
  if (!dir.exists(models_dir)) {
    dir.create(models_dir, recursive = TRUE)
  }

  # Save file
  filename <- sprintf("lr_models_%s_%s.rds", group, outcome)
  filepath <- file.path(models_dir, filename)

  saveRDS(lr_result, filepath)

  cat(sprintf("  ✓ Saved models to: %s\n", filename))
}

#' Load saved linear regression models
#'
#' @param group Group name
#' @param outcome Outcome name
#' @param config Configuration list
#' @return Loaded model results
load_lr_models <- function(group, outcome, config) {

  models_dir <- file.path(config$project$output_directory, "models", "linear_regression")
  filename <- sprintf("lr_models_%s_%s.rds", group, outcome)
  filepath <- file.path(models_dir, filename)

  if (!file.exists(filepath)) {
    stop(sprintf("Model file not found: %s", filepath))
  }

  models <- readRDS(filepath)
  cat(sprintf("✓ Loaded LR models from: %s\n", filename))

  return(models)
}

#' Extract coefficients from linear regression models
#'
#' @param lr_models List of LR models from train_lr_all_persons()
#' @return data.table with coefficients for each person
extract_lr_coefficients <- function(lr_models) {

  coef_list <- lapply(lr_models, function(model_result) {
    if (isTRUE(model_result$is_fallback) || !isTRUE(model_result$success)) {
      return(NULL)
    }

    model <- model_result$model
    coefs <- coef(model)

    # Convert to data.table
    dt <- data.table(
      person_id = model_result$person_id,
      term = names(coefs),
      coefficient = as.numeric(coefs)
    )

    return(dt)
  })

  # Combine all
  coef_list <- coef_list[!sapply(coef_list, is.null)]

  if (length(coef_list) == 0) {
    return(data.table())
  }

  coef_dt <- rbindlist(coef_list)

  return(coef_dt)
}

#' Generate predictions for new data using trained LR models
#'
#' @param lr_models List of trained LR models
#' @param new_data data.table with new data to predict
#' @param person_id_col Name of person ID column
#' @return data.table with predictions
predict_lr_new_data <- function(lr_models, new_data, person_id_col = "person_idx") {

  # Get unique person IDs in new data
  person_ids <- unique(new_data[[person_id_col]])

  # Predict for each person
  pred_list <- lapply(person_ids, function(pid) {
    # Get person's model
    model_result <- lr_models[[as.character(pid)]]

    if (is.null(model_result)) {
      warning(sprintf("No model found for person %s", pid))
      return(NULL)
    }

    # Get person's data
    person_new_data <- new_data[get(person_id_col) == pid]

    # Predict
    if (isTRUE(model_result$is_fallback)) {
      # Use mean prediction
      predictions <- rep(model_result$mean_y, nrow(person_new_data))
    } else {
      predictions <- predict(model_result$model, newdata = person_new_data)
    }

    # Return data.table
    result <- copy(person_new_data)
    result[, prediction := predictions]
    result[, person_id := pid]

    return(result)
  })

  # Combine
  pred_list <- pred_list[!sapply(pred_list, is.null)]

  if (length(pred_list) == 0) {
    return(data.table())
  }

  predictions_dt <- rbindlist(pred_list)

  return(predictions_dt)
}

#' Create summary report for LR training results
#'
#' @param lr_results Results from train_lr_all()
#' @return data.table with summary statistics
summarize_lr_results <- function(lr_results) {

  summary_list <- lapply(names(lr_results), function(key) {
    result <- lr_results[[key]]

    # Calculate metrics
    models <- result$models
    successful_models <- models[sapply(models, function(m) isTRUE(m$success) && !isTRUE(m$is_fallback))]

    if (length(successful_models) == 0) {
      return(data.table(
        group = result$group,
        outcome = result$outcome,
        n_total = result$n_models,
        n_success = 0,
        n_fallback = result$n_fallback,
        avg_train_r2 = NA_real_,
        avg_train_rmse = NA_real_,
        avg_test_r2 = NA_real_,
        avg_test_rmse = NA_real_
      ))
    }

    # Calculate averages
    avg_train_r2 <- mean(sapply(successful_models, function(m) m$train_metrics$r_squared), na.rm = TRUE)
    avg_train_rmse <- mean(sapply(successful_models, function(m) m$train_metrics$rmse), na.rm = TRUE)

    test_r2_values <- sapply(successful_models, function(m) {
      if (!is.null(m$test_metrics)) m$test_metrics$r_squared else NA
    })
    avg_test_r2 <- mean(test_r2_values, na.rm = TRUE)

    test_rmse_values <- sapply(successful_models, function(m) {
      if (!is.null(m$test_metrics)) m$test_metrics$rmse else NA
    })
    avg_test_rmse <- mean(test_rmse_values, na.rm = TRUE)

    data.table(
      group = result$group,
      outcome = result$outcome,
      n_total = result$n_models,
      n_success = result$n_success,
      n_fallback = result$n_fallback,
      avg_train_r2 = avg_train_r2,
      avg_train_rmse = avg_train_rmse,
      avg_test_r2 = avg_test_r2,
      avg_test_rmse = avg_test_rmse
    )
  })

  summary_dt <- rbindlist(summary_list)

  return(summary_dt)
}
