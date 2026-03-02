# Population Weights Examples

## Overview

Population weights are used to aggregate person-specific predictions to population-level estimates. Each person type is weighted by their proportion in the target population.

## File Format

**Required columns:**
- `person_idx` - Person type identifier (must match data file)
- `population_proportion` - Weight for this person type (should sum to 1.0)

**Optional columns:**
- `comorbidity_description` / `product_description` - Human-readable description
- Any other metadata columns

## Example Files

### healthcare_weights.csv

Weights based on comorbidity prevalence in the general population:
- 16 person types (all combinations of 4 chronic conditions)
- Healthy individuals have highest weight (0.42)
- Comorbidities decrease with more conditions
- Reflects realistic disease co-occurrence patterns

| Condition Count | Example Types | Total Weight |
|-----------------|---------------|--------------|
| 0 conditions | Type 1 | 0.42 |
| 1 condition | Types 2-5, 9 | 0.30 |
| 2 conditions | Types 4, 6-7, 10-11, 13 | 0.17 |
| 3 conditions | Types 8, 12, 14-15 | 0.08 |
| 4 conditions | Type 16 | 0.01 |

### manufacturing_weights.csv

Weights based on typical product mix in manufacturing:
- 16 product types (complexity x volume x priority)
- High-volume standard products have highest weights
- Express priority products have lower weights (premium service)
- Simple products dominate typical production

| Product Category | Weight Range | Notes |
|------------------|--------------|-------|
| Simple products | 0.03-0.18 | Highest for high-volume standard |
| Moderate products | 0.02-0.12 | Bulk of mid-tier production |
| Complex products | 0.02-0.08 | Specialized manufacturing |
| Custom products | 0.02-0.06 | Lower volume, higher margin |

## How Weights Are Used

**Population prediction formula:**
```
population_pred = Σ(person_pred[i] × weight[i])
```

**Example with healthcare weights:**
```R
# Quality of life predictions by comorbidity profile
person_predictions = c(
  type_1 = 87.2,   # healthy
  type_2 = 74.8,   # diabetes only
  type_3 = 75.2,   # cardiovascular only
  ...
  type_16 = 56.8   # all conditions
)

# Weighted by prevalence
weights = c(0.42, 0.08, 0.07, 0.04, 0.06, ...)

# Population-level quality of life
population_qol = sum(person_predictions * weights)
```

## Creating Your Own Weights

### From Prevalence Data

```R
library(data.table)

# Example: Comorbidity prevalence from health survey
prevalence <- data.table(
  person_idx = 1:16,
  condition_pattern = c("none", "diabetes", "cardio", ...),
  prevalence_rate = c(0.45, 0.10, 0.08, ...)  # from survey
)

# Normalize to sum to 1.0
prevalence[, population_proportion := prevalence_rate / sum(prevalence_rate)]

# Save
fwrite(prevalence[, .(person_idx, population_proportion)],
       "my_healthcare_weights.csv")
```

### From Production Data

```R
# Example: Product mix from last year's orders
product_mix <- data.table(
  person_idx = 1:16,
  product_type = c("Simple-Low-Std", "Simple-Low-Exp", ...),
  annual_units = c(150000, 25000, 180000, ...)
)

# Calculate proportions
product_mix[, population_proportion := annual_units / sum(annual_units)]

# Save
fwrite(product_mix[, .(person_idx, population_proportion)],
       "my_manufacturing_weights.csv")
```

### Equal Weights (No Weighting)

```R
n_persons <- 16

equal_weights <- data.table(
  person_idx = 1:n_persons,
  population_proportion = 1/n_persons
)

fwrite(equal_weights, "equal_weights.csv")
```

## Validation

Weights should:
1. **Sum to 1.0** (or very close due to rounding)
2. **All be positive** (no negative weights)
3. **Match person IDs** in your data file
4. **Cover all person types** in your dataset

```R
# Validation check
weights <- fread("my_weights.csv")
stopifnot(abs(sum(weights$population_proportion) - 1.0) < 0.001)
stopifnot(all(weights$population_proportion > 0))
```

## Usage in Config

```yaml
modeling:
  use_population_weights: true

population_weighting:
  weights_file: "examples/population_weights/healthcare_weights.csv"
  person_id_column: "person_idx"
  weight_column: "population_proportion"
```

## Sensitivity Analysis

Test how results change with different weight assumptions:

```R
# Scenario 1: Equal weights (no demographic adjustment)
weights_equal <- rep(1/16, 16)

# Scenario 2: Emphasize high-risk groups
weights_risk <- original_weights
weights_risk[12:16] <- weights_risk[12:16] * 2
weights_risk <- weights_risk / sum(weights_risk)

# Compare predictions
pred_original <- sum(person_preds * original_weights)
pred_equal <- sum(person_preds * weights_equal)
pred_risk <- sum(person_preds * weights_risk)
```

## Common Issues

**Issue:** "Population weights don't sum to 1.0"
- **Solution:** Normalize them: `weight[i] / sum(weights)`

**Issue:** "Missing weights for person X"
- **Solution:** Ensure weights file includes all person IDs in data

**Issue:** "Weights file not found"
- **Solution:** Check file path in config is correct (relative to working directory)
