# Generalized Metamodeling System - Batch 2 Complete ✅

## What Was Created in Batch 2

### New Modules

1. **`R/01_data_loader.R`** (~400 lines)
   - Generic CSV/RDS loading
   - Column name mapping
   - Data quality checks
   - Missing data handling
   - Auto-detection features

2. **`R/02_preprocessing.R`** (~450 lines)
   - Train/test splitting
   - Person-specific data extraction
   - Constant predictor detection
   - Data standardization
   - Validation functions

3. **`test_data_loading.R`** (~250 lines)
   - Comprehensive test suite
   - Verifies all Batch 2 functionality
   - 8 independent tests

### Updated Files

- **`main.R`** - Integrated data loading and preprocessing into pipeline

---

## Key Features Implemented

### 1. Generic Data Loading ✅

**Loads any CSV structure:**

```R
# Automatically loads all enabled files from config
data_list <- load_all_data(config)

# Returns named list:
# $lhs_patientnav
# $kmeans_mailedfit
# etc.
```

**Features:**
- Auto-detects file type (CSV, TXT, RDS)
- Handles any column names
- Reports loading errors gracefully
- Tracks data source

### 2. Column Mapping System ✅

**Your columns → Standard names**

```yaml
# In config.yaml
variables:
  column_mapping:
    enabled: true
    "screen_before": "FIT_baseline"  # Your name → Standard
    "screen_at": "FIT_intervention"
```

**No more hardcoded column names!**

### 3. Data Quality Checks ✅

Automatically reports:
- Dimensions (rows × columns)
- Number of person types
- Missing values (count and %)
- Which predictors/outcomes are present

```
▶ Data Quality Check:
  Dimensions: 1000 rows × 15 columns
  Person types: 180 unique values
  Missing values: 23 (0.15%)
  Predictors: 9/9 found ✓
  Outcomes: 7/7 found ✓
```

### 4. Missing Data Handling ✅

**Three strategies:**

```yaml
data:
  missing_data:
    strategy: "complete_cases"  # Remove rows with NA
    # OR
    strategy: "impute"           # Fill with median/mean
    imputation_method: "median"
    # OR
    strategy: "drop_variable"    # Remove columns with too many NA
```

### 5. Train/Test Splitting ✅

**Automatic 80/20 split (configurable):**

```R
split <- split_train_test(data, train_ratio = 0.8, seed = 42)

# Returns:
# $train - training data
# $test - test data
# $n_train - training sample count
# $n_test - test sample count
```

### 6. Person-Specific Processing ✅

**Prepares data for each person type:**

```R
person_data <- prepare_person_data(
  data = full_data,
  person_id = 1,
  predictors = c("x1", "x2", "x3"),
  outcome = "y"
)

# Returns:
# $train - person's training data
# $test - person's test data
# $predictors_used - non-constant predictors
# $constant_predictors - dropped predictors
# $outcome_is_constant - flag for degenerate cases
```

### 7. Constant Predictor Detection ✅

**Automatically detects and drops:**
- Predictors with only 1 unique value
- All-NA predictors
- Zero-variance predictors

```R
const_preds <- detect_constant_predictors(train_data, predictor_cols)
# Returns: c("predictor_that_never_changes")
```

**Logged for transparency:**
```
  ⚠ Person 42 has 2 constant predictors: screen_after, colo_after
```

### 8. Dataset Validation ✅

**Checks if data is suitable for modeling:**

```R
validation <- validate_person_dataset(person_data, min_samples = 2)

# Returns:
# $is_valid - TRUE/FALSE
# $reason - "Valid" or error message
```

**Catches problems:**
- Insufficient training samples
- No non-constant predictors
- Constant outcome (no variation)
- Missing data

### 9. Comprehensive Validation Reports ✅

**Summary across all person types:**

```R
validation <- validate_all_persons(person_datasets, config)

# Output:
# ▶ Validating person datasets...
#   Valid datasets: 175/180 (97.2%)
#
#   Reasons for invalid datasets:
#     • Insufficient training samples: 3
#     • No non-constant predictors: 2
```

---

## How to Use

### Step 1: Update Config

```yaml
data:
  input_files:
    - name: "my_experiment"
      path: "data/experiment_results.csv"
      enabled: true

  person_id_column: "person_id"

variables:
  predictors:
    - "x1"
    - "x2"
    - "x3"

  outcomes:
    - "y1"
    - "y2"
```

### Step 2: Test Data Loading

```R
# Run the test script
source("test_data_loading.R")
```

**Expected output:**
```
TEST 1: Loading configuration
✓ TEST 1 PASSED

TEST 2: Getting enabled input files
✓ TEST 2 PASSED

TEST 3: Loading data files
✓ TEST 3 PASSED

...

All basic tests completed!
```

### Step 3: Load Data in Pipeline

```R
source("main.R")

# Run only data loading
results <- run_metamodeling_pipeline(steps = c("load", "validate"))

# Check results
str(results$data_raw)
str(results$person_datasets)
```

---

## What Works Now

✅ **Data Loading**
- Load any CSV/RDS file
- Column mapping
- Quality checks
- Error handling

✅ **Preprocessing**
- Train/test splitting
- Person-specific extraction
- Constant predictor detection
- Missing data handling

✅ **Validation**
- Dataset suitability checks
- Comprehensive reports
- Problem identification

✅ **Integration**
- Works with main pipeline
- Configurable via YAML
- Extensive logging

---

## Example Workflows

### Minimal Example

```yaml
# config.yaml
project:
  name: "Quick_Test"
  working_directory: "."
  output_directory: "results"

data:
  input_files:
    - name: "test_data"
      path: "test.csv"
  person_id_column: "id"

variables:
  predictors: ["x1", "x2"]
  outcomes: ["y"]

modeling:
  train_test_split: 0.8
```

```R
# Run
source("main.R")
results <- run_metamodeling_pipeline(steps = c("load", "validate"))
```

### With Column Mapping

```yaml
variables:
  predictors:
    - "screen_before"
    - "screen_at"

  column_mapping:
    enabled: true
    "screen_before": "FIT_T0"     # Your CSV has "FIT_T0"
    "screen_at": "FIT_T1"          # Your CSV has "FIT_T1"
```

### Custom Missing Data Strategy

```yaml
data:
  missing_data:
    strategy: "impute"
    imputation_method: "median"
```

---

## Testing Your Data

### Run Tests

```R
source("test_data_loading.R")
```

### What Gets Tested

1. ✓ Config loading
2. ✓ File detection
3. ✓ Data loading (if files exist)
4. ✓ Quality checks
5. ✓ Train/test splitting
6. ✓ Constant predictor detection
7. ✓ Person-specific preparation
8. ✓ Dataset validation

### Interpreting Results

**All tests pass** → Ready for Batch 3!

**Some tests fail** → Check:
- File paths in config.yaml
- Column names match
- Required columns present
- Data types are numeric

---

## Common Issues & Solutions

### Issue: "File not found"

```
✗ TEST 3 FAILED: File not found: data/my_data.csv
```

**Solution:** Check paths in `config.yaml`
```yaml
data:
  input_files:
    - name: "my_data"
      path: "summaries_cache/summary_lhs_patientnav.csv"  # Full path
```

### Issue: "Missing required columns"

```
✗ Missing required columns: screen_before, screen_at
```

**Solution:** Enable column mapping
```yaml
variables:
  column_mapping:
    enabled: true
    "screen_before": "your_column_name"
```

### Issue: "Person ID column not found"

```
⚠ Person ID column 'person_idx' not found
```

**Solution:** Check column name
```yaml
data:
  person_id_column: "person_id"  # Match your actual column
```

### Issue: High missing data

```
Missing values: 5000 (25.00%)
```

**Solution:** Choose strategy
```yaml
data:
  missing_data:
    strategy: "complete_cases"  # or "impute" or "drop_variable"
```

---

## Data Structure Requirements

### Minimum Requirements

Your CSV must have:
1. **Person ID column** - Identifies different person types
2. **Predictor columns** - Numeric independent variables
3. **Outcome columns** - Numeric dependent variables

### Example CSV Structure

```csv
person_idx,x1,x2,x3,y1,y2
1,0.5,0.3,0.7,10.2,5.3
1,0.6,0.4,0.8,11.1,5.5
2,0.2,0.1,0.4,8.5,4.2
2,0.3,0.2,0.5,9.1,4.7
...
```

### Recommendations

- **Use descriptive column names** (config handles mapping)
- **Include person/group identifiers**
- **Numeric data** for predictors and outcomes
- **Reasonable sample sizes** (>10 rows per person type)

---

## What's Coming Next

### Batch 3: Core Metamodeling
- `03_metamodel_lr.R` - Linear regression training
- `04_metamodel_nn.R` - Neural network training
- `05_metamodel_rf.R` - Random forest training
- Person-specific model fitting
- Hyperparameter tuning
- Model persistence

### Integration

Batch 3 will use the `person_datasets` created in Batch 2:

```R
# From Batch 2
results$person_datasets  # Ready for training!

# In Batch 3
train_linear_regression(results$person_datasets, config)
train_neural_network(results$person_datasets, config)
# etc.
```

---

## File Sizes

- `01_data_loader.R`: ~15 KB
- `02_preprocessing.R`: ~16 KB
- `test_data_loading.R`: ~8 KB
- Updated `main.R`: +2 KB

**Batch 2 Total: ~41 KB of new code**
**Cumulative: ~68 KB**

---

## Progress Tracker

| Batch | Status | Lines Added |
|-------|--------|-------------|
| 1 | ✅ DONE | ~1,100 lines |
| **2** | ✅ **DONE** | ~1,100 lines |
| 3 | ⏳ Next | ~1,200 lines est. |
| 4 | ⏳ Pending | ~800 lines est. |
| 5 | ⏳ Pending | ~400 lines est. |
| 6 | ⏳ Pending | ~500 lines est. |

**Total so far: ~2,200 lines** of production-ready, documented code!

---

## Quick Start Checklist

- [x] Batch 1 complete (config system)
- [x] Batch 2 complete (data loading)
- [ ] Edit `config.yaml` with your file paths
- [ ] Run `test_data_loading.R`
- [ ] Verify all tests pass
- [ ] Ready for Batch 3!

---

**Batch 2 Status: ✅ COMPLETE**

Foundation + Data Loading are solid! Ready for metamodel training in Batch 3.

---

**Ready for Batch 3?** Say "Continue to Batch 3" when you're ready!
