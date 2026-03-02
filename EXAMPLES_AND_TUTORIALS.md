# Examples and Tutorials - Complete Guide

## Quick Navigation

**Just want to get started fast?** → [Quick Start Tutorial](tutorials/QUICKSTART.md)

**Want to understand everything?** → [Complete Walkthrough](tutorials/COMPLETE_WALKTHROUGH.md)

**Need example data?** → See examples below

---

## Available Examples

### 1. Manufacturing Queueing Example (Recommended for First-Time Users)

**Location:** `examples/manufacturing/`

**What it is:**
- 16 product types based on queueing theory
- Combinations of complexity (Simple/Moderate/Complex/Custom), volume (Low/High), and priority (Standard/Express)
- 160 total observations (10 per product type)
- 12 predictors covering 4 queueing domains
- 4 outcomes (cycle time, throughput, on-time delivery, unit cost)

**Best for:**
- Learning the system
- Testing your installation
- Understanding person-specific modeling
- Quick validation that everything works
- Manufacturing/operations research applications

**Run it:**
```R
source("main.R")
results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml"
)
```

**Files:**
- `manufacturing_data.csv` - The dataset
- `config_manufacturing.yaml` - Configuration
- `generate_manufacturing_data.R` - Data generation script
- `README.md` - Detailed guide

---

### 2. Healthcare Comorbidity Example

**Location:** `examples/healthcare/`

**What it is:**
- 16 comorbidity profiles (all combinations of 4 chronic conditions)
- Conditions: Diabetes, Cardiovascular, Mental Health, Chronic Pain
- 160 total observations (10 per profile)
- 7 predictors (intervention intensities, adherence, lifestyle)
- 4 outcomes (quality of life, hospitalization risk, cost, mortality)
- Includes population weighting by prevalence

**Best for:**
- Understanding real-world healthcare applications
- Learning population-weighted predictions
- Multiple outcomes modeling
- Hyperparameter tuning practice
- Health economics and epidemiology applications

**Run it:**
```R
results <- run_metamodeling_pipeline(
  config_file = "examples/healthcare/config_healthcare.yaml"
)
```

**Files:**
- `healthcare_data.csv` - The dataset
- `config_healthcare.yaml` - Configuration
- `generate_healthcare_data.R` - Data generation script
- `README.md` - Detailed guide

---

## Example Comparison

| Feature | Manufacturing | Healthcare |
|---------|--------------|------------|
| Person types | 16 product types | 16 comorbidity profiles |
| Observations | 160 | 160 |
| Predictors | 12 | 7 |
| Outcomes | 4 | 4 |
| Domain | Operations/Queueing | Clinical/Epidemiology |
| Best model likely | Random Forest | Random Forest/NN |
| Population weights | Product mix | Disease prevalence |

---

## Supporting Files

### Population Weights

**Location:** `examples/population_weights/`

**Files:**
- `manufacturing_weights.csv` - Product mix weights (16 types)
- `healthcare_weights.csv` - Comorbidity prevalence weights (16 types)
- `README.md` - How to create your own

**Format:**
```csv
person_idx,population_proportion
1,0.15
2,0.03
3,0.18
...
```

Weights must sum to 1.0.

---

### Prediction Scenarios

**Location:** `examples/scenarios/`

**Files:**
- `manufacturing_scenarios.csv` - 10 capacity planning scenarios
- `healthcare_scenarios.csv` - 10 intervention scenarios
- `README.md` - How to create your own

**Format:**
Must include all predictor columns. Example:
```csv
scenario_id,arrival_rate,service_rate,...,scenario_type
1,12,18,...,"Current state baseline"
2,12,25,...,"Capacity expansion"
```

---

## Tutorials

### Quick Start (5 minutes)

**File:** `tutorials/QUICKSTART.md`

**Covers:**
- Minimum steps to run first example
- What each step does
- How to check results
- Quick troubleshooting

**Perfect for:** Getting running immediately

---

### Complete Walkthrough (30 minutes)

**File:** `tutorials/COMPLETE_WALKTHROUGH.md`

**Covers:**
- Preparing your own data
- Creating custom config files
- Running step-by-step
- Interpreting all results
- Advanced features:
  - Population predictions
  - Ensemble methods
  - Hyperparameter tuning
  - Multiple outcomes
- Best practices
- Troubleshooting

**Perfect for:** Deep understanding and using your own data

---

## Recommended Learning Path

### Path 1: Quick Learner (30 minutes)

1. Read [Quick Start](tutorials/QUICKSTART.md)
2. Run manufacturing example
3. Examine output files
4. Try healthcare example
5. You're ready for your own data!

### Path 2: Thorough Learner (2 hours)

1. Read [Quick Start](tutorials/QUICKSTART.md)
2. Run manufacturing example
3. Read [Complete Walkthrough](tutorials/COMPLETE_WALKTHROUGH.md)
4. Run healthcare example with modifications
5. Read relevant Batch READMEs:
   - `README_Batch3.md` - Training details
   - `README_Batch4.md` - Prediction & evaluation
6. Prepare your own data and config
7. Run on your data!

### Path 3: Expert Track (4+ hours)

1-6. Same as Thorough Learner
7. Read all example READMEs
8. Experiment with different configurations
9. Try all ensemble methods
10. Create custom population weights
11. Generate scenario grids
12. Explore model diagnostics
13. Master all features before production use

---

## Testing Your Installation

### Minimum Test (1 minute)

```R
setwd("C:/path/to/Metamodel_Generalized")
source("main.R")
source("test_data_loading.R")  # Should pass all tests
```

### Full Test (5 minutes)

```R
source("test_metamodels.R")     # Batch 3 tests
source("test_prediction.R")     # Batch 4 tests
```

### Example Test (2 minutes)

```R
results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml"
)

# Should complete without errors
# Check: results$evaluation$best
```

---

## File Organization

```
Metamodel_Generalized/
├── examples/
│   ├── manufacturing/
│   │   ├── manufacturing_data.csv
│   │   ├── config_manufacturing.yaml
│   │   ├── generate_manufacturing_data.R
│   │   └── README.md
│   ├── healthcare/
│   │   ├── healthcare_data.csv
│   │   ├── config_healthcare.yaml
│   │   ├── generate_healthcare_data.R
│   │   └── README.md
│   ├── population_weights/
│   │   ├── manufacturing_weights.csv
│   │   ├── healthcare_weights.csv
│   │   └── README.md
│   └── scenarios/
│       ├── manufacturing_scenarios.csv
│       ├── healthcare_scenarios.csv
│       └── README.md
├── tutorials/
│   ├── QUICKSTART.md
│   └── COMPLETE_WALKTHROUGH.md
└── EXAMPLES_AND_TUTORIALS.md (this file)
```

---

## Common Questions

**Q: Which example should I start with?**
A: Manufacturing example - it's comprehensive and demonstrates all features.

**Q: Do I need population weights?**
A: No, they're optional. Only needed for population-level aggregation.

**Q: Can I use the examples as templates for my data?**
A: Yes! Copy the configs and modify them for your data structure.

**Q: Which metamodel is best?**
A: Depends on your data! Run all three and compare. Random Forest often performs well for non-linear relationships.

**Q: How much data do I need?**
A: Minimum 10 observations per person type, 20+ recommended.

**Q: Can I have missing data?**
A: Yes, configure `missing_data` strategy in config.yaml

**Q: What's the difference between the two examples?**
A: Manufacturing focuses on queueing/operations; Healthcare focuses on clinical interventions. Both have 16 person types and 4 outcomes but different predictor domains.

---

## Next Steps After Examples

1. **Use your own data** - Follow Complete Walkthrough
2. **Add more metamodels** - Continue with Batch 5 (SVR, QR, CR)
3. **Add visualizations** - Continue with Batch 6
4. **Optimize performance** - Enable hyperparameter tuning
5. **Production use** - Add robust error handling for your domain

---

## Getting Help

1. **Check relevant README:**
   - Example-specific: `examples/*/README.md`
   - Batch-specific: `README_Batch*.md`
   - Feature-specific: `examples/population_weights/README.md`, etc.

2. **Run tests:**
   ```R
   source("test_data_loading.R")
   source("test_metamodels.R")
   source("test_prediction.R")
   ```

3. **Validate your config:**
   ```R
   config <- load_config("my_config.yaml")
   print_config_summary(config)
   ```

---

**Ready to start?** Open [Quick Start Tutorial](tutorials/QUICKSTART.md) and run your first model in 5 minutes!
