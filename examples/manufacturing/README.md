# Manufacturing Queueing Example

## Overview

This example demonstrates metamodeling for manufacturing operations using queueing theory principles. It models 16 product types representing different combinations of complexity, volume, and priority levels, with predictors spanning four key queueing domains: production line, job shop scheduling, maintenance, and supply chain.

## Product Types (16 Categories)

| person_idx | Complexity | Volume | Priority | Description |
|------------|------------|--------|----------|-------------|
| 1 | Simple | Low | Standard | Basic products, low demand |
| 2 | Simple | Low | Express | Basic products, rush orders |
| 3 | Simple | High | Standard | Basic products, mass production |
| 4 | Simple | High | Express | Basic products, high-priority mass |
| 5 | Moderate | Low | Standard | Mid-complexity, low demand |
| 6 | Moderate | Low | Express | Mid-complexity, rush orders |
| 7 | Moderate | High | Standard | Mid-complexity, mass production |
| 8 | Moderate | High | Express | Mid-complexity, high-priority mass |
| 9 | Complex | Low | Standard | Complex products, custom work |
| 10 | Complex | Low | Express | Complex products, expedited |
| 11 | Complex | High | Standard | Complex products, scale production |
| 12 | Complex | High | Express | Complex products, premium service |
| 13 | Custom | Low | Standard | Fully custom, small batch |
| 14 | Custom | Low | Express | Fully custom, urgent |
| 15 | Custom | High | Standard | Custom at scale |
| 16 | Custom | High | Express | Custom premium service |

## Data Description

**File:** `manufacturing_data.csv`

- **160 total observations** (10 per product type)
- **16 product types** (complexity x volume x priority combinations)
- **12 predictors** covering all 4 queueing domains
- **4 outcomes** measuring operational performance

### Predictors by Domain

**Production Line:**
| Variable | Units | Description |
|----------|-------|-------------|
| `arrival_rate` | units/hour | Incoming work rate |
| `service_rate` | units/hour | Processing capacity |
| `wip_inventory` | units | Work-in-progress queue length |

**Job Shop Scheduling:**
| Variable | Units | Description |
|----------|-------|-------------|
| `num_operations` | count | Number of processing steps (1-10) |
| `setup_time` | minutes | Changeover time between jobs |
| `due_date_tightness` | 0-1 | How tight the deadline is |

**Maintenance:**
| Variable | Units | Description |
|----------|-------|-------------|
| `machine_age` | years | Equipment age |
| `maintenance_interval` | hours | Time between scheduled maintenance |
| `technician_availability` | 0-1 | Repair resource availability |

**Supply Chain:**
| Variable | Units | Description |
|----------|-------|-------------|
| `supplier_lead_time` | days | Input material lead time |
| `inventory_level` | units | Raw material buffer stock |
| `demand_variability` | 0-1 | Demand uncertainty coefficient |

### Outcomes

| Variable | Units | Description |
|----------|-------|-------------|
| `cycle_time` | hours | Total time from start to finish |
| `throughput` | units/day | Daily output rate |
| `on_time_delivery` | 0-1 | Proportion delivered on time |
| `unit_cost` | dollars | Cost per unit produced |

## Queueing Theory Background

The data generation follows established queueing theory relationships:

**Little's Law:** L = λW
- L = average number in system (WIP)
- λ = arrival rate
- W = average time in system (cycle time)

**Traffic Intensity:** ρ = λ/μ
- λ = arrival rate
- μ = service rate
- System stability requires ρ < 1

**Key Relationships:**
- Higher arrival rate → longer queues → longer cycle times
- Service rate must exceed arrival rate for stability
- Express priority reduces cycle time but increases cost
- Complex products require more operations and longer setup times

## Quick Start

```R
setwd("") #set to correct working directory
source("main.R")

results <- run_metamodeling_pipeline(
  config_file = "examples/manufacturing/config_manufacturing.yaml"
)
```

## Expected Results

**Model Performance by Outcome:**

| Outcome | Best Model | Typical R² |
|---------|------------|------------|
| cycle_time | Random Forest | 0.88-0.95 |
| throughput | Neural Network | 0.85-0.92 |
| on_time_delivery | Random Forest | 0.78-0.85 |
| unit_cost | Linear Regression | 0.90-0.96 |

**Why different models excel:**
- **Cycle time**: Non-linear queueing effects favor RF
- **Throughput**: Complex interactions favor NN
- **On-time delivery**: Multiple threshold effects favor RF
- **Unit cost**: Largely additive cost components favor LR

## Using Population Weights

Weights represent product mix in a typical manufacturing plant:

```R
# Load weights
pop_weights <- load_population_weights(config)

# Predict plant-level outcomes for a scenario
scenario <- data.table(
  arrival_rate = 15,
  service_rate = 20,
  wip_inventory = 10,
  num_operations = 4,
  setup_time = 15,
  due_date_tightness = 0.5,
  machine_age = 5,
  maintenance_interval = 150,
  technician_availability = 0.85,
  supplier_lead_time = 5,
  inventory_level = 300,
  demand_variability = 0.25
)

pop_pred <- predict_population(
  results$models$random_forest[[1]]$models,
  scenario,
  pop_weights,
  "random_forest"
)

print(pop_pred$population_prediction)
```

## Capacity Planning Scenarios

The scenario file (`manufacturing_scenarios.csv`) includes:

1. **Current state**: Baseline operations
2. **Capacity expansion**: Increased service rate
3. **Lean manufacturing**: Reduced WIP, shorter setup times
4. **Preventive maintenance**: More frequent maintenance, newer equipment
5. **Supply chain optimization**: Shorter lead times, higher inventory
6. **Express prioritization**: Shift toward express processing
7. **Volume increase**: Higher arrival rates
8. **Full optimization**: All improvements combined

## Operational Interpretation

**Cycle Time Model:**
- WIP inventory is strongest predictor (Little's Law)
- Service rate inversely related
- Setup time adds linearly per operation
- Express priority provides ~30% reduction

**Throughput Model:**
- Service rate is primary driver
- Technician availability critical for utilization
- Maintenance interval affects downtime
- Volume (high vs low) affects economies of scale

**On-Time Delivery Model:**
- Due date tightness is primary driver (tighter = harder)
- Demand variability reduces reliability
- Express priority improves OTD
- Supply chain reliability matters for complex products

**Unit Cost Model:**
- Complexity is strongest driver
- Express priority adds premium
- High volume provides discount
- Setup time and operations add labor cost

## Output Files

Results saved to `results_manufacturing/`:

```
results_manufacturing/
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

### Capacity Planning Analysis

```R
# Evaluate impact of increasing service rate
service_rates <- seq(15, 30, by = 2.5)

capacity_analysis <- lapply(service_rates, function(sr) {
  scenario <- data.table(
    arrival_rate = 15,
    service_rate = sr,
    wip_inventory = 10,
    num_operations = 4,
    setup_time = 15,
    due_date_tightness = 0.5,
    machine_age = 5,
    maintenance_interval = 150,
    technician_availability = 0.85,
    supplier_lead_time = 5,
    inventory_level = 300,
    demand_variability = 0.25
  )

  pred <- predict_population(
    results$models$random_forest$manufacturing_data_cycle_time$models,
    scenario,
    pop_weights,
    "random_forest"
  )

  list(service_rate = sr, cycle_time = pred$population_prediction)
})

# Plot capacity vs cycle time tradeoff
```

### Product Mix Optimization

```R
# Compare outcomes across product types
product_predictions <- lapply(1:16, function(pt) {
  # Get model for this product type
  model <- results$models$random_forest$manufacturing_data_unit_cost$models[[pt]]

  # Predict for standard scenario
  predict(model$model, scenario)
})

# Find most profitable product mix
```

## Files in This Example

| File | Description |
|------|-------------|
| `manufacturing_data.csv` | Main dataset (160 rows) |
| `config_manufacturing.yaml` | Pipeline configuration |
| `generate_manufacturing_data.R` | Data generation script |
| `README.md` | This documentation |

## Related Files

| File | Location |
|------|----------|
| Population weights | `examples/population_weights/manufacturing_weights.csv` |
| Planning scenarios | `examples/scenarios/manufacturing_scenarios.csv` |

## Next Steps

1. Adjust scenarios for your specific manufacturing context
2. Modify weights to match your product mix
3. Add additional predictors (labor cost, energy prices, etc.)
4. Compare with healthcare example for cross-domain insights
