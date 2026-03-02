suppressPackageStartupMessages({
  # Core data manipulation
  library(data.table)
  library(dplyr)
  library(readr)

  # Metamodeling
  library(caret)
  library(nnet)
  library(randomForest)
  library(e1071)
  library(kernlab)

  # Decision trees
  library(rpart)
  library(rpart.plot)

  # Visualization
  library(ggplot2)
  library(ggridges)
  library(ggh4x)
  library(GGally)
  library(scales)
  library(viridis)
  library(gridExtra)

  # Utilities
  library(yaml)
  library(progress)
  library(tools)
  library(stringr)
})

source("R/00_config_loader.R")
source("R/utils.R")
source("R/01_data_loader.R")
source("R/02_preprocessing.R")

# Metamodel training modules 
source("R/03_metamodel_lr.R")
source("R/04_metamodel_nn.R")
source("R/05_metamodel_rf.R")

# Prediction and evaluation module
source("R/06_population_prediction.R")
source("R/07_model_evaluation.R")
source("R/08_ensemble.R")

# Additional metamodel modules 
source("R/09_metamodel_svr.R")
source("R/10_metamodel_qr.R")
source("R/11_metamodel_cr.R")

# Visualization and decision tree modules
source("R/12_decision_tree.R")
source("R/13_visualization.R")

#####MAIN PIPELINE FUNCTION#####
run_metamodeling_pipeline <- function(config_file = "config.yaml",
                                     steps = c("load", "validate", "train",
                                              "predict", "evaluate", "decision_tree", "visualize")) {

  start_time <- Sys.time()
  # Load configuration
  config <- load_config(config_file)
  # Print summary
  print_config_summary(config)
  # Setup output directories
  setup_output_directories(config)
  # Setup logging
  if (config$logging$log_to_file) {
    setup_logging(config)
  }
  # Set random seed
  set.seed(config$modeling$random_seed)
  cat(sprintf("✓ Random seed set to: %d\n", config$modeling$random_seed))
  # Set working directory
  if (dir.exists(config$project$working_directory)) {
    setwd(config$project$working_directory)
    cat(sprintf("✓ Working directory: %s\n", getwd()))
  }
  # Initialize results list
  results <- list(
    config = config,
    start_time = start_time
  )
  #####STEP 1: DATA LOADING#####

  if ("load" %in% steps) {

    step_start <- Sys.time()
    print_section_header("STEP 1: DATA LOADING")

    # Load and prepare all data
    results$data_raw <- load_and_prepare_data(config)

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Data loading", step_duration)
  }

  #####STEP 2: DATA VALIDATION & PREPROCESSING#####
  if ("validate" %in% steps && !is.null(results$data_raw)) {

    step_start <- Sys.time()
    print_section_header("STEP 2: VALIDATION & PREPROCESSING")

    # Prepare person-specific datasets for each group and outcome
    results$person_datasets <- list()

    for (group_name in names(results$data_raw)) {
      cat(sprintf("\n--- Processing group: %s ---\n", group_name))

      group_data <- results$data_raw[[group_name]]$data

      # Prepare for each outcome
      for (outcome in config$variables$outcomes) {

        # Check if outcome exists in this group's data
        if (!(outcome %in% names(group_data))) {
          if (isTRUE(config$validation$skip_missing_outcomes)) {
            cat(sprintf("\nOutcome: %s - SKIPPED (not in data)\n", outcome))
            next
          } else {
            warning(sprintf("Outcome '%s' not found in group '%s'", outcome, group_name))
            next
          }
        }

        cat(sprintf("\nOutcome: %s\n", outcome))

        # Prepare all persons
        person_ds <- prepare_all_persons(group_data, config, outcome)

        # Validate
        validation <- validate_all_persons(person_ds, config)

        # Store
        key <- paste(group_name, outcome, sep = "_")
        results$person_datasets[[key]] <- list(
          group = group_name,
          outcome = outcome,
          datasets = person_ds,
          validation = validation
        )
      }
    }

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Validation & preprocessing", step_duration)
  }

  #####STEP 3: METAMODEL TRAINING#####

  if ("train" %in% steps && !is.null(results$person_datasets)) {

    step_start <- Sys.time()
    print_section_header("STEP 3: METAMODEL TRAINING")

    # Get enabled metamodels
    enabled_mm <- get_enabled_metamodels(config)

    if (length(enabled_mm) == 0) {
      cat("No metamodels enabled in configuration\n")
    } else {
      cat(sprintf("Training %d metamodel type(s):\n", length(enabled_mm)))
      for (mm in enabled_mm) {
        cat(sprintf("  • %s\n", mm))
      }

      # Initialize models storage
      results$models <- list()

      # Initialize computational metrics storage
      results$comp_metrics <- create_empty_comp_metrics()
      results$comp_metrics_by_step <- list()

      # Load population weights if configured
      population_weights <- NULL
      if (config$modeling$use_population_weights &&
          !is.null(config$population_weighting$weights_file)) {
        population_weights <- load_population_weights(config)
      }

      # Train each enabled metamodel type
      for (mm in enabled_mm) {
        cat(sprintf("\n>>> Training %s <<<\n", toupper(mm)))

        # Start computational metrics tracking for this metamodel type
        mm_metrics_start <- start_metrics_tracking()

        results$models[[mm]] <- switch(mm,
          "linear_regression" = train_lr_all(results$person_datasets, config),
          "neural_network" = train_nn_all(results$person_datasets, config),
          "random_forest" = train_rf_all(results$person_datasets, config),
          "support_vector_regression" = train_svr_all(results$person_datasets, config),
          "quadratic_regression" = train_qr_all(results$person_datasets, config),
          "cubic_regression" = train_cr_all(results$person_datasets, config),
          {
            warning(sprintf("Unknown metamodel type: %s", mm))
            NULL
          }
        )

        # Stop metrics tracking and store
        mm_metrics <- stop_metrics_tracking(mm_metrics_start)

        # Count models trained
        n_models <- if (!is.null(results$models[[mm]])) {
          sum(sapply(results$models[[mm]], function(x) length(x$models)))
        } else 0

        results$comp_metrics_by_step[[mm]] <- list(
          model_type = mm,
          n_models = n_models,
          wall_time_sec = mm_metrics$wall_time_sec,
          cpu_user_sec = mm_metrics$cpu_user_sec,
          cpu_system_sec = mm_metrics$cpu_system_sec,
          cpu_total_sec = mm_metrics$cpu_total_sec,
          memory_start_mb = mm_metrics$memory_start_mb,
          memory_end_mb = mm_metrics$memory_end_mb,
          memory_delta_mb = mm_metrics$memory_delta_mb,
          memory_peak_mb = mm_metrics$memory_peak_mb,
          timestamp_start = mm_metrics$timestamp_start,
          timestamp_end = mm_metrics$timestamp_end
        )

        cat(sprintf("  ⏱ Time: %s | CPU: %.1fs | Memory: %.1f MB (peak: %.1f MB)\n",
                    format_duration(mm_metrics$wall_time_sec),
                    mm_metrics$cpu_total_sec,
                    mm_metrics$memory_delta_mb,
                    mm_metrics$memory_peak_mb))

        # Save individual metrics file for this metamodel type
        mm_metrics_dt <- as.data.table(results$comp_metrics_by_step[[mm]])
        mm_metrics_file <- file.path(config$project$output_directory,
                                     sprintf("computational_metrics_%s.csv", mm))
        fwrite(mm_metrics_dt, mm_metrics_file)
        cat(sprintf("  ✓ Metrics saved: %s\n", mm_metrics_file))
      }

      # Convert step metrics to data.table for saving
      results$comp_metrics_summary <- rbindlist(lapply(results$comp_metrics_by_step, as.data.table))
    }

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Metamodel training", step_duration)
  }

  #####STEP 4: PREDICTION & ENSEMBLE#####


  if ("predict" %in% steps && !is.null(results$models)) {

    step_start <- Sys.time()
    print_section_header("STEP 4: PREDICTION & ENSEMBLE")

    # Load population weights if needed
    population_weights <- NULL
    if (config$modeling$use_population_weights &&
        !is.null(config$population_weighting$weights_file)) {
      population_weights <- load_population_weights(config)
    }

    # Generate population-level predictions if scenarios provided
    if (!is.null(config$prediction$scenario_file) &&
        file.exists(config$prediction$scenario_file)) {

      cat("\n▶ Loading prediction scenarios...\n")
      scenarios <- fread(config$prediction$scenario_file)
      cat(sprintf("  Loaded %d scenarios\n", nrow(scenarios)))

      # Generate population predictions
      results$population_predictions <- generate_all_population_predictions(
        results$models,
        scenarios,
        population_weights,
        config
      )

    } else {
      cat("\n⚠ No scenario file specified - skipping population predictions\n")
      cat("   To generate predictions, add 'scenario_file' to config\n")
    }

    # Generate ensemble predictions if configured
    if (isTRUE(config$ensemble$enabled) && length(results$models) > 1) {

      cat("\n▶ Generating ensemble predictions...\n")

      # Determine ensemble method
      ensemble_method <- config$ensemble$method %||% "simple_average"
      cat(sprintf("  Ensemble method: %s\n", ensemble_method))

      # Calculate weights if using weighted average
      if (ensemble_method == "weighted_average") {
        # Use test performance to calculate weights
        # This will be available after evaluation step
        cat("  ⚠ Weighted ensemble requires evaluation step first\n")
        cat("    Using simple average instead\n")
        ensemble_method <- "simple_average"
      }

      # For now, store ensemble configuration
      results$ensemble_config <- list(
        method = ensemble_method,
        enabled = TRUE
      )

      cat("  ✓ Ensemble configuration stored\n")
    }

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Prediction & Ensemble", step_duration)
  }

  # ----------------------------------------------------------------------------
  # STEP 5: EVALUATION
  # ----------------------------------------------------------------------------

  if ("evaluate" %in% steps && !is.null(results$models)) {

    step_start <- Sys.time()
    print_section_header("STEP 5: EVALUATION")

    # Generate comprehensive evaluation report
    results$evaluation <- generate_evaluation_report(results$models, config)

    # Print best models
    cat("\n▶ Top performing models:\n")
    best_models <- results$evaluation$best
    for (i in 1:min(5, nrow(best_models))) {
      cat(sprintf("  %d. %s (%s) - Test R² = %.3f\n",
                  i,
                  best_models$combination[i],
                  best_models$model_type[i],
                  best_models$mean_test_r2[i]))
    }

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Evaluation", step_duration)
  }

  # ----------------------------------------------------------------------------
  # STEP 6: DECISION TREE ANALYSIS
  # ----------------------------------------------------------------------------

  if ("decision_tree" %in% steps && isTRUE(config$decision_tree$enabled) &&
      !is.null(results$models)) {

    step_start <- Sys.time()
    print_section_header("STEP 6: DECISION TREE ANALYSIS")

    # Build decision tree for intervention recommendations
    cat("\n▶ Building decision tree for intervention recommendations...\n")

    target_outcome <- config$decision_tree$target_outcome %||% config$variables$outcomes[1]
    n_simulations <- config$decision_tree$n_simulations %||% 1000

    cat(sprintf("  Target outcome: %s\n", target_outcome))
    cat(sprintf("  Simulations: %d\n", n_simulations))

    # Load population weights if available
    population_weights <- NULL
    if (config$population$use_weighting &&
        !is.null(config$population$weights$file_path) &&
        file.exists(config$population$weights$file_path)) {
      population_weights <- load_population_weights(config)
    }

    # Build decision tree
    results$decision_tree <- build_decision_tree(
      metamodel_results = results$models,
      config = config,
      target_outcome = target_outcome,
      n_simulations = n_simulations,
      population_weights = population_weights
    )

    # Plot decision tree if visualization enabled
    if (config$visualizations$plots$decision_tree$enabled) {
      output_dir <- file.path(config$project$output_directory, "visualizations")
      if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

      tree_plot_file <- file.path(output_dir, config$visualizations$plots$decision_tree$output_file)

      plot_decision_tree(
        results$decision_tree,
        output_file = tree_plot_file
      )
    }

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Decision tree analysis", step_duration)
  }

  # ----------------------------------------------------------------------------
  # STEP 7: VISUALIZATION
  # ----------------------------------------------------------------------------

  if ("visualize" %in% steps && isTRUE(config$visualizations$enabled) &&
      !is.null(results$evaluation)) {

    step_start <- Sys.time()
    print_section_header("STEP 7: VISUALIZATION")

    # Generate comprehensive visualization report
    cat("\n▶ Generating visualization report...\n")

    results$plots <- create_visualization_report(
      pipeline_results = results,
      config = config
    )

    cat(sprintf("  ✓ Generated %d plots\n", length(results$plots)))

    step_duration <- as.numeric(difftime(Sys.time(), step_start, units = "secs"))
    print_completion("Visualization", step_duration)
  }

  # ----------------------------------------------------------------------------
  # COMPLETION
  # ----------------------------------------------------------------------------

  total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  print_section_header("PIPELINE COMPLETE")

  cat(sprintf("Total runtime: %s\n", format_duration(total_duration)))
  cat(sprintf("Start time: %s\n", format(start_time, "%Y-%m-%d %H:%M:%S")))
  cat(sprintf("End time: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

  # Print and save computational metrics if available
  if (!is.null(results$comp_metrics_summary) && nrow(results$comp_metrics_summary) > 0) {
    cat("\n")
    cat("--------------------------------------------------------------------------------\n")
    cat("                    COMPUTATIONAL METRICS BY MODEL TYPE                        \n")
    cat("--------------------------------------------------------------------------------\n")

    for (i in seq_len(nrow(results$comp_metrics_summary))) {
      row <- results$comp_metrics_summary[i]
      cat(sprintf("\n  %s:\n", toupper(row$model_type)))
      cat(sprintf("    Models trained: %d\n", row$n_models))
      cat(sprintf("    Wall time: %s\n", format_duration(row$wall_time_sec)))
      cat(sprintf("    CPU time: %.2f sec (user: %.2f, system: %.2f)\n",
                  row$cpu_total_sec, row$cpu_user_sec, row$cpu_system_sec))
      cat(sprintf("    Memory: %.1f MB used (peak: %.1f MB)\n",
                  row$memory_delta_mb, row$memory_peak_mb))
    }

    # Save computational metrics to CSV
    comp_metrics_path <- file.path(config$project$output_directory, "computational_metrics.csv")
    fwrite(results$comp_metrics_summary, comp_metrics_path)
    cat(sprintf("\n✓ Computational metrics saved: %s\n", comp_metrics_path))
  }

  # Close logging
  if (config$logging$log_to_file) {
    close_logging(config)
  }

  cat("\n✓ All results saved to:\n")
  cat(sprintf("   %s\n", config$project$output_directory))

  cat("\n")
  cat("================================================================================\n")
  cat("                            SUCCESS!                                           \n")
  cat("================================================================================\n")
  cat("\n")

  results$end_time <- Sys.time()
  results$duration <- total_duration

  invisible(results)
}

# ------------------------------------------------------------------------------
# CONVENIENCE FUNCTIONS
# ------------------------------------------------------------------------------

#' Run only specific metamodel types
#'
#' @param metamodel_types Character vector of metamodel names
#' @param config_file Path to configuration file
run_specific_metamodels <- function(metamodel_types, config_file = "config.yaml") {

  config <- load_config(config_file)

  # Disable all metamodels
  for (mm in names(config$metamodels)) {
    config$metamodels[[mm]]$enabled <- FALSE
  }

  # Enable only requested metamodels
  for (mm in metamodel_types) {
    if (mm %in% names(config$metamodels)) {
      config$metamodels[[mm]]$enabled <- TRUE
    } else {
      warning(sprintf("Unknown metamodel type: %s", mm))
    }
  }

  # Save modified config temporarily
  temp_config <- tempfile(fileext = ".yaml")
  yaml::write_yaml(config, temp_config)

  # Run pipeline with modified config
  results <- run_metamodeling_pipeline(temp_config)

  # Clean up
  unlink(temp_config)

  return(results)
}

#' Quick test run with minimal configuration
#'
#' @param config_file Path to configuration file
test_run <- function(config_file = "config.yaml") {

  cat("\n")
  cat("================================================================================\n")
  cat("                            TEST RUN MODE                                      \n")
  cat("================================================================================\n")
  cat("\n")
  cat("Running with only Linear Regression on first outcome\n\n")

  config <- load_config(config_file)

  # Enable only LR
  config$metamodels$linear_regression$enabled <- TRUE
  config$metamodels$neural_network$enabled <- FALSE
  config$metamodels$random_forest$enabled <- FALSE
  config$metamodels$svr$enabled <- FALSE

  # Use only first outcome
  config$variables$outcomes <- config$variables$outcomes[1]

  # Save temporary config
  temp_config <- tempfile(fileext = ".yaml")
  yaml::write_yaml(config, temp_config)

  # Run
  results <- run_metamodeling_pipeline(temp_config, steps = c("load", "validate", "train"))

  # Clean up
  unlink(temp_config)

  return(results)
}

# ------------------------------------------------------------------------------
# MAIN EXECUTION
# ------------------------------------------------------------------------------

# Uncomment one of these to run automatically:

# Full pipeline
# results <- run_metamodeling_pipeline()

# Test run
# results <- test_run()

# Specific metamodels only
# results <- run_specific_metamodels(c("linear_regression", "neural_network"))

cat("\n")
cat("================================================================================\n")
cat("                      READY TO RUN                                             \n")
cat("================================================================================\n")
cat("\n")
cat("To start, run:\n")
cat("  results <- run_metamodeling_pipeline()\n")
cat("\n")
cat("Or for a quick test:\n")
cat("  results <- test_run()\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
