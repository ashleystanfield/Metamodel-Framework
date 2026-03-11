# Metamodel Framework

A generalized framework for training individual-level metamodels from simulation outputs, generating population-level predictions, and supporting data-driven decision making. The framework trains separate models for each entity type (e.g., person, product), compares multiple metamodeling approaches, and aggregates predictions using population weights.

This framework accompanies the paper: *"AI Metamodeling for Population Health Prediction: A Case Study in Colorectal Cancer Prevention Planning."*

## Features

- **Six metamodel types**: Linear, Quadratic, and Cubic Regression, Support Vector Regression, Neural Network, and Random Forest
- **Person-specific models**: Trains a separate metamodel for each entity type, outcome, and discrete input combination
- **Automated comparison**: Ranks all metamodel types by R², RMSE, and MAE
- **Population-level prediction**: Aggregates individual predictions using demographic weights
- **Ensemble methods**: Combines predictions via simple averaging, weighted averaging, median, or stacking
- **Decision tree analysis**: Identifies which intervention minimizes a target metric based on input characteristics
- **Shiny web interface**: Interactive GUI for non-programmers
- **Configuration-driven**: Control the entire pipeline from a single YAML file — no R code changes needed

## Installation

**Requirements**: R 4.0.0 or higher

1. Clone the repository:
   ```bash
   git clone https://github.com/ashleystanfield/Metamodel-Framework.git
   cd Metamodel-Framework
   ```

2. Open R and run the setup script to install dependencies and validate your environment:
   ```r
   source("setup.R")
   ```

## Quick Start

Run one of the included examples (manufacturing or healthcare):

```r
source("run_example.R")

# Manufacturing example (queueing/operations)
run_manufacturing()

# Healthcare example (chronic disease comorbidities)
run_healthcare()

# Fast mode — Linear Regression only
run_manufacturing(fast = TRUE)
```

Results are saved to `results_manufacturing/` or `results_healthcare/`.

## Using Your Own Data

1. Prepare a CSV file where each row is one observation, with columns for:
   - An entity/person type identifier
   - Predictor variables (continuous inputs)
   - Outcome variables (simulation outputs)

2. Edit `config.yaml` to specify:
   - Your data file path(s)
   - Predictor, outcome, and demographic column names
   - Which metamodel types to enable
   - Train/test split, cross-validation, and hyperparameter settings

3. Run the pipeline:
   ```r
   source("main.R")
   results <- run_metamodeling_pipeline("config.yaml")
   ```

See `tutorials/COMPLETE_WALKTHROUGH.md` for a detailed guide.

## Included Examples

| Example | Entity Types | Predictors | Outcomes | Domain |
|---------|-------------|------------|----------|--------|
| **Manufacturing** | 16 product types (complexity, volume, priority) | 12 (arrival rate, service rate, setup time, etc.) | 4 (cycle time, throughput, on-time delivery, unit cost) | Queueing / Operations |
| **Healthcare** | 16 comorbidity profiles (4 chronic conditions) | 7 (intervention intensities, adherence, lifestyle) | 4 (quality of life, hospitalization risk, cost, mortality) | Chronic Disease Management |

Both examples include population weights and scenario files for population-level prediction.

## Shiny Web Interface

Launch the interactive GUI:

```r
shiny::runApp("shiny_app")
```

Upload data, configure metamodels, run the pipeline, and download results — all from a browser.

## Repository Structure

```
Metamodel-Framework/
├── main.R                    # Main pipeline entry point
├── setup.R                   # Installation and validation
├── run_example.R             # Quick example runners
├── config.yaml               # Configuration template
├── R/                        # Core R modules (config, data, models, evaluation)
├── examples/                 # Manufacturing and healthcare examples with data
├── shiny_app/                # Interactive web interface
├── tutorials/                # Quick start and complete walkthrough guides
├── output/                   # Default output directory
├── results_healthcare/       # Example healthcare results
└── results_manufacturing/    # Example manufacturing results
```

## Documentation

- **[Quick Start](tutorials/QUICKSTART.md)** — Get running in 5 minutes
- **[Complete Walkthrough](tutorials/COMPLETE_WALKTHROUGH.md)** — 30-minute comprehensive guide
- **[Examples & Tutorials](EXAMPLES_AND_TUTORIALS.md)** — Overview of all examples and learning paths

## Citation

If you use this framework in your research, please cite:

```
@article{stanfield2025metamodel,
  title={AI Metamodeling for Population Health Prediction: A Case Study in Colorectal Cancer Prevention Planning},
  author={Stanfield, Ashley and Mayorga, Maria and O'Leary, Meghan and Hassmiller-Lich, Kristen},
  year={2025}
}
```

## License

This project is released for academic and research use. See [LICENSE](LICENSE) for details.
