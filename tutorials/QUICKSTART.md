# Quick Start Guide - 5 Minutes to Your First Model

## Prerequisites

```R
# Install required packages (one-time setup)
install.packages(c("data.table", "yaml", "nnet", "randomForest", "caret"))
```

## Fastest Path: Manufacturing Example

### 1. Navigate to Project

```R
setwd("C:/Users/ashle/Metamodel_Generalized")
```

### 2. Load and Run

```R
source("main.R")

results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml"
)
```

**That's it!** You've just trained 3 types of metamodels on 16 product types.

---

## What Just Happened?

The system:
1. Loaded `manufacturing_data.csv` (160 observations, 16 product types)
2. Split into train/test (75/25) for each of 16 product types
3. Trained Linear Regression models (16 person-specific models per outcome)
4. Trained Neural Network models (16 person-specific models per outcome)
5. Trained Random Forest models (16 person-specific models per outcome)
6. Evaluated all models on test data
7. Saved results to `results_manufacturing/`

**Total: 192 models trained automatically!** (16 product types x 4 outcomes x 3 model types)

---

## Check Your Results

### See Best Model

```R
print(results$evaluation$best)
```

Expected output:
```
  model_type     | outcome    | mean_test_r2 | rank
  random_forest  | cycle_time | 0.91         | 1
```

### See All Performance

```R
print(results$evaluation$aggregated)
```

### Access Individual Models

```R
# Get Random Forest model for product type 1, cycle_time
outcome_key <- "manufacturing_data_cycle_time"
rf_models <- results$models$random_forest[[outcome_key]]$models

# Check product type 1's model
product_1 <- rf_models[[1]]

cat("Product Type 1 Performance:\n")
cat(sprintf("  Training R²: %.3f\n", product_1$train_metrics$r_squared))
cat(sprintf("  Test R²: %.3f\n", product_1$test_metrics$r_squared))
```

---

## Output Files

Check `results_manufacturing/` directory:

```
results_manufacturing/
├── models/
│   ├── linear_regression/
│   ├── neural_network/
│   └── random_forest/
├── model_comparison_aggregated.csv
├── model_rankings.csv
└── best_models.csv
```

---

## Next Steps

### Try Different Steps

```R
# Just load and validate (no training)
results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml",
  steps = c("load", "validate")
)

# Full pipeline
results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml",
  steps = c("load", "validate", "train", "evaluate")
)
```

### Run Healthcare Example

```R
results_healthcare <- run_metamodeling_pipeline(
  config_file = "examples/healthcare/config_healthcare.yaml"
)
```

This example includes:
- 16 comorbidity profiles (all combinations of 4 chronic conditions)
- Population weighting by disease prevalence
- 4 health outcomes (quality of life, hospitalization risk, cost, mortality)
- Hyperparameter tuning enabled

---

## Common Quick Fixes

### Error: "File not found"

```R
# Make sure you're in the right directory
getwd()  # Should end in "Metamodel_Generalized"

# If not:
setwd("C:/Users/ashle/Metamodel_Generalized")
```

### Error: "Package not found"

```R
# Install missing package
install.packages("package_name")
```

### Want Faster Testing?

Edit config file to disable tuning and some metamodels:

```yaml
metamodels:
  linear_regression:
    enabled: true
  neural_network:
    enabled: false  # Turn off for speed
  random_forest:
    enabled: false  # Turn off for speed
```

---

## Understanding the Manufacturing Example

**Data:** 16 product types defined by complexity, volume, and priority:
- 4 complexity levels: Simple, Moderate, Complex, Custom
- 2 volume levels: Low, High
- 2 priority levels: Standard, Express

**Predictors (12):** Cover 4 queueing domains:
- Production line: arrival_rate, service_rate, wip_inventory
- Job shop: num_operations, setup_time, due_date_tightness
- Maintenance: machine_age, maintenance_interval, technician_availability
- Supply chain: supplier_lead_time, inventory_level, demand_variability

**Outcomes (4):**
- cycle_time (hours)
- throughput (units/day)
- on_time_delivery (proportion)
- unit_cost (dollars)

**Why Random Forest often wins:** Non-linear queueing relationships!

---

## What to Read Next

1. **Complete Walkthrough** (`tutorials/COMPLETE_WALKTHROUGH.md`)
   - Step-by-step with explanations
   - Using your own data
   - Advanced features

2. **Batch READMEs**
   - `README_Batch3.md` - Metamodel training details
   - `README_Batch4.md` - Population prediction & evaluation

3. **Example READMEs**
   - `examples/manufacturing/README.md`
   - `examples/healthcare/README.md`

---

## Troubleshooting

Still stuck? Check:

1. **All required packages installed?**
   ```R
   library(data.table)
   library(yaml)
   library(nnet)
   library(randomForest)
   ```

2. **Example files exist?**
   ```R
   file.exists("examples/manufacturing/manufacturing_data.csv")
   ```

3. **Config file valid?**
   ```R
   config <- yaml::read_yaml("examples/manufacturing/config_manufacturing.yaml")
   print(config$data$input_files)
   ```

---

**You're ready to go!** Run the manufacturing example and explore the results.
