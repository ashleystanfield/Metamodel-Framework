################################################################################
#                         PREPROCESSING MODULE                                 #
################################################################################
# Data preprocessing functions for metamodel training
# Handles train/test splitting, person-specific data extraction,
# constant predictor detection, and feature engineering
################################################################################

suppressPackageStartupMessages({
  library(data.table)
})

#' Split data into train and test sets
#'
#' @param data data.table
#' @param train_ratio Proportion for training (0-1)
#' @param seed Random seed
#' @return List with train and test data.tables
split_train_test <- function(data, train_ratio = 0.8, seed = NULL) {

  if (!is.null(seed)) {
    set.seed(seed)
  }

  n <- nrow(data)
  n_train <- max(1L, floor(train_ratio * n))

  if (n == 0) {
    return(list(train = data[0], test = data[0]))
  }

  # Random indices for training
  train_idx <- sample.int(n, n_train)

  train_data <- data[train_idx]
  test_data <- if (n > n_train) data[-train_idx] else data[0]

  return(list(
    train = train_data,
    test = test_data,
    train_idx = train_idx,
    n_train = n_train,
    n_test = nrow(test_data)
  ))
}

#' Extract data for a specific person type
#'
#' @param data data.table
#' @param person_id Person identifier value
#' @param person_id_col Name of person ID column
#' @param required_cols Columns to keep
#' @return data.table for that person
extract_person_data <- function(data, person_id, person_id_col, required_cols) {

  # Filter by person
  person_data <- data[get(person_id_col) == person_id]

  # Select required columns
  if (!is.null(required_cols)) {
    available_cols <- intersect(required_cols, names(person_data))
    person_data <- person_data[, ..available_cols]
  }

  # Remove rows with any NA in required columns
  person_data <- person_data[complete.cases(person_data)]

  return(person_data)
}

#' Detect constant predictors in a dataset
#'
#' @param data data.table
#' @param predictor_cols Column names to check
#' @return Character vector of constant predictor names
detect_constant_predictors <- function(data, predictor_cols) {

  if (nrow(data) == 0 || length(predictor_cols) == 0) {
    return(character(0))
  }

  # Check each predictor
  const_cols <- names(which(vapply(data[, ..predictor_cols], function(x) {
    # Get unique non-NA values
    unique_vals <- unique(x)
    unique_vals <- unique_vals[!is.na(unique_vals)]

    # Constant if 0 or 1 unique value
    length(unique_vals) <= 1
  }, logical(1))))

  return(const_cols)
}

#' Remove constant predictors and log them
#'
#' @param predictors Character vector of predictor names
#' @param constant_predictors Character vector of constant predictor names
#' @return Character vector of non-constant predictors
remove_constant_predictors <- function(predictors, constant_predictors) {

  if (length(constant_predictors) == 0) {
    return(predictors)
  }

  non_constant <- setdiff(predictors, constant_predictors)

  return(non_constant)
}

#' Prepare data for person-specific modeling
#'
#' @param data data.table with all data
#' @param person_id Person identifier
#' @param person_id_col Name of person ID column
#' @param predictors Vector of predictor names
#' @param outcome Name of outcome variable
#' @param train_ratio Training split ratio
#' @param seed Random seed
#' @param drop_constants Whether to drop constant predictors
#' @return List with training/test data and metadata
prepare_person_data <- function(data, person_id, person_id_col,
                               predictors, outcome,
                               train_ratio = 0.8, seed = NULL,
                               drop_constants = TRUE) {

  # Extract person-specific data
  required_cols <- c(person_id_col, predictors, outcome)
  person_data <- extract_person_data(data, person_id, person_id_col, required_cols)

  # Check if enough data
  if (nrow(person_data) == 0) {
    return(list(
      person_id = person_id,
      n_total = 0,
      n_train = 0,
      n_test = 0,
      train = NULL,
      test = NULL,
      predictors_used = character(0),
      constant_predictors = character(0),
      error = "No data available"
    ))
  }

  # Split train/test
  split <- split_train_test(person_data, train_ratio, seed)

  # Detect constant predictors (only on training data)
  constant_preds <- character(0)
  predictors_used <- predictors

  if (drop_constants && nrow(split$train) > 0) {
    constant_preds <- detect_constant_predictors(split$train, predictors)

    if (length(constant_preds) > 0) {
      predictors_used <- remove_constant_predictors(predictors, constant_preds)
    }
  }

  # Check if outcome is constant (degenerate case)
  outcome_is_constant <- FALSE
  if (nrow(split$train) > 0) {
    unique_outcomes <- uniqueN(split$train[[outcome]], na.rm = TRUE)
    outcome_is_constant <- unique_outcomes < 2
  }

  result <- list(
    person_id = person_id,
    n_total = nrow(person_data),
    n_train = split$n_train,
    n_test = split$n_test,
    train = split$train,
    test = split$test,
    predictors_used = predictors_used,
    constant_predictors = constant_preds,
    n_predictors = length(predictors_used),
    n_constant = length(constant_preds),
    outcome_is_constant = outcome_is_constant,
    error = NULL
  )

  return(result)
}

#' Prepare all person-specific datasets
#'
#' @param data data.table
#' @param config Configuration list
#' @param outcome Single outcome variable name
#' @return List of prepared datasets, one per person
prepare_all_persons <- function(data, config, outcome) {

  person_id_col <- config$data$person_id_column
  predictors <- config$variables$predictors
  train_ratio <- config$modeling$train_test_split
  drop_constants <- config$modeling$drop_constant_predictors

  # NOTE: Seed should be set ONCE in main.R before all processing.
  # Do NOT set seed here - let the RNG naturally progress through all
  # groups and persons (matching original implementation behavior).

  # Get all person IDs
  person_ids <- sort(unique(data[[person_id_col]]))
  n_persons <- length(person_ids)

  cat(sprintf("\n▶ Preparing data for %d person types (outcome: %s)...\n",
              n_persons, outcome))

  # Progress bar
  pb <- create_progress_bar(n_persons, config = config)

  # Prepare each person
  person_datasets <- vector("list", n_persons)
  names(person_datasets) <- as.character(person_ids)

  for (i in seq_along(person_ids)) {
    person_id <- person_ids[i]

    # Pass seed = NULL so each person gets a different random split
    # (RNG state naturally progresses from the initial set.seed above)
    person_datasets[[i]] <- prepare_person_data(
      data = data,
      person_id = person_id,
      person_id_col = person_id_col,
      predictors = predictors,
      outcome = outcome,
      train_ratio = train_ratio,
      seed = NULL,
      drop_constants = drop_constants
    )

    tick_progress(pb)
  }

  # Summary statistics
  n_with_data <- sum(sapply(person_datasets, function(x) x$n_total > 0))
  n_constant_outcome <- sum(sapply(person_datasets, function(x) isTRUE(x$outcome_is_constant)))
  avg_train_size <- mean(sapply(person_datasets, function(x) x$n_train))

  cat(sprintf("\n  Persons with data: %d/%d\n", n_with_data, n_persons))
  cat(sprintf("  Avg training samples per person: %.1f\n", avg_train_size))

  if (n_constant_outcome > 0) {
    cat(sprintf("  ⚠ Persons with constant outcome: %d (will use mean predictor)\n",
                n_constant_outcome))
  }

  return(person_datasets)
}

#' Check if dataset is suitable for modeling
#'
#' @param person_data Result from prepare_person_data
#' @param min_samples Minimum required training samples
#' @return List with is_valid flag and reason
validate_person_dataset <- function(person_data, min_samples = 2) {

  reasons <- character(0)

  # No data
  if (person_data$n_total == 0) {
    return(list(is_valid = FALSE, reason = "No data available"))
  }

  # Too few training samples
  if (person_data$n_train < min_samples) {
    reasons <- c(reasons, sprintf("Insufficient training samples (%d < %d)",
                                 person_data$n_train, min_samples))
  }

  # No predictors after dropping constants
  if (length(person_data$predictors_used) == 0) {
    reasons <- c(reasons, "No non-constant predictors")
  }

  # Constant outcome
  if (isTRUE(person_data$outcome_is_constant)) {
    reasons <- c(reasons, "Outcome is constant (no variation)")
  }

  # Determine validity
  is_valid <- length(reasons) == 0

  result <- list(
    is_valid = is_valid,
    reason = if (length(reasons) > 0) paste(reasons, collapse = "; ") else "Valid"
  )

  return(result)
}

#' Create fallback model for problematic datasets
#'
#' @param person_data Result from prepare_person_data
#' @param outcome Outcome variable name
#' @return List with fallback model information
create_fallback_model <- function(person_data, outcome) {

  # Calculate mean of outcome on training data
  if (!is.null(person_data$train) && nrow(person_data$train) > 0) {
    mean_y <- mean(person_data$train[[outcome]], na.rm = TRUE)
  } else {
    mean_y <- NA_real_
  }

  fallback <- list(
    type = "mean_only",
    mean_y = mean_y,
    person_id = person_data$person_id,
    reason = "Insufficient data or constant predictors"
  )

  return(fallback)
}

#' Standardize (center and scale) predictors
#'
#' @param train_data Training data.table
#' @param test_data Test data.table (optional)
#' @param predictor_cols Columns to standardize
#' @return List with standardized data and scaling parameters
standardize_predictors <- function(train_data, test_data = NULL, predictor_cols) {

  # Calculate means and sds from training data
  means <- train_data[, lapply(.SD, mean, na.rm = TRUE), .SDcols = predictor_cols]
  sds <- train_data[, lapply(.SD, sd, na.rm = TRUE), .SDcols = predictor_cols]

  # Replace zero SDs with 1 (to avoid division by zero)
  sds[sds == 0] <- 1

  # Standardize training data
  train_std <- copy(train_data)
  for (col in predictor_cols) {
    train_std[[col]] <- (train_std[[col]] - means[[col]]) / sds[[col]]
  }

  # Standardize test data using training parameters
  test_std <- NULL
  if (!is.null(test_data) && nrow(test_data) > 0) {
    test_std <- copy(test_data)
    for (col in predictor_cols) {
      test_std[[col]] <- (test_std[[col]] - means[[col]]) / sds[[col]]
    }
  }

  result <- list(
    train = train_std,
    test = test_std,
    means = means,
    sds = sds,
    predictor_cols = predictor_cols
  )

  return(result)
}

#' Generate person-level summary statistics
#'
#' @param person_datasets List of person datasets
#' @return data.table with summary statistics
summarize_person_datasets <- function(person_datasets) {

  summary_list <- lapply(person_datasets, function(pd) {
    data.table(
      person_id = pd$person_id,
      n_total = pd$n_total,
      n_train = pd$n_train,
      n_test = pd$n_test,
      n_predictors_used = pd$n_predictors,
      n_constant_predictors = pd$n_constant,
      constant_predictors = if (length(pd$constant_predictors) > 0) {
        paste(pd$constant_predictors, collapse = ";")
      } else {
        ""
      },
      outcome_is_constant = pd$outcome_is_constant %||% FALSE,
      has_error = !is.null(pd$error),
      error_message = pd$error %||% ""
    )
  })

  summary_dt <- rbindlist(summary_list)

  return(summary_dt)
}

#' Null-coalescing operator
#'
#' @param x First value
#' @param y Default value if x is NULL
#' @return x if not NULL, otherwise y
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

#' Validate all person datasets and create summary report
#'
#' @param person_datasets List of person datasets
#' @param config Configuration list
#' @return List with validation results
validate_all_persons <- function(person_datasets, config) {

  min_samples <- config$validation$minimum_sample_size %||% 2

  cat("\n▶ Validating person datasets...\n")

  validation_results <- lapply(person_datasets, function(pd) {
    validation <- validate_person_dataset(pd, min_samples)

    list(
      person_id = pd$person_id,
      is_valid = validation$is_valid,
      reason = validation$reason,
      n_train = pd$n_train,
      n_predictors = pd$n_predictors
    )
  })

  # Summary
  n_valid <- sum(sapply(validation_results, function(x) x$is_valid))
  n_total <- length(validation_results)

  cat(sprintf("  Valid datasets: %d/%d (%.1f%%)\n",
              n_valid, n_total, 100 * n_valid / n_total))

  # Reasons for invalid datasets
  invalid_results <- validation_results[!sapply(validation_results, function(x) x$is_valid)]

  if (length(invalid_results) > 0) {
    reason_counts <- table(sapply(invalid_results, function(x) x$reason))
    cat("\n  Reasons for invalid datasets:\n")
    for (reason in names(reason_counts)) {
      cat(sprintf("    • %s: %d\n", reason, reason_counts[reason]))
    }
  }

  return(list(
    results = validation_results,
    n_valid = n_valid,
    n_invalid = n_total - n_valid,
    pct_valid = 100 * n_valid / n_total
  ))
}
