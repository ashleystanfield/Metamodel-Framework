
#####CONFIG LOADER MODULE#####
# This module handles loading and validating the configuration file
# Supports YAML configuration files

library(yaml)

#' Load configuration from YAML file
#'
#' @param config_path Path to config.yaml file
#' @return List containing configuration parameters
#' @export
load_config <- function(config_path = "config.yaml") {

  if (!file.exists(config_path)) {
    stop(sprintf("Configuration file not found: %s", config_path))
  }
  cat("                    LOADING CONFIGURATION                                      \n")
  config <- yaml::read_yaml(config_path)
  cat(sprintf("Loaded configuration from: %s\n", config_path))
  cat(sprintf("Project: %s\n", config$project$name))
  # Validate configuration if enabled
  if (isTRUE(config$validation$validate_config)) {
    validate_config(config)
  }
  return(config)
}

#' Validate configuration structure and values
#'
#' @param config Configuration list
#' @return TRUE if valid, stops execution if invalid
validate_config <- function(config) {

  cat("\n Validating configuration...\n")

  errors <- character(0)
  warnings <- character(0)

  #####REQUIRED FIELDS#####
  # Project settings
  if (is.null(config$project$name)) {
    errors <- c(errors, "Missing: project$name")
  }

  if (is.null(config$project$working_directory)) {
    errors <- c(errors, "Missing: project$working_directory")
  }

  # Data settings
  if (is.null(config$data$input_files) || length(config$data$input_files) == 0) {
    errors <- c(errors, "Missing: data$input_files (must specify at least one)")
  }

  if (is.null(config$data$person_id_column)) {
    errors <- c(errors, "Missing: data$person_id_column")
  }

  # Variables
  if (is.null(config$variables$predictors) || length(config$variables$predictors) == 0) {
    errors <- c(errors, "Missing: variables$predictors (must specify at least one)")
  }

  if (is.null(config$variables$outcomes) || length(config$variables$outcomes) == 0) {
    errors <- c(errors, "Missing: variables$outcomes (must specify at least one)")
  }

  #####FILE EXISTENCE#####
  # Check working directory
  if (!dir.exists(config$project$working_directory)) {
    errors <- c(errors, sprintf("Working directory does not exist: %s",
                                config$project$working_directory))
  }

  # Check input files (only for enabled files)
  for (i in seq_along(config$data$input_files)) {
    file_info <- config$data$input_files[[i]]

    # Skip if explicitly disabled
    if (!is.null(file_info$enabled) && !file_info$enabled) {
      next
    }

    full_path <- file.path(config$project$working_directory, file_info$path)

    if (!file.exists(full_path) && !file.exists(file_info$path)) {
      warnings <- c(warnings, sprintf("Input file not found: %s", file_info$path))
    }
  }

  #####PARAMETER RANGES#####
  # Train/test split
  split_ratio <- config$modeling$train_test_split
  if (!is.null(split_ratio)) {
    if (split_ratio <= 0 || split_ratio >= 1) {
      errors <- c(errors, "train_test_split must be between 0 and 1")
    }
  }

  # Random seed
  if (!is.null(config$modeling$random_seed)) {
    if (!is.numeric(config$modeling$random_seed)) {
      errors <- c(errors, "random_seed must be numeric")
    }
  }

  # Cross-validation folds
  if (!is.null(config$modeling$cross_validation$n_folds)) {
    if (config$modeling$cross_validation$n_folds < 2) {
      errors <- c(errors, "cross_validation n_folds must be >= 2")
    }
  }

  #####METAMODEL CHECKS#####
  # Check if at least one metamodel is enabled
  metamodels_enabled <- sapply(names(config$metamodels), function(mm) {
    isTRUE(config$metamodels[[mm]]$enabled)
  })

  if (!any(metamodels_enabled)) {
    warnings <- c(warnings, "No metamodels enabled - nothing will be trained")
  }

  #####REPORT RESULTS#####
  if (length(errors) > 0) {
    cat("\n CONFIGURATION VALIDATION FAILED\n\n")
    cat("Errors:\n")
    for (err in errors) {
      cat(sprintf("  • %s\n", err))
    }
    stop("Configuration validation failed. Please fix errors and try again.")
  }

  if (length(warnings) > 0) {
    cat("\n Configuration warnings:\n")
    for (warn in warnings) {
      cat(sprintf("  • %s\n", warn))
    }
  }

  cat("\n✓ Configuration validated successfully\n")

  return(TRUE)
}

#' Get enabled input files from configuration
#'
#' @param config Configuration list
#' @return Named vector of file paths
get_enabled_input_files <- function(config) {

  files <- list()

  for (file_info in config$data$input_files) {
    # Check if enabled (default TRUE if not specified)
    is_enabled <- if (is.null(file_info$enabled)) TRUE else file_info$enabled

    if (is_enabled) {
      # Try full path first, then relative to working directory
      full_path <- file.path(config$project$working_directory, file_info$path)

      if (file.exists(file_info$path)) {
        files[[file_info$name]] <- file_info$path
      } else if (file.exists(full_path)) {
        files[[file_info$name]] <- full_path
      } else {
        warning(sprintf("File not found for '%s': %s", file_info$name, file_info$path))
      }
    }
  }

  return(files)
}

#' Get enabled metamodels from configuration
#'
#' @param config Configuration list
#' @return Character vector of enabled metamodel names
get_enabled_metamodels <- function(config) {

  enabled <- character(0)

  for (mm_name in names(config$metamodels)) {
    if (isTRUE(config$metamodels[[mm_name]]$enabled)) {
      enabled <- c(enabled, mm_name)
    }
  }

  return(enabled)
}

#' Print configuration summary
#'
#' @param config Configuration list
print_config_summary <- function(config) {

  cat("                    CONFIGURATION SUMMARY                                      \n")

  cat(sprintf("Project: %s\n", config$project$name))
  cat(sprintf("Working Directory: %s\n", config$project$working_directory))
  cat(sprintf("Output Directory: %s\n", config$project$output_directory))

  cat("\n--- Data ---\n")
  enabled_files <- get_enabled_input_files(config)
  cat(sprintf("Input Files: %d enabled\n", length(enabled_files)))
  for (name in names(enabled_files)) {
    cat(sprintf("  • %s\n", name))
  }

  cat("\n--- Variables ---\n")
  cat(sprintf("Predictors: %d\n", length(config$variables$predictors)))
  cat(sprintf("  %s\n", paste(config$variables$predictors, collapse = ", ")))
  cat(sprintf("Outcomes: %d\n", length(config$variables$outcomes)))
  cat(sprintf("  %s\n", paste(config$variables$outcomes, collapse = ", ")))

  cat("\n--- Modeling ---\n")
  cat(sprintf("Random Seed: %d\n", config$modeling$random_seed))
  cat(sprintf("Train/Test Split: %.0f%%/%.0f%%\n",
              config$modeling$train_test_split * 100,
              (1 - config$modeling$train_test_split) * 100))

  enabled_mm <- get_enabled_metamodels(config)
  cat(sprintf("Metamodels Enabled: %d\n", length(enabled_mm)))
  for (mm in enabled_mm) {
    cat(sprintf("  • %s\n", mm))
  }

  cat("\n================================================================================\n\n")
}
