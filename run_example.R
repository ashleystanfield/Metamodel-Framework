# =============================================================================
# Run Example - Easy way to run the included examples
# =============================================================================
#
# USAGE:
#   source("run_example.R")
#
# Then call one of these:
#   run_manufacturing()    # Run the manufacturing queueing example
#   run_healthcare()       # Run the healthcare comorbidity example
#
# Or just type:
#   list_examples()        # See all available examples
#
# =============================================================================

# Load the main pipeline
source("main.R")

#' List all available examples
list_examples <- function() {
  cat("\n")
  cat("=============================================================\n")
  cat("  AVAILABLE EXAMPLES\n")
  cat("=============================================================\n")
  cat("\n")
  cat("  1. MANUFACTURING (Queueing Theory)\n")
  cat("     - 16 product types (complexity x volume x priority)\n
")
  cat("     - 12 predictors, 4 outcomes\n")
  cat("     - Run with: run_manufacturing()\n")
  cat("\n")
  cat("  2. HEALTHCARE (Comorbidity)\n")
  cat("     - 16 patient profiles (combinations of 4 chronic conditions)\n")
  cat("     - 7 predictors, 4 outcomes\n")
  cat("     - Run with: run_healthcare()\n")
  cat("\n")
  cat("=============================================================\n")
  cat("\n")
}

#' Run the manufacturing queueing example
#' @param fast If TRUE, only runs Linear Regression (faster for testing)
run_manufacturing <- function(fast = FALSE) {
  cat("\n>> Starting MANUFACTURING example...\n\n")

  config_file <- "examples/manufacturing/config_manufacturing.yaml"

  if (fast) {
    cat("   (Fast mode: Linear Regression only)\n\n")
    # Load config, disable NN and RF
    config <- yaml::read_yaml(config_file)
    config$metamodels$neural_network$enabled <- FALSE
    config$metamodels$random_forest$enabled <- FALSE

    # Write temp config
    temp_config <- "temp_manufacturing_fast.yaml"
    yaml::write_yaml(config, temp_config)
    config_file <- temp_config
  }

  results <- run_metamodeling_pipeline(config_file = config_file)

  # Clean up temp file
  if (fast && file.exists("temp_manufacturing_fast.yaml")) {
    file.remove("temp_manufacturing_fast.yaml")
  }

  cat("\n>> Manufacturing example complete!\n")
  cat(">> Results saved to: results_manufacturing/\n\n")

  return(results)
}

#' Run the healthcare comorbidity example
#' @param fast If TRUE, only runs Linear Regression (faster for testing)
run_healthcare <- function(fast = FALSE) {
  cat("\n>> Starting HEALTHCARE example...\n\n")

  config_file <- "examples/healthcare/config_healthcare.yaml"

  if (fast) {
    cat("   (Fast mode: Linear Regression only)\n\n")
    # Load config, disable NN and RF
    config <- yaml::read_yaml(config_file)
    config$metamodels$neural_network$enabled <- FALSE
    config$metamodels$random_forest$enabled <- FALSE

    # Write temp config
    temp_config <- "temp_healthcare_fast.yaml"
    yaml::write_yaml(config, temp_config)
    config_file <- temp_config
  }

  results <- run_metamodeling_pipeline(config_file = config_file)

  # Clean up temp file
  if (fast && file.exists("temp_healthcare_fast.yaml")) {
    file.remove("temp_healthcare_fast.yaml")
  }

  cat("\n>> Healthcare example complete!\n")
  cat(">> Results saved to: results_healthcare/\n\n")

  return(results)
}

# Show available examples when script is loaded
list_examples()
