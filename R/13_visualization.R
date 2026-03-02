################################################################################
#                                                                              #
#                    VISUALIZATION MODULE FOR METAMODEL RESULTS                #
#                                                                              #
#  This module creates publication-quality visualizations for metamodel        #
#  performance, including:                                                     #
#  - R² heatmaps across metamodels and outcomes                               #
#  - Distribution plots (joy plots) for R² values                             #
#  - Population-level prediction comparisons                                   #
#  - Variable importance charts                                                #
#  - Prediction vs actual scatter plots                                        #
#  - Model comparison bar charts                                               #
#                                                                              #
################################################################################

library(data.table)
library(ggplot2)
library(ggridges)
library(viridis)
library(gridExtra)

#' Create R² heatmap across metamodels and outcomes
#'
#' @param evaluation_results Evaluation results from pipeline
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_r2_heatmap <- function(evaluation_results,
                           output_file = NULL,
                           width = 12,
                           height = 8) {

  cat("\n▶ Creating R² heatmap...\n")

  # Extract R² values
  if ("aggregated" %in% names(evaluation_results)) {
    data <- copy(evaluation_results$aggregated)
  } else {
    data <- copy(evaluation_results)
  }

  # Check for required columns - handle both old and new formats
  if ("combination" %in% names(data) && !("outcome" %in% names(data))) {
    # Parse combination column into group and outcome
    # Format is typically: "groupname_outcomename"
    data[, c("group", "outcome") := tstrsplit(combination, "_(?=[^_]+$)", perl = TRUE)]
    # If parsing failed, use combination as outcome
    data[is.na(outcome), outcome := combination]
    data[is.na(group), group := "all"]
  }

  # Ensure required columns exist
  required_cols <- c("model_type", "mean_test_r2")
  if (!all(required_cols %in% names(data))) {
    stop("Data must contain columns: ", paste(required_cols, collapse = ", "))
  }

  # Add default group/outcome if missing
  if (!"outcome" %in% names(data)) data[, outcome := "outcome"]
  if (!"group" %in% names(data)) data[, group := "all"]

  # Create plot
  p <- ggplot(data, aes(x = outcome, y = model_type, fill = mean_test_r2)) +
    geom_tile(color = "white", size = 0.5) +
    geom_text(aes(label = sprintf("%.2f", mean_test_r2)),
              color = "white", size = 3, fontface = "bold") +
    facet_wrap(~ group, ncol = 3, scales = "free_x") +
    scale_fill_viridis(
      name = "Test R²",
      limits = c(0, 1),
      option = "plasma",
      direction = -1
    ) +
    labs(
      title = "Metamodel Performance Comparison",
      subtitle = "Test R² across outcomes and groups",
      x = "Outcome",
      y = "Metamodel Type"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      axis.text.y = element_text(size = 10),
      strip.text = element_text(size = 11, face = "bold"),
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      legend.position = "right",
      panel.grid = element_blank()
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Heatmap saved: %s\n", output_file))
  }

  return(p)
}


#' Create joy plots (ridge plots) for R² distributions
#'
#' @param evaluation_results Evaluation results from pipeline
#' @param metric Metric to plot (default: "test_r2")
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_r2_distributions <- function(evaluation_results,
                                 metric = "test_r2",
                                 output_file = NULL,
                                 width = 10,
                                 height = 8) {

  cat("\n▶ Creating R² distribution plots...\n")

  # Extract person-level results (try multiple possible names)
  if ("comparison" %in% names(evaluation_results)) {
    data <- copy(evaluation_results$comparison)
  } else if ("person_level" %in% names(evaluation_results)) {
    data <- copy(evaluation_results$person_level)
  } else if ("detailed" %in% names(evaluation_results)) {
    data <- copy(evaluation_results$detailed)
  } else {
    data <- copy(evaluation_results)
  }

  # Check if metric column exists
  if (!metric %in% names(data)) {
    # Try to find a similar column
    if ("mean_test_r2" %in% names(data) && metric == "test_r2") {
      metric <- "mean_test_r2"
    } else {
      cat(sprintf("  Warning: Metric '%s' not found, skipping distribution plot\n", metric))
      return(NULL)
    }
  }

  # Ensure model_type exists
  if (!"model_type" %in% names(data)) {
    cat("  Warning: 'model_type' column not found, skipping distribution plot\n")
    return(NULL)
  }

  # Create plot
  p <- ggplot(data, aes(x = .data[[metric]], y = model_type, fill = model_type)) +
    geom_density_ridges(
      alpha = 0.7,
      scale = 1.5,
      quantile_lines = TRUE,
      quantiles = 2
    ) +
    scale_fill_viridis(discrete = TRUE, option = "turbo") +
    scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    labs(
      title = "Distribution of Model Performance",
      subtitle = sprintf("Distribution of %s across person types", metric),
      x = sprintf("%s", gsub("_", " ", toupper(metric))),
      y = "Metamodel Type"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      axis.text.y = element_text(size = 11),
      legend.position = "none",
      panel.grid.minor = element_blank()
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Distribution plot saved: %s\n", output_file))
  }

  return(p)
}


#' Create population-level prediction comparison
#'
#' @param population_predictions data.table with population predictions
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_population_predictions <- function(population_predictions,
                                       output_file = NULL,
                                       width = 10,
                                       height = 6) {

  cat("\n▶ Creating population prediction plot...\n")

  # Handle list structure (keyed by combination)
  if (is.list(population_predictions) && !is.data.table(population_predictions)) {
    # Convert list of data.tables to long format
    plot_data_list <- lapply(names(population_predictions), function(combo) {
      dt <- population_predictions[[combo]]
      # Find prediction columns (start with "pred_")
      pred_cols <- grep("^pred_", names(dt), value = TRUE)

      if (length(pred_cols) == 0) {
        return(NULL)
      }

      # Get mean predictions across scenarios for each model type
      result <- data.table(
        outcome = combo,
        model_type = gsub("^pred_", "", pred_cols),
        prediction = sapply(pred_cols, function(col) mean(dt[[col]], na.rm = TRUE))
      )
      return(result)
    })

    plot_data <- rbindlist(plot_data_list[!sapply(plot_data_list, is.null)])

    # Clean up outcome names (extract just the outcome part)
    plot_data[, outcome := gsub(".*_", "", outcome)]

  } else {
    # Already in expected format or data.table
    plot_data <- copy(population_predictions)

    # Check for required columns
    required_cols <- c("model_type", "outcome", "prediction")
    if (!all(required_cols %in% names(plot_data))) {
      # Try to find prediction columns
      pred_cols <- grep("^pred_|prediction", names(plot_data), value = TRUE)
      if (length(pred_cols) == 0) {
        cat("  Warning: Cannot create population plot - missing required columns\n")
        return(NULL)
      }
    }
  }

  if (nrow(plot_data) == 0) {
    cat("  Warning: No data for population prediction plot\n")
    return(NULL)
  }

  # Create plot
  p <- ggplot(plot_data,
              aes(x = model_type, y = prediction, fill = model_type)) +
    geom_bar(stat = "identity", alpha = 0.8) +
    geom_text(aes(label = sprintf("%.2f", prediction)),
              vjust = -0.5, size = 3.5) +
    facet_wrap(~ outcome, scales = "free_y", ncol = 2) +
    scale_fill_viridis(discrete = TRUE, option = "plasma") +
    labs(
      title = "Population-Level Predictions by Metamodel",
      subtitle = "Mean predictions across scenarios",
      x = "Metamodel Type",
      y = "Predicted Value"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      strip.text = element_text(size = 11, face = "bold"),
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      legend.position = "none"
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Population prediction plot saved: %s\n", output_file))
  }

  return(p)
}


#' Create variable importance chart
#'
#' @param variable_importance Named vector or data.table of variable importance
#' @param model_name Name of model for title
#' @param top_n Number of top variables to show (default: 10)
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_variable_importance <- function(variable_importance,
                                    model_name = "Model",
                                    top_n = 10,
                                    output_file = NULL,
                                    width = 8,
                                    height = 6) {

  cat("\n▶ Creating variable importance plot...\n")

  # Convert to data.table if needed
  if (is.vector(variable_importance)) {
    var_dt <- data.table(
      variable = names(variable_importance),
      importance = as.numeric(variable_importance)
    )
  } else {
    var_dt <- as.data.table(variable_importance)
  }

  # Sort and select top N
  setorder(var_dt, -importance)
  var_dt <- head(var_dt, top_n)

  # Create plot
  p <- ggplot(var_dt, aes(x = reorder(variable, importance), y = importance)) +
    geom_bar(stat = "identity", fill = "#440154FF", alpha = 0.8) +
    geom_text(aes(label = sprintf("%.1f", importance)),
              hjust = -0.2, size = 3.5) +
    coord_flip() +
    labs(
      title = sprintf("Variable Importance - %s", model_name),
      subtitle = sprintf("Top %d predictors", top_n),
      x = "Variable",
      y = "Importance Score"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      axis.text.y = element_text(size = 10)
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Variable importance plot saved: %s\n", output_file))
  }

  return(p)
}


#' Create prediction vs actual scatter plot
#'
#' @param predictions data.table with 'actual' and 'predicted' columns
#' @param model_name Name of model for title
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_predictions_vs_actual <- function(predictions,
                                      model_name = "Model",
                                      output_file = NULL,
                                      width = 8,
                                      height = 8) {

  cat("\n▶ Creating prediction vs actual plot...\n")

  # Ensure required columns
  if (!all(c("actual", "predicted") %in% names(predictions))) {
    stop("Data must contain 'actual' and 'predicted' columns")
  }

  # Calculate R²
  r2 <- cor(predictions$actual, predictions$predicted)^2

  # Create plot
  p <- ggplot(predictions, aes(x = actual, y = predicted)) +
    geom_point(alpha = 0.5, color = "#440154FF", size = 2) +
    geom_abline(intercept = 0, slope = 1, color = "red", linetype = "dashed", size = 1) +
    geom_smooth(method = "lm", color = "blue", fill = "lightblue", alpha = 0.3) +
    annotate("text", x = Inf, y = -Inf,
             label = sprintf("R² = %.3f", r2),
             hjust = 1.1, vjust = -0.5, size = 5, fontface = "bold") +
    labs(
      title = sprintf("Predictions vs Actual - %s", model_name),
      subtitle = "Red line = perfect prediction, Blue line = actual fit",
      x = "Actual Value",
      y = "Predicted Value"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 11, hjust = 0.5),
      aspect.ratio = 1
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Prediction vs actual plot saved: %s\n", output_file))
  }

  return(p)
}


#' Create model comparison bar chart
#'
#' @param evaluation_summary Summary data.table with model performance metrics
#' @param metric Metric to compare (default: "mean_test_r2")
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_model_comparison <- function(evaluation_summary,
                                 metric = "mean_test_r2",
                                 output_file = NULL,
                                 width = 10,
                                 height = 6) {

  cat("\n▶ Creating model comparison plot...\n")

  # Ensure required columns
  if (!"model_type" %in% names(evaluation_summary)) {
    cat("  Warning: 'model_type' column not found, skipping comparison plot\n")
    return(NULL)
  }

  if (!metric %in% names(evaluation_summary)) {
    cat(sprintf("  Warning: '%s' column not found, skipping comparison plot\n", metric))
    return(NULL)
  }

  # Order by metric (use setorderv with column name)
  eval_copy <- copy(evaluation_summary)
  setorderv(eval_copy, metric, order = -1L)

  # Create plot
  p <- ggplot(eval_copy, aes(x = reorder(model_type, .data[[metric]]),
                              y = .data[[metric]],
                              fill = model_type)) +
    geom_bar(stat = "identity", alpha = 0.8) +
    geom_text(aes(label = sprintf("%.3f", .data[[metric]])),
              hjust = -0.2, size = 4) +
    coord_flip() +
    scale_fill_viridis(discrete = TRUE, option = "turbo") +
    scale_y_continuous(limits = c(0, max(eval_copy[[metric]]) * 1.1)) +
    labs(
      title = "Metamodel Performance Comparison",
      subtitle = sprintf("Ranked by %s", gsub("_", " ", metric)),
      x = "Metamodel Type",
      y = gsub("_", " ", toupper(metric))
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      legend.position = "none",
      axis.text.y = element_text(size = 11)
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Model comparison plot saved: %s\n", output_file))
  }

  return(p)
}


#' Create comprehensive visualization report
#'
#' @param pipeline_results Complete results from run_metamodeling_pipeline()
#' @param config Configuration list
#' @param output_dir Directory to save plots
#'
#' @return List of ggplot objects
create_visualization_report <- function(pipeline_results, config, output_dir = NULL) {

  cat("\n")
  cat("================================================================================\n")
  cat("                    CREATING VISUALIZATION REPORT                              \n")
  cat("================================================================================\n")
  cat("\n")

  # Create output directory if specified
  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }
  } else {
    output_dir <- file.path(config$project$output_directory, "visualizations")
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }
  }

  plots <- list()

  # Get plot settings with defaults
  plot_settings <- config$visualizations$plots
  r2_heatmap_enabled <- isTRUE(plot_settings$r2_heatmap$enabled) || is.null(plot_settings)
  joy_plots_enabled <- isTRUE(plot_settings$joy_plots$enabled) || is.null(plot_settings)
  pop_estimates_enabled <- isTRUE(plot_settings$population_estimates$enabled) || is.null(plot_settings)

  # 1. R² Heatmap
  if (r2_heatmap_enabled) {
    cat("▶ Generating R² heatmap...\n")
    heatmap_file <- file.path(output_dir, plot_settings$r2_heatmap$output_file %||% "r2_heatmap.png")
    plots$r2_heatmap <- plot_r2_heatmap(
      pipeline_results$evaluation,
      output_file = heatmap_file,
      width = plot_settings$r2_heatmap$width %||% 10,
      height = plot_settings$r2_heatmap$height %||% 8
    )
  }

  # 2. Joy Plots
  if (joy_plots_enabled) {
    cat("▶ Generating R² distribution plots...\n")
    joy_file <- file.path(output_dir, plot_settings$joy_plots$output_file %||% "r2_distributions.png")
    plots$joy_plots <- plot_r2_distributions(
      pipeline_results$evaluation,
      output_file = joy_file
    )
  }

  # 3. Population Estimates
  if (pop_estimates_enabled &&
      !is.null(pipeline_results$population_predictions)) {
    cat("▶ Generating population prediction plot...\n")
    pop_file <- file.path(output_dir, plot_settings$population_estimates$output_file %||% "population_predictions.png")
    plots$population_estimates <- plot_population_predictions(
      pipeline_results$population_predictions,
      output_file = pop_file
    )
  }

  # 4. Model Comparison
  cat("▶ Generating model comparison plot...\n")
  comparison_file <- file.path(output_dir, "model_comparison.png")
  plots$model_comparison <- plot_model_comparison(
    pipeline_results$evaluation$aggregated,
    output_file = comparison_file
  )

  # 5. Individual Metamodel Performance (one plot per outcome)
  cat("▶ Generating per-outcome performance plots...\n")

  outcomes <- unique(pipeline_results$evaluation$aggregated$outcome)

  for (outcome in outcomes) {
    outcome_data <- pipeline_results$evaluation$aggregated[outcome == outcome]

    outcome_file <- file.path(output_dir, sprintf("comparison_%s.png", outcome))

    plots[[sprintf("comparison_%s", outcome)]] <- plot_model_comparison(
      outcome_data,
      output_file = outcome_file
    )
  }

  cat("\n")
  cat("================================================================================\n")
  cat("                    VISUALIZATION REPORT COMPLETE                              \n")
  cat("================================================================================\n")
  cat(sprintf("Plots saved to: %s\n", output_dir))
  cat(sprintf("Total plots created: %d\n", length(plots)))
  cat("\n")

  return(plots)
}


#' Create training vs test R² comparison plot
#'
#' @param evaluation_results Evaluation results with train and test R²
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return ggplot object
plot_train_vs_test <- function(evaluation_results,
                              output_file = NULL,
                              width = 10,
                              height = 8) {

  cat("\n▶ Creating train vs test comparison...\n")

  # Extract data
  if ("aggregated" %in% names(evaluation_results)) {
    data <- evaluation_results$aggregated
  } else {
    data <- evaluation_results
  }

  # Ensure required columns
  required_cols <- c("model_type", "mean_train_r2", "mean_test_r2")
  if (!all(required_cols %in% names(data))) {
    stop("Data must contain: ", paste(required_cols, collapse = ", "))
  }

  # Calculate overfitting (train - test)
  data[, overfitting := mean_train_r2 - mean_test_r2]

  # Create plot
  p <- ggplot(data, aes(x = mean_test_r2, y = mean_train_r2, color = model_type)) +
    geom_point(size = 4, alpha = 0.7) +
    geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "red", size = 1) +
    geom_text(aes(label = model_type), vjust = -1, size = 3, show.legend = FALSE) +
    scale_color_viridis(discrete = TRUE, option = "plasma") +
    scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    labs(
      title = "Training vs Test Performance",
      subtitle = "Points above red line indicate overfitting",
      x = "Test R²",
      y = "Training R²",
      color = "Metamodel"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5),
      aspect.ratio = 1,
      legend.position = "bottom"
    )

  # Save if output file specified
  if (!is.null(output_file)) {
    ggsave(output_file, plot = p, width = width, height = height, dpi = 300)
    cat(sprintf("  ✓ Train vs test plot saved: %s\n", output_file))
  }

  return(p)
}


#' Create multi-panel diagnostic plot
#'
#' @param model_results Results from a single metamodel
#' @param model_name Name of the model
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return Grid of ggplot objects
plot_model_diagnostics <- function(model_results,
                                  model_name = "Model",
                                  output_file = NULL,
                                  width = 12,
                                  height = 10) {

  cat(sprintf("\n▶ Creating diagnostic plots for %s...\n", model_name))

  # This would require actual vs predicted data from the model
  # Placeholder for now - would need to be customized based on available data

  cat("  Note: Diagnostic plot requires prediction data\n")

  return(NULL)
}
