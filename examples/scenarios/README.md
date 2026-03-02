# Prediction Scenarios Examples

## Overview

Scenario files contain predictor values for generating predictions. Each row is a scenario to predict.

## File Format

**Required:**
- All predictor columns used in training must be present
- Column names must exactly match those in training data

**Optional:**
- `scenario_id` - Identifier for each scenario
- `intervention_type` / `scenario_type` - Description of the scenario
- These are ignored during prediction but helpful for interpretation

## Example Files

### healthcare_scenarios.csv

10 intervention scenarios for chronic disease management:

| Scenario | Description |
|----------|-------------|
| 1 | Baseline (current standard of care) |
| 2 | Enhanced diabetes management |
| 3 | Cardiovascular focus |
| 4 | Mental health integration |
| 5 | Pain management program |
| 6 | High adherence support |
| 7 | Lifestyle intervention |
| 8 | Comprehensive care (all high) |
| 9 | Cardio-diabetes priority |
| 10 | Mental health + Pain focus |

**Predictors:**
- `diabetes_intervention`, `cardio_intervention`, `mental_intervention`, `pain_intervention` (0-1)
- `medication_adherence` (0-1)
- `visit_frequency` (1-12)
- `lifestyle_score` (0-100)

### manufacturing_scenarios.csv

10 capacity planning scenarios for production optimization:

| Scenario | Description |
|----------|-------------|
| 1 | Current state baseline |
| 2 | Capacity expansion (+39% service rate) |
| 3 | Lean manufacturing (reduced WIP/setup) |
| 4 | Preventive maintenance focus |
| 5 | Supply chain optimization |
| 6 | Express prioritization shift |
| 7 | Volume increase (+50% arrival) |
| 8 | Full optimization (all improvements) |
| 9 | Simple products focus |
| 10 | Complex products emphasis |

**Predictors:**
- Production: `arrival_rate`, `service_rate`, `wip_inventory`
- Scheduling: `num_operations`, `setup_time`, `due_date_tightness`
- Maintenance: `machine_age`, `maintenance_interval`, `technician_availability`
- Supply chain: `supplier_lead_time`, `inventory_level`, `demand_variability`

## Usage

### Generate Population Predictions

```R
# Load scenarios
scenarios <- fread("examples/scenarios/healthcare_scenarios.csv")

# Generate predictions
predictions <- predict_population_scenarios(
  models = rf_models,
  scenarios = scenarios,
  population_weights = pop_weights,
  model_type = "random_forest"
)

# Result: scenarios + population_prediction column
print(predictions)
```

### Compare Scenarios

```R
# Find best scenario for quality of life
best_idx <- which.max(predictions$population_prediction)
best_scenario <- scenarios[best_idx, ]

cat("Best intervention scenario:\n")
print(best_scenario)
```

### Multi-Outcome Comparison

```R
# Healthcare: Compare all 4 outcomes
outcomes <- c("quality_of_life", "hospitalization_risk", "annual_cost", "mortality_risk")

scenario_comparison <- lapply(outcomes, function(outcome) {
  preds <- predict_population_scenarios(
    results$models$random_forest[[paste0("healthcare_data_", outcome)]]$models,
    scenarios,
    pop_weights,
    "random_forest"
  )
  data.table(outcome = outcome, scenario_id = 1:nrow(scenarios), prediction = preds$population_prediction)
})

comparison <- rbindlist(scenario_comparison)
dcast(comparison, scenario_id ~ outcome, value.var = "prediction")
```

## Creating Your Own Scenarios

### Method 1: Manual Entry

```R
library(data.table)

# Healthcare scenarios
scenarios <- data.table(
  diabetes_intervention = c(0.3, 0.7, 0.9),
  cardio_intervention = c(0.3, 0.7, 0.9),
  mental_intervention = c(0.3, 0.5, 0.7),
  pain_intervention = c(0.3, 0.5, 0.7),
  medication_adherence = c(0.6, 0.8, 0.9),
  visit_frequency = c(4, 6, 8),
  lifestyle_score = c(50, 65, 80),
  description = c("Low", "Medium", "High")
)

fwrite(scenarios, "my_healthcare_scenarios.csv")
```

### Method 2: Grid Generation

```R
# Create grid of all combinations
diabetes_levels <- c(0.3, 0.6, 0.9)
adherence_levels <- c(0.6, 0.75, 0.9)

grid <- expand.grid(
  diabetes_intervention = diabetes_levels,
  medication_adherence = adherence_levels
)

# Add fixed values for other predictors
grid$cardio_intervention <- 0.5
grid$mental_intervention <- 0.5
grid$pain_intervention <- 0.5
grid$visit_frequency <- 5
grid$lifestyle_score <- 60

fwrite(grid, "sensitivity_scenarios.csv")
```

### Method 3: Sample from Data

```R
# Use actual data values as scenarios
training_data <- fread("examples/healthcare/healthcare_data.csv")

# Sample unique predictor combinations
set.seed(42)
predictors <- c("diabetes_intervention", "cardio_intervention", "mental_intervention",
                "pain_intervention", "medication_adherence", "visit_frequency", "lifestyle_score")
scenarios <- unique(training_data[, ..predictors])[sample(.N, 20), ]

fwrite(scenarios, "sampled_scenarios.csv")
```

## Validation

Before using scenarios, verify:

1. **All predictors present:**
   ```R
   # For healthcare
   required_cols <- c("diabetes_intervention", "cardio_intervention", "mental_intervention",
                      "pain_intervention", "medication_adherence", "visit_frequency", "lifestyle_score")

   missing <- setdiff(required_cols, names(scenarios))
   if (length(missing) > 0) {
     stop("Missing columns: ", paste(missing, collapse=", "))
   }
   ```

2. **Values in reasonable range:**
   ```R
   summary(scenarios)

   # Check bounds
   stopifnot(all(scenarios$medication_adherence >= 0 & scenarios$medication_adherence <= 1))
   stopifnot(all(scenarios$visit_frequency >= 1 & scenarios$visit_frequency <= 12))
   ```

3. **No missing values:**
   ```R
   if (any(!complete.cases(scenarios))) {
     warning("Scenarios contain missing values")
   }
   ```

## Configuration

Reference scenarios in config:

```yaml
prediction:
  scenario_file: "examples/scenarios/healthcare_scenarios.csv"
  export_predictions_csv: true
```

## Output

Predictions include all input columns plus:
- `population_prediction` - Weighted population-level prediction
- `model_type` - Which metamodel was used

Example output:
```
scenario_id | diabetes_intervention | ... | population_prediction | model_type
1           | 0.30                  | ... | 72.5                  | random_forest
2           | 0.80                  | ... | 76.8                  | random_forest
...
```

## Scenario Analysis Tips

1. **Start with baseline**: Always include current state for comparison
2. **Test one factor at a time**: Isolate effects of individual changes
3. **Include extreme scenarios**: Test model behavior at boundaries
4. **Check feasibility**: Ensure scenarios are practically achievable
5. **Consider interactions**: Some improvements may be synergistic
