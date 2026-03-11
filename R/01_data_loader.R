#####DATA LOADER MODULE#####
# Generic data loading functions that work with any CSV structure
# Handles column mapping, file validation, and data type detection

suppressPackageStartupMessages({
  library(data.table)
  library(readr)
})

#' Load all data files specified in configuration
#'
#' @param config Configuration list
#' @return Named list of data.tables, one per input file
#' @export
load_all_data <- function(config) {

  cat("Loading data files...\n")

  # Get enabled input files
  input_files <- get_enabled_input_files(config)

  if (length(input_files) == 0) {
    stop("No input files specified or enabled in configuration")
  }

  # Load each file
  data_list <- list()

  for (file_name in names(input_files)) {
    file_path <- input_files[[file_name]]

    cat(sprintf("  Loading: %s... ", file_name))

    tryCatch({
      data <- load_single_file(file_path, file_name, config)
      data_list[[file_name]] <- data
      cat(sprintf(" (%d rows, %d columns)\n", nrow(data), ncol(data)))

    }, error = function(e) {
      cat(sprintf(" FAILED\n"))
      warning(sprintf("Failed to load %s: %s", file_name, e$message))
    })
  }

  if (length(data_list) == 0) {
    stop("No data files were successfully loaded")
  }

  cat(sprintf("\n Loaded %d data file(s)\n", length(data_list)))

  return(data_list)
}

#' Load a single data file
#'
#' @param file_path Path to file
#' @param file_name Name identifier for the file
#' @param config Configuration list
#' @return data.table
load_single_file <- function(file_path, file_name, config) {

  # Check file exists
  if (!file.exists(file_path)) {
    stop(sprintf("File not found: %s", file_path))
  }

  # Detect file type
  file_ext <- tolower(tools::file_ext(file_path))

  # Load based on file type
  data <- switch(file_ext,
    "csv" = fread(file_path, showProgress = FALSE),
    "txt" = fread(file_path, showProgress = FALSE),
    "rds" = readRDS(file_path),
    stop(sprintf("Unsupported file type: %s", file_ext))
  )

  # Convert to data.table if needed
  if (!is.data.table(data)) {
    data <- as.data.table(data)
  }

  # Apply column mapping if configured
  if (isTRUE(config$variables$column_mapping$enabled)) {
    data <- apply_column_mapping(data, config)
  }

  # Add source file identifier
  data[, data_source := file_name]

  return(data)
}

#' Apply column name mapping
#'
#' @param data data.table
#' @param config Configuration list
#' @return data.table with renamed columns
apply_column_mapping <- function(data, config) {

  mapping <- config$variables$column_mapping

  # Remove 'enabled' flag
  mapping$enabled <- NULL

  if (length(mapping) == 0) {
    return(data)
  }

  renamed_count <- 0

  for (standard_name in names(mapping)) {
    user_name <- mapping[[standard_name]]

    if (user_name %in% names(data)) {
      setnames(data, user_name, standard_name)
      renamed_count <- renamed_count + 1
    }
  }

  if (renamed_count > 0) {
    cat(sprintf("  Mapped %d column(s)\n", renamed_count))
  }

  return(data)
}

#' Validate that required columns exist
#'
#' @param data data.table
#' @param required_cols Character vector of required column names
#' @param data_name Name of the dataset (for error messages)
#' @return TRUE if valid, stops if invalid
validate_required_columns <- function(data, required_cols, data_name = "data") {

  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required columns in %s: %s",
                 data_name,
                 paste(missing_cols, collapse = ", ")))
  }

  return(TRUE)
}

#' Check data quality and report statistics
#'
#' @param data data.table
#' @param config Configuration list
#' @return List of data quality metrics
check_data_quality <- function(data, config) {

  person_id_col <- config$data$person_id_column
  predictors <- config$variables$predictors
  outcomes <- config$variables$outcomes

  cat("\n Data Quality Check:\n")

  # Basic dimensions
  cat(sprintf("  Dimensions: %d rows × %d columns\n", nrow(data), ncol(data)))

  # Check person ID column
  if (person_id_col %in% names(data)) {
    n_persons <- uniqueN(data[[person_id_col]])
    cat(sprintf("  Person types: %d unique values\n", n_persons))
  } else {
    warning(sprintf("Person ID column '%s' not found", person_id_col))
  }

  # Missing values
  missing_summary <- data[, lapply(.SD, function(x) sum(is.na(x)))]
  total_missing <- sum(unlist(missing_summary))
  missing_pct <- 100 * total_missing / (nrow(data) * ncol(data))

  cat(sprintf("  Missing values: %d (%.2f%%)\n", total_missing, missing_pct))

  # Check predictors
  missing_predictors <- setdiff(predictors, names(data))
  if (length(missing_predictors) > 0) {
    warning(sprintf("Predictors not found in data: %s",
                   paste(missing_predictors, collapse = ", ")))
  } else {
    cat(sprintf("  Predictors: %d/%d found ✓\n", length(predictors), length(predictors)))
  }

  # Check outcomes
  missing_outcomes <- setdiff(outcomes, names(data))
  if (length(missing_outcomes) > 0) {
    warning(sprintf("Outcomes not found in data: %s",
                   paste(missing_outcomes, collapse = ", ")))
  } else {
    cat(sprintf("  Outcomes: %d/%d found ✓\n", length(outcomes), length(outcomes)))
  }

  quality_report <- list(
    n_rows = nrow(data),
    n_cols = ncol(data),
    n_persons = if (person_id_col %in% names(data)) uniqueN(data[[person_id_col]]) else NA,
    missing_total = total_missing,
    missing_pct = missing_pct,
    predictors_found = length(setdiff(predictors, missing_predictors)),
    predictors_total = length(predictors),
    outcomes_found = length(setdiff(outcomes, missing_outcomes)),
    outcomes_total = length(outcomes)
  )

  return(quality_report)
}

#' Detect numeric columns automatically
#'
#' @param data data.table
#' @param exclude_cols Columns to exclude from detection
#' @return Character vector of numeric column names
detect_numeric_columns <- function(data, exclude_cols = c()) {

  numeric_cols <- names(data)[sapply(data, is.numeric)]
  numeric_cols <- setdiff(numeric_cols, exclude_cols)

  return(numeric_cols)
}

#' Suggest predictors based on data structure
#'
#' @param data data.table
#' @param exclude_cols Columns to exclude
#' @return Character vector of suggested predictor names
suggest_predictors <- function(data, exclude_cols = c()) {

  # Get numeric columns
  numeric_cols <- detect_numeric_columns(data, exclude_cols)

  # Exclude likely ID columns
  id_patterns <- c("id", "idx", "index", "number", "code")
  numeric_cols <- numeric_cols[!grepl(paste(id_patterns, collapse = "|"),
                                     numeric_cols, ignore.case = TRUE)]

  return(numeric_cols)
}

#' Handle missing data according to configuration
#'
#' @param data data.table
#' @param config Configuration list
#' @return data.table with missing data handled
handle_missing_data <- function(data, config) {

  strategy <- config$data$missing_data$strategy

  if (is.null(strategy)) {
    strategy <- "complete_cases"
  }

  original_nrow <- nrow(data)

  cat(sprintf("\n Handling missing data (strategy: %s)...\n", strategy))

  data <- switch(strategy,
    "complete_cases" = {
      # Remove rows with any NA
      data_clean <- data[complete.cases(data)]
      removed <- original_nrow - nrow(data_clean)
      if (removed > 0) {
        cat(sprintf("  Removed %d rows with missing values\n", removed))
      }
      data_clean
    },

    "impute" = {
      # Impute with median/mode
      method <- config$data$missing_data$imputation_method
      if (is.null(method)) method <- "median"

      data_imputed <- impute_missing(data, method)
      cat(sprintf("  Imputed missing values using %s\n", method))
      data_imputed
    },

    "drop_variable" = {
      # Remove columns with too many missing values
      threshold <- 0.5  # Drop if >50% missing
      missing_pct <- data[, lapply(.SD, function(x) mean(is.na(x)))]

      cols_to_drop <- names(missing_pct)[missing_pct > threshold]

      if (length(cols_to_drop) > 0) {
        data[, (cols_to_drop) := NULL]
        cat(sprintf("  Dropped %d columns with >%.0f%% missing\n",
                   length(cols_to_drop), threshold * 100))
      }

      # Then remove remaining rows with NA
      data[complete.cases(data)]
    },

    {
      warning(sprintf("Unknown missing data strategy: %s. Using complete_cases.", strategy))
      data[complete.cases(data)]
    }
  )

  cat(sprintf("  Final dataset: %d rows\n", nrow(data)))

  return(data)
}

#' Impute missing values
#'
#' @param data data.table
#' @param method Imputation method ('median', 'mean', 'mode')
#' @return data.table with imputed values
impute_missing <- function(data, method = "median") {

  data_imputed <- copy(data)

  for (col in names(data_imputed)) {
    if (any(is.na(data_imputed[[col]]))) {

      if (is.numeric(data_imputed[[col]])) {
        # Numeric columns
        fill_value <- switch(method,
          "median" = median(data_imputed[[col]], na.rm = TRUE),
          "mean" = mean(data_imputed[[col]], na.rm = TRUE),
          "zero" = 0,
          median(data_imputed[[col]], na.rm = TRUE)
        )

        data_imputed[is.na(get(col)), (col) := fill_value]

      } else {
        # Categorical columns - use mode
        mode_value <- names(sort(table(data_imputed[[col]]), decreasing = TRUE))[1]
        data_imputed[is.na(get(col)), (col) := mode_value]
      }
    }
  }

  return(data_imputed)
}

#' Load and prepare all data with full pipeline
#'
#' @param config Configuration list
#' @return List with prepared data for each file
#' @export
load_and_prepare_data <- function(config) {

  print_section_header("DATA LOADING & PREPARATION")

  # Load all files
  data_list <- load_all_data(config)

  # Check quality and handle missing data for each file
  prepared_data <- list()

  for (file_name in names(data_list)) {
    cat(sprintf("\n--- Processing: %s ---\n", file_name))

    data <- data_list[[file_name]]

    # Quality check
    quality <- check_data_quality(data, config)

    # Handle missing data
    data_clean <- handle_missing_data(data, config)

    # Validate required columns exist (predictors are required, outcomes are optional per file)
    required_cols <- c(
      config$data$person_id_column,
      config$variables$predictors
    )

    # Check which outcomes are available in this file
    available_outcomes <- intersect(config$variables$outcomes, names(data_clean))
    missing_outcomes <- setdiff(config$variables$outcomes, names(data_clean))

    if (length(missing_outcomes) > 0) {
      cat(sprintf("  Note: Missing outcomes in this file: %s\n", paste(missing_outcomes, collapse = ", ")))
    }

    tryCatch({
      validate_required_columns(data_clean, required_cols, file_name)
    }, error = function(e) {
      warning(sprintf("Validation failed for %s: %s", file_name, e$message))
      return(NULL)
    })

    prepared_data[[file_name]] <- list(
      data = data_clean,
      quality = quality,
      n_rows_original = nrow(data),
      n_rows_final = nrow(data_clean)
    )
  }

  cat("\n✓ Data loading and preparation complete\n")

  return(prepared_data)
}
