# Healthcare Comorbidity Example

## Overview

This example demonstrates metamodeling for chronic disease management with comorbid conditions. It models 16 person types representing all possible combinations of four chronic conditions: diabetes, cardiovascular disease, mental health conditions, and chronic pain.

## Person Types (16 Comorbidity Profiles)

| person_idx | Conditions |
|------------|------------|
| 1 | Healthy baseline (no conditions) |
| 2 | Diabetes only |
| 3 | Cardiovascular only |
| 4 | Diabetes + Cardiovascular |
| 5 | Mental health only |
| 6 | Diabetes + Mental health |
| 7 | Cardiovascular + Mental health |
| 8 | Diabetes + Cardiovascular + Mental health |
| 9 | Chronic pain only |
| 10 | Diabetes + Chronic pain |
| 11 | Cardiovascular + Chronic pain |
| 12 | Diabetes + Cardiovascular + Chronic pain |
| 13 | Mental health + Chronic pain |
| 14 | Diabetes + Mental health + Chronic pain |
| 15 | Cardiovascular + Mental health + Chronic pain |
| 16 | All four conditions |

## Data Description

**File:** `healthcare_data.csv`

- **160 total observations** (10 per comorbidity profile)
- **16 person types** representing all 2^4 combinations of conditions
- **7 predictors** measuring intervention intensities and patient characteristics
- **4 outcomes** measuring health and economic impacts

### Predictors

| Variable | Range | Description |
|----------|-------|-------------|
| `diabetes_intervention` | 0-1 | Intensity of diabetes management (0 if not diabetic) |
| `cardio_intervention` | 0-1 | Intensity of cardiovascular treatment |
| `mental_intervention` | 0-1 | Intensity of mental health treatment |
| `pain_intervention` | 0-1 | Intensity of chronic pain management |
| `medication_adherence` | 0-1 | Overall medication adherence rate |
| `visit_frequency` | 1-12 | Healthcare visits per year |
| `lifestyle_score` | 0-100 | Diet, exercise, sleep composite score |

### Outcomes

| Variable | Range | Description |
|----------|-------|-------------|
| `quality_of_life` | 0-100 | SF-36 style composite score |
| `hospitalization_risk` | 0-1 | Probability of hospitalization in next year |
| `annual_cost` | dollars | Projected annual healthcare costs |
| `mortality_risk` | 0-1 | 5-year mortality probability |

## Data Generation Logic

The synthetic data follows realistic clinical relationships:

- **Comorbidity burden**: More conditions = higher baseline risk and costs
- **Intervention effectiveness**: Appropriate interventions improve outcomes
- **Adherence effects**: Higher adherence improves all outcomes
- **Lifestyle impact**: Better lifestyle scores correlate with better health
- **Interaction effects**: Interventions for present conditions have multiplicative benefits

Key relationships:
- Cardiovascular interventions have the largest impact on mortality
- Mental health and pain interventions have the largest impact on quality of life
- Poor adherence significantly increases hospitalization risk and costs

## Quick Start

```R
setwd("") #set to correct working directory with metamodel framework
source("main.R")

results <- run_metamodeling_pipeline(
  config_file = "examples/healthcare/config_healthcare.yaml"
)
```

## Expected Results

**Model Performance by Outcome:**

| Outcome | Best Model | Typical R² |
|---------|------------|------------|
| quality_of_life | Random Forest | 0.85-0.92 |
| hospitalization_risk | Neural Network | 0.82-0.88 |
| annual_cost | Random Forest | 0.88-0.94 |
| mortality_risk | Neural Network | 0.80-0.87 |

**Why non-linear models perform better:**
- Interaction effects between conditions
- Diminishing returns from interventions
- Threshold effects in risk factors

## Using Population Weights

Population weights reflect real-world comorbidity prevalence:

```R
# Load weights (automatically applied if enabled in config)
pop_weights <- load_population_weights(config)

# Predict population-level outcomes
scenario <- data.table(
  diabetes_intervention = 0.7,
  cardio_intervention = 0.7,
  mental_intervention = 0.6,
  pain_intervention = 0.6,
  medication_adherence = 0.8,
  visit_frequency = 6,
  lifestyle_score = 60
)

pop_pred <- predict_population(
  results$models$random_forest[[1]]$models,
  scenario,
  pop_weights,
  "random_forest"
)

print(pop_pred$population_prediction)
```

## Intervention Scenarios

The scenario file (`healthcare_scenarios.csv`) includes:

1. **Baseline**: Current standard of care
2. **Enhanced diabetes management**: Intensive glucose control
3. **Cardiovascular focus**: Aggressive risk factor management
4. **Mental health integration**: Enhanced psychiatric care
5. **Pain management program**: Multimodal pain intervention
6. **High adherence support**: Medication management programs
7. **Lifestyle intervention**: Intensive diet/exercise programs
8. **Comprehensive care**: All interventions at high intensity

## Clinical Interpretation

**Quality of Life Model:**
- Pain and mental health interventions have largest coefficients
- Lifestyle score is consistently important
- More conditions = lower baseline, but higher improvement potential

**Hospitalization Risk Model:**
- Cardiovascular interventions most protective
- Adherence is critical - poor adherence doubles risk
- Visit frequency shows U-shaped relationship

**Annual Cost Model:**
- Interventions add upfront cost but reduce hospitalization costs
- Poor adherence is most expensive (leads to complications)
- Optimal point: moderate-high intervention intensity

**Mortality Risk Model:**
- Cardiovascular status dominates predictions
- Diabetes control is second most important
- Lifestyle factors matter more for younger patients

## Output Files

Results saved to `results_healthcare/`:

```
results_healthcare/
├── models/
│   ├── linear_regression/
│   ├── neural_network/
│   └── random_forest/
├── model_comparison_aggregated.csv
├── model_rankings.csv
├── best_models.csv
└── population_predictions_*.csv
```

## Advanced Usage

### Compare Intervention Strategies

```R
# Load all scenarios
scenarios <- fread("examples/scenarios/healthcare_scenarios.csv")

# Predict for each scenario
predictions <- lapply(1:nrow(scenarios), function(i) {
  predict_population(
    results$models$random_forest$healthcare_data_quality_of_life$models,
    scenarios[i, ],
    pop_weights,
    "random_forest"
  )
})

# Find best strategy for quality of life
qol_predictions <- sapply(predictions, function(p) p$population_prediction)
best_scenario <- which.max(qol_predictions)
```

### Subgroup Analysis

```R
# Compare outcomes by condition burden
# Person types 1: 0 conditions, 2-5: 1 condition, 6-11: 2 conditions, etc.
condition_count <- c(0, rep(1, 4), rep(2, 6), rep(3, 4), 4)

# Get predictions stratified by burden
stratified_results <- lapply(0:4, function(n) {
  person_types <- which(condition_count == n)
  # Analyze predictions for these person types
})
```

## Files in This Example

| File | Description |
|------|-------------|
| `healthcare_data.csv` | Main dataset (160 rows) |
| `config_healthcare.yaml` | Pipeline configuration |
| `generate_healthcare_data.R` | Data generation script |
| `README.md` | This documentation |

## Related Files

| File | Location |
|------|----------|
| Population weights | `examples/population_weights/healthcare_weights.csv` |
| Intervention scenarios | `examples/scenarios/healthcare_scenarios.csv` |

## Next Steps

1. Modify intervention scenarios to test new strategies
2. Adjust population weights for different populations
3. Add additional predictors (age, sex, etc.)
4. Compare with manufacturing example for cross-domain learning
