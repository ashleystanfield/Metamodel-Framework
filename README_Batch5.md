# Batch 5: Advanced Metamodels

## Overview

Batch 5 adds three advanced metamodel types to the generalized metamodeling system:

1. **Support Vector Regression (SVR)** - Kernel-based non-linear regression
2. **Quadratic Regression (QR)** - Polynomial degree-2 regression
3. **Cubic Regression (CR)** - Polynomial degree-3 regression

These metamodels complement the foundational models from Batch 3 (Linear Regression, Neural Networks, Random Forests) by providing additional capabilities for capturing non-linear relationships in your data.

---

## What's New in Batch 5

### Files Added

```
R/
├── 09_metamodel_svr.R       # Support Vector Regression
├── 10_metamodel_qr.R        # Quadratic Regression
└── 11_metamodel_cr.R        # Cubic Regression

test_batch5.R                # Comprehensive test suite
README_Batch5.md             # This file
```

### Updates to Existing Files

- **main.R** - Integrated Batch 5 metamodels into pipeline
- **config.yaml** - Added configuration sections for SVR, QR, CR

---

## Metamodel Details

### 1. Support Vector Regression (SVR)

**Module:** `R/09_metamodel_svr.R`

**What it does:**
- Uses kernel methods to capture non-linear relationships
- Projects data into higher-dimensional space where linear regression works well
- Particularly effective for complex, non-linear patterns

**Key features:**
- Radial basis function (RBF) kernel
- Automatic data standardization (required for SVR)
- Hyperparameter tuning for cost and epsilon parameters
- Robust to outliers

**When to use:**
- Data has complex non-linear patterns
- You suspect non-linear relationships but don't know the functional form
- Data has outliers that affect other methods
- You want robust predictions

**Configuration:**

```yaml
metamodels:
  support_vector_regression:
    enabled: true
    kernel: "radial"  # Options: "radial", "linear", "polynomial"
    tune_hyperparameters: true
    tune_cost_grid: [0.1, 1, 10, 100]  # Regularization parameter
    tune_epsilon_grid: [0.01, 0.1, 0.5]  # Epsilon-insensitive zone
    save_models: true
    save_metrics: true
```

**Example usage:**

```R
# Enable SVR in config
config$metamodels$support_vector_regression$enabled <- TRUE

# Run pipeline
results <- run_metamodeling_pipeline(config_file = "config.yaml")

# Access SVR models
svr_models <- results$models$support_vector_regression

# Make predictions
new_data <- data.table(person_id = 1, x1 = 5.0, x2 = 10.0)
predictions <- predict_svr_new_data(svr_models$my_data_outcome$models,
                                   new_data, "person_id")
```

---

### 2. Quadratic Regression (QR)

**Module:** `R/10_metamodel_qr.R`

**What it does:**
- Extends linear regression with squared terms (x²) and interactions (x×y)
- Captures parabolic and U-shaped relationships
- Automatically expands features to include polynomial terms

**Key features:**
- Automatic feature expansion (x² and x×y terms)
- No data standardization required
- Fast training (uses linear regression on expanded features)
- Interpretable coefficients

**When to use:**
- You expect quadratic relationships (e.g., diminishing returns)
- Relationships show curvature in exploratory plots
- You want more flexibility than linear regression but simpler than neural networks
- You need interpretable coefficients

**Feature expansion example:**

Original predictors: `x1`, `x2`, `x3`

Expanded features:
- Original: `x1`, `x2`, `x3`
- Squared: `x1²`, `x2²`, `x3²`
- Interactions: `x1×x2`, `x1×x3`, `x2×x3`

Total: 9 features (3 + 3 + 3)

**Configuration:**

```yaml
metamodels:
  quadratic_regression:
    enabled: true
    include_interactions: true  # Include two-way interaction terms
    tune_hyperparameters: false
    save_models: true
    save_metrics: true
```

**Example usage:**

```R
# Enable QR in config
config$metamodels$quadratic_regression$enabled <- TRUE

# Run pipeline
results <- run_metamodeling_pipeline(config_file = "config.yaml")

# Access QR models
qr_models <- results$models$quadratic_regression

# Extract coefficients to see quadratic effects
coefs <- extract_qr_coefficients(qr_models$my_data_outcome$models)
print(coefs[term %like% "_sq"])  # View squared term coefficients
```

---

### 3. Cubic Regression (CR)

**Module:** `R/11_metamodel_cr.R`

**What it does:**
- Extends quadratic regression with cubic terms (x³) and higher-order interactions
- Captures S-shaped curves and more complex non-linear patterns
- Automatically expands features to include degree-3 polynomial terms

**Key features:**
- Automatic feature expansion (x², x³, x×y, x²×y, x×y×z terms)
- Configurable interaction terms (two-way and three-way)
- Automatic overfitting detection (too many features vs samples)
- Fallback to mean prediction when overfitting risk detected

**When to use:**
- Quadratic regression isn't flexible enough
- You see S-shaped or inflection-point patterns in data
- Relationships change direction multiple times
- You have sufficient data (cubic terms increase feature count dramatically)

**Feature expansion example:**

Original predictors: `x1`, `x2`

Expanded features (with two-way interactions, no three-way):
- Original: `x1`, `x2`
- Squared: `x1²`, `x2²`
- Cubic: `x1³`, `x2³`
- Two-way: `x1×x2`
- Squared interactions: `x1²×x2`, `x1×x2²`

Total: 9 features

**⚠️ Warning:** With 3 predictors and three-way interactions enabled, you can get 30+ features. This risks overfitting with small datasets.

**Configuration:**

```yaml
metamodels:
  cubic_regression:
    enabled: true
    include_two_way_interactions: true   # Include x×y terms
    include_three_way_interactions: false  # Include x×y×z (can overfit!)
    tune_hyperparameters: false
    save_models: true
    save_metrics: true
```

**Example usage:**

```R
# Enable CR in config
config$metamodels$cubic_regression$enabled <- TRUE
config$metamodels$cubic_regression$include_three_way_interactions <- FALSE  # Safer

# Run pipeline
results <- run_metamodeling_pipeline(config_file = "config.yaml")

# Access CR models
cr_models <- results$models$cubic_regression

# Check for fallback models (overfitting warning)
summary <- summarize_cr_results(cr_models)
print(summary[is_fallback == TRUE])
```

---

## Choosing the Right Metamodel

### Decision Guide

```
Data Relationship          → Recommended Metamodel
================================================================================
Linear                     → Linear Regression (LR)
Curved (parabolic)         → Quadratic Regression (QR)
S-shaped or complex curve  → Cubic Regression (CR) or Neural Network (NN)
Unknown/complex            → Support Vector Regression (SVR) or Random Forest (RF)
Need interpretability      → Linear, Quadratic, or Cubic Regression
Need flexibility           → Neural Network, Random Forest, or SVR
Have small dataset         → Linear or Quadratic Regression (fewer parameters)
Have large dataset         → Any model (more data = better performance)
```

### Performance Comparison

Based on typical use cases:

| Metamodel | Flexibility | Speed | Interpretability | Data Needs | Overfitting Risk |
|-----------|-------------|-------|------------------|------------|------------------|
| Linear Regression | Low | Fast | High | Low | Low |
| Quadratic Regression | Medium | Fast | Medium | Medium | Medium |
| Cubic Regression | High | Fast | Low | High | High |
| Support Vector Regression | Very High | Medium | Very Low | Medium | Medium |
| Neural Network | Very High | Slow | Very Low | High | High |
| Random Forest | Very High | Medium | Low | Medium | Low |

### Best Practices

**1. Always compare multiple models**
```R
# Enable several metamodels
config$metamodels$linear_regression$enabled <- TRUE
config$metamodels$quadratic_regression$enabled <- TRUE
config$metamodels$support_vector_regression$enabled <- TRUE
config$metamodels$random_forest$enabled <- TRUE

# Train all and compare
results <- run_metamodeling_pipeline(config_file = "config.yaml")

# Check which performs best
print(results$evaluation$best)
```

**2. Start simple, add complexity as needed**
```
Step 1: Linear Regression (baseline)
Step 2: If LR test R² < 0.7, try Quadratic Regression
Step 3: If QR test R² < 0.8, try SVR or Random Forest
Step 4: If still poor, try Neural Network or Cubic Regression
```

**3. Watch for overfitting**
```R
# Check train vs test R²
summary <- summarize_qr_results(qr_results)

# Large gap indicates overfitting
summary[, overfitting := train_r2 - test_r2]
summary[overfitting > 0.2]  # Concerning cases
```

**4. Use hyperparameter tuning for SVR**
```yaml
support_vector_regression:
  tune_hyperparameters: true  # Important for SVR!
  tune_cost_grid: [0.1, 1, 10, 100]
  tune_epsilon_grid: [0.01, 0.1, 0.5]
```

**5. Be cautious with cubic regression**
```yaml
cubic_regression:
  include_three_way_interactions: false  # Usually safer
  # Only enable if you have 50+ observations per person
```

---

## Running the Test Suite

Validate your Batch 5 installation:

```R
source("test_batch5.R")
```

The test suite checks:
- ✓ Feature expansion (quadratic and cubic)
- ✓ Single person training (all 3 metamodels)
- ✓ Multiple person training
- ✓ Prediction on new data
- ✓ Coefficient extraction
- ✓ Fallback model handling

Expected output:
```
================================================================================
                   ✓ ALL TESTS PASSED
================================================================================

Total tests:  12
Passed:       12 (100%)
Failed:       0
```

---

## Common Issues and Solutions

### Issue 1: SVR Training is Slow

**Problem:** SVR with hyperparameter tuning takes a long time

**Solutions:**
```yaml
# Option 1: Disable tuning for quick testing
support_vector_regression:
  tune_hyperparameters: false

# Option 2: Use smaller grid
support_vector_regression:
  tune_cost_grid: [1, 10]  # Instead of [0.1, 1, 10, 100]
  tune_epsilon_grid: [0.1]  # Instead of [0.01, 0.1, 0.5]
```

### Issue 2: Many Cubic Regression Fallback Models

**Problem:** CR reports "Too many features vs samples"

**Explanation:** Cubic regression creates many features. With 5 predictors and three-way interactions, you get 50+ features, which exceeds sample size for small datasets.

**Solutions:**
```yaml
# Option 1: Disable three-way interactions
cubic_regression:
  include_three_way_interactions: false

# Option 2: Use fewer predictors
variables:
  predictors:
    - "x1"  # Only use most important predictors
    - "x2"
    # Remove less important ones

# Option 3: Increase train_test_split to give more training data
modeling:
  train_test_split: 0.85  # Was 0.80
```

### Issue 3: Quadratic Regression Underperforms

**Problem:** QR test R² is lower than Linear Regression

**Explanation:** Your data may truly be linear, or quadratic terms are adding noise.

**Solutions:**
```yaml
# Try without interactions
quadratic_regression:
  include_interactions: false  # Only use x² terms, not x×y

# Or just use Linear Regression if it performs better
# The system will rank models by performance anyway
```

### Issue 4: SVR Predictions are All Similar

**Problem:** SVR predicts nearly identical values for different inputs

**Explanation:** Cost parameter may be too low, causing over-smoothing.

**Solutions:**
```yaml
support_vector_regression:
  tune_cost_grid: [10, 100, 1000]  # Try higher values
  # Higher cost = less regularization = more flexible model
```

---

## Integration with Batch 4 (Prediction & Evaluation)

All Batch 5 metamodels integrate seamlessly with Batch 4 features:

### Population-Level Prediction

```R
# Load population weights
pop_weights <- load_population_weights(config)

# Make population prediction with SVR
scenarios <- fread("scenarios.csv")
pop_pred <- predict_population(
  results$models$support_vector_regression$my_data_outcome$models,
  scenarios,
  pop_weights,
  "support_vector_regression"
)
```

### Ensemble Predictions

```R
# Calculate weights based on test R²
weights <- calculate_ensemble_weights(
  results$evaluation$aggregated,
  metric = "mean_test_r2"
)

# Ensemble includes SVR, QR, CR automatically
ensemble_pred <- predict_population_ensemble(
  results$models,
  scenarios,
  pop_weights,
  ensemble_method = "weighted_average",
  model_weights = weights
)
```

### Model Comparison

```R
# Compare all models (including Batch 5)
comparison <- results$evaluation$aggregated

# View by model type
comparison[order(-mean_test_r2)]

# Example output:
#   model_type                    mean_test_r2  rank
#   support_vector_regression     0.89          1
#   random_forest                 0.87          2
#   quadratic_regression          0.85          3
#   neural_network                0.83          4
#   cubic_regression              0.81          5
#   linear_regression             0.76          6
```

---

## Examples

### Example 1: Simple Comparison

```R
# Load config
config <- load_config("examples/simple/config_simple.yaml")

# Enable Batch 5 metamodels
config$metamodels$quadratic_regression$enabled <- TRUE
config$metamodels$cubic_regression$enabled <- TRUE
config$metamodels$support_vector_regression$enabled <- TRUE

# Run pipeline
results <- run_metamodeling_pipeline(config_file = "config.yaml")

# Check best model
print(results$evaluation$best)
```

### Example 2: SVR with Tuning

```R
# Create config with SVR focus
config <- load_config("config.yaml")

# Only enable SVR for focused testing
config$metamodels$linear_regression$enabled <- FALSE
config$metamodels$neural_network$enabled <- FALSE
config$metamodels$random_forest$enabled <- FALSE
config$metamodels$quadratic_regression$enabled <- FALSE
config$metamodels$cubic_regression$enabled <- FALSE
config$metamodels$support_vector_regression$enabled <- TRUE

# Enable hyperparameter tuning
config$metamodels$support_vector_regression$tune_hyperparameters <- TRUE

# Run
results <- run_metamodeling_pipeline(config_file = "config.yaml")

# Examine SVR results
summary <- summarize_svr_results(results$models$support_vector_regression)
print(summary)
```

### Example 3: Polynomial Progression

Compare how adding polynomial terms affects performance:

```R
# Test 1: Linear only
results_lr <- run_specific_metamodels("linear_regression", "config.yaml")
lr_r2 <- results_lr$evaluation$best$mean_test_r2[1]

# Test 2: Add quadratic
results_qr <- run_specific_metamodels("quadratic_regression", "config.yaml")
qr_r2 <- results_qr$evaluation$best$mean_test_r2[1]

# Test 3: Add cubic
results_cr <- run_specific_metamodels("cubic_regression", "config.yaml")
cr_r2 <- results_cr$evaluation$best$mean_test_r2[1]

# Compare
cat(sprintf("Linear:    R² = %.3f\n", lr_r2))
cat(sprintf("Quadratic: R² = %.3f (+%.3f)\n", qr_r2, qr_r2 - lr_r2))
cat(sprintf("Cubic:     R² = %.3f (+%.3f)\n", cr_r2, cr_r2 - qr_r2))
```

---

## Next Steps

After completing Batch 5:

1. **Batch 6**: Decision trees and visualizations
   - Decision tree classifier for intervention recommendations
   - R² heatmaps, joy plots, scatter plots
   - Variable importance charts

2. **Optimize your models**: Now that you have 6 metamodel types, experiment to find the best for your specific data

3. **Production use**: Deploy your best-performing models for your domain

---

## Additional Resources

- **Test file**: `test_batch5.R` - Comprehensive test suite
- **Example configs**: `examples/simple/config_simple.yaml`, `examples/healthcare/config_healthcare.yaml`
- **Batch 3 README**: `README_Batch3.md` - Foundational metamodels (LR, NN, RF)
- **Batch 4 README**: `README_Batch4.md` - Prediction and evaluation
- **Complete Walkthrough**: `tutorials/COMPLETE_WALKTHROUGH.md`

---

## Summary

**Batch 5 adds:**
- ✓ Support Vector Regression (SVR) - kernel-based non-linear regression
- ✓ Quadratic Regression (QR) - polynomial degree-2 regression
- ✓ Cubic Regression (CR) - polynomial degree-3 regression
- ✓ Automatic feature expansion for polynomial models
- ✓ Hyperparameter tuning for SVR
- ✓ Integration with existing pipeline
- ✓ Comprehensive test suite

**Total metamodel types available: 6**
1. Linear Regression (Batch 3)
2. Neural Network (Batch 3)
3. Random Forest (Batch 3)
4. Support Vector Regression (Batch 5)
5. Quadratic Regression (Batch 5)
6. Cubic Regression (Batch 5)

**Ready for Batch 6**: Decision trees and visualizations!
