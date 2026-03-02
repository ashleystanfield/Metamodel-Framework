################################################################################
#                                                                              #
#           FULL PRODUCTION BENCHMARK - ALL METAMODELS ON FULL DATASET        #
#                                                                              #
#  This script runs complete benchmarking on your FULL dataset with:          #
#  - Real-time progress tracking                                               #
#  - Time remaining estimates                                                  #
#  - Incremental result saving (won't lose progress if interrupted)            #
#  - Per-metamodel-type detailed metrics                                       #
#  - Memory profiling throughout training                                      #
#                                                                              #
#  Expected runtime: Several days for full dataset                             #
#  Use smart_benchmark first to get time estimates!                            #
#                                                                              #
################################################################################

cat("\n")
cat("================================================================================\n")
cat("    FULL PRODUCTION BENCHMARK - ALL METAMODELS ON COMPLETE DATASET            \n")
cat("================================================================================\n")
cat("\n")

# ==============================================================================
# SETUP
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(progress)
  library(pryr)
})

source("R/00_config_loader.R")
source("R/utils.R")
source("R/01_data_loader.R")
source("R/02_preprocessing.R")
source("R/03_metamodel_lr.R")
source("R/04_metamodel_nn.R")
source("R/05_metamodel_rf.R")
source("R/09_metamodel_svr.R")
source("R/10_metamodel_qr.R")
source("R/11_metamodel_cr.R")

# ==============================================================================
# ENHANCED TRAINING WRAPPER WITH PROGRESS TRACKING
# ==============================================================================

#' Train with detailed progress and timing
#'
#' Wraps the standard train_*_all_persons() functions with progress bars
#' and per-person timing metrics
train_with_progress <- function(person_datasets, outcome, config,
                               train_fn, model_name) {

  n_persons <- length(person_datasets)

  cat(sprintf("\n>>> Training %s for outcome: %s <<<\n", model_name, outcome))
  cat(sprintf("    Training %d person-specific models\n", n_persons))

  # Initialize progress bar
  pb <- progress_bar$new(
    format = "  [:bar] :percent | :current/:total | Elapsed: :elapsed | ETA: :eta",
    total = n_persons,
    clear = FALSE,
    width = 80
  )

  # Storage for per-person metrics
  person_timings <- numeric(n_persons)
  person_cpu_user <- numeric(n_persons)
  person_cpu_system <- numeric(n_persons)
  person_memory <- numeric(n_persons)

  # Train each person with timing
  models <- list()
  n_fallback <- 0

  overall_start <- Sys.time()

  for (i in seq_along(person_datasets)) {
    person_data <- person_datasets[[i]]
    person_id <- person_data$person_id

    # Time this person (both elapsed and CPU)
    gc(reset = TRUE)
    mem_before <- as.numeric(pryr::mem_used())

    # Use system.time() to capture CPU time
    timing <- system.time({
      # Train (different function signatures for different models)
      if (model_name == "Linear Regression") {
        model <- train_lr_person(person_data, outcome, config)
      } else if (model_name == "Quadratic Regression") {
        model <- train_qr_person(person_data, outcome, config)
      } else if (model_name == "Cubic Regression") {
        model <- train_cr_person(person_data, outcome, config)
      } else if (model_name == "Neural Network") {
        model <- train_nn_person(person_data, outcome, config,
                                tune_hyperparameters = config$metamodels$neural_network$tune_hyperparameters)
      } else if (model_name == "Random Forest") {
        model <- train_rf_person(person_data, outcome, config,
                                tune_hyperparameters = config$metamodels$random_forest$tune_hyperparameters)
      } else if (model_name == "SVR") {
        model <- train_svr_person(person_data, outcome, config,
                                 tune_hyperparameters = config$metamodels$support_vector_regression$tune_hyperparameters)
      }
    })

    # Extract timing metrics
    person_elapsed <- timing["elapsed"]
    person_cpu_usr <- timing["user.self"]
    person_cpu_sys <- timing["sys.self"]

    mem_after <- as.numeric(pryr::mem_used())
    person_mem <- (mem_after - mem_before) / 1024^2  # MB

    # Store
    models[[as.character(person_id)]] <- model
    person_timings[i] <- person_elapsed
    person_cpu_user[i] <- person_cpu_usr
    person_cpu_system[i] <- person_cpu_sys
    person_memory[i] <- person_mem

    if (model$is_fallback) {
      n_fallback <- n_fallback + 1
    }

    # Update progress bar
    pb$tick()

    # Every 10 models, print statistics
    if (i %% 10 == 0) {
      avg_time <- mean(person_timings[1:i])
      remaining <- n_persons - i
      eta_sec <- remaining * avg_time
      eta_min <- eta_sec / 60

      cat(sprintf("\n    [Stats] Avg: %.2fs/model | Remaining: ~%.1f min | Fallback: %d/%d\n",
                  avg_time, eta_min, n_fallback, i))
    }
  }

  overall_elapsed <- as.numeric(difftime(Sys.time(), overall_start, units = "secs"))
  total_cpu_user <- sum(person_cpu_user)
  total_cpu_system <- sum(person_cpu_system)
  total_cpu <- total_cpu_user + total_cpu_system

  # Calculate timing variability
  sd_time <- sd(person_timings)
  cv_time <- sd_time / mean(person_timings)  # Coefficient of variation

  cat(sprintf("\n  ✓ Complete: %d models in %.2f min (%.2f sec/model)\n",
              n_persons, overall_elapsed/60, overall_elapsed/n_persons))
  cat(sprintf("  ✓ CPU time: User=%.2f min, System=%.2f min, Total=%.2f min\n",
              total_cpu_user/60, total_cpu_system/60, total_cpu/60))
  cat(sprintf("  ✓ CPU efficiency: %.1f%% (CPU/Elapsed)\n",
              100 * total_cpu / overall_elapsed))
  cat(sprintf("  ✓ Timing variability: SD=%.2fs, CV=%.1f%%\n",
              sd_time, cv_time * 100))
  cat(sprintf("  ✓ Fallback models: %d (%.1f%%)\n",
              n_fallback, 100*n_fallback/n_persons))
  cat(sprintf("  ✓ Avg memory per model: %.2f MB\n", mean(person_memory)))

  return(list(
    models = models,
    outcome = outcome,
    n_persons = n_persons,
    n_fallback = n_fallback,
    person_timings = person_timings,
    person_cpu_user = person_cpu_user,
    person_cpu_system = person_cpu_system,
    person_memory = person_memory,
    total_time_sec = overall_elapsed,
    total_cpu_user_sec = total_cpu_user,
    total_cpu_system_sec = total_cpu_system,
    total_cpu_sec = total_cpu,
    avg_time_per_model = overall_elapsed / n_persons,
    avg_cpu_per_model = total_cpu / n_persons,
    avg_memory_per_model = mean(person_memory),
    cpu_efficiency = 100 * total_cpu / overall_elapsed,
    sd_time = sd_time,
    cv_time = cv_time
  ))
}


#' Train all persons/outcomes for one metamodel type with full tracking
train_metamodel_type_full <- function(person_datasets_list, config,
                                     train_fn, model_name, model_key) {

  cat("\n")
  cat("================================================================================\n")
  cat(sprintf("                  TRAINING: %s", toupper(model_name)))
  cat("\n================================================================================\n")

  start_time <- Sys.time()

  # Count total models
  total_models <- 0
  for (entry in person_datasets_list) {
    total_models <- total_models + length(entry$person_datasets)
  }

  cat(sprintf("\nTotal models to train: %d\n", total_models))
  cat(sprintf("Groups-Outcomes combinations: %d\n", length(person_datasets_list)))

  # Train for each group-outcome combination
  results_list <- list()
  all_timings <- numeric()
  all_cpu_user <- numeric()
  all_cpu_system <- numeric()
  all_memory <- numeric()

  for (i in seq_along(person_datasets_list)) {
    entry <- person_datasets_list[[i]]
    key <- names(person_datasets_list)[i]

    cat(sprintf("\n--- Combination %d/%d: %s ---\n",
                i, length(person_datasets_list), key))

    result <- train_with_progress(
      entry$person_datasets,
      entry$outcome,
      config,
      train_fn,
      model_name
    )

    result$group <- entry$group
    results_list[[key]] <- result

    all_timings <- c(all_timings, result$person_timings)
    all_cpu_user <- c(all_cpu_user, result$person_cpu_user)
    all_cpu_system <- c(all_cpu_system, result$person_cpu_system)
    all_memory <- c(all_memory, result$person_memory)

    # Save intermediate results
    saveRDS(results_list, file.path(config$project$output_directory,
                                    sprintf("benchmark_%s_intermediate.rds", model_key)))
  }

  end_time <- Sys.time()
  total_elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

  total_cpu_user <- sum(all_cpu_user)
  total_cpu_system <- sum(all_cpu_system)
  total_cpu <- total_cpu_user + total_cpu_system

  # Timing variability
  sd_time <- sd(all_timings)
  cv_time <- sd_time / mean(all_timings)

  # Hyperparameter tuning overhead estimate
  tuning_enabled <- FALSE
  tuning_overhead_pct <- 0
  if (model_key == "nn" && config$metamodels$neural_network$tune_hyperparameters) {
    tuning_enabled <- TRUE
    tuning_overhead_pct <- 400  # NN tuning adds ~4-5x overhead
  } else if (model_key == "rf" && config$metamodels$random_forest$tune_hyperparameters) {
    tuning_enabled <- TRUE
    tuning_overhead_pct <- 300  # RF tuning adds ~3-4x overhead
  } else if (model_key == "svr" && config$metamodels$support_vector_regression$tune_hyperparameters) {
    tuning_enabled <- TRUE
    tuning_overhead_pct <- 500  # SVR tuning adds ~5-6x overhead
  }

  time_without_tuning_est <- ifelse(tuning_enabled,
                                     total_elapsed / (1 + tuning_overhead_pct/100),
                                     total_elapsed)
  tuning_time_est <- total_elapsed - time_without_tuning_est

  # Parallel speedup estimate
  n_cores <- parallel::detectCores(logical = FALSE)  # Physical cores
  theoretical_speedup <- min(n_cores, total_models)
  parallel_time_est_hours <- total_elapsed / theoretical_speedup / 3600
  parallel_time_est_days <- parallel_time_est_hours / 24

  # Model file sizes (if models were saved)
  total_model_size_mb <- 0
  avg_model_size_mb <- 0
  if (config$modeling$save_models) {
    model_dir <- file.path(config$project$output_directory, "models", model_key)
    if (dir.exists(model_dir)) {
      model_files <- list.files(model_dir, pattern = "\\.rds$", full.names = TRUE)
      if (length(model_files) > 0) {
        file_sizes <- file.size(model_files) / 1024^2  # MB
        total_model_size_mb <- sum(file_sizes)
        avg_model_size_mb <- mean(file_sizes)
      }
    }
  }

  # Prediction time benchmark (sample)
  prediction_time_ms <- NA
  if (length(results_list) > 0) {
    cat("\n▶ Benchmarking prediction time...\n")

    # Get first model result
    first_result <- results_list[[1]]
    if (!is.null(first_result$models) && length(first_result$models) > 0) {
      first_model <- first_result$models[[1]]

      if (!first_model$is_fallback) {
        # Create sample prediction data (100 scenarios)
        n_pred_samples <- 100
        predictors <- first_model$predictors_used

        sample_data <- data.table(person_id = 1)
        for (pred in predictors) {
          sample_data[, (pred) := runif(n_pred_samples, 0, 100)]
        }

        # Time predictions
        pred_timing <- system.time({
          if (model_key == "lr") {
            preds <- predict(first_model$model, newdata = sample_data)
          } else if (model_key == "qr") {
            expanded <- apply_quadratic_expansion(sample_data, first_model$expansion_spec)
            preds <- predict(first_model$model, newdata = expanded)
          } else if (model_key == "cr") {
            expanded <- apply_cubic_expansion(sample_data, first_model$expansion_spec)
            preds <- predict(first_model$model, newdata = expanded)
          } else if (model_key == "nn") {
            std_data <- standardize_predictors_new(sample_data,
                                                   first_model$standardization$means,
                                                   first_model$standardization$sds,
                                                   predictors)
            preds <- predict(first_model$model, newdata = std_data)
          } else if (model_key == "rf") {
            preds <- predict(first_model$model, newdata = sample_data)
          } else if (model_key == "svr") {
            std_data <- standardize_predictors_new(sample_data,
                                                   first_model$standardization$means,
                                                   first_model$standardization$sds,
                                                   predictors)
            preds <- predict(first_model$model, newdata = std_data)
          }
        })

        prediction_time_ms <- (pred_timing["elapsed"] / n_pred_samples) * 1000
        cat(sprintf("  ✓ Prediction time: %.2f ms per scenario\n", prediction_time_ms))
      }
    }
  }

  # Summary statistics
  cat("\n")
  cat("================================================================================\n")
  cat(sprintf("              %s - COMPLETE SUMMARY", toupper(model_name)))
  cat("\n================================================================================\n")
  cat(sprintf("Total models trained: %d\n", total_models))
  cat(sprintf("Total elapsed time: %.2f hours (%.2f days)\n",
              total_elapsed/3600, total_elapsed/86400))
  cat(sprintf("Total CPU time: %.2f hours (User: %.2f, System: %.2f)\n",
              total_cpu/3600, total_cpu_user/3600, total_cpu_system/3600))
  cat(sprintf("CPU efficiency: %.1f%% (CPU/Elapsed)\n",
              100 * total_cpu / total_elapsed))
  cat(sprintf("Average time per model: %.2f seconds (CPU: %.2f sec)\n",
              mean(all_timings), mean(all_cpu_user + all_cpu_system)))
  cat(sprintf("Median time per model: %.2f seconds\n", median(all_timings)))
  cat(sprintf("Min/Max time: %.2f / %.2f seconds\n", min(all_timings), max(all_timings)))
  cat(sprintf("Timing variability: SD=%.2fs, CV=%.1f%%\n", sd_time, cv_time * 100))

  if (tuning_enabled) {
    cat(sprintf("Hyperparameter tuning: ENABLED (est. %.1f%% overhead)\n", tuning_overhead_pct))
    cat(sprintf("  Estimated time without tuning: %.2f hours\n", time_without_tuning_est/3600))
    cat(sprintf("  Estimated tuning time: %.2f hours\n", tuning_time_est/3600))
  } else {
    cat("Hyperparameter tuning: DISABLED\n")
  }

  cat(sprintf("Average memory per model: %.2f MB\n", mean(all_memory)))
  cat(sprintf("Total memory footprint estimate: %.2f GB\n", sum(all_memory)/1024))

  if (total_model_size_mb > 0) {
    cat(sprintf("Model storage: %.2f MB total (%.3f MB per model)\n",
                total_model_size_mb, avg_model_size_mb))
  }

  if (!is.na(prediction_time_ms)) {
    cat(sprintf("Prediction time: %.2f ms per scenario\n", prediction_time_ms))
  }

  cat(sprintf("\nParallelization potential (%d cores available):\n", n_cores))
  cat(sprintf("  Theoretical speedup: %.1fx\n", theoretical_speedup))
  cat(sprintf("  Estimated parallel time: %.2f hours (%.2f days)\n",
              parallel_time_est_hours, parallel_time_est_days))
  cat("\n")

  return(list(
    results = results_list,
    model_name = model_name,
    total_models = total_models,
    total_time_sec = total_elapsed,
    total_time_hours = total_elapsed / 3600,
    total_time_days = total_elapsed / 86400,
    total_cpu_sec = total_cpu,
    total_cpu_user_sec = total_cpu_user,
    total_cpu_system_sec = total_cpu_system,
    total_cpu_hours = total_cpu / 3600,
    cpu_efficiency = 100 * total_cpu / total_elapsed,
    avg_time_per_model = mean(all_timings),
    avg_cpu_per_model = mean(all_cpu_user + all_cpu_system),
    median_time_per_model = median(all_timings),
    min_time_per_model = min(all_timings),
    max_time_per_model = max(all_timings),
    sd_time = sd_time,
    cv_time = cv_time,
    avg_memory_per_model = mean(all_memory),
    total_memory_gb = sum(all_memory) / 1024,
    tuning_enabled = tuning_enabled,
    tuning_overhead_pct = tuning_overhead_pct,
    time_without_tuning_hours = time_without_tuning_est / 3600,
    tuning_time_hours = tuning_time_est / 3600,
    total_model_size_mb = total_model_size_mb,
    avg_model_size_mb = avg_model_size_mb,
    prediction_time_ms = prediction_time_ms,
    n_cores_available = n_cores,
    theoretical_speedup = theoretical_speedup,
    parallel_time_est_days = parallel_time_est_days,
    all_timings = all_timings,
    all_cpu_user = all_cpu_user,
    all_cpu_system = all_cpu_system,
    all_memory = all_memory
  ))
}


# ==============================================================================
# MAIN BENCHMARK FUNCTION
# ==============================================================================

#' Full production benchmark on complete dataset
#'
#' @param config_file Path to configuration file
#' @param metamodel_types Character vector of metamodel types to benchmark
#'        Options: "lr", "qr", "cr", "nn", "rf", "svr"
#'        Default: all 6 types
#' @param save_results Save detailed results?
#'
#' @return List with comprehensive benchmark results
benchmark_full_production <- function(config_file = "config.yaml",
                                     metamodel_types = c("lr", "qr", "cr", "nn", "rf", "svr"),
                                     save_results = TRUE) {

  overall_start <- Sys.time()

  cat("\n")
  cat("================================================================================\n")
  cat("                    FULL PRODUCTION BENCHMARK                                  \n")
  cat("================================================================================\n")
  cat(sprintf("Started: %s\n", format(overall_start, "%Y-%m-%d %H:%M:%S")))
  cat(sprintf("Config: %s\n", config_file))
  cat(sprintf("Metamodel types: %s\n", paste(metamodel_types, collapse = ", ")))
  cat("\n")
  cat("⚠️  WARNING: This will take DAYS to complete on full dataset!\n")
  cat("    - Results are saved incrementally\n")
  cat("    - You can stop/resume by re-running\n")
  cat("    - Check *_intermediate.rds files for progress\n")
  cat("\n")

  # Load config
  config <- load_config(config_file)

  # Setup output directory
  output_dir <- config$project$output_directory
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  # Load and prepare data
  cat("================================================================================\n")
  cat("                         LOADING DATA                                          \n")
  cat("================================================================================\n")

  data_raw <- load_and_prepare_data(config)

  # Prepare person datasets
  cat("\n")
  cat("================================================================================\n")
  cat("                    PREPARING PERSON DATASETS                                  \n")
  cat("================================================================================\n")

  person_datasets_list <- list()

  for (group_name in names(data_raw)) {
    cat(sprintf("\nProcessing group: %s\n", group_name))
    group_data <- data_raw[[group_name]]$data

    for (outcome in config$variables$outcomes) {
      person_ds <- prepare_all_persons(group_data, config, outcome)
      key <- paste(group_name, outcome, sep = "_")
      person_datasets_list[[key]] <- list(
        group = group_name,
        outcome = outcome,
        person_datasets = person_ds
      )
    }
  }

  cat(sprintf("\n✓ Prepared %d group-outcome combinations\n", length(person_datasets_list)))

  # Calculate total models
  total_models_per_type <- 0
  for (entry in person_datasets_list) {
    total_models_per_type <- total_models_per_type + length(entry$person_datasets)
  }

  cat(sprintf("✓ Total models per metamodel type: %d\n", total_models_per_type))
  cat(sprintf("✓ Total models across all types: %d\n",
              total_models_per_type * length(metamodel_types)))

  # Benchmark each metamodel type
  benchmark_results <- list()

  if ("lr" %in% metamodel_types) {
    benchmark_results[["lr"]] <- train_metamodel_type_full(
      person_datasets_list, config, train_lr_person, "Linear Regression", "lr"
    )
  }

  if ("qr" %in% metamodel_types) {
    benchmark_results[["qr"]] <- train_metamodel_type_full(
      person_datasets_list, config, train_qr_person, "Quadratic Regression", "qr"
    )
  }

  if ("cr" %in% metamodel_types) {
    benchmark_results[["cr"]] <- train_metamodel_type_full(
      person_datasets_list, config, train_cr_person, "Cubic Regression", "cr"
    )
  }

  if ("nn" %in% metamodel_types) {
    benchmark_results[["nn"]] <- train_metamodel_type_full(
      person_datasets_list, config, train_nn_person, "Neural Network", "nn"
    )
  }

  if ("rf" %in% metamodel_types) {
    benchmark_results[["rf"]] <- train_metamodel_type_full(
      person_datasets_list, config, train_rf_person, "Random Forest", "rf"
    )
  }

  if ("svr" %in% metamodel_types) {
    benchmark_results[["svr"]] <- train_metamodel_type_full(
      person_datasets_list, config, train_svr_person, "SVR", "svr"
    )
  }

  # ==============================================================================
  # FINAL SUMMARY
  # ==============================================================================

  overall_end <- Sys.time()
  total_duration <- as.numeric(difftime(overall_end, overall_start, units = "secs"))

  cat("\n")
  cat("================================================================================\n")
  cat("                    COMPLETE BENCHMARK SUMMARY                                 \n")
  cat("================================================================================\n")
  cat("\n")

  # Create summary table
  summary_rows <- list()
  for (type in names(benchmark_results)) {
    result <- benchmark_results[[type]]
    summary_rows[[type]] <- data.table(
      metamodel = result$model_name,
      total_models = result$total_models,
      total_time_hours = result$total_time_hours,
      total_time_days = result$total_time_days,
      total_cpu_hours = result$total_cpu_hours,
      cpu_efficiency_pct = result$cpu_efficiency,
      avg_time_per_model_sec = result$avg_time_per_model,
      avg_cpu_per_model_sec = result$avg_cpu_per_model,
      median_time_per_model_sec = result$median_time_per_model,
      avg_memory_per_model_mb = result$avg_memory_per_model,
      total_memory_gb = result$total_memory_gb
    )
  }

  summary_dt <- rbindlist(summary_rows)
  setorder(summary_dt, total_time_days)

  print(summary_dt)

  cat("\n")
  cat(sprintf("🏁 BENCHMARK COMPLETE\n"))
  cat(sprintf("   Started: %s\n", format(overall_start, "%Y-%m-%d %H:%M:%S")))
  cat(sprintf("   Ended: %s\n", format(overall_end, "%Y-%m-%d %H:%M:%S")))
  cat(sprintf("   Total duration: %.2f days (%.1f hours)\n",
              total_duration/86400, total_duration/3600))
  cat("\n")

  # Save final results
  if (save_results) {
    results_file <- file.path(output_dir, "benchmark_full_production_results.rds")
    saveRDS(benchmark_results, results_file)
    cat(sprintf("✓ Full results saved to: %s\n", results_file))

    summary_file <- file.path(output_dir, "benchmark_full_production_summary.csv")
    fwrite(summary_dt, summary_file)
    cat(sprintf("✓ Summary saved to: %s\n", summary_file))
  }

  return(list(
    detailed_results = benchmark_results,
    summary = summary_dt,
    total_duration_days = total_duration / 86400
  ))
}


# ==============================================================================
# CONVENIENCE FUNCTIONS
# ==============================================================================

#' Benchmark just the fast models (LR, QR, CR)
benchmark_fast_models <- function(config_file = "config.yaml") {
  cat("Benchmarking fast models only: LR, QR, CR\n")
  cat("(This should complete in hours, not days)\n\n")

  benchmark_full_production(config_file, metamodel_types = c("lr", "qr", "cr"))
}

#' Benchmark just the slow models (NN, RF, SVR)
benchmark_slow_models <- function(config_file = "config.yaml") {
  cat("Benchmarking slow models only: NN, RF, SVR\n")
  cat("⚠️  WARNING: This will take DAYS!\n\n")

  benchmark_full_production(config_file, metamodel_types = c("nn", "rf", "svr"))
}


# ==============================================================================
# USAGE
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("                            READY TO BENCHMARK                                  \n")
cat("================================================================================\n")
cat("\n")
cat("⚠️  IMPORTANT: Run smart_benchmark FIRST to get time estimates!\n")
cat("\n")
cat("Usage:\n")
cat("\n")
cat("# Full benchmark (all 6 types) - TAKES DAYS!\n")
cat("results <- benchmark_full_production('config.yaml')\n")
cat("\n")
cat("# Fast models only (LR, QR, CR) - Takes hours\n")
cat("results <- benchmark_fast_models('config.yaml')\n")
cat("\n")
cat("# Slow models only (NN, RF, SVR) - Takes days\n")
cat("results <- benchmark_slow_models('config.yaml')\n")
cat("\n")
cat("# Specific types only\n")
cat("results <- benchmark_full_production('config.yaml', \n")
cat("                                     metamodel_types = c('lr', 'nn'))\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
