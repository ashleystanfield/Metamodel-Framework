################################################################################
#                           UTILITY FUNCTIONS                                  #
################################################################################
# General utility functions used across the metamodeling pipeline
################################################################################

suppressPackageStartupMessages({
  library(data.table)
  library(progress)
})

# =============================================================================
# COMPUTATIONAL METRICS TRACKING
# =============================================================================

#' Get current memory usage in MB
#'
#' @return Memory usage in MB
get_memory_usage_mb <- function() {
  # Get memory info - works on Windows, Linux, Mac
  mem_info <- gc(verbose = FALSE, reset = FALSE)
  # Sum of Vcells and Ncells used (in MB)
  used_mb <- sum(mem_info[, 2])  # Column 2 is "used" in MB
  return(used_mb)
}

#' Get peak memory usage in MB (resets counter)
#'
#' @param reset Whether to reset the peak counter
#' @return Peak memory usage in MB
get_peak_memory_mb <- function(reset = TRUE) {
  mem_info <- gc(verbose = FALSE, reset = reset)
  # Column 6 is "max used" in MB
  peak_mb <- sum(mem_info[, 6])
  return(peak_mb)
}

#' Get CPU time information
#'
#' @return List with user, system, and elapsed time
get_cpu_times <- function() {
  times <- proc.time()
  return(list(
    user = times["user.self"],
    system = times["sys.self"],
    elapsed = times["elapsed"]
  ))
}

#' Start computational metrics tracking
#'
#' @return List with start state for metrics tracking
start_metrics_tracking <- function() {
  # Force garbage collection and reset peak memory
  gc(verbose = FALSE, reset = TRUE)

  start_state <- list(
    start_time = Sys.time(),
    start_proc_time = proc.time(),
    start_memory_mb = get_memory_usage_mb(),
    peak_memory_reset = TRUE
  )

  return(start_state)
}

#' Stop computational metrics tracking and calculate metrics
#'
#' @param start_state List returned from start_metrics_tracking()
#' @return List with all computational metrics
stop_metrics_tracking <- function(start_state) {
  # Get end state
end_time <- Sys.time()
  end_proc_time <- proc.time()
  end_memory_mb <- get_memory_usage_mb()
  peak_memory_mb <- get_peak_memory_mb(reset = FALSE)

  # Calculate elapsed times
  elapsed <- end_proc_time - start_state$start_proc_time

  metrics <- list(
    # Wall clock time
    wall_time_sec = as.numeric(difftime(end_time, start_state$start_time, units = "secs")),

    # CPU times
    cpu_user_sec = as.numeric(elapsed["user.self"]),
    cpu_system_sec = as.numeric(elapsed["sys.self"]),
    cpu_total_sec = as.numeric(elapsed["user.self"]) + as.numeric(elapsed["sys.self"]),

    # Memory usage
    memory_start_mb = start_state$start_memory_mb,
    memory_end_mb = end_memory_mb,
    memory_delta_mb = end_memory_mb - start_state$start_memory_mb,
    memory_peak_mb = peak_memory_mb,

    # Timestamps
    timestamp_start = start_state$start_time,
    timestamp_end = end_time
  )

  return(metrics)
}

#' Create empty computational metrics data.table
#'
#' @return Empty data.table with metric columns
create_empty_comp_metrics <- function() {
  data.table(
    group = character(),
    outcome = character(),
    person_id = integer(),
    model_type = character(),
    wall_time_sec = numeric(),
    cpu_user_sec = numeric(),
    cpu_system_sec = numeric(),
    cpu_total_sec = numeric(),
    memory_start_mb = numeric(),
    memory_end_mb = numeric(),
    memory_delta_mb = numeric(),
    memory_peak_mb = numeric(),
    n_train = integer(),
    n_test = integer(),
    n_predictors = integer(),
    timestamp_start = as.POSIXct(character()),
    timestamp_end = as.POSIXct(character())
  )
}

#' Add computational metrics to a data.table row
#'
#' @param metrics List from stop_metrics_tracking()
#' @param group Group name
#' @param outcome Outcome name
#' @param person_id Person ID
#' @param model_type Metamodel type name
#' @param n_train Number of training samples
#' @param n_test Number of test samples
#' @param n_predictors Number of predictors used
#' @return data.table row with all metrics
create_comp_metrics_row <- function(metrics, group, outcome, person_id, model_type,
                                    n_train = NA, n_test = NA, n_predictors = NA) {
  data.table(
    group = group,
    outcome = outcome,
    person_id = as.integer(person_id),
    model_type = model_type,
    wall_time_sec = metrics$wall_time_sec,
    cpu_user_sec = metrics$cpu_user_sec,
    cpu_system_sec = metrics$cpu_system_sec,
    cpu_total_sec = metrics$cpu_total_sec,
    memory_start_mb = metrics$memory_start_mb,
    memory_end_mb = metrics$memory_end_mb,
    memory_delta_mb = metrics$memory_delta_mb,
    memory_peak_mb = metrics$memory_peak_mb,
    n_train = as.integer(n_train),
    n_test = as.integer(n_test),
    n_predictors = as.integer(n_predictors),
    timestamp_start = metrics$timestamp_start,
    timestamp_end = metrics$timestamp_end
  )
}

#' Aggregate computational metrics by model type
#'
#' @param comp_metrics data.table of computational metrics
#' @return data.table with aggregated metrics per model type
aggregate_comp_metrics_by_model <- function(comp_metrics) {
  if (nrow(comp_metrics) == 0) {
    return(data.table())
  }

  comp_metrics[, .(
    n_models = .N,
    total_wall_time_sec = sum(wall_time_sec, na.rm = TRUE),
    mean_wall_time_sec = mean(wall_time_sec, na.rm = TRUE),
    median_wall_time_sec = median(wall_time_sec, na.rm = TRUE),
    min_wall_time_sec = min(wall_time_sec, na.rm = TRUE),
    max_wall_time_sec = max(wall_time_sec, na.rm = TRUE),
    total_cpu_time_sec = sum(cpu_total_sec, na.rm = TRUE),
    mean_cpu_time_sec = mean(cpu_total_sec, na.rm = TRUE),
    mean_memory_delta_mb = mean(memory_delta_mb, na.rm = TRUE),
    max_memory_peak_mb = max(memory_peak_mb, na.rm = TRUE),
    total_train_samples = sum(n_train, na.rm = TRUE),
    mean_train_samples = mean(n_train, na.rm = TRUE)
  ), by = model_type]
}

#' Aggregate computational metrics by group and outcome
#'
#' @param comp_metrics data.table of computational metrics
#' @return data.table with aggregated metrics per group/outcome
aggregate_comp_metrics_by_group <- function(comp_metrics) {
  if (nrow(comp_metrics) == 0) {
    return(data.table())
  }

  comp_metrics[, .(
    n_models = .N,
    total_wall_time_sec = sum(wall_time_sec, na.rm = TRUE),
    mean_wall_time_sec = mean(wall_time_sec, na.rm = TRUE),
    total_cpu_time_sec = sum(cpu_total_sec, na.rm = TRUE),
    mean_memory_delta_mb = mean(memory_delta_mb, na.rm = TRUE),
    max_memory_peak_mb = max(memory_peak_mb, na.rm = TRUE)
  ), by = .(group, outcome, model_type)]
}

#' Print computational metrics summary
#'
#' @param comp_metrics data.table of computational metrics
print_comp_metrics_summary <- function(comp_metrics) {
  if (nrow(comp_metrics) == 0) {
    cat("No computational metrics recorded.\n")
    return(invisible(NULL))
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    COMPUTATIONAL METRICS SUMMARY                              \n")
  cat("================================================================================\n\n")

  # Overall summary
  cat("OVERALL:\n")
  cat(sprintf("  Total models trained: %d\n", nrow(comp_metrics)))
  cat(sprintf("  Total wall time: %s\n", format_duration(sum(comp_metrics$wall_time_sec, na.rm = TRUE))))
  cat(sprintf("  Total CPU time: %s\n", format_duration(sum(comp_metrics$cpu_total_sec, na.rm = TRUE))))
  cat(sprintf("  Peak memory usage: %.1f MB\n", max(comp_metrics$memory_peak_mb, na.rm = TRUE)))

  # By model type
  cat("\nBY MODEL TYPE:\n")
  by_model <- aggregate_comp_metrics_by_model(comp_metrics)

  for (i in seq_len(nrow(by_model))) {
    row <- by_model[i]
    cat(sprintf("\n  %s:\n", toupper(row$model_type)))
    cat(sprintf("    Models: %d\n", row$n_models))
    cat(sprintf("    Total time: %s\n", format_duration(row$total_wall_time_sec)))
    cat(sprintf("    Mean time/model: %.3f sec\n", row$mean_wall_time_sec))
    cat(sprintf("    Mean CPU time/model: %.3f sec\n", row$mean_cpu_time_sec))
    cat(sprintf("    Mean memory delta: %.2f MB\n", row$mean_memory_delta_mb))
    cat(sprintf("    Peak memory: %.1f MB\n", row$max_memory_peak_mb))
  }

  cat("\n================================================================================\n")
}

#' Save computational metrics to CSV
#'
#' @param comp_metrics data.table of computational metrics
#' @param output_dir Output directory path
#' @param prefix File name prefix
save_comp_metrics <- function(comp_metrics, output_dir, prefix = "comp_metrics") {
  if (nrow(comp_metrics) == 0) {
    return(invisible(NULL))
  }

  # Ensure output directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Save detailed metrics
  detail_path <- file.path(output_dir, paste0(prefix, "_detailed.csv"))
  fwrite(comp_metrics, detail_path)
  cat(sprintf("✓ Saved detailed computational metrics: %s\n", detail_path))

  # Save aggregated by model type
  by_model <- aggregate_comp_metrics_by_model(comp_metrics)
  model_path <- file.path(output_dir, paste0(prefix, "_by_model.csv"))
  fwrite(by_model, model_path)
  cat(sprintf("✓ Saved metrics by model type: %s\n", model_path))

  # Save aggregated by group/outcome
  by_group <- aggregate_comp_metrics_by_group(comp_metrics)
  group_path <- file.path(output_dir, paste0(prefix, "_by_group.csv"))
  fwrite(by_group, group_path)
  cat(sprintf("✓ Saved metrics by group/outcome: %s\n", group_path))
}

# =============================================================================
# ORIGINAL UTILITY FUNCTIONS
# =============================================================================

#' Initialize logging
#'
#' @param config Configuration list
setup_logging <- function(config) {

  if (config$logging$log_to_file) {
    log_path <- file.path(config$project$output_directory, config$project$log_file)
    sink(log_path, append = TRUE, split = TRUE)

    cat("\n")
    cat("================================================================================\n")
    cat(sprintf("  METAMODELING RUN: %s\n", Sys.time()))
    cat("================================================================================\n")
  }
}

#' Close logging
close_logging <- function(config) {
  if (config$logging$log_to_file) {
    sink()
  }
}

#' Log message with timestamp
#'
#' @param msg Message to log
#' @param level Log level (INFO, WARNING, ERROR, DEBUG)
log_message <- function(msg, level = "INFO", config = NULL) {

  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  formatted_msg <- sprintf("[%s] %s: %s", timestamp, level, msg)

  # Print to console
  cat(formatted_msg, "\n")

  # Also write to log file if configured
  if (!is.null(config) && config$logging$log_to_file) {
    log_path <- file.path(config$project$output_directory, config$project$log_file)
    cat(formatted_msg, "\n", file = log_path, append = TRUE)
  }
}

#' Create output directory structure
#'
#' @param config Configuration list
setup_output_directories <- function(config) {

  base_dir <- config$project$output_directory

  # Create base output directory
  if (!dir.exists(base_dir)) {
    dir.create(base_dir, recursive = TRUE)
    cat(sprintf("✓ Created output directory: %s\n", base_dir))
  }

  # Create subdirectories for each metamodel type
  enabled_mm <- get_enabled_metamodels(config)

  for (mm in enabled_mm) {
    mm_dir <- file.path(base_dir, mm)
    if (!dir.exists(mm_dir)) {
      dir.create(mm_dir, recursive = TRUE)
    }
  }

  # Create visualization directory if enabled
  if (config$visualizations$enabled) {
    viz_dir <- file.path(base_dir, "visualizations")
    if (!dir.exists(viz_dir)) {
      dir.create(viz_dir, recursive = TRUE)
    }
  }

  cat("✓ Output directory structure created\n")
}

#' Generate output filename
#'
#' @param config Configuration list
#' @param type File type (models, metrics, predictions, etc.)
#' @param metamodel_name Name of metamodel
#' @param outcome Name of outcome variable
#' @param group Name of data group
#' @param extension File extension
#' @return Full path to output file
generate_output_filename <- function(config, type, metamodel_name,
                                    outcome, group, extension = "csv") {

  base_dir <- config$project$output_directory

  # Add timestamp if configured
  if (config$output$naming$use_timestamps) {
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    filename <- sprintf("%s_%s_%s_%s_%s.%s",
                       type, metamodel_name, outcome, group, timestamp, extension)
  } else {
    filename <- sprintf("%s_%s_%s_%s.%s",
                       type, metamodel_name, outcome, group, extension)
  }

  # Add prefix if configured
  if (!is.null(config$output$naming$prefix)) {
    filename <- paste0(config$output$naming$prefix, "_", filename)
  }

  full_path <- file.path(base_dir, metamodel_name, filename)

  return(full_path)
}

#' Create progress bar
#'
#' @param total Total number of iterations
#' @param format Progress bar format
#' @param config Configuration list
#' @return Progress bar object or NULL if disabled
create_progress_bar <- function(total, format = "[:bar] :current/:total (:percent) ETA: :eta",
                               config = NULL) {

  # Check if progress bars are enabled
  if (!is.null(config) && !config$logging$progress_bars) {
    return(NULL)
  }

  pb <- progress_bar$new(
    format = format,
    total = total,
    clear = FALSE,
    width = 70
  )

  return(pb)
}

#' Update progress bar safely
#'
#' @param pb Progress bar object
#' @param n Number of ticks to advance
tick_progress <- function(pb, n = 1) {
  if (!is.null(pb)) {
    pb$tick(n)
  }
}

#' Detect person types in data
#'
#' @param data Data frame or data.table
#' @param person_id_col Name of person ID column
#' @return List with person IDs and count
detect_person_types <- function(data, person_id_col) {

  if (!person_id_col %in% names(data)) {
    stop(sprintf("Person ID column '%s' not found in data", person_id_col))
  }

  persons <- sort(unique(data[[person_id_col]]))
  n_persons <- length(persons)

  cat(sprintf("✓ Detected %d person types\n", n_persons))

  return(list(
    persons = persons,
    n_persons = n_persons
  ))
}

#' Detect constant predictors
#'
#' @param data Data frame with predictor columns
#' @param predictors Character vector of predictor names
#' @return Character vector of constant predictor names
detect_constant_predictors <- function(data, predictors) {

  const_cols <- names(which(vapply(data[, ..predictors], function(x) {
    ux <- unique(x)
    ux <- ux[!is.na(ux)]
    length(ux) <= 1
  }, logical(1))))

  return(const_cols)
}

#' Safe model prediction with error handling
#'
#' @param model Trained model object
#' @param newdata Data for prediction
#' @return Numeric vector of predictions or NA if error
safe_predict <- function(model, newdata) {

  result <- tryCatch({
    as.numeric(predict(model, newdata = newdata))
  }, error = function(e) {
    warning(sprintf("Prediction failed: %s", e$message))
    rep(NA_real_, nrow(newdata))
  })

  return(result)
}

#' Calculate R-squared
#'
#' @param actual Actual values
#' @param predicted Predicted values
#' @return R-squared value
calculate_r2 <- function(actual, predicted) {

  # Remove NA values
  valid <- !is.na(actual) & !is.na(predicted) & is.finite(actual) & is.finite(predicted)

  if (sum(valid) == 0) {
    return(NA_real_)
  }

  actual <- actual[valid]
  predicted <- predicted[valid]

  ss_res <- sum((actual - predicted)^2)
  ss_tot <- sum((actual - mean(actual))^2)

  if (ss_tot == 0) {
    return(NA_real_)
  }

  r2 <- 1 - ss_res / ss_tot

  return(r2)
}

#' Calculate multiple regression metrics
#'
#' @param actual Actual values
#' @param predicted Predicted values
#' @return Data frame with metrics
calculate_metrics <- function(actual, predicted) {

  # Remove NA values
  valid <- !is.na(actual) & !is.na(predicted) & is.finite(actual) & is.finite(predicted)

  if (sum(valid) < 2) {
    return(data.frame(
      n = sum(valid),
      r_squared = NA_real_,
      rmse = NA_real_,
      mae = NA_real_,
      mape = NA_real_
    ))
  }

  actual <- actual[valid]
  predicted <- predicted[valid]

  # R-squared
  ss_res <- sum((actual - predicted)^2)
  ss_tot <- sum((actual - mean(actual))^2)
  r_squared <- if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_

  # RMSE
  rmse <- sqrt(mean((actual - predicted)^2))

  # MAE
  mae <- mean(abs(actual - predicted))

  # MAPE (avoid division by zero)
  mape <- if (all(actual != 0)) {
    mean(abs((actual - predicted) / actual)) * 100
  } else {
    NA_real_
  }

  return(data.frame(
    n = length(actual),
    r_squared = r_squared,
    rmse = rmse,
    mae = mae,
    mape = mape
  ))
}

#' Format time duration
#'
#' @param seconds Number of seconds
#' @return Formatted string
format_duration <- function(seconds) {

  if (seconds < 60) {
    return(sprintf("%.1f seconds", seconds))
  } else if (seconds < 3600) {
    return(sprintf("%.1f minutes", seconds / 60))
  } else {
    return(sprintf("%.1f hours", seconds / 3600))
  }
}

#' Print section header
#'
#' @param title Section title
#' @param width Width of header (characters)
print_section_header <- function(title, width = 80) {

  cat("\n")
  cat(rep("=", width), sep = "")
  cat("\n")
  left_pad <- paste(rep(" ", floor((width - nchar(title)) / 2)), collapse = "")
  right_pad <- paste(rep(" ", ceiling((width - nchar(title)) / 2)), collapse = "")
  cat(sprintf("%s%s%s\n", left_pad, title, right_pad))
  cat(rep("=", width), sep = "")
  cat("\n\n")
}

#' Print completion message
#'
#' @param section Section name
#' @param duration Duration in seconds
print_completion <- function(section, duration = NULL) {

  cat("\n")
  cat(sprintf("✓ %s complete", section))

  if (!is.null(duration)) {
    cat(sprintf(" (%s)", format_duration(duration)))
  }

  cat("\n")
}

#' Load population weights from file
#'
#' @param config Configuration list
#' @return Named list of weights (person_id -> weight)
load_population_weights <- function(config) {

  weights_file <- config$population_weighting$weights_file

  if (is.null(weights_file) || !file.exists(weights_file)) {
    warning("Population weights file not found. Using uniform weights.")
    return(NULL)
  }

  cat(sprintf("▶ Loading population weights from: %s\n", weights_file))

  # Load weights
  weights_data <- fread(weights_file)

  # Get column names from config or use defaults
  person_col <- config$population_weighting$person_id_column %||% "person_idx"
  weight_col <- config$population_weighting$weight_column %||% "weight"

  # Check columns exist
  if (!person_col %in% names(weights_data) || !weight_col %in% names(weights_data)) {
    warning(sprintf("Required columns not found in weights file: %s, %s", person_col, weight_col))
    return(NULL)
  }

  # Convert to named list
  weights_list <- as.list(weights_data[[weight_col]])
  names(weights_list) <- as.character(weights_data[[person_col]])

  cat(sprintf("  Loaded weights for %d person types\n", length(weights_list)))

  return(weights_list)
}
