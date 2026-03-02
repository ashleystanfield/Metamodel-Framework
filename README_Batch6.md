# Batch 6: Decision Trees and Visualizations

## Overview

Batch 6 completes the generalized metamodeling system by adding:

1. **Decision Tree Analysis** - Automatically recommends optimal interventions based on person characteristics
2. **Comprehensive Visualizations** - Publication-quality plots for model performance and predictions

These final components transform the system from a modeling tool into a complete decision support platform.

---

## What's New in Batch 6

### Files Added

```
R/
├── 12_decision_tree.R       # Decision tree for intervention recommendations
└── 13_visualization.R       # Comprehensive visualization suite

README_Batch6.md             # This file
```

### Updates to Existing Files

- **main.R** - Integrated decision tree and visualization steps into pipeline
- **config.yaml** - Decision tree and visualization settings already present

---

## Module 1: Decision Tree Analysis

**File:** `R/12_decision_tree.R`

### What It Does

The decision tree module analyzes metamodel predictions across different interventions and builds a classification tree that recommends which intervention is optimal for each person type based on their characteristics.

**Key Features:**
- Simulates outcomes across multiple interventions
- Identifies best intervention per person type
- Trains interpretable decision tree classifier
- Generates decision rules for practitioners
- Validates recommendations with cross-validation
- Exports tree visualization

**Workflow:**

```
1. For each person type:
   ├─ Predict outcome under Intervention A (using trained metamodels)
   ├─ Predict outcome under Intervention B
   ├─ Predict outcome under Intervention C
   └─ Select intervention with best predicted outcome

2. Train decision tree:
   ├─ Input: Person characteristics (age, screening rates, etc.)
   └─ Output: Optimal intervention for that person type

3. Generate decision rules:
   └─ "If screen_before < 40% → Use Mailed FIT"
   └─ "If screen_before ≥ 40% → Use Reminders"
```

### Configuration

Add to `config.yaml`:

```yaml
decision_tree:
  enabled: true
  n_simulations: 1000                    # Number of person profiles to simulate
  target_outcome: "cancer_averted"       # Outcome to optimize
  classification_method: "rpart"         # Decision tree algorithm
```

### Functions

#### `build_decision_tree()`

Main function that builds the decision tree.

**Parameters:**
- `metamodel_results` - Trained metamodels from pipeline
- `config` - Configuration list
- `target_outcome` - Outcome to optimize (e.g., "cancer_averted")
- `n_simulations` - Number of person profiles to generate
- `person_data` - Optional custom person characteristics
- `population_weights` - Optional population weights

**Returns:**
- `model` - Trained rpart decision tree
- `data` - Training data with optimal interventions
- `predictions` - Tree predictions
- `accuracy` - Classification accuracy
- `confusion_matrix` - Confusion matrix
- `variable_importance` - Variable importance scores
- `intervention_names` - Names of interventions compared
- `avg_improvement` - Average improvement from optimal choice

**Example:**

```R
# After running metamodel pipeline
results <- run_metamodeling_pipeline("config.yaml")

# Build decision tree
tree_results <- build_decision_tree(
  metamodel_results = results$models,
  config = config,
  target_outcome = "cancer_averted",
  n_simulations = 1000
)

# View results
cat(sprintf("Training accuracy: %.1f%%\n", tree_results$accuracy * 100))
print(tree_results$variable_importance)
```

#### `plot_decision_tree()`

Visualizes the decision tree.

**Parameters:**
- `decision_tree_result` - Result from `build_decision_tree()`
- `output_file` - Path to save plot (optional)
- `width` - Plot width in inches
- `height` - Plot height in inches

**Example:**

```R
plot_decision_tree(
  tree_results,
  output_file = "decision_tree.png",
  width = 12,
  height = 8
)
```

#### `recommend_intervention()`

Recommends interventions for new persons.

**Parameters:**
- `decision_tree_result` - Result from `build_decision_tree()`
- `new_person_data` - data.table with person characteristics

**Returns:**
- data.table with `person_id` and `recommended_intervention`

**Example:**

```R
# Create new person profile
new_person <- data.table(
  person_id = 1,
  screen_before = 35.0,
  diag_before = 70.0,
  age = 55
)

# Get recommendation
recommendation <- recommend_intervention(tree_results, new_person)
print(recommendation)
# Output: person_id=1, recommended_intervention="mailedfit"
```

#### `cross_validate_tree()`

Performs k-fold cross-validation on decision tree.

**Parameters:**
- `tree_data` - Training data from `build_decision_tree()`
- `formula` - Formula object for tree
- `n_folds` - Number of CV folds (default: 5)

**Returns:**
- data.table with fold-level accuracy

**Example:**

```R
cv_results <- cross_validate_tree(
  tree_data = tree_results$data,
  formula = optimal_intervention ~ screen_before + screen_at + diag_before,
  n_folds = 5
)

print(cv_results)
```

### Use Cases

**1. Intervention Selection**

```R
# Which intervention is best for low screening populations?
low_screening <- data.table(
  person_id = 1:100,
  screen_before = runif(100, 0, 30),
  diag_before = runif(100, 50, 80)
)

recommendations <- recommend_intervention(tree_results, low_screening)
table(recommendations$recommended_intervention)
```

**2. Policy Guidelines**

```R
# Extract decision rules
print(tree_results$model)

# Example output:
# Node 1: screen_before < 40
#   → Recommended: Mailed FIT (n=450, improvement=0.12)
# Node 2: screen_before >= 40
#   → Recommended: Reminders (n=550, improvement=0.08)
```

**3. Targeting High-Impact Populations**

```R
# Which populations benefit most from intervention?
tree_results$data[order(-improvement), .(person_id, improvement, optimal_intervention)]
```

---

## Module 2: Comprehensive Visualizations

**File:** `R/13_visualization.R`

### What It Does

Creates publication-quality visualizations for metamodel results, including:
- R² heatmaps across models and outcomes
- Distribution plots (joy/ridge plots)
- Population prediction comparisons
- Variable importance charts
- Prediction vs actual scatter plots
- Model comparison bar charts
- Training vs test performance

### Configuration

Already in `config.yaml`:

```yaml
visualizations:
  enabled: true

  plots:
    r2_heatmap:
      enabled: true
      output_file: "r2_heatmap.png"
      width: 12
      height: 8

    joy_plots:
      enabled: true
      output_file: "r2_distributions.png"

    population_estimates:
      enabled: true
      output_file: "population_estimates.png"

    decision_tree:
      enabled: true
      output_file: "decision_tree.png"
```

### Functions

#### `plot_r2_heatmap()`

Creates heatmap of R² values across metamodels and outcomes.

**Parameters:**
- `evaluation_results` - Evaluation results from pipeline
- `output_file` - Path to save plot (optional)
- `width`, `height` - Plot dimensions

**Example:**

```R
plot_r2_heatmap(
  results$evaluation,
  output_file = "r2_heatmap.png",
  width = 12,
  height = 8
)
```

**Visualization:**
- Rows: Metamodel types (LR, QR, CR, NN, RF, SVR)
- Columns: Outcomes (cancer_averted, life_years_lost, etc.)
- Color: Test R² (0 = dark purple, 1 = yellow)
- Facets: Groups (lhs_patientnav, kmeans_mailedfit, etc.)

#### `plot_r2_distributions()`

Creates ridge plots showing R² distributions across person types.

**Parameters:**
- `evaluation_results` - Evaluation results
- `metric` - Metric to plot (default: "test_r2")
- `output_file` - Path to save plot (optional)

**Example:**

```R
plot_r2_distributions(
  results$evaluation,
  metric = "test_r2",
  output_file = "r2_distributions.png"
)
```

**Interpretation:**
- Each ridge = one metamodel type
- Horizontal spread = variability across person types
- Median line = typical performance
- Wide distribution = inconsistent performance

#### `plot_population_predictions()`

Compares population-level predictions across metamodels.

**Parameters:**
- `population_predictions` - Population predictions data.table
- `output_file` - Path to save plot (optional)

**Example:**

```R
plot_population_predictions(
  results$population_predictions,
  output_file = "population_estimates.png"
)
```

#### `plot_variable_importance()`

Bar chart of variable importance.

**Parameters:**
- `variable_importance` - Named vector or data.table
- `model_name` - Model name for title
- `top_n` - Number of top variables to show (default: 10)
- `output_file` - Path to save plot (optional)

**Example:**

```R
# Extract from random forest
rf_importance <- results$models$random_forest$lhs_patientnav_cancer_averted$variable_importance

plot_variable_importance(
  rf_importance,
  model_name = "Random Forest",
  top_n = 10,
  output_file = "variable_importance_rf.png"
)
```

#### `plot_predictions_vs_actual()`

Scatter plot of predictions vs actual values.

**Parameters:**
- `predictions` - data.table with 'actual' and 'predicted' columns
- `model_name` - Model name for title
- `output_file` - Path to save plot (optional)

**Example:**

```R
# Extract predictions from model
pred_data <- data.table(
  actual = test_data$outcome,
  predicted = predict(model, test_data)
)

plot_predictions_vs_actual(
  pred_data,
  model_name = "Neural Network",
  output_file = "predictions_vs_actual_nn.png"
)
```

**Interpretation:**
- Red dashed line = perfect prediction
- Blue line = actual fit
- Points near red line = accurate predictions
- R² displayed in corner

#### `plot_model_comparison()`

Bar chart comparing models by a metric.

**Parameters:**
- `evaluation_summary` - Summary data.table
- `metric` - Metric to compare (default: "mean_test_r2")
- `output_file` - Path to save plot (optional)

**Example:**

```R
plot_model_comparison(
  results$evaluation$aggregated,
  metric = "mean_test_r2",
  output_file = "model_comparison.png"
)
```

#### `plot_train_vs_test()`

Scatter plot comparing training vs test R² (overfitting detection).

**Parameters:**
- `evaluation_results` - Evaluation results
- `output_file` - Path to save plot (optional)

**Example:**

```R
plot_train_vs_test(
  results$evaluation,
  output_file = "train_vs_test.png"
)
```

**Interpretation:**
- Points above red line = overfitting
- Points on red line = good generalization
- Distance from line = degree of overfitting

#### `create_visualization_report()`

Generates all visualizations at once.

**Parameters:**
- `pipeline_results` - Complete results from pipeline
- `config` - Configuration list
- `output_dir` - Directory to save plots (optional)

**Returns:**
- List of ggplot objects

**Example:**

```R
# After running full pipeline
results <- run_metamodeling_pipeline("config.yaml")

# Generate all plots
plots <- create_visualization_report(
  results,
  config,
  output_dir = "figures"
)

# Access individual plots
print(plots$r2_heatmap)
print(plots$model_comparison)
```

---

## Complete Workflow Example

### Step 1: Run Full Pipeline with Batch 6

```R
# Load system
source("main.R")

# Run complete pipeline (includes decision tree + visualizations)
results <- run_metamodeling_pipeline("config.yaml")
```

This automatically:
1. Loads and validates data
2. Trains all 6 metamodel types
3. Generates predictions
4. Evaluates performance
5. **Builds decision tree** (NEW in Batch 6)
6. **Creates visualizations** (NEW in Batch 6)

### Step 2: Review Outputs

**Decision Tree Outputs:**
```
summaries_cache/decision_tree/
├── decision_tree_model.rds           # Trained tree model
├── decision_tree_data.csv            # Training data
├── decision_tree_predictions.csv     # Predictions
└── decision_tree_summary.csv         # Summary statistics
```

**Visualization Outputs:**
```
summaries_cache/visualizations/
├── r2_heatmap.png                    # Performance heatmap
├── r2_distributions.png              # Distribution plots
├── population_estimates.png          # Population predictions
├── decision_tree.png                 # Decision tree diagram
├── model_comparison.png              # Overall comparison
└── comparison_[outcome].png          # Per-outcome comparisons
```

### Step 3: Use Results for Decision Making

**Intervention Recommendation:**

```R
# Get decision tree
tree <- results$decision_tree

# Recommend for new person
new_person <- data.table(
  person_id = 999,
  screen_before = 25.0,
  screen_at = 30.0,
  diag_before = 65.0,
  diag_at = 75.0
)

recommendation <- recommend_intervention(tree, new_person)
cat(sprintf("Recommended intervention: %s\n", recommendation$recommended_intervention))
```

**Model Selection:**

```R
# View model comparison
plot(results$plots$model_comparison)

# Get best model
best <- results$evaluation$best[1]
cat(sprintf("Best model: %s (R² = %.3f)\n",
            best$model_type, best$mean_test_r2))
```

**Identify High-Value Targets:**

```R
# Which person types benefit most?
high_impact <- tree$data[order(-improvement)]
head(high_impact[, .(person_id, optimal_intervention, improvement)])
```

---

## Running Individual Components

### Decision Tree Only

```R
# After training metamodels
results <- run_metamodeling_pipeline(
  "config.yaml",
  steps = c("load", "validate", "train", "decision_tree")
)

tree_results <- results$decision_tree
```

### Visualizations Only

```R
# After evaluation
results <- run_metamodeling_pipeline(
  "config.yaml",
  steps = c("load", "validate", "train", "evaluate", "visualize")
)

plots <- results$plots
```

### Custom Decision Tree Analysis

```R
# Load configuration
config <- load_config("config.yaml")

# Assume you have trained metamodels
# results$models contains: linear_regression, neural_network, etc.

# Custom decision tree
custom_tree <- build_decision_tree(
  metamodel_results = results$models,
  config = config,
  target_outcome = "life_years_lost",  # Different outcome
  n_simulations = 2000                 # More simulations
)

# Custom visualization
plot_decision_tree(custom_tree, output_file = "custom_tree.png")
```

### Custom Visualizations

```R
# Create specific plot
heatmap <- plot_r2_heatmap(
  results$evaluation,
  output_file = "custom_heatmap.png",
  width = 14,
  height = 10
)

# Customize with ggplot
library(ggplot2)
heatmap +
  labs(title = "Custom Title") +
  theme(text = element_text(size = 14))
```

---

## Configuration Options

### Decision Tree Settings

```yaml
decision_tree:
  enabled: true                         # Enable decision tree analysis
  n_simulations: 1000                   # Number of person profiles
  target_outcome: "cancer_averted"      # Outcome to optimize
  classification_method: "rpart"        # Algorithm (currently only rpart)
```

### Visualization Settings

```yaml
visualizations:
  enabled: true                         # Master switch for all visualizations

  plots:
    r2_heatmap:
      enabled: true
      output_file: "r2_heatmap.png"
      width: 12
      height: 8

    joy_plots:
      enabled: true
      output_file: "r2_distributions.png"

    population_estimates:
      enabled: true
      output_file: "population_estimates.png"

    decision_tree:
      enabled: true
      output_file: "decision_tree.png"
```

---

## Common Use Cases

### 1. Intervention Targeting

**Goal:** Identify which populations should receive which intervention.

```R
# Build decision tree
tree <- build_decision_tree(
  results$models,
  config,
  target_outcome = "cancer_averted"
)

# Extract decision rules
print(tree$model)

# Variable importance
print(tree$variable_importance)

# Visualize
plot_decision_tree(tree, output_file = "intervention_targeting.png")
```

### 2. Model Performance Reporting

**Goal:** Create figures for publication.

```R
# Generate all plots
plots <- create_visualization_report(results, config)

# Customize individual plots
heatmap <- plots$r2_heatmap +
  theme_minimal(base_size = 14) +
  labs(title = "Metamodel Performance Comparison")

ggsave("publication_figure1.png", heatmap, width = 12, height = 8, dpi = 300)
```

### 3. Overfitting Detection

**Goal:** Identify which models are overfitting.

```R
# Train vs test comparison
plot_train_vs_test(results$evaluation, output_file = "overfitting_check.png")

# Calculate overfitting gap
eval_data <- results$evaluation$aggregated
eval_data[, overfitting_gap := mean_train_r2 - mean_test_r2]
eval_data[overfitting_gap > 0.1]  # Models with concerning overfitting
```

### 4. Scenario Analysis

**Goal:** Compare interventions under different scenarios.

```R
# Create scenarios
scenarios <- data.table(
  scenario_id = 1:3,
  screen_before = c(20, 50, 80),
  diag_before = c(60, 70, 85)
)

# Get recommendations for each scenario
recommendations <- recommend_intervention(tree, scenarios)
print(recommendations)
```

---

## Troubleshooting

### Issue 1: Decision Tree Has Low Accuracy

**Problem:** Tree accuracy < 60%

**Possible causes:**
- Interventions have similar effectiveness (no clear winner)
- Not enough simulations
- Target outcome has high noise

**Solutions:**

```yaml
# Increase simulations
decision_tree:
  n_simulations: 5000  # Was 1000

# Try different outcome
decision_tree:
  target_outcome: "cancer_death"  # More distinct differences
```

### Issue 2: Visualizations Not Generated

**Problem:** Plots missing from output directory

**Check:**

```R
# Is visualization enabled?
config$visualizations$enabled  # Should be TRUE

# Are evaluation results available?
!is.null(results$evaluation)  # Should be TRUE

# Check output directory
dir.exists(file.path(config$project$output_directory, "visualizations"))
```

### Issue 3: Decision Tree Shows Only One Intervention

**Problem:** Tree recommends same intervention for everyone

**Explanation:** One intervention consistently outperforms others.

**Verify:**

```R
# Check intervention distribution
table(tree$best_intervention)

# Check improvement
summary(tree$improvement_by_person)

# If improvement is very small, interventions are similar
```

**Solution:** This might be valid! If one intervention is universally best, the tree correctly identifies this.

### Issue 4: Large Decision Trees (Hard to Interpret)

**Problem:** Tree is too complex with many nodes

**Solution:** Increase complexity parameter:

```R
# Modify tree training parameters in R/12_decision_tree.R
tree_model <- rpart(
  formula = formula_obj,
  data = tree_data,
  method = "class",
  control = rpart.control(
    minsplit = 30,      # Increase from 20
    minbucket = 15,     # Increase from 10
    cp = 0.02,          # Increase from 0.01 (more pruning)
    maxdepth = 4        # Decrease from 5 (shallower tree)
  )
)
```

---

## Integration with Previous Batches

### With Batch 3 (Metamodels)

Decision trees use all 6 metamodel types:
- Linear Regression
- Neural Network
- Random Forest
- Quadratic Regression
- Cubic Regression
- Support Vector Regression

Enable/disable specific models in config to see impact on recommendations.

### With Batch 4 (Prediction & Evaluation)

Visualizations use evaluation results:
```R
results$evaluation$aggregated   # → plot_r2_heatmap()
results$evaluation$person_level # → plot_r2_distributions()
results$population_predictions  # → plot_population_predictions()
```

### With Batch 5 (Advanced Metamodels)

Polynomial models provide variable importance:
```R
# Quadratic/Cubic variable importance
qr_importance <- extract_qr_variable_importance(results$models$quadratic_regression)
plot_variable_importance(qr_importance, model_name = "Quadratic Regression")
```

---

## Summary

**Batch 6 adds:**
- ✅ Decision tree for intervention recommendations
- ✅ 8+ visualization types
- ✅ Automated intervention targeting
- ✅ Publication-quality figures
- ✅ Overfitting detection plots
- ✅ Complete decision support system

**Total System Capabilities (All Batches):**

| Feature | Batch |
|---------|-------|
| Configuration management | 1-2 |
| Data loading & validation | 1-2 |
| Linear Regression | 3 |
| Neural Networks | 3 |
| Random Forests | 3 |
| Quadratic Regression | 5 |
| Cubic Regression | 5 |
| Support Vector Regression | 5 |
| Population prediction | 4 |
| Ensemble methods | 4 |
| Model evaluation | 4 |
| **Decision trees** | **6** |
| **Visualizations** | **6** |

**The system is now complete and production-ready!**

---

## Next Steps

1. **Run the complete pipeline:**
   ```R
   source("main.R")
   results <- run_metamodeling_pipeline("config.yaml")
   ```

2. **Review decision tree recommendations**
3. **Examine visualizations**
4. **Apply to your domain-specific problems**
5. **Customize for your needs**

---

## Additional Resources

- **Decision Tree Documentation**: `R/12_decision_tree.R`
- **Visualization Documentation**: `R/13_visualization.R`
- **Main Pipeline**: `main.R`
- **Configuration**: `config.yaml`
- **Batch 5 README**: `README_Batch5.md`
- **Batch 4 README**: `README_Batch4.md`
- **Batch 3 README**: `README_Batch3.md`

---

## Congratulations!

You now have a complete, production-ready metamodeling system with:
- 6 metamodel types
- Automated intervention recommendations
- Comprehensive visualizations
- Full evaluation framework
- Decision support tools

**Ready to make data-driven decisions!**
