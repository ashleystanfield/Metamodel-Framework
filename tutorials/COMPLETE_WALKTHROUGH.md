# Complete Walkthrough - Using Your Own Data

## Table of Contents
1. [Preparing Your Data](#preparing-your-data)
2. [Creating Your Config](#creating-your-config)
3. [Running the Pipeline](#running-the-pipeline)
4. [Interpreting Results](#interpreting-results)
5. [Advanced Features](#advanced-features)

---

## Preparing Your Data

### Required Structure

Your CSV must have:
- **Person ID column** - Identifies different groups/types
- **Predictor columns** - Independent variables (numeric)
- **Outcome columns** - Dependent variables (numeric)

### Example CSV Structure

```csv
person_idx,predictor1,predictor2,predictor3,outcome1,outcome2
1,5.2,10.3,15.1,25.6,30.2
1,5.4,10.5,15.3,26.1,30.8
2,6.1,11.2,16.5,28.3,32.1
2,6.3,11.4,16.7,28.9,32.7
...
```

### Data Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Rows per person type | 10 | 20+ |
| Person types | 3 | 10+ |
| Predictors | 2 | 5-15 |
| Outcomes | 1 | 1-4 |

### Example Datasets

**Healthcare (16 comorbidity profiles):**
```csv
person_idx,diabetes_intervention,cardio_intervention,...,quality_of_life
1,0,0,...,87.2
1,0,0,...,83.5
...
16,0.678,0.656,...,52.8
```

**Manufacturing (16 product types):**
```csv
person_idx,arrival_rate,service_rate,wip_inventory,...,cycle_time
1,8.2,16.5,5,...,2.8
1,11.5,17.8,8,...,3.5
...
16,13.5,25.8,17,...,32.2
```

---

## Creating Your Config

### Step 1: Copy Template

```bash
cp examples/manufacturing/config_manufacturing.yaml my_config.yaml
```

### Step 2: Edit Basic Settings

```yaml
project:
  name: "My_Project"
  output_directory: "my_results"

data:
  input_files:
    - name: "my_data"
      path: "path/to/my_data.csv"
      enabled: true

  person_id_column: "person_idx"  # Change to your column name

variables:
  predictors:
    - "predictor1"  # List YOUR predictor names
    - "predictor2"
    - "predictor3"

  outcomes:
    - "outcome1"  # List YOUR outcome names
    - "outcome2"
```

### Step 3: Choose Metamodels

```yaml
metamodels:
  linear_regression:
    enabled: true

  neural_network:
    enabled: true
    tune_hyperparameters: false  # Set true for better performance (slower)

  random_forest:
    enabled: true
    tune_hyperparameters: false  # Set true for better performance (slower)
```

**Recommendation:** Start with `tune_hyperparameters: false` for speed, then enable later.

---

## Running the Pipeline

### Basic Run

```R
setwd("C:/path/to/Metamodel_Generalized")
source("main.R")

results <- run_metamodeling_pipeline(config_file = "my_config.yaml")
```

### Step-by-Step Run

```R
# Step 1: Load and validate data only
results <- run_metamodeling_pipeline(
  config_file = "my_config.yaml",
  steps = c("load", "validate")
)

# Check validation results
print(results$person_datasets[[1]]$validation)

# Step 2: If validation looks good, train models
results <- run_metamodeling_pipeline(
  config_file = "my_config.yaml",
  steps = c("load", "validate", "train")
)

# Step 3: Evaluate
results <- run_metamodeling_pipeline(
  config_file = "my_config.yaml",
  steps = c("load", "validate", "train", "evaluate")
)
```

---

## Interpreting Results

### Check Overall Performance

```R
# Best model for each outcome
print(results$evaluation$best)

# All models ranked
print(results$evaluation$ranked)

# Detailed comparison
print(results$evaluation$aggregated)
```

### Example Output (Healthcare)

```
model_type        | combination                      | mean_test_r2 | rank
random_forest     | healthcare_data_quality_of_life  | 0.89         | 1
neural_network    | healthcare_data_quality_of_life  | 0.86         | 2
linear_regression | healthcare_data_quality_of_life  | 0.82         | 3
```

### Example Output (Manufacturing)

```
model_type        | combination                      | mean_test_r2 | rank
random_forest     | manufacturing_data_cycle_time    | 0.92         | 1
neural_network    | manufacturing_data_throughput    | 0.88         | 2
linear_regression | manufacturing_data_unit_cost     | 0.94         | 3
```

### Check Individual Person Models

```R
# Get models for cycle_time outcome
outcome_key <- "manufacturing_data_cycle_time"
rf_models <- results$models$random_forest[[outcome_key]]$models

# Check product type 1's model
product_1 <- rf_models[[1]]

cat("Product Type 1 Performance:\n")
cat(sprintf("  Training R²: %.3f\n", product_1$train_metrics$r_squared))
cat(sprintf("  Test R²: %.3f\n", product_1$test_metrics$r_squared))
cat(sprintf("  Predictors used: %d\n", product_1$n_predictors))
```

### Export Results

```R
# Results are automatically exported to output_directory/
# - model_comparison_aggregated.csv
# - model_rankings.csv
# - best_models.csv

# Load and view
comparison <- fread("my_results/model_comparison_aggregated.csv")
print(comparison)
```

---

## Advanced Features

### 1. Population-Level Predictions

Create population weights file (`my_weights.csv`):
```csv
person_idx,population_proportion
1,0.15
2,0.03
3,0.18
...
16,0.03
```

Update config:
```yaml
modeling:
  use_population_weights: true

population_weighting:
  weights_file: "my_weights.csv"
  person_id_column: "person_idx"
  weight_column: "population_proportion"
```

Generate predictions:
```R
# Load weights
pop_weights <- load_population_weights(config)

# Single scenario (manufacturing example)
scenario <- data.table(
  arrival_rate = 15,
  service_rate = 22,
  wip_inventory = 8,
  num_operations = 4,
  setup_time = 12,
  due_date_tightness = 0.5,
  machine_age = 4,
  maintenance_interval = 140,
  technician_availability = 0.85,
  supplier_lead_time = 4,
  inventory_level = 350,
  demand_variability = 0.22
)

# Population prediction
pop_pred <- predict_population(
  results$models$random_forest$manufacturing_data_cycle_time$models,
  scenario,
  pop_weights,
  "random_forest"
)

print(pop_pred$population_prediction)
```

### 2. Ensemble Predictions

```yaml
ensemble:
  enabled: true
  method: "weighted_average"  # or "simple_average", "median"
  weighting_metric: "mean_test_r2"
```

```R
# Calculate ensemble weights
weights <- calculate_ensemble_weights(
  results$evaluation$aggregated,
  metric = "mean_test_r2"
)

# Make ensemble prediction
ensemble_pred <- predict_population_ensemble(
  results$models,
  scenario,
  pop_weights,
  ensemble_method = "weighted_average",
  model_weights = weights
)
```

### 3. Hyperparameter Tuning

For better performance (slower):

```yaml
neural_network:
  tune_hyperparameters: true
  tune_size_grid: [3, 5, 10, 15]
  tune_decay_grid: [0.001, 0.01, 0.1]

random_forest:
  tune_hyperparameters: true
  tune_ntree_grid: [100, 300, 500]
  tune_mtry_grid: [2, 3, 4, 5]
```

### 4. Multiple Outcomes

Train separate models for each outcome:

```yaml
variables:
  outcomes:
    - "cycle_time"
    - "throughput"
    - "on_time_delivery"
    - "unit_cost"
```

Access results:
```R
# Cycle time models
ct_key <- "manufacturing_data_cycle_time"
rf_cycle <- results$models$random_forest[[ct_key]]

# Throughput models
tp_key <- "manufacturing_data_throughput"
rf_throughput <- results$models$random_forest[[tp_key]]
```

### 5. Scenario Comparison

```R
# Load scenarios
scenarios <- fread("examples/scenarios/manufacturing_scenarios.csv")

# Predict for all scenarios
predictions <- lapply(1:nrow(scenarios), function(i) {
  predict_population(
    results$models$random_forest$manufacturing_data_cycle_time$models,
    scenarios[i, ],
    pop_weights,
    "random_forest"
  )
})

# Find best scenario
cycle_times <- sapply(predictions, function(p) p$population_prediction)
best_idx <- which.min(cycle_times)  # minimize cycle time

cat("Best scenario for cycle time:\n")
print(scenarios[best_idx, ])
```

---

## Troubleshooting

### Low Test R²

**Problem:** Training R² = 0.95, Test R² = 0.45

**Causes:**
- Overfitting
- Too few test samples
- High noise in data

**Solutions:**
1. Use simpler models (try LR instead of RF)
2. Increase train/test ratio: `train_test_split: 0.85`
3. Enable regularization (higher `decay` for NN)
4. Collect more data

### Many Fallback Models

**Problem:** "80% of models are fallback"

**Causes:**
- Too few samples per person
- All predictors are constant for that person
- Outcome doesn't vary

**Solutions:**
1. Reduce `minimum_sample_size` in config
2. Check for constant predictors in data
3. Combine similar person types

### Model Training is Slow

**Solutions:**
1. Disable hyperparameter tuning initially
2. Train only one metamodel type first
3. Reduce number of outcomes
4. Use smaller `ntree` for Random Forest

---

## Best Practices

### 1. Start Simple
- Use manufacturing example first
- One metamodel type
- One outcome
- Small dataset

### 2. Validate Early
```R
results <- run_metamodeling_pipeline(
  config_file = "my_config.yaml",
  steps = c("load", "validate")  # Just validate first!
)
```

### 3. Compare Models
- Always train multiple types
- Check which performs best for YOUR data
- Different data = different best model

### 4. Check Assumptions
- Linear Regression: assumes linear relationships
- Neural Network: needs standardization (automatic)
- Random Forest: handles non-linearity well

### 5. Save Your Work
```yaml
modeling:
  save_models: true
  export_predictions: true
```

Models are saved automatically - you can load them later without retraining!

---

## Example Workflows

### Healthcare Comorbidity Analysis

```R
# 1. Run pipeline
results <- run_metamodeling_pipeline(
  config_file = "examples/healthcare/config_healthcare.yaml"
)

# 2. Load weights
pop_weights <- load_population_weights(config)

# 3. Compare intervention strategies
scenarios <- fread("examples/scenarios/healthcare_scenarios.csv")

qol_predictions <- sapply(1:nrow(scenarios), function(i) {
  pred <- predict_population(
    results$models$random_forest$healthcare_data_quality_of_life$models,
    scenarios[i, ],
    pop_weights,
    "random_forest"
  )
  pred$population_prediction
})

# 4. Find best intervention
best <- which.max(qol_predictions)
cat("Best intervention for quality of life:\n")
print(scenarios[best, ])
```

### Manufacturing Capacity Planning

```R
# 1. Run pipeline
results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml"
)

# 2. Test capacity scenarios
scenarios <- fread("examples/scenarios/manufacturing_scenarios.csv")

cycle_predictions <- sapply(1:nrow(scenarios), function(i) {
  pred <- predict_population(
    results$models$random_forest$manufacturing_data_cycle_time$models,
    scenarios[i, ],
    pop_weights,
    "random_forest"
  )
  pred$population_prediction
})

# 3. Find optimal configuration
best <- which.min(cycle_predictions)  # minimize cycle time
cat("Best configuration for cycle time:\n")
print(scenarios[best, ])
```

---

## Next Steps

After mastering this walkthrough:

1. **Batch 5:** Add SVR, Quadratic, Cubic Regression
2. **Batch 6:** Visualizations and Decision Trees
3. **Your Research:** Apply to your domain!

---

Need help? Check the example-specific READMEs or Batch documentation.
