################################################################################
#                                                                              #
#              METAMODEL COMPUTATIONAL COST BENCHMARKING SCRIPT                #
#                                                                              #
#  Measures computational cost for all 6 metamodel types:                     #
#  - Linear Regression (LR)                                                    #
#  - Neural Network (NN)                                                       #
#  - Random Forest (RF)                                                        #
#  - Support Vector Regression (SVR)                                           #
#  - Quadratic Regression (QR)                                                 #
#  - Cubic Regression (CR)                                                     #
#                                                                              #
#  Metrics tracked:                                                            #
#  - Elapsed time (wall clock)                                                 #
#  - CPU time (user + system)                                                  #
#  - Peak memory usage                                                         #
#  - Memory allocations                                                        #
#                                                                              #
#  USAGE:                                                                      #
#    source("benchmark_metamodels.R")                                         #
#    results <- benchmark_all_metamodels(config_file = "config.yaml")         #
#                                                                              #
################################################################################

cat("\n")
cat("================================================================================\n")
cat("              METAMODEL COMPUTATIONAL COST BENCHMARKING                        \n")
cat("================================================================================\n")
cat("\n")

# ==============================================================================
# SETUP
# ==============================================================================

cat("▶ Loading required libraries...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(bench)      # For accurate benchmarking
  library(pryr)       # For memory profiling
})

# Source all modules
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

cat("✓ Libraries and modules loaded\n\n")

# ==============================================================================
# BENCHMARKING FUNCTIONS
# ==============================================================================

#' Benchmark a single metamodel training function
#'
#' @param train_fn Function to benchmark (e.g., train_lr_all)
#' @param person_datasets Person datasets list
#' @param config Configuration list
#' @param model_name Name of the model for reporting
#' @param ... Additional arguments to pass to train_fn
#'
#' @return List with timing and memory metrics
benchmark_single_metamodel <- function(train_fn, person_datasets, config,
                                      model_name, ...) {

  cat(sprintf("\n>>> Benchmarking %s <<<\n", model_name))

  # Force garbage collection before benchmark
  gc(reset = TRUE)

  # Get initial memory state
  mem_before <- as.numeric(pryr::mem_used())

  # Benchmark with bench::mark (more accurate than system.time)
  bench_result <- bench::mark(
    {
      result <- train_fn(person_datasets, config, ...)
      result
    },
    iterations = 1,
    check = FALSE,
    memory = TRUE
  )

  # Get final memory state
  mem_after <- as.numeric(pryr::mem_used())

  # Extract metrics
  elapsed_time <- as.numeric(bench_result$median)  # seconds
  total_time <- as.numeric(bench_result$total_time)
  mem_alloc <- as.numeric(bench_result$mem_alloc)  # bytes allocated
  n_gc <- bench_result$n_gc  # number of garbage collections

  # Calculate peak memory (approximation)
  peak_mem_mb <- (mem_after - mem_before) / 1024^2
  mem_alloc_mb <- mem_alloc / 1024^2

  # Get CPU info (system.time gives user/system/elapsed)
  cpu_time <- system.time({
    invisible(train_fn(person_datasets, config, ...))
  })

  # Report
  cat(sprintf("  ✓ Elapsed time: %.2f seconds (%.2f minutes)\n",
              elapsed_time, elapsed_time / 60))
  cat(sprintf("  ✓ CPU time: User=%.2fs, System=%.2fs\n",
              cpu_time["user.self"], cpu_time["sys.self"]))
  cat(sprintf("  ✓ Memory allocated: %.2f MB\n", mem_alloc_mb))
  cat(sprintf("  ✓ Peak memory delta: %.2f MB\n", peak_mem_mb))
  cat(sprintf("  ✓ Garbage collections: %d\n", n_gc))

  return(list(
    model = model_name,
    elapsed_seconds = elapsed_time,
    elapsed_minutes = elapsed_time / 60,
    cpu_user_seconds = cpu_time["user.self"],
    cpu_system_seconds = cpu_time["sys.self"],
    cpu_total_seconds = cpu_time["user.self"] + cpu_time["sys.self"],
    memory_allocated_mb = mem_alloc_mb,
    peak_memory_delta_mb = peak_mem_mb,
    n_garbage_collections = n_gc,
    timestamp = Sys.time()
  ))
}


#' Benchmark all metamodels
#'
#' @param config_file Path to configuration file
#' @param tune_hyperparameters Logical; enable hyperparameter tuning for all?
#' @param save_results Logical; save benchmark results to CSV?
#'
#' @return data.table with benchmark results for all metamodels
benchmark_all_metamodels <- function(config_file = "config.yaml",
                                    tune_hyperparameters = FALSE,
                                    save_results = TRUE) {

  start_time <- Sys.time()

  cat("\n")
  cat("================================================================================\n")
  cat("                    BENCHMARK CONFIGURATION                                    \n")
  cat("================================================================================\n")
  cat(sprintf("Config file: %s\n", config_file))
  cat(sprintf("Hyperparameter tuning: %s\n", ifelse(tune_hyperparameters, "ENABLED", "DISABLED")))
  cat(sprintf("Started at: %s\n", format(start_time, "%Y-%m-%d %H:%M:%S")))
  cat("\n")

  # Load configuration
  config <- load_config(config_file)

  # Override tuning settings if specified
  if (!tune_hyperparameters) {
    config$metamodels$neural_network$tune_hyperparameters <- FALSE
    config$metamodels$random_forest$tune_hyperparameters <- FALSE
    config$metamodels$support_vector_regression$tune_hyperparameters <- FALSE
  }

  # Load and prepare data
  cat("================================================================================\n")
  cat("                         STEP 1: DATA LOADING                                  \n")
  cat("================================================================================\n")

  data_raw <- load_and_prepare_data(config)

  cat("\n")
  cat("================================================================================\n")
  cat("                    STEP 2: DATA PREPROCESSING                                 \n")
  cat("================================================================================\n")

  # Prepare person-specific datasets
  person_datasets <- list()

  for (group_name in names(data_raw)) {
    cat(sprintf("\n--- Processing group: %s ---\n", group_name))

    group_data <- data_raw[[group_name]]$data

    # Prepare for each outcome
    for (outcome in config$variables$outcomes) {
      cat(sprintf("Outcome: %s\n", outcome))

      # Prepare all persons
      person_ds <- prepare_all_persons(group_data, config, outcome)

      # Store
      key <- paste(group_name, outcome, sep = "_")
      person_datasets[[key]] <- list(
        group = group_name,
        outcome = outcome,
        person_datasets = person_ds
      )
    }
  }

  cat(sprintf("\n✓ Prepared %d group-outcome combinations\n", length(person_datasets)))

  # Initialize results list
  benchmark_results <- list()

  # ==============================================================================
  # BENCHMARK EACH METAMODEL
  # ==============================================================================

  cat("\n")
  cat("================================================================================\n")
  cat("                    STEP 3: BENCHMARKING METAMODELS                            \n")
  cat("================================================================================\n")

  # 1. Linear Regression
  benchmark_results[["linear_regression"]] <- benchmark_single_metamodel(
    train_fn = train_lr_all,
    person_datasets = person_datasets,
    config = config,
    model_name = "Linear Regression (LR)"
  )

  # 2. Quadratic Regression
  benchmark_results[["quadratic_regression"]] <- benchmark_single_metamodel(
    train_fn = train_qr_all,
    person_datasets = person_datasets,
    config = config,
    model_name = "Quadratic Regression (QR)"
  )

  # 3. Cubic Regression
  benchmark_results[["cubic_regression"]] <- benchmark_single_metamodel(
    train_fn = train_cr_all,
    person_datasets = person_datasets,
    config = config,
    model_name = "Cubic Regression (CR)"
  )

  # 4. Neural Network
  benchmark_results[["neural_network"]] <- benchmark_single_metamodel(
    train_fn = train_nn_all,
    person_datasets = person_datasets,
    config = config,
    model_name = "Neural Network (NN)"
  )

  # 5. Random Forest
  # Note: RF accepts optional population_weights argument
  population_weights <- NULL
  if (config$modeling$use_population_weights) {
    population_weights <- load_population_weights(config)
  }

  benchmark_results[["random_forest"]] <- benchmark_single_metamodel(
    train_fn = train_rf_all,
    person_datasets = person_datasets,
    config = config,
    model_name = "Random Forest (RF)",
    population_weights = population_weights
  )

  # 6. Support Vector Regression
  benchmark_results[["support_vector_regression"]] <- benchmark_single_metamodel(
    train_fn = train_svr_all,
    person_datasets = person_datasets,
    config = config,
    model_name = "Support Vector Regression (SVR)"
  )

  # ==============================================================================
  # AGGREGATE RESULTS
  # ==============================================================================

  cat("\n")
  cat("================================================================================\n")
  cat("                         BENCHMARK SUMMARY                                     \n")
  cat("================================================================================\n")

  # Convert to data.table
  results_dt <- rbindlist(benchmark_results, fill = TRUE)

  # Add relative metrics (compared to fastest)
  min_time <- min(results_dt$elapsed_seconds)
  results_dt[, relative_speed := elapsed_seconds / min_time]
  results_dt[, speedup := min_time / elapsed_seconds]

  # Rank by elapsed time
  results_dt[, rank_time := rank(elapsed_seconds)]
  results_dt[, rank_memory := rank(memory_allocated_mb)]

  # Order by elapsed time
  setorder(results_dt, elapsed_seconds)

  # Print summary table
  cat("\n")
  cat("Ranked by Elapsed Time:\n")
  cat("================================================================================\n")
  print(results_dt[, .(
    Rank = rank_time,
    Model = model,
    `Time (min)` = round(elapsed_minutes, 2),
    `CPU (s)` = round(cpu_total_seconds, 2),
    `Memory (MB)` = round(memory_allocated_mb, 1),
    `Rel. Speed` = round(relative_speed, 2),
    `GC Count` = n_garbage_collections
  )])

  cat("\n")
  cat("Ranked by Memory Usage:\n")
  cat("================================================================================\n")
  results_dt_mem <- copy(results_dt)
  setorder(results_dt_mem, memory_allocated_mb)
  print(results_dt_mem[, .(
    Rank = rank_memory,
    Model = model,
    `Memory (MB)` = round(memory_allocated_mb, 1),
    `Peak Δ (MB)` = round(peak_memory_delta_mb, 1),
    `Time (min)` = round(elapsed_minutes, 2)
  )])

  # ==============================================================================
  # SAVE RESULTS
  # ==============================================================================

  if (save_results) {
    output_dir <- config$project$output_directory
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }

    # Save detailed results
    output_file <- file.path(output_dir, "benchmark_results.csv")
    fwrite(results_dt, output_file)
    cat(sprintf("\n✓ Benchmark results saved to: %s\n", output_file))

    # Create summary report
    report_file <- file.path(output_dir, "benchmark_report.txt")
    sink(report_file)

    cat("================================================================================\n")
    cat("         METAMODEL COMPUTATIONAL COST BENCHMARK REPORT                         \n")
    cat("================================================================================\n")
    cat(sprintf("Date: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    cat(sprintf("Config: %s\n", config_file))
    cat(sprintf("Hyperparameter tuning: %s\n",
                ifelse(tune_hyperparameters, "ENABLED", "DISABLED")))
    cat("\n")

    cat("DATA SUMMARY\n")
    cat("--------------------------------------------------------------------------------\n")
    cat(sprintf("Number of group-outcome combinations: %d\n", length(person_datasets)))
    cat(sprintf("Predictors: %s\n", paste(config$variables$predictors, collapse = ", ")))
    cat(sprintf("Outcomes: %s\n", paste(config$variables$outcomes, collapse = ", ")))
    cat("\n")

    cat("METAMODELS BENCHMARKED\n")
    cat("--------------------------------------------------------------------------------\n")
    for (i in 1:nrow(results_dt)) {
      cat(sprintf("%d. %s\n", i, results_dt$model[i]))
      cat(sprintf("   Elapsed: %.2f min | CPU: %.2f s | Memory: %.1f MB\n",
                  results_dt$elapsed_minutes[i],
                  results_dt$cpu_total_seconds[i],
                  results_dt$memory_allocated_mb[i]))
    }
    cat("\n")

    cat("KEY FINDINGS\n")
    cat("--------------------------------------------------------------------------------\n")
    fastest <- results_dt[1]
    slowest <- results_dt[.N]
    most_memory <- results_dt_mem[.N]
    least_memory <- results_dt_mem[1]

    cat(sprintf("⚡ Fastest: %s (%.2f minutes)\n", fastest$model, fastest$elapsed_minutes))
    cat(sprintf("🐌 Slowest: %s (%.2f minutes, %.1fx slower)\n",
                slowest$model, slowest$elapsed_minutes, slowest$relative_speed))
    cat(sprintf("💾 Least memory: %s (%.1f MB)\n",
                least_memory$model, least_memory$memory_allocated_mb))
    cat(sprintf("🧠 Most memory: %s (%.1f MB)\n",
                most_memory$model, most_memory$memory_allocated_mb))
    cat("\n")

    cat("RECOMMENDATIONS\n")
    cat("--------------------------------------------------------------------------------\n")
    cat("For quick prototyping: Use ", fastest$model, "\n", sep = "")
    cat("For production (balanced): Consider top 3 fastest with good accuracy\n")
    cat("For limited memory: Use ", least_memory$model, "\n", sep = "")
    cat("\n")

    cat("FULL RESULTS TABLE\n")
    cat("--------------------------------------------------------------------------------\n")
    print(results_dt)

    sink()

    cat(sprintf("✓ Benchmark report saved to: %s\n", report_file))
  }

  # ==============================================================================
  # COMPLETION
  # ==============================================================================

  end_time <- Sys.time()
  total_duration <- as.numeric(difftime(end_time, start_time, units = "mins"))

  cat("\n")
  cat("================================================================================\n")
  cat("                     BENCHMARKING COMPLETE                                     \n")
  cat("================================================================================\n")
  cat(sprintf("Total benchmarking time: %.2f minutes\n", total_duration))
  cat(sprintf("Start: %s\n", format(start_time, "%H:%M:%S")))
  cat(sprintf("End: %s\n", format(end_time, "%H:%M:%S")))
  cat("\n")

  return(results_dt)
}


#' Quick benchmark with example data
#'
#' @param example Which example to use ("simple" or "healthcare")
#' @return Benchmark results data.table
benchmark_quick <- function(example = "simple") {

  config_file <- switch(example,
    "simple" = "examples/simple/config_simple.yaml",
    "healthcare" = "examples/healthcare/config_healthcare.yaml",
    "examples/simple/config_simple.yaml"
  )

  cat(sprintf("Running quick benchmark with %s example...\n", example))
  cat("(Hyperparameter tuning disabled for speed)\n\n")

  results <- benchmark_all_metamodels(
    config_file = config_file,
    tune_hyperparameters = FALSE,
    save_results = TRUE
  )

  return(results)
}


#' Benchmark with hyperparameter tuning enabled
#'
#' @param config_file Path to configuration file
#' @return Benchmark results data.table
benchmark_with_tuning <- function(config_file = "config.yaml") {

  cat("Running benchmark with HYPERPARAMETER TUNING enabled...\n")
  cat("⚠ This will take significantly longer!\n\n")

  results <- benchmark_all_metamodels(
    config_file = config_file,
    tune_hyperparameters = TRUE,
    save_results = TRUE
  )

  return(results)
}


# ==============================================================================
# USAGE EXAMPLES
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("                            READY TO BENCHMARK                                  \n")
cat("================================================================================\n")
cat("\n")
cat("Usage examples:\n")
cat("\n")
cat("1. Quick benchmark with simple example:\n")
cat("   results <- benchmark_quick('simple')\n")
cat("\n")
cat("2. Quick benchmark with healthcare example:\n")
cat("   results <- benchmark_quick('healthcare')\n")
cat("\n")
cat("3. Benchmark your own data (no tuning):\n")
cat("   results <- benchmark_all_metamodels('config.yaml', tune_hyperparameters = FALSE)\n")
cat("\n")
cat("4. Full benchmark with hyperparameter tuning (slow!):\n")
cat("   results <- benchmark_with_tuning('config.yaml')\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
