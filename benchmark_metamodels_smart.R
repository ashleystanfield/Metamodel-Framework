################################################################################
#                                                                              #
#              SMART METAMODEL BENCHMARKING - STRATIFIED SAMPLING              #
#                                                                              #
#  This script benchmarks on a SUBSET and extrapolates to full dataset.       #
#  Use this for realistic time/cost estimates without waiting days.           #
#                                                                              #
#  Strategy:                                                                   #
#  1. Sample N persons, M outcomes, K groups                                   #
#  2. Train all 6 metamodel types on this subset                              #
#  3. Measure per-model computational cost                                     #
#  4. Extrapolate to your full dataset size                                    #
#                                                                              #
################################################################################

cat("\n")
cat("================================================================================\n")
cat("       SMART METAMODEL BENCHMARKING (Stratified Sampling)                     \n")
cat("================================================================================\n")
cat("\n")

# ==============================================================================
# SETUP
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(bench)
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
# SMART BENCHMARKING FUNCTION
# ==============================================================================

#' Smart benchmark with stratified sampling
#'
#' @param config_file Path to configuration file
#' @param n_persons Number of persons to sample (default: 10)
#' @param n_outcomes Number of outcomes to sample (default: 2)
#' @param n_groups Number of groups to sample (default: 1)
#' @param tune_hyperparameters Enable hyperparameter tuning?
#' @param save_results Save results to CSV?
#'
#' @return List with benchmark results and extrapolations
smart_benchmark <- function(config_file = "config.yaml",
                           n_persons = 10,
                           n_outcomes = 2,
                           n_groups = 1,
                           tune_hyperparameters = TRUE,
                           save_results = TRUE) {

  start_time <- Sys.time()

  cat("\n")
  cat("================================================================================\n")
  cat("                    SMART BENCHMARK CONFIGURATION                              \n")
  cat("================================================================================\n")
  cat(sprintf("Config file: %s\n", config_file))
  cat(sprintf("Sample size: %d persons × %d outcomes × %d groups = %d models\n",
              n_persons, n_outcomes, n_groups, n_persons * n_outcomes * n_groups))
  cat(sprintf("Hyperparameter tuning: %s\n", ifelse(tune_hyperparameters, "ENABLED", "DISABLED")))
  cat(sprintf("Started at: %s\n", format(start_time, "%Y-%m-%d %H:%M:%S")))
  cat("\n")

  # Load configuration
  config <- load_config(config_file)

  # Override tuning settings
  config$metamodels$neural_network$tune_hyperparameters <- tune_hyperparameters
  config$metamodels$random_forest$tune_hyperparameters <- tune_hyperparameters
  config$metamodels$support_vector_regression$tune_hyperparameters <- tune_hyperparameters

  # ==============================================================================
  # STEP 1: LOAD FULL DATA & CALCULATE TOTAL SIZE
  # ==============================================================================

  cat("================================================================================\n")
  cat("                    STEP 1: ANALYZING FULL DATASET                             \n")
  cat("================================================================================\n")

  data_raw <- load_and_prepare_data(config)

  # Calculate full dataset size
  total_persons <- 0
  total_groups <- length(data_raw)
  total_outcomes <- length(config$variables$outcomes)

  for (group_name in names(data_raw)) {
    group_data <- data_raw[[group_name]]$data
    n_persons_in_group <- length(unique(group_data$person_idx))
    total_persons <- max(total_persons, n_persons_in_group)
  }

  total_models_full <- total_persons * total_outcomes * total_groups

  cat(sprintf("\n📊 Full Dataset Statistics:\n"))
  cat(sprintf("   Persons: %d\n", total_persons))
  cat(sprintf("   Outcomes: %d\n", total_outcomes))
  cat(sprintf("   Groups: %d\n", total_groups))
  cat(sprintf("   Total models per metamodel type: %d\n", total_models_full))
  cat("\n")

  # ==============================================================================
  # STEP 2: CREATE STRATIFIED SAMPLE
  # ==============================================================================

  cat("================================================================================\n")
  cat("                    STEP 2: CREATING STRATIFIED SAMPLE                         \n")
  cat("================================================================================\n")

  # Sample groups
  sampled_groups <- head(names(data_raw), n_groups)
  cat(sprintf("✓ Sampled %d group(s): %s\n", n_groups, paste(sampled_groups, collapse = ", ")))

  # Sample outcomes
  sampled_outcomes <- head(config$variables$outcomes, n_outcomes)
  cat(sprintf("✓ Sampled %d outcome(s): %s\n", n_outcomes, paste(sampled_outcomes, collapse = ", ")))

  # Prepare sampled person datasets
  person_datasets_sample <- list()

  for (group_name in sampled_groups) {
    group_data <- data_raw[[group_name]]$data

    # Sample persons
    all_persons <- sort(unique(group_data$person_idx))
    sampled_persons <- head(all_persons, n_persons)

    cat(sprintf("\n✓ Group '%s': Sampling %d persons from %d total\n",
                group_name, length(sampled_persons), length(all_persons)))

    # Filter data to sampled persons
    group_data_sample <- group_data[person_idx %in% sampled_persons]

    for (outcome in sampled_outcomes) {
      # Prepare person datasets
      person_ds <- prepare_all_persons(group_data_sample, config, outcome)

      # Store
      key <- paste(group_name, outcome, sep = "_")
      person_datasets_sample[[key]] <- list(
        group = group_name,
        outcome = outcome,
        person_datasets = person_ds
      )
    }
  }

  total_models_sample <- n_persons * n_outcomes * n_groups

  cat(sprintf("\n📊 Sample Dataset Statistics:\n"))
  cat(sprintf("   Models per metamodel type: %d\n", total_models_sample))
  cat(sprintf("   Sampling ratio: %.1f%% of full dataset\n",
              100 * total_models_sample / total_models_full))
  cat("\n")

  # ==============================================================================
  # STEP 3: BENCHMARK EACH METAMODEL ON SAMPLE
  # ==============================================================================

  cat("================================================================================\n")
  cat("                    STEP 3: BENCHMARKING ON SAMPLE                             \n")
  cat("================================================================================\n")

  benchmark_results <- list()

  # Function to benchmark one metamodel
  benchmark_one <- function(train_fn, model_name, ...) {
    cat(sprintf("\n>>> Benchmarking %s <<<\n", model_name))

    gc(reset = TRUE)
    mem_before <- as.numeric(pryr::mem_used())

    # Benchmark
    timing <- system.time({
      result <- train_fn(person_datasets_sample, config, ...)
    })

    mem_after <- as.numeric(pryr::mem_used())

    elapsed_sec <- timing["elapsed"]
    cpu_sec <- timing["user.self"] + timing["sys.self"]
    mem_mb <- (mem_after - mem_before) / 1024^2

    # Calculate per-model cost
    per_model_time_sec <- elapsed_sec / total_models_sample
    per_model_mem_mb <- mem_mb / total_models_sample

    # Extrapolate to full dataset
    full_time_sec <- per_model_time_sec * total_models_full
    full_time_hours <- full_time_sec / 3600
    full_time_days <- full_time_hours / 24
    full_mem_mb <- per_model_mem_mb * total_models_full

    cat(sprintf("  Sample (%d models):\n", total_models_sample))
    cat(sprintf("    Time: %.1f seconds (%.2f min)\n", elapsed_sec, elapsed_sec/60))
    cat(sprintf("    CPU: %.1f seconds\n", cpu_sec))
    cat(sprintf("    Memory: %.1f MB\n", mem_mb))
    cat(sprintf("\n  Per-Model Average:\n"))
    cat(sprintf("    Time: %.2f seconds/model\n", per_model_time_sec))
    cat(sprintf("    Memory: %.3f MB/model\n", per_model_mem_mb))
    cat(sprintf("\n  📈 EXTRAPOLATED to Full Dataset (%d models):\n", total_models_full))
    cat(sprintf("    Time: %.1f hours (%.2f days)\n", full_time_hours, full_time_days))
    cat(sprintf("    Memory: %.1f MB (%.2f GB)\n", full_mem_mb, full_mem_mb/1024))
    cat("\n")

    return(list(
      model = model_name,
      sample_models = total_models_sample,
      sample_time_sec = elapsed_sec,
      sample_cpu_sec = cpu_sec,
      sample_mem_mb = mem_mb,
      per_model_time_sec = per_model_time_sec,
      per_model_mem_mb = per_model_mem_mb,
      full_models = total_models_full,
      full_time_sec = full_time_sec,
      full_time_hours = full_time_hours,
      full_time_days = full_time_days,
      full_mem_mb = full_mem_mb,
      full_mem_gb = full_mem_mb / 1024
    ))
  }

  # Benchmark all metamodels
  benchmark_results[["lr"]] <- benchmark_one(train_lr_all, "Linear Regression (LR)")
  benchmark_results[["qr"]] <- benchmark_one(train_qr_all, "Quadratic Regression (QR)")
  benchmark_results[["cr"]] <- benchmark_one(train_cr_all, "Cubic Regression (CR)")
  benchmark_results[["nn"]] <- benchmark_one(train_nn_all, "Neural Network (NN)")
  benchmark_results[["rf"]] <- benchmark_one(train_rf_all, "Random Forest (RF)", NULL)
  benchmark_results[["svr"]] <- benchmark_one(train_svr_all, "Support Vector Regression (SVR)")

  # ==============================================================================
  # STEP 4: SUMMARY & RECOMMENDATIONS
  # ==============================================================================

  cat("\n")
  cat("================================================================================\n")
  cat("                    BENCHMARK SUMMARY & EXTRAPOLATIONS                         \n")
  cat("================================================================================\n")
  cat("\n")

  results_dt <- rbindlist(benchmark_results, fill = TRUE)
  setorder(results_dt, full_time_days)

  cat("Ranked by Estimated Full Dataset Time:\n")
  cat("--------------------------------------------------------------------------------\n")
  print(results_dt[, .(
    Rank = 1:.N,
    Model = model,
    `Per-Model (sec)` = round(per_model_time_sec, 2),
    `Full Time (days)` = round(full_time_days, 2),
    `Full Time (hrs)` = round(full_time_hours, 1),
    `Full Memory (GB)` = round(full_mem_gb, 2)
  )])

  cat("\n")
  cat("⚡ FASTEST: ", results_dt$model[1], "\n", sep = "")
  cat(sprintf("   Estimated time: %.2f days (%.1f hours)\n",
              results_dt$full_time_days[1], results_dt$full_time_hours[1]))
  cat("\n")
  cat("🐌 SLOWEST: ", results_dt$model[.N], "\n", sep = "")
  cat(sprintf("   Estimated time: %.2f days (%.1f hours)\n",
              results_dt$full_time_days[.N], results_dt$full_time_hours[.N]))
  cat(sprintf("   %.1fx slower than fastest\n",
              results_dt$full_time_days[.N] / results_dt$full_time_days[1]))
  cat("\n")

  # Total time estimate
  total_time_all <- sum(results_dt$full_time_days)
  cat(sprintf("⏱️  TOTAL TIME to train all 6 metamodel types: %.2f days (%.1f hours)\n",
              total_time_all, total_time_all * 24))
  cat("\n")

  # ==============================================================================
  # RECOMMENDATIONS
  # ==============================================================================

  cat("================================================================================\n")
  cat("                              RECOMMENDATIONS                                  \n")
  cat("================================================================================\n")
  cat("\n")

  cat("Based on these estimates:\n\n")

  # Check if any model takes > 1 day
  slow_models <- results_dt[full_time_days > 1]
  if (nrow(slow_models) > 0) {
    cat("⚠️  WARNING: The following models will take > 1 day:\n")
    for (i in 1:nrow(slow_models)) {
      cat(sprintf("   • %s: %.1f days\n",
                  slow_models$model[i], slow_models$full_time_days[i]))
    }
    cat("\n")
    cat("💡 Consider:\n")
    cat("   1. Disable hyperparameter tuning (set tune_hyperparameters = FALSE)\n")
    cat("      - Can reduce time by 5-10x\n")
    cat("   2. Use parallel processing (if available)\n")
    cat("   3. Run overnight/over weekend\n")
    cat("   4. Train only fastest models first\n")
    cat("\n")
  }

  # Check memory
  high_mem_models <- results_dt[full_mem_gb > 10]
  if (nrow(high_mem_models) > 0) {
    cat("⚠️  HIGH MEMORY USAGE:\n")
    for (i in 1:nrow(high_mem_models)) {
      cat(sprintf("   • %s: %.1f GB\n",
                  high_mem_models$model[i], high_mem_models$full_mem_gb[i]))
    }
    cat("\n")
    cat("💡 Ensure your system has sufficient RAM\n\n")
  }

  cat("✅ Recommended order (fastest to slowest):\n")
  for (i in 1:nrow(results_dt)) {
    cat(sprintf("   %d. %s (%.1f hours)\n",
                i, results_dt$model[i], results_dt$full_time_hours[i]))
  }
  cat("\n")

  # ==============================================================================
  # SAVE RESULTS
  # ==============================================================================

  if (save_results) {
    output_dir <- config$project$output_directory
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

    output_file <- file.path(output_dir, "smart_benchmark_results.csv")
    fwrite(results_dt, output_file)
    cat(sprintf("✓ Results saved to: %s\n", output_file))
  }

  # ==============================================================================
  # COMPLETION
  # ==============================================================================

  end_time <- Sys.time()
  benchmark_duration <- as.numeric(difftime(end_time, start_time, units = "mins"))

  cat("\n")
  cat("================================================================================\n")
  cat("                         BENCHMARK COMPLETE                                    \n")
  cat("================================================================================\n")
  cat(sprintf("Benchmark duration: %.2f minutes\n", benchmark_duration))
  cat(sprintf("Sample size: %d models (%.1f%% of full dataset)\n",
              total_models_sample, 100 * total_models_sample / total_models_full))
  cat(sprintf("Extrapolated to: %d models (full dataset)\n", total_models_full))
  cat("\n")

  return(list(
    results = results_dt,
    sample_size = total_models_sample,
    full_size = total_models_full,
    total_estimated_days = total_time_all
  ))
}

# ==============================================================================
# USAGE
# ==============================================================================

cat("\n")
cat("================================================================================\n")
cat("                            READY TO BENCHMARK                                  \n")
cat("================================================================================\n")
cat("\n")
cat("Usage:\n")
cat("\n")
cat("# Quick estimate (10 persons, 2 outcomes, 1 group = 20 models)\n")
cat("results <- smart_benchmark('config.yaml', n_persons=10, n_outcomes=2, n_groups=1)\n")
cat("\n")
cat("# More accurate estimate (30 persons, 3 outcomes, 2 groups = 180 models)\n")
cat("results <- smart_benchmark('config.yaml', n_persons=30, n_outcomes=3, n_groups=2)\n")
cat("\n")
cat("# Without hyperparameter tuning (faster sample)\n")
cat("results <- smart_benchmark('config.yaml', tune_hyperparameters=FALSE)\n")
cat("\n")
cat("================================================================================\n")
cat("\n")
