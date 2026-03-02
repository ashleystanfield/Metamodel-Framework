################################################################################
#                                                                              #
#                    DECISION TREE FOR INTERVENTION RECOMMENDATIONS            #
#                                                                              #
#  This module builds decision trees to recommend optimal interventions        #
#  based on person characteristics and predicted outcomes.                     #
#                                                                              #
#  Key features:                                                               #
#  - Simulates outcomes across multiple interventions                          #
#  - Identifies best intervention per person type                              #
#  - Trains classification tree on optimal choices                             #
#  - Generates interpretable decision rules                                    #
#  - Validates recommendations with cross-validation                           #
#                                                                              #
################################################################################

library(data.table)
library(rpart)
library(rpart.plot)

#' Build decision tree for intervention recommendations
#'
#' @param metamodel_results List of trained metamodels by intervention
#' @param config Configuration list
#' @param target_outcome Outcome to optimize (e.g., "cancer_averted")
#' @param n_simulations Number of Monte Carlo simulations (default: 1000)
#' @param person_data Optional person characteristics data.table
#' @param population_weights Optional population weights
#'
#' @return List with decision tree model, predictions, and evaluation metrics
build_decision_tree <- function(metamodel_results,
                               config,
                               target_outcome,
                               n_simulations = 1000,
                               person_data = NULL,
                               population_weights = NULL) {

  cat("\n")
  cat("================================================================================\n")
  cat("                    DECISION TREE ANALYSIS                                     \n")
  cat("================================================================================\n")
  cat(sprintf("Target outcome: %s\n", target_outcome))
  cat(sprintf("Simulations: %d\n", n_simulations))
  cat("\n")

  # ==============================================================================
  # STEP 1: EXTRACT AVAILABLE INTERVENTIONS
  # ==============================================================================

  cat("▶ Step 1: Identifying available interventions...\n")

  # Get intervention names from metamodel results
  intervention_names <- names(metamodel_results)
  n_interventions <- length(intervention_names)

  cat(sprintf("  ✓ Found %d interventions: %s\n",
              n_interventions, paste(intervention_names, collapse = ", ")))

  if (n_interventions < 2) {
    stop("Decision tree requires at least 2 interventions to compare")
  }

  # ==============================================================================
  # STEP 2: GENERATE PERSON CHARACTERISTICS (if not provided)
  # ==============================================================================

  if (is.null(person_data)) {
    cat("\n▶ Step 2: Generating person characteristics...\n")

    # Get predictor variables
    predictors <- config$variables$predictors

    # Generate random person profiles
    person_data <- data.table(person_id = 1:n_simulations)

    for (pred in predictors) {
      # Generate realistic values based on predictor name
      if (grepl("screen|diag", pred, ignore.case = TRUE)) {
        # Screening/diagnosis rates: typically 0-100%
        person_data[, (pred) := runif(n_simulations, 0, 100)]
      } else if (grepl("age", pred, ignore.case = TRUE)) {
        # Age: typically 45-75
        person_data[, (pred) := runif(n_simulations, 45, 75)]
      } else {
        # Default: uniform 0-100
        person_data[, (pred) := runif(n_simulations, 0, 100)]
      }
    }

    cat(sprintf("  ✓ Generated %d person profiles with %d characteristics\n",
                n_simulations, length(predictors)))
  } else {
    cat("\n▶ Step 2: Using provided person characteristics...\n")
    cat(sprintf("  ✓ Loaded %d person profiles\n", nrow(person_data)))
  }

  # ==============================================================================
  # STEP 3: SIMULATE OUTCOMES FOR EACH INTERVENTION
  # ==============================================================================

  cat("\n▶ Step 3: Simulating outcomes across interventions...\n")

  outcome_predictions <- list()

  for (intervention in intervention_names) {
    cat(sprintf("\n  Intervention: %s\n", intervention))

    # Get models for this intervention and outcome
    intervention_results <- metamodel_results[[intervention]]

    # Find models for target outcome
    outcome_key <- NULL
    for (key in names(intervention_results)) {
      if (grepl(target_outcome, key, fixed = TRUE)) {
        outcome_key <- key
        break
      }
    }

    if (is.null(outcome_key)) {
      warning(sprintf("No models found for outcome '%s' in intervention '%s'",
                     target_outcome, intervention))
      next
    }

    # Get person-specific models
    person_models <- intervention_results[[outcome_key]]$person_datasets

    if (is.null(person_models)) {
      warning(sprintf("No person models found for %s", intervention))
      next
    }

    # Make predictions for each person type
    predictions_by_person <- list()

    for (person_idx in seq_along(person_models)) {
      person_model <- person_models[[person_idx]]

      if (person_model$is_fallback) {
        # Use fallback prediction
        pred_value <- person_model$fallback_value
      } else {
        # Use trained model
        model_obj <- person_model$model

        # Prepare prediction data
        pred_data <- person_data[, person_model$predictors_used, with = FALSE]

        # Make prediction
        pred_value <- mean(predict(model_obj, newdata = pred_data))
      }

      predictions_by_person[[person_idx]] <- pred_value
    }

    # Average across person types
    avg_prediction <- mean(unlist(predictions_by_person))

    outcome_predictions[[intervention]] <- list(
      intervention = intervention,
      predictions = predictions_by_person,
      avg_prediction = avg_prediction
    )

    cat(sprintf("    Average predicted %s: %.4f\n", target_outcome, avg_prediction))
  }

  # ==============================================================================
  # STEP 4: IDENTIFY OPTIMAL INTERVENTION PER PERSON
  # ==============================================================================

  cat("\n▶ Step 4: Identifying optimal intervention per person...\n")

  # Create matrix of predictions: rows = persons, cols = interventions
  n_persons <- length(outcome_predictions[[1]]$predictions)
  pred_matrix <- matrix(NA, nrow = n_persons, ncol = n_interventions)
  colnames(pred_matrix) <- intervention_names

  for (i in seq_along(intervention_names)) {
    intervention <- intervention_names[i]
    preds <- unlist(outcome_predictions[[intervention]]$predictions)
    pred_matrix[, i] <- preds
  }

  # Find best intervention for each person (maximize target outcome)
  best_intervention_idx <- apply(pred_matrix, 1, which.max)
  best_intervention <- intervention_names[best_intervention_idx]

  # Calculate improvement over worst intervention
  worst_value <- apply(pred_matrix, 1, min)
  best_value <- apply(pred_matrix, 1, max)
  improvement <- best_value - worst_value

  cat(sprintf("  ✓ Optimal interventions identified for %d persons\n", n_persons))
  cat(sprintf("  ✓ Average improvement: %.4f %s\n",
              mean(improvement), target_outcome))

  # Distribution of optimal interventions
  cat("\n  Optimal intervention distribution:\n")
  intervention_counts <- table(best_intervention)
  for (int_name in names(intervention_counts)) {
    pct <- 100 * intervention_counts[int_name] / n_persons
    cat(sprintf("    %s: %d persons (%.1f%%)\n",
                int_name, intervention_counts[int_name], pct))
  }

  # ==============================================================================
  # STEP 5: PREPARE TRAINING DATA FOR DECISION TREE
  # ==============================================================================

  cat("\n▶ Step 5: Preparing decision tree training data...\n")

  # Combine person characteristics with optimal intervention
  tree_data <- copy(person_data)
  tree_data[, optimal_intervention := best_intervention]
  tree_data[, improvement := improvement]

  # Add predicted outcomes for each intervention
  for (i in seq_along(intervention_names)) {
    intervention <- intervention_names[i]
    col_name <- paste0("pred_", intervention)
    tree_data[, (col_name) := pred_matrix[, i]]
  }

  cat(sprintf("  ✓ Training data prepared: %d rows, %d columns\n",
              nrow(tree_data), ncol(tree_data)))

  # ==============================================================================
  # STEP 6: TRAIN DECISION TREE
  # ==============================================================================

  cat("\n▶ Step 6: Training decision tree classifier...\n")

  # Prepare formula
  predictors <- config$variables$predictors
  formula_str <- paste("optimal_intervention ~", paste(predictors, collapse = " + "))
  formula_obj <- as.formula(formula_str)

  # Train tree with rpart
  tree_model <- rpart(
    formula = formula_obj,
    data = tree_data,
    method = "class",
    control = rpart.control(
      minsplit = 20,      # Minimum observations in node to split
      minbucket = 10,     # Minimum observations in leaf
      cp = 0.01,          # Complexity parameter
      maxdepth = 5        # Maximum tree depth
    )
  )

  cat("  ✓ Decision tree trained\n")
  cat(sprintf("  ✓ Tree depth: %d\n", max(tree_model$cptable[, "nsplit"]) + 1))
  cat(sprintf("  ✓ Leaf nodes: %d\n", sum(tree_model$frame$var == "<leaf>")))

  # ==============================================================================
  # STEP 7: EVALUATE MODEL
  # ==============================================================================

  cat("\n▶ Step 7: Evaluating decision tree performance...\n")

  # Make predictions
  tree_predictions <- predict(tree_model, newdata = tree_data, type = "class")

  # Calculate accuracy
  accuracy <- mean(tree_predictions == tree_data$optimal_intervention)

  cat(sprintf("  ✓ Training accuracy: %.1f%%\n", accuracy * 100))

  # Confusion matrix
  confusion <- table(Predicted = tree_predictions, Actual = tree_data$optimal_intervention)

  cat("\n  Confusion matrix:\n")
  print(confusion)

  # Per-intervention accuracy
  cat("\n  Per-intervention accuracy:\n")
  for (int_name in intervention_names) {
    subset_idx <- tree_data$optimal_intervention == int_name
    if (sum(subset_idx) > 0) {
      int_accuracy <- mean(tree_predictions[subset_idx] == int_name)
      cat(sprintf("    %s: %.1f%%\n", int_name, int_accuracy * 100))
    }
  }

  # ==============================================================================
  # STEP 8: EXTRACT DECISION RULES
  # ==============================================================================

  cat("\n▶ Step 8: Extracting decision rules...\n")

  # Get variable importance
  var_importance <- tree_model$variable.importance

  if (!is.null(var_importance) && length(var_importance) > 0) {
    cat("\n  Variable importance:\n")
    var_importance_sorted <- sort(var_importance, decreasing = TRUE)
    for (i in seq_along(var_importance_sorted)) {
      var_name <- names(var_importance_sorted)[i]
      importance <- var_importance_sorted[i]
      cat(sprintf("    %d. %s: %.2f\n", i, var_name, importance))
    }
  }

  # ==============================================================================
  # STEP 9: SAVE RESULTS
  # ==============================================================================

  if (config$decision_tree$enabled && config$modeling$save_models) {
    cat("\n▶ Step 9: Saving decision tree results...\n")

    output_dir <- file.path(config$project$output_directory, "decision_tree")
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }

    # Save tree model
    model_file <- file.path(output_dir, "decision_tree_model.rds")
    saveRDS(tree_model, model_file)
    cat(sprintf("  ✓ Model saved: %s\n", model_file))

    # Save training data
    data_file <- file.path(output_dir, "decision_tree_data.csv")
    fwrite(tree_data, data_file)
    cat(sprintf("  ✓ Training data saved: %s\n", data_file))

    # Save predictions
    pred_data <- tree_data[, .(person_id, optimal_intervention)]
    pred_data[, predicted_intervention := tree_predictions]
    pred_data[, correct := optimal_intervention == predicted_intervention]

    pred_file <- file.path(output_dir, "decision_tree_predictions.csv")
    fwrite(pred_data, pred_file)
    cat(sprintf("  ✓ Predictions saved: %s\n", pred_file))

    # Save summary statistics
    summary_stats <- data.table(
      metric = c("n_persons", "n_interventions", "training_accuracy",
                 "avg_improvement", "tree_depth", "leaf_nodes"),
      value = c(n_persons, n_interventions, accuracy, mean(improvement),
                max(tree_model$cptable[, "nsplit"]) + 1,
                sum(tree_model$frame$var == "<leaf>"))
    )

    summary_file <- file.path(output_dir, "decision_tree_summary.csv")
    fwrite(summary_stats, summary_file)
    cat(sprintf("  ✓ Summary saved: %s\n", summary_file))
  }

  # ==============================================================================
  # RETURN RESULTS
  # ==============================================================================

  cat("\n")
  cat("================================================================================\n")
  cat("                    DECISION TREE ANALYSIS COMPLETE                            \n")
  cat("================================================================================\n")
  cat(sprintf("Training accuracy: %.1f%%\n", accuracy * 100))
  cat(sprintf("Average improvement: %.4f %s\n", mean(improvement), target_outcome))
  cat("\n")

  return(list(
    model = tree_model,
    data = tree_data,
    predictions = tree_predictions,
    accuracy = accuracy,
    confusion_matrix = confusion,
    variable_importance = var_importance,
    intervention_names = intervention_names,
    target_outcome = target_outcome,
    avg_improvement = mean(improvement),
    improvement_by_person = improvement
  ))
}


#' Plot decision tree
#'
#' @param decision_tree_result Result from build_decision_tree()
#' @param output_file Optional file path to save plot
#' @param width Plot width in inches
#' @param height Plot height in inches
#'
#' @return NULL (creates plot)
plot_decision_tree <- function(decision_tree_result,
                              output_file = NULL,
                              width = 12,
                              height = 8) {

  if (!is.null(output_file)) {
    png(output_file, width = width, height = height, units = "in", res = 300)
  }

  # Plot with rpart.plot
  rpart.plot(
    decision_tree_result$model,
    main = sprintf("Decision Tree for Optimal Intervention\n(Target: %s)",
                   decision_tree_result$target_outcome),
    type = 4,           # Draw splits at tree levels
    extra = 104,        # Show percentage of observations + class
    fallen.leaves = TRUE,
    box.palette = "auto",
    shadow.col = "gray",
    nn = TRUE           # Show node numbers
  )

  if (!is.null(output_file)) {
    dev.off()
    cat(sprintf("✓ Decision tree plot saved: %s\n", output_file))
  }
}


#' Recommend intervention for new persons
#'
#' @param decision_tree_result Result from build_decision_tree()
#' @param new_person_data data.table with person characteristics
#'
#' @return data.table with person_id and recommended_intervention
recommend_intervention <- function(decision_tree_result, new_person_data) {

  # Make predictions
  recommendations <- predict(
    decision_tree_result$model,
    newdata = new_person_data,
    type = "class"
  )

  # Create result table
  result <- data.table(
    person_id = new_person_data$person_id,
    recommended_intervention = as.character(recommendations)
  )

  return(result)
}


#' Cross-validate decision tree
#'
#' @param tree_data Training data from build_decision_tree()
#' @param formula Formula object for tree
#' @param n_folds Number of CV folds (default: 5)
#'
#' @return data.table with CV results
cross_validate_tree <- function(tree_data, formula, n_folds = 5) {

  cat("\n")
  cat("================================================================================\n")
  cat("                    DECISION TREE CROSS-VALIDATION                             \n")
  cat("================================================================================\n")
  cat(sprintf("Folds: %d\n", n_folds))
  cat("\n")

  n <- nrow(tree_data)
  fold_ids <- sample(rep(1:n_folds, length.out = n))

  cv_results <- list()

  for (fold in 1:n_folds) {
    cat(sprintf("▶ Fold %d/%d\n", fold, n_folds))

    # Split data
    train_idx <- fold_ids != fold
    test_idx <- fold_ids == fold

    train_data <- tree_data[train_idx]
    test_data <- tree_data[test_idx]

    # Train model
    fold_model <- rpart(
      formula = formula,
      data = train_data,
      method = "class",
      control = rpart.control(minsplit = 20, minbucket = 10, cp = 0.01, maxdepth = 5)
    )

    # Predict on test set
    fold_predictions <- predict(fold_model, newdata = test_data, type = "class")

    # Calculate accuracy
    fold_accuracy <- mean(fold_predictions == test_data$optimal_intervention)

    cat(sprintf("  Test accuracy: %.1f%%\n", fold_accuracy * 100))

    cv_results[[fold]] <- list(
      fold = fold,
      n_train = sum(train_idx),
      n_test = sum(test_idx),
      accuracy = fold_accuracy
    )
  }

  # Aggregate results
  cv_dt <- rbindlist(cv_results)

  avg_accuracy <- mean(cv_dt$accuracy)
  sd_accuracy <- sd(cv_dt$accuracy)

  cat("\n")
  cat("================================================================================\n")
  cat("                    CROSS-VALIDATION RESULTS                                   \n")
  cat("================================================================================\n")
  cat(sprintf("Mean test accuracy: %.1f%% ± %.1f%%\n",
              avg_accuracy * 100, sd_accuracy * 100))
  cat("\n")

  return(cv_dt)
}
