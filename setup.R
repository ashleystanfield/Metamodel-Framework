################################################################################
#                         METAMODEL FRAMEWORK SETUP SCRIPT                     #
################################################################################
#  Run this script on a new computer to:
#    1. Install required R packages
#    2. Validate config.yaml exists
#    3. Check that data files are accessible
#    4. Update paths in config.yaml (optional)
#    5. Run a quick validation test
#
#  USAGE:
#    1. Open R or RStudio
#    2. Set working directory to the Metamodel_Generalized folder
#    3. Run: source("setup.R")
#
################################################################################

cat("\n")
cat("================================================================================\n")
cat("              METAMODEL FRAMEWORK SETUP                                        \n")
cat("================================================================================\n")
cat("\n")

# ==============================================================================
# STEP 1: CHECK R VERSION
# ==============================================================================

cat("STEP 1: Checking R version...\n")

r_version <- getRversion()
cat(sprintf("  R version: %s\n", r_version))

if (r_version < "4.0.0") {
  warning("R version 4.0.0 or higher is recommended. You have ", r_version)
} else {
  cat("  [OK] R version is sufficient\n")
}

cat("\n")

# ==============================================================================
# STEP 2: INSTALL REQUIRED PACKAGES
# ==============================================================================

cat("STEP 2: Checking and installing required packages...\n\n")

# Define required packages
required_packages <- c(
  "data.table",    # Fast data manipulation
  "caret",         # Machine learning framework
  "kernlab",       # Support Vector Regression
  "randomForest",  # Random Forest
  "nnet",          # Neural Networks

  "yaml",          # Config file parsing
  "progress",      # Progress bars
  "readr"          # File reading utilities
)

# Optional packages (for benchmarking)
optional_packages <- c(
  "bench",         # Accurate benchmarking
  "pryr"           # Memory profiling
)

install_if_missing <- function(packages, optional = FALSE) {
  for (pkg in packages) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      cat(sprintf("  [OK] %s (installed)\n", pkg))
    } else {
      cat(sprintf("  [--] %s (not installed) - Installing...\n", pkg))
      tryCatch({
        install.packages(pkg, quiet = TRUE)
        if (requireNamespace(pkg, quietly = TRUE)) {
          cat(sprintf("       [OK] %s installed successfully\n", pkg))
        } else {
          if (optional) {
            cat(sprintf("       [WARN] %s failed to install (optional)\n", pkg))
          } else {
            cat(sprintf("       [ERROR] %s failed to install\n", pkg))
          }
        }
      }, error = function(e) {
        if (optional) {
          cat(sprintf("       [WARN] %s: %s (optional)\n", pkg, e$message))
        } else {
          cat(sprintf("       [ERROR] %s: %s\n", pkg, e$message))
        }
      })
    }
  }
}

cat("Required packages:\n")
install_if_missing(required_packages, optional = FALSE)

cat("\nOptional packages (for benchmarking):\n")
install_if_missing(optional_packages, optional = TRUE)

cat("\n")

# ==============================================================================
# STEP 3: CHECK WORKING DIRECTORY
# ==============================================================================

cat("STEP 3: Checking working directory...\n")

current_wd <- getwd()
cat(sprintf("  Current directory: %s\n", current_wd))

# Check if we're in the right directory
expected_files <- c("config.yaml", "main.R", "R/utils.R")
missing_files <- character()

for (f in expected_files) {
  if (!file.exists(f)) {
    missing_files <- c(missing_files, f)
  }
}

if (length(missing_files) > 0) {
  cat("\n  [ERROR] Missing expected files:\n")
  for (f in missing_files) {
    cat(sprintf("    - %s\n", f))
  }
  cat("\n  Please ensure you're running this script from the Metamodel_Generalized folder.\n")
  cat("  Use: setwd('path/to/Metamodel_Generalized') before running setup.R\n\n")
  stop("Setup cannot continue. Please fix the working directory.")
} else {
  cat("  [OK] All expected framework files found\n")
}

cat("\n")

# ==============================================================================
# STEP 4: LOAD AND VALIDATE CONFIG
# ==============================================================================

cat("STEP 4: Loading and validating config.yaml...\n")

library(yaml)
config <- tryCatch({
  yaml::read_yaml("config.yaml")
}, error = function(e) {
  cat(sprintf("  [ERROR] Failed to read config.yaml: %s\n", e$message))
  stop("Setup cannot continue without valid config.yaml")
})

cat("  [OK] config.yaml loaded successfully\n")

# Check project settings
cat(sprintf("  Project name: %s\n", config$project$name))
cat(sprintf("  Working directory (in config): %s\n", config$project$working_directory))
cat(sprintf("  Output directory: %s\n", config$project$output_directory))

cat("\n")

# ==============================================================================
# STEP 5: CHECK DATA FILES
# ==============================================================================

cat("STEP 5: Checking data files...\n\n")

input_files <- config$data$input_files
data_status <- data.frame(
  name = character(),
  path = character(),
  enabled = logical(),
  exists = logical(),
  stringsAsFactors = FALSE
)

all_files_ok <- TRUE

for (file_info in input_files) {
  file_name <- file_info$name
  file_path <- file_info$path
  file_enabled <- isTRUE(file_info$enabled)
  file_exists <- file.exists(file_path)

  data_status <- rbind(data_status, data.frame(
    name = file_name,
    path = file_path,
    enabled = file_enabled,
    exists = file_exists,
    stringsAsFactors = FALSE
  ))

  if (file_enabled) {
    if (file_exists) {
      # Try to read first few rows to validate
      tryCatch({
        test_read <- data.table::fread(file_path, nrows = 5, showProgress = FALSE)
        cat(sprintf("  [OK] %s\n", file_name))
        cat(sprintf("       Path: %s\n", file_path))
        cat(sprintf("       Columns: %d\n", ncol(test_read)))
      }, error = function(e) {
        cat(sprintf("  [WARN] %s - File exists but cannot be read: %s\n", file_name, e$message))
        all_files_ok <<- FALSE
      })
    } else {
      cat(sprintf("  [ERROR] %s - FILE NOT FOUND\n", file_name))
      cat(sprintf("          Path: %s\n", file_path))
      all_files_ok <- FALSE
    }
  } else {
    cat(sprintf("  [SKIP] %s (disabled in config)\n", file_name))
  }
  cat("\n")
}

if (!all_files_ok) {
  cat("================================================================================\n")
  cat("  WARNING: Some data files are missing!\n")
  cat("================================================================================\n")
  cat("\n")
  cat("  You need to either:\n")
  cat("    1. Copy your data files to the paths specified in config.yaml\n")
  cat("    2. OR edit config.yaml to point to where your data files are located\n")
  cat("\n")
  cat("  To update paths, edit the 'data > input_files > path' entries in config.yaml\n")
  cat("\n")
}

# ==============================================================================
# STEP 6: CHECK OUTPUT DIRECTORY
# ==============================================================================

cat("STEP 6: Checking output directory...\n")

output_dir <- config$project$output_directory

if (!dir.exists(output_dir)) {
  cat(sprintf("  Output directory does not exist: %s\n", output_dir))
  cat("  Creating output directory...\n")
  tryCatch({
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("  [OK] Created: %s\n", output_dir))
  }, error = function(e) {
    cat(sprintf("  [ERROR] Failed to create output directory: %s\n", e$message))
  })
} else {
  cat(sprintf("  [OK] Output directory exists: %s\n", output_dir))
}

cat("\n")

# ==============================================================================
# STEP 7: VALIDATE R MODULES
# ==============================================================================

cat("STEP 7: Validating R modules...\n")

r_modules <- list.files("R", pattern = "\\.R$", full.names = TRUE)
cat(sprintf("  Found %d R modules in R/ folder:\n", length(r_modules)))

modules_ok <- TRUE
for (module in r_modules) {
  # Try to parse each module (syntax check)
  tryCatch({
    parse(file = module)
    cat(sprintf("    [OK] %s\n", basename(module)))
  }, error = function(e) {
    cat(sprintf("    [ERROR] %s - Syntax error: %s\n", basename(module), e$message))
    modules_ok <<- FALSE
  })
}

cat("\n")

# ==============================================================================
# STEP 8: UPDATE CONFIG PATHS (OPTIONAL)
# ==============================================================================

cat("STEP 8: Path configuration helper...\n\n")

update_paths <- function() {
  cat("  Current working directory path in config:\n")
  cat(sprintf("    %s\n\n", config$project$working_directory))
  cat(sprintf("  Actual current working directory:\n"))
  cat(sprintf("    %s\n\n", getwd()))

  if (config$project$working_directory != getwd()) {
    cat("  [NOTE] These paths don't match.\n")
    cat("  Consider updating config.yaml with:\n")
    cat(sprintf('    working_directory: "%s"\n', gsub("\\\\", "/", getwd())))
  } else {
    cat("  [OK] Paths match.\n")
  }
}

update_paths()

cat("\n")

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("================================================================================\n")
cat("                           SETUP SUMMARY                                       \n")
cat("================================================================================\n")
cat("\n")

# Count issues
issues <- 0

if (length(missing_files) > 0) {
  issues <- issues + 1
  cat("[X] Framework files missing\n")
} else {
  cat("[OK] Framework files present\n")
}

if (!all_files_ok) {
  issues <- issues + 1
  cat("[X] Some data files missing or unreadable\n")
} else {
  cat("[OK] All enabled data files accessible\n")
}

if (!modules_ok) {
  issues <- issues + 1
  cat("[X] Some R modules have syntax errors\n")
} else {
  cat("[OK] All R modules pass syntax check\n")
}

cat("\n")

if (issues == 0) {
  cat("================================================================================\n")
  cat("  SETUP COMPLETE - Ready to run!\n")
  cat("================================================================================\n")
  cat("\n")
  cat("  Next steps:\n")
  cat("    1. Run the main pipeline:     source('main.R')\n")
  cat("    2. Or run benchmarking:       source('benchmark_metamodels.R')\n")
  cat("                                  results <- benchmark_all_metamodels('config.yaml')\n")
  cat("\n")
} else {
  cat("================================================================================\n")
  cat(sprintf("  SETUP INCOMPLETE - %d issue(s) found\n", issues))
  cat("================================================================================\n")
  cat("\n")
  cat("  Please fix the issues above before running the framework.\n")
  cat("  Most common fix: Update file paths in config.yaml\n")
  cat("\n")
}

# ==============================================================================
# HELPER FUNCTION: Generate config template
# ==============================================================================

#' Generate a config.yaml snippet with current paths
#' Call this function to get updated paths for your config
generate_path_snippet <- function(data_folder = NULL) {
  cat("\n")
  cat("# Copy this into your config.yaml, updating the data folder path:\n")
  cat("\n")
  cat("project:\n")
  cat(sprintf('  working_directory: "%s"\n', gsub("\\\\", "/", getwd())))
  cat('  output_directory: "output"\n')
  cat("\n")

  if (!is.null(data_folder)) {
    data_folder <- gsub("\\\\", "/", data_folder)
    cat("data:\n")
    cat("  input_files:\n")
    cat(sprintf('    - name: "lhs_reminders"\n'))
    cat(sprintf('      path: "%s/summary_lhs_reminders.csv"\n', data_folder))
    cat('      enabled: true\n')
    cat("\n")
    cat(sprintf('    - name: "lhs_mailedfit"\n'))
    cat(sprintf('      path: "%s/summary_lhs_mailedfit.csv"\n', data_folder))
    cat('      enabled: true\n')
    cat("\n")
    cat(sprintf('    - name: "kmeans_reminders"\n'))
    cat(sprintf('      path: "%s/summary_kmeans_reminders.csv"\n', data_folder))
    cat('      enabled: true\n')
    cat("\n")
    cat(sprintf('    - name: "kmeans_mailedfit"\n'))
    cat(sprintf('      path: "%s/summary_kmeans_mailedfit.csv"\n', data_folder))
    cat('      enabled: true\n')
  }
}

cat("================================================================================\n")
cat("  HELPER: To generate updated paths for config.yaml, run:\n")
cat('    generate_path_snippet("C:/path/to/your/data/folder")\n')
cat("================================================================================\n")
cat("\n")
