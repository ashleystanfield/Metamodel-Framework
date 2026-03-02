# =============================================================================
# Metamodel Pipeline — Shiny GUI
# =============================================================================
# Launch with:  shiny::runApp("shiny_app")  from the project root
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(shinyWidgets)
  library(shinyjs)
  library(DT)
  library(yaml)
  library(data.table)
})

# Path to the pipeline root (one level up from shiny_app/)
PIPELINE_ROOT <- normalizePath(file.path(dirname(getwd()), ""), winslash = "/")
if (file.exists(file.path(getwd(), "main.R"))) {
  PIPELINE_ROOT <- normalizePath(getwd(), winslash = "/")
} else if (file.exists(file.path(dirname(getwd()), "main.R"))) {
  PIPELINE_ROOT <- normalizePath(dirname(getwd()), winslash = "/")
}

# Helpers -------------------------------------------------------------------

parse_numeric_vector <- function(text) {
  if (is.null(text) || trimws(text) == "") return(numeric(0))
  vals <- trimws(unlist(strsplit(text, ",")))
  suppressWarnings(as.numeric(vals))
}

parse_string_vector <- function(text) {
  if (is.null(text) || trimws(text) == "") return(character(0))
  trimws(unlist(strsplit(text, ",")))
}

safe_null <- function(x) if (is.null(x) || is.na(x) || x == "") NULL else x

# =============================================================================
# UI
# =============================================================================
ui <- navbarPage(
  title = "Metamodel Pipeline",
  id    = "main_nav",
  theme = NULL,

  header = tagList(useShinyjs()),

  # ─── Tab 1: Data & Variables ──────────────────────────────────────────────
  tabPanel("Data & Variables", value = "tab_data",
    fluidPage(
      h3("Project"),
      fluidRow(
        column(4, textInput("project_name", "Project Name", value = "CRC_Screening_Metamodels")),
        column(4, textInput("working_directory", "Working Directory", value = PIPELINE_ROOT)),
        column(4, textInput("output_directory", "Output Directory", value = "output"))
      ),

      hr(), h3("Data Files"),
      helpText("Upload CSVs or enter file paths on disk. Click 'Add File' for more."),
      div(id = "file_slots",
        # Slot 1 (always present)
        wellPanel(id = "file_panel_1",
          fluidRow(
            column(3, textInput("file_name_1", "Dataset Name", value = "dataset_1")),
            column(1, materialSwitch("file_enabled_1", "On", value = TRUE, status = "success")),
            column(4, textInput("file_path_1", "File Path (or leave blank to upload)", value = "")),
            column(4, fileInput("file_upload_1", "Upload CSV", accept = ".csv"))
          )
        )
      ),
      fluidRow(
        column(3, actionButton("add_file", "Add File", icon = icon("plus"), class = "btn-sm btn-info")),
        column(3, actionButton("remove_file", "Remove Last", icon = icon("minus"), class = "btn-sm btn-warning"))
      ),

      hr(), h3("Data Options"),
      fluidRow(
        column(3, textInput("person_id_column", "Person ID Column", value = "person_idx")),
        column(3, selectInput("missing_strategy", "Missing Data Strategy",
                              choices = c("complete_cases", "impute", "drop_variable"))),
        column(3, conditionalPanel("input.missing_strategy == 'impute'",
                   selectInput("imputation_method", "Imputation Method",
                               choices = c("median", "mean", "knn"))))
      ),

      hr(), h3("Variable Selection"),
      helpText("Columns are auto-detected after you load files. Select which are predictors, outcomes, and demographics."),
      fluidRow(
        column(4, pickerInput("predictors", "Predictor Variables", choices = NULL,
                              multiple = TRUE, options = list(`actions-box` = TRUE,
                              `live-search` = TRUE, `selected-text-format` = "count > 3"))),
        column(4, pickerInput("outcomes", "Outcome Variables", choices = NULL,
                              multiple = TRUE, options = list(`actions-box` = TRUE,
                              `live-search` = TRUE, `selected-text-format` = "count > 3"))),
        column(4, pickerInput("demographics", "Demographic Variables (optional)", choices = NULL,
                              multiple = TRUE, options = list(`actions-box` = TRUE,
                              `live-search` = TRUE, `selected-text-format` = "count > 3")))
      ),
      h4("Data Preview"),
      DT::dataTableOutput("data_preview")
    )
  ),

  # ─── Tab 2: Modeling ──────────────────────────────────────────────────────
  tabPanel("Modeling", value = "tab_modeling",
    fluidPage(
      h3("Training Parameters"),
      fluidRow(
        column(3, numericInput("random_seed", "Random Seed", value = 42, min = 1)),
        column(3, sliderInput("train_test_split", "Train / Test Split", min = 0.5, max = 0.95,
                              value = 0.8, step = 0.05)),
        column(3, materialSwitch("drop_constant", "Drop Constant Predictors", value = TRUE, status = "primary")),
        column(3, materialSwitch("save_models", "Save Trained Models", value = TRUE, status = "primary"))
      ),
      fluidRow(
        column(3, materialSwitch("export_predictions", "Export Predictions CSV", value = TRUE, status = "primary"))
      ),

      hr(), h3("Cross-Validation"),
      fluidRow(
        column(3, materialSwitch("cv_enabled", "Enable Cross-Validation", value = TRUE, status = "primary")),
        column(3, conditionalPanel("input.cv_enabled",
                   numericInput("cv_folds", "Number of Folds", value = 5, min = 2, max = 20)))
      ),

      hr(), h3("Parallel Processing"),
      fluidRow(
        column(3, materialSwitch("parallel_enabled", "Enable Parallel", value = FALSE, status = "primary")),
        column(3, conditionalPanel("input.parallel_enabled",
                   numericInput("parallel_cores", "Cores",
                                value = max(1, parallel::detectCores() - 1),
                                min = 1, max = parallel::detectCores())))
      )
    )
  ),

  # ─── Tab 3: Metamodels ───────────────────────────────────────────────────
  tabPanel("Metamodels", value = "tab_metamodels",
    fluidPage(
      h3("Enable / Configure Metamodels"),

      # LR
      wellPanel(
        fluidRow(
          column(4, materialSwitch("lr_enabled", "Linear Regression", value = TRUE, status = "success")),
          column(8, helpText("Standard OLS regression. No hyperparameters."))
        )
      ),

      # QR
      wellPanel(
        fluidRow(
          column(4, materialSwitch("qr_enabled", "Quadratic Regression", value = TRUE, status = "success")),
          column(8, conditionalPanel("input.qr_enabled",
            fluidRow(
              column(6, materialSwitch("qr_interactions", "Include Interactions", value = TRUE, status = "primary")),
              column(6, materialSwitch("qr_tune", "Tune Hyperparameters", value = FALSE, status = "primary"))
            )
          ))
        )
      ),

      # CR
      wellPanel(
        fluidRow(
          column(4, materialSwitch("cr_enabled", "Cubic Regression", value = TRUE, status = "success")),
          column(8, conditionalPanel("input.cr_enabled",
            fluidRow(
              column(4, materialSwitch("cr_two_way", "2-Way Interactions", value = TRUE, status = "primary")),
              column(4, materialSwitch("cr_three_way", "3-Way Interactions", value = FALSE, status = "primary")),
              column(4, materialSwitch("cr_tune", "Tune Hyperparameters", value = FALSE, status = "primary"))
            )
          ))
        )
      ),

      # SVR
      wellPanel(
        fluidRow(
          column(4, materialSwitch("svr_enabled", "Support Vector Regression", value = TRUE, status = "success")),
          column(8, conditionalPanel("input.svr_enabled",
            fluidRow(
              column(4, selectInput("svr_kernel", "Kernel", choices = c("radial", "linear", "polynomial"))),
              column(4, textInput("svr_cost_grid", "Cost Grid", value = "0.1, 1, 10, 100")),
              column(4, textInput("svr_epsilon_grid", "Epsilon Grid", value = "0.01, 0.1, 0.5"))
            ),
            materialSwitch("svr_tune", "Tune Hyperparameters", value = TRUE, status = "primary")
          ))
        )
      ),

      # NN
      wellPanel(
        fluidRow(
          column(4, materialSwitch("nn_enabled", "Neural Network", value = TRUE, status = "success")),
          column(8, conditionalPanel("input.nn_enabled",
            fluidRow(
              column(3, textInput("nn_size_grid", "Size Grid", value = "1, 3, 5, 10")),
              column(3, textInput("nn_decay_grid", "Decay Grid", value = "0, 0.0001, 0.001, 0.01")),
              column(3, numericInput("nn_max_iter", "Max Iterations", value = 500, min = 50)),
              column(3, numericInput("nn_max_weights", "Max Weights", value = 20000, min = 500))
            ),
            fluidRow(
              column(3, materialSwitch("nn_center", "Center Inputs", value = TRUE, status = "primary")),
              column(3, materialSwitch("nn_scale", "Scale Inputs", value = TRUE, status = "primary"))
            )
          ))
        )
      ),

      # RF
      wellPanel(
        fluidRow(
          column(4, materialSwitch("rf_enabled", "Random Forest", value = TRUE, status = "success")),
          column(8, conditionalPanel("input.rf_enabled",
            fluidRow(
              column(6, textInput("rf_mtry_grid", "mtry Grid", value = "2, 3, 4, 5, 6")),
              column(6, numericInput("rf_ntree", "Number of Trees", value = 500, min = 50, max = 10000))
            )
          ))
        )
      )
    )
  ),

  # ─── Tab 4: Ensemble & Population ────────────────────────────────────────
  tabPanel("Ensemble & Population", value = "tab_ensemble",
    fluidPage(
      h3("Ensemble Settings"),
      fluidRow(
        column(3, materialSwitch("ensemble_enabled", "Enable Ensemble", value = TRUE, status = "success")),
        column(4, conditionalPanel("input.ensemble_enabled",
                   selectInput("ensemble_method", "Method",
                               choices = c("simple_average", "weighted_average", "median", "stacking")))),
        column(4, conditionalPanel("input.ensemble_enabled && input.ensemble_method == 'weighted_average'",
                   selectInput("weighting_metric", "Weighting Metric",
                               choices = c("mean_test_r2", "mean_test_rmse"))))
      ),

      hr(), h3("Population Weighting"),
      fluidRow(
        column(3, materialSwitch("pop_weighting", "Use Population Weighting", value = FALSE, status = "success")),
        column(3, conditionalPanel("input.pop_weighting",
                   selectInput("pop_source", "Weight Source", choices = c("equal", "census", "file"))))
      ),
      conditionalPanel("input.pop_weighting && input.pop_source == 'file'",
        fluidRow(
          column(4, textInput("pop_weight_path", "Weight File Path", value = "")),
          column(4, fileInput("pop_weight_upload", "Or Upload Weights CSV", accept = ".csv"))
        )
      ),
      conditionalPanel("input.pop_weighting && input.pop_source == 'census'",
        wellPanel(
          h4("Census Demographics"),
          fluidRow(
            column(4, textInput("census_gender_cats", "Gender Categories", value = "male, female")),
            column(4, textInput("census_gender_props", "Gender Proportions", value = "0.48, 0.52"))
          ),
          fluidRow(
            column(4, textInput("census_race_cats", "Race Categories", value = "white, black, other")),
            column(4, textInput("census_race_props", "Race Proportions", value = "0.75, 0.13, 0.12"))
          ),
          fluidRow(
            column(4, textInput("census_age_cats", "Age Brackets", value = "45-49, 50-54, 55-59, 60-64, 65-69, 70-74")),
            column(4, textInput("census_age_props", "Age Proportions", value = "0.20, 0.19, 0.18, 0.16, 0.15, 0.12"))
          )
        )
      )
    )
  ),

  # ─── Tab 5: Interventions ────────────────────────────────────────────────
  tabPanel("Interventions", value = "tab_interventions",
    fluidPage(
      h3("Intervention Definitions"),
      helpText("Define intervention functions applied to predictors. Pre-populated with defaults."),
      div(id = "intervention_slots"),
      fluidRow(
        column(3, actionButton("add_intervention", "Add Intervention", icon = icon("plus"),
                               class = "btn-sm btn-info")),
        column(3, actionButton("remove_intervention", "Remove Last", icon = icon("minus"),
                               class = "btn-sm btn-warning"))
      )
    )
  ),

  # ─── Tab 6: Decision Tree & Visualization ────────────────────────────────
  tabPanel("Decision Tree & Viz", value = "tab_viz",
    fluidPage(
      h3("Decision Tree"),
      fluidRow(
        column(3, materialSwitch("dt_enabled", "Enable Decision Tree", value = TRUE, status = "success")),
        column(3, conditionalPanel("input.dt_enabled",
                   numericInput("dt_n_simulations", "Simulations", value = 1000, min = 100))),
        column(3, conditionalPanel("input.dt_enabled",
                   selectInput("dt_target_outcome", "Target Outcome", choices = NULL))),
        column(3, conditionalPanel("input.dt_enabled",
                   selectInput("dt_method", "Method", choices = c("rpart"))))
      ),

      hr(), h3("Visualizations"),
      fluidRow(
        column(3, materialSwitch("viz_enabled", "Enable Visualizations", value = TRUE, status = "success"))
      ),
      conditionalPanel("input.viz_enabled",
        fluidRow(
          column(3, materialSwitch("viz_r2_heatmap", "R-squared Heatmap", value = TRUE, status = "primary")),
          column(3, materialSwitch("viz_joy_plots", "Joy Plots", value = TRUE, status = "primary")),
          column(3, materialSwitch("viz_pop_estimates", "Population Estimates", value = TRUE, status = "primary")),
          column(3, materialSwitch("viz_decision_tree", "Decision Tree Plot", value = TRUE, status = "primary"))
        ),
        conditionalPanel("input.viz_r2_heatmap",
          fluidRow(
            column(3, numericInput("viz_r2_width", "Heatmap Width (in)", value = 12, min = 4)),
            column(3, numericInput("viz_r2_height", "Heatmap Height (in)", value = 8, min = 4))
          )
        )
      )
    )
  ),

  # ─── Tab 7: Run & Results ───────────────────────────────────────────────
  tabPanel("Run & Results", value = "tab_run",
    fluidPage(
      fluidRow(
        column(6,
          h3("Pipeline Control"),
          fluidRow(
            column(4, actionButton("preview_config", "Preview Config", icon = icon("eye"),
                                   class = "btn-info btn-lg")),
            column(4, actionButton("run_pipeline", "Run Pipeline", icon = icon("play"),
                                   class = "btn-success btn-lg")),
            column(4, downloadButton("download_config", "Download YAML", class = "btn-default btn-lg"))
          ),
          hr(),
          h4("Validation"),
          verbatimTextOutput("validation_output")
        ),
        column(6,
          h3("Status"),
          verbatimTextOutput("run_status")
        )
      ),

      hr(),
      tabsetPanel(id = "results_tabs",
        tabPanel("Config Preview", verbatimTextOutput("config_preview")),
        tabPanel("Console Log", verbatimTextOutput("run_log")),
        tabPanel("Metrics",
          DT::dataTableOutput("metrics_table")
        ),
        tabPanel("Best Models",
          DT::dataTableOutput("best_models_table")
        ),
        tabPanel("Computational Metrics",
          DT::dataTableOutput("comp_metrics_table")
        ),
        tabPanel("Plots",
          uiOutput("plot_gallery")
        ),
        tabPanel("Downloads",
          br(),
          downloadButton("download_results_zip", "Download All Results (ZIP)", class = "btn-primary btn-lg")
        )
      )
    )
  )
)

# =============================================================================
# SERVER
# =============================================================================
server <- function(input, output, session) {

  # ── Reactive state ────────────────────────────────────────────────────────
  file_count        <- reactiveVal(1L)
  uploaded_data     <- reactiveVal(list())    # name -> data.table
  file_paths_stable <- reactiveVal(list())    # name -> stable path on disk
  pipeline_results  <- reactiveVal(NULL)
  pipeline_proc     <- reactiveVal(NULL)
  run_log_text      <- reactiveVal("")
  intervention_count <- reactiveVal(0L)
  interventions_data <- reactiveVal(list())

  # ── All detected columns across loaded files ─────────────────────────────
  all_columns <- reactive({
    dl <- uploaded_data()
    if (length(dl) == 0) return(character(0))
    sort(unique(unlist(lapply(dl, names))))
  })

  # Update pickers when columns change
  observe({
    cols <- all_columns()
    updatePickerInput(session, "predictors",  choices = cols)
    updatePickerInput(session, "outcomes",    choices = cols)
    updatePickerInput(session, "demographics", choices = cols)
  })

  # Update decision tree target outcome when outcomes change
  observe({
    updateSelectInput(session, "dt_target_outcome", choices = input$outcomes)
  })

  # ── Dynamic file slot management ─────────────────────────────────────────
  observeEvent(input$add_file, {
    n <- file_count() + 1L
    file_count(n)
    insertUI(
      selector = "#file_slots",
      where    = "beforeEnd",
      ui = wellPanel(id = paste0("file_panel_", n),
        fluidRow(
          column(3, textInput(paste0("file_name_", n), "Dataset Name", value = paste0("dataset_", n))),
          column(1, materialSwitch(paste0("file_enabled_", n), "On", value = TRUE, status = "success")),
          column(4, textInput(paste0("file_path_", n), "File Path", value = "")),
          column(4, fileInput(paste0("file_upload_", n), "Upload CSV", accept = ".csv"))
        )
      )
    )
  })

  observeEvent(input$remove_file, {
    n <- file_count()
    if (n <= 1) return()
    removeUI(selector = paste0("#file_panel_", n))
    file_count(n - 1L)
  })

  # ── File loading (upload OR path) ────────────────────────────────────────
  observe({
    n <- file_count()
    for (i in seq_len(n)) {
      local({
        idx <- i
        upload_id <- paste0("file_upload_", idx)
        path_id   <- paste0("file_path_", idx)
        name_id   <- paste0("file_name_", idx)

        # Watch upload
        observeEvent(input[[upload_id]], {
          req(input[[upload_id]])
          # Copy to stable location
          stable_dir <- file.path(PIPELINE_ROOT, "shiny_app", "data")
          if (!dir.exists(stable_dir)) dir.create(stable_dir, recursive = TRUE)
          dest <- file.path(stable_dir, input[[upload_id]]$name)
          file.copy(input[[upload_id]]$datapath, dest, overwrite = TRUE)

          dt <- tryCatch(data.table::fread(dest, nrows = 5000), error = function(e) NULL)
          if (!is.null(dt)) {
            nm <- input[[name_id]]
            dl <- uploaded_data()
            dl[[nm]] <- dt
            uploaded_data(dl)
            fp <- file_paths_stable()
            fp[[nm]] <- normalizePath(dest, winslash = "/")
            file_paths_stable(fp)
          }
        }, ignoreInit = TRUE)
      })
    }
  })

  # Load from path when user finishes typing (debounced)
  observe({
    n <- file_count()
    for (i in seq_len(n)) {
      local({
        idx <- i
        path_id <- paste0("file_path_", idx)
        name_id <- paste0("file_name_", idx)

        observeEvent(input[[path_id]], {
          p <- input[[path_id]]
          if (is.null(p) || trimws(p) == "" || !file.exists(p)) return()
          dt <- tryCatch(data.table::fread(p, nrows = 5000), error = function(e) NULL)
          if (!is.null(dt)) {
            nm <- input[[name_id]]
            dl <- uploaded_data()
            dl[[nm]] <- dt
            uploaded_data(dl)
            fp <- file_paths_stable()
            fp[[nm]] <- normalizePath(p, winslash = "/")
            file_paths_stable(fp)
          }
        }, ignoreInit = TRUE)
      })
    }
  })

  # Data preview
  output$data_preview <- DT::renderDataTable({
    dl <- uploaded_data()
    if (length(dl) == 0) return(NULL)
    first <- dl[[1]]
    DT::datatable(head(first, 50), options = list(scrollX = TRUE, pageLength = 10))
  })

  # ── Default interventions ────────────────────────────────────────────────
  observe({
    if (intervention_count() == 0L) {
      defaults <- list(
        list(name = "mailedfit", enabled = TRUE, type = "custom_function",
             formula = "9.4103*x^3 - 7.6205*x^2 + 2.5342*x + 0.1506",
             input_var = "screen_before", output_var = "screen_at", bounds = "0, 1"),
        list(name = "reminders", enabled = TRUE, type = "piecewise",
             formula = "0.8212*x + 0.0592 if x <= 0.30; 1.006*x if x > 0.30",
             input_var = "screen_before", output_var = "screen_at", bounds = "0, 1"),
        list(name = "usualcare", enabled = TRUE, type = "identity",
             formula = "", input_var = "", output_var = "", bounds = "")
      )
      interventions_data(defaults)
      intervention_count(3L)
      for (k in seq_along(defaults)) {
        d <- defaults[[k]]
        insertUI(
          selector = "#intervention_slots", where = "beforeEnd",
          ui = wellPanel(id = paste0("int_panel_", k),
            fluidRow(
              column(2, textInput(paste0("int_name_", k), "Name", value = d$name)),
              column(1, materialSwitch(paste0("int_enabled_", k), "On", value = d$enabled, status = "success")),
              column(2, selectInput(paste0("int_type_", k), "Type",
                                    choices = c("custom_function", "piecewise", "identity"),
                                    selected = d$type)),
              column(3, textInput(paste0("int_formula_", k), "Formula / Segments", value = d$formula)),
              column(2, textInput(paste0("int_input_var_", k), "Input Var", value = d$input_var)),
              column(2, textInput(paste0("int_output_var_", k), "Output Var", value = d$output_var))
            )
          )
        )
      }
    }
  })

  observeEvent(input$add_intervention, {
    k <- intervention_count() + 1L
    intervention_count(k)
    insertUI(
      selector = "#intervention_slots", where = "beforeEnd",
      ui = wellPanel(id = paste0("int_panel_", k),
        fluidRow(
          column(2, textInput(paste0("int_name_", k), "Name", value = paste0("intervention_", k))),
          column(1, materialSwitch(paste0("int_enabled_", k), "On", value = TRUE, status = "success")),
          column(2, selectInput(paste0("int_type_", k), "Type",
                                choices = c("custom_function", "piecewise", "identity"))),
          column(3, textInput(paste0("int_formula_", k), "Formula / Segments", value = "")),
          column(2, textInput(paste0("int_input_var_", k), "Input Var", value = "")),
          column(2, textInput(paste0("int_output_var_", k), "Output Var", value = ""))
        )
      )
    )
  })

  observeEvent(input$remove_intervention, {
    k <- intervention_count()
    if (k <= 0) return()
    removeUI(selector = paste0("#int_panel_", k))
    intervention_count(k - 1L)
  })

  # ── Build config list from all inputs ────────────────────────────────────
  build_config <- reactive({

    # --- input files ---
    input_files <- list()
    for (i in seq_len(file_count())) {
      nm   <- input[[paste0("file_name_", i)]]
      en   <- input[[paste0("file_enabled_", i)]]
      fp   <- file_paths_stable()
      path <- if (!is.null(fp[[nm]])) fp[[nm]] else input[[paste0("file_path_", i)]]
      if (is.null(path) || trimws(path) == "") path <- ""
      input_files[[length(input_files) + 1]] <- list(name = nm, path = path, enabled = isTRUE(en))
    }

    # --- interventions ---
    interventions_cfg <- list()
    for (k in seq_len(intervention_count())) {
      iname   <- input[[paste0("int_name_", k)]]
      ienabled <- isTRUE(input[[paste0("int_enabled_", k)]])
      itype   <- input[[paste0("int_type_", k)]]
      iformula <- input[[paste0("int_formula_", k)]]
      iinput  <- input[[paste0("int_input_var_", k)]]
      ioutput <- input[[paste0("int_output_var_", k)]]

      int_entry <- list(enabled = ienabled, type = itype)
      if (itype == "custom_function") {
        int_entry$formula        <- iformula
        int_entry$input_variable <- iinput
        int_entry$output_variable <- ioutput
        int_entry$bounds         <- parse_numeric_vector(input[[paste0("int_bounds_", k)]] %||% "0,1")
      } else if (itype == "piecewise") {
        # Parse semicolon-separated segments
        segs <- trimws(unlist(strsplit(iformula, ";")))
        segments <- lapply(segs, function(s) {
          parts <- trimws(unlist(strsplit(s, " if ")))
          if (length(parts) == 2) list(formula = parts[1], condition = parts[2])
          else list(formula = s, condition = "TRUE")
        })
        int_entry$segments        <- segments
        int_entry$input_variable  <- iinput
        int_entry$output_variable <- ioutput
        int_entry$bounds          <- parse_numeric_vector("0,1")
      } else {
        int_entry$description <- "No intervention - baseline comparison"
      }
      if (!is.null(iname) && nchar(iname) > 0) {
        interventions_cfg[[iname]] <- int_entry
      }
    }

    # --- population ---
    pop_cfg <- list(use_weighting = isTRUE(input$pop_weighting))
    if (isTRUE(input$pop_weighting)) {
      pop_cfg$weights <- list(source = input$pop_source)
      if (input$pop_source == "file") {
        wp <- file_paths_stable()[["__pop_weights__"]]
        if (is.null(wp)) wp <- input$pop_weight_path
        pop_cfg$weights$file_path <- wp
      } else if (input$pop_source == "census") {
        pop_cfg$weights$demographics <- list(
          gender = list(
            categories = parse_string_vector(input$census_gender_cats),
            proportions = parse_numeric_vector(input$census_gender_props)
          ),
          race = list(
            categories = parse_string_vector(input$census_race_cats),
            proportions = parse_numeric_vector(input$census_race_props)
          ),
          age_brackets = list(
            categories = parse_string_vector(input$census_age_cats),
            proportions = parse_numeric_vector(input$census_age_props)
          )
        )
      }
    }

    # --- assemble ---
    list(
      project = list(
        name = input$project_name,
        description = "Generated by Shiny GUI",
        working_directory = input$working_directory,
        output_directory  = input$output_directory,
        log_file = "metamodel_log.txt"
      ),
      data = list(
        input_files      = input_files,
        person_id_column = input$person_id_column,
        n_persons        = NULL,
        missing_data = list(
          strategy           = input$missing_strategy,
          imputation_method  = if (input$missing_strategy == "impute") input$imputation_method else "median"
        )
      ),
      variables = list(
        predictors     = input$predictors,
        outcomes       = input$outcomes,
        demographics   = input$demographics,
        column_mapping = list(enabled = FALSE)
      ),
      modeling = list(
        random_seed              = input$random_seed,
        train_test_split         = input$train_test_split,
        drop_constant_predictors = isTRUE(input$drop_constant),
        save_models              = isTRUE(input$save_models),
        export_predictions       = isTRUE(input$export_predictions),
        use_population_weights   = isTRUE(input$pop_weighting),
        cross_validation = list(
          enabled = isTRUE(input$cv_enabled),
          n_folds = input$cv_folds
        ),
        parallel = list(
          enabled = isTRUE(input$parallel_enabled),
          n_cores = input$parallel_cores
        )
      ),
      metamodels = list(
        linear_regression = list(
          enabled      = isTRUE(input$lr_enabled),
          save_models  = TRUE,
          save_metrics = TRUE
        ),
        quadratic_regression = list(
          enabled              = isTRUE(input$qr_enabled),
          include_interactions = isTRUE(input$qr_interactions),
          tune_hyperparameters = isTRUE(input$qr_tune),
          save_models = TRUE, save_metrics = TRUE
        ),
        cubic_regression = list(
          enabled                      = isTRUE(input$cr_enabled),
          include_two_way_interactions = isTRUE(input$cr_two_way),
          include_three_way_interactions = isTRUE(input$cr_three_way),
          tune_hyperparameters         = isTRUE(input$cr_tune),
          save_models = TRUE, save_metrics = TRUE
        ),
        support_vector_regression = list(
          enabled              = isTRUE(input$svr_enabled),
          kernel               = input$svr_kernel,
          tune_hyperparameters = isTRUE(input$svr_tune),
          tune_cost_grid       = parse_numeric_vector(input$svr_cost_grid),
          tune_epsilon_grid    = parse_numeric_vector(input$svr_epsilon_grid),
          save_models = TRUE, save_metrics = TRUE
        ),
        neural_network = list(
          enabled = isTRUE(input$nn_enabled),
          hyperparameters = list(
            size_grid      = parse_numeric_vector(input$nn_size_grid),
            decay_grid     = parse_numeric_vector(input$nn_decay_grid),
            max_iterations = input$nn_max_iter,
            max_weights    = input$nn_max_weights
          ),
          preprocessing = list(
            center = isTRUE(input$nn_center),
            scale  = isTRUE(input$nn_scale)
          ),
          save_models = TRUE, save_metrics = TRUE, save_grid_search = TRUE
        ),
        random_forest = list(
          enabled = isTRUE(input$rf_enabled),
          hyperparameters = list(
            mtry_grid = parse_numeric_vector(input$rf_mtry_grid),
            ntree     = input$rf_ntree
          ),
          save_models = TRUE, save_metrics = TRUE, save_individual_predictions = TRUE
        )
      ),
      prediction = list(scenario_file = NULL, export_predictions_csv = TRUE),
      ensemble = list(
        enabled          = isTRUE(input$ensemble_enabled),
        method           = input$ensemble_method,
        weighting_metric = input$weighting_metric
      ),
      population    = pop_cfg,
      interventions = interventions_cfg,
      decision_tree = list(
        enabled               = isTRUE(input$dt_enabled),
        n_simulations         = input$dt_n_simulations,
        target_outcome        = input$dt_target_outcome,
        classification_method = input$dt_method
      ),
      visualizations = list(
        enabled = isTRUE(input$viz_enabled),
        plots = list(
          r2_heatmap = list(
            enabled     = isTRUE(input$viz_r2_heatmap),
            output_file = "r2_heatmap.png",
            width       = input$viz_r2_width,
            height      = input$viz_r2_height
          ),
          joy_plots = list(
            enabled     = isTRUE(input$viz_joy_plots),
            output_file = "r2_distributions.png"
          ),
          population_estimates = list(
            enabled     = isTRUE(input$viz_pop_estimates),
            output_file = "population_estimates.png"
          ),
          decision_tree = list(
            enabled     = isTRUE(input$viz_decision_tree),
            output_file = "decision_tree.png"
          )
        )
      ),
      output = list(
        naming = list(use_timestamps = FALSE, prefix = "metamodel"),
        save_models = TRUE, save_metrics = TRUE, save_predictions = TRUE,
        save_constants_log = TRUE, compress_models = FALSE
      ),
      computational_metrics = list(
        enabled = TRUE, track_wall_time = TRUE, track_cpu_time = TRUE,
        track_memory = TRUE, granularity = "step", save_to_csv = TRUE,
        print_summary = TRUE
      ),
      logging = list(verbose = TRUE, progress_bars = TRUE, log_to_file = TRUE, log_level = "INFO"),
      validation = list(
        validate_data = TRUE, validate_config = TRUE,
        warn_on_constant_predictors = TRUE, warn_on_missing_data = TRUE,
        warn_on_small_sample_size = TRUE, minimum_sample_size = 10,
        skip_missing_outcomes = TRUE
      )
    )
  })

  # ── Config preview ──────────────────────────────────────────────────────
  observeEvent(input$preview_config, {
    cfg <- build_config()
    output$config_preview <- renderText({
      yaml::as.yaml(cfg)
    })
    updateTabsetPanel(session, "results_tabs", selected = "Config Preview")
  })

  # ── Download config YAML ────────────────────────────────────────────────
  output$download_config <- downloadHandler(
    filename = function() "config.yaml",
    content  = function(file) {
      yaml::write_yaml(build_config(), file)
    }
  )

  # ── Input validation ────────────────────────────────────────────────────
  validate_inputs <- reactive({
    errs <- character(0)
    fp <- file_paths_stable()
    if (length(fp) == 0) errs <- c(errs, "No data files loaded.")
    if (is.null(input$predictors) || length(input$predictors) == 0)
      errs <- c(errs, "Select at least one predictor variable.")
    if (is.null(input$outcomes) || length(input$outcomes) == 0)
      errs <- c(errs, "Select at least one outcome variable.")
    any_mm <- isTRUE(input$lr_enabled) || isTRUE(input$qr_enabled) || isTRUE(input$cr_enabled) ||
              isTRUE(input$svr_enabled) || isTRUE(input$nn_enabled) || isTRUE(input$rf_enabled)
    if (!any_mm) errs <- c(errs, "Enable at least one metamodel.")
    errs
  })

  output$validation_output <- renderText({
    errs <- validate_inputs()
    if (length(errs) == 0) "All checks passed." else paste("Issues:", paste(errs, collapse = "\n  "))
  })

  # ── Run pipeline ───────────────────────────────────────────────────────
  observeEvent(input$run_pipeline, {
    errs <- validate_inputs()
    if (length(errs) > 0) {
      showNotification(paste(errs, collapse = "\n"), type = "error", duration = 8)
      return()
    }

    shinyjs::disable("run_pipeline")
    pipeline_results(NULL)
    run_log_text("Pipeline starting...\n")

    # Write config
    cfg <- build_config()
    config_path <- file.path(PIPELINE_ROOT, "shiny_app", "config_shiny.yaml")
    yaml::write_yaml(cfg, config_path)

    stdout_log <- file.path(PIPELINE_ROOT, "shiny_app", "pipeline_stdout.log")
    stderr_log <- file.path(PIPELINE_ROOT, "shiny_app", "pipeline_stderr.log")

    # Try callr first, fall back to synchronous
    if (requireNamespace("callr", quietly = TRUE)) {

      proc <- callr::r_bg(
        function(config_path, root_dir) {
          setwd(root_dir)
          source("main.R", local = TRUE)
          run_metamodeling_pipeline(config_path)
        },
        args   = list(config_path = normalizePath(config_path, winslash = "/"),
                      root_dir    = PIPELINE_ROOT),
        stdout = stdout_log,
        stderr = stderr_log
      )
      pipeline_proc(proc)

    } else {
      # Synchronous fallback
      withProgress(message = "Running pipeline...", {
        log_out <- capture.output({
          tryCatch({
            old_wd <- getwd()
            setwd(PIPELINE_ROOT)
            source("main.R", local = TRUE)
            res <- run_metamodeling_pipeline(normalizePath(config_path, winslash = "/"))
            pipeline_results(res)
            setwd(old_wd)
          }, error = function(e) {
            showNotification(paste("Pipeline error:", e$message), type = "error", duration = 15)
            setwd(old_wd)
          })
        })
        run_log_text(paste(log_out, collapse = "\n"))
      })
      shinyjs::enable("run_pipeline")
    }
  })

  # ── Poll background process ─────────────────────────────────────────────
  observe({
    proc <- pipeline_proc()
    if (is.null(proc)) return()
    invalidateLater(2000)

    stdout_log <- file.path(PIPELINE_ROOT, "shiny_app", "pipeline_stdout.log")
    if (file.exists(stdout_log)) {
      run_log_text(paste(readLines(stdout_log, warn = FALSE), collapse = "\n"))
    }

    if (!proc$is_alive()) {
      tryCatch({
        res <- proc$get_result()
        pipeline_results(res)
        showNotification("Pipeline completed successfully!", type = "message", duration = 10)
      }, error = function(e) {
        showNotification(paste("Pipeline failed:", e$message), type = "error", duration = 15)
        stderr_log <- file.path(PIPELINE_ROOT, "shiny_app", "pipeline_stderr.log")
        if (file.exists(stderr_log)) {
          err_text <- paste(readLines(stderr_log, warn = FALSE), collapse = "\n")
          run_log_text(paste0(run_log_text(), "\n\n=== ERRORS ===\n", err_text))
        }
      })
      pipeline_proc(NULL)
      shinyjs::enable("run_pipeline")
    }
  })

  # ── Status display ─────────────────────────────────────────────────────
  output$run_status <- renderText({
    proc <- pipeline_proc()
    if (!is.null(proc) && proc$is_alive()) {
      "Pipeline is RUNNING..."
    } else if (!is.null(pipeline_results())) {
      "Pipeline COMPLETED."
    } else {
      "Ready."
    }
  })

  output$run_log <- renderText({ run_log_text() })

  # ── Results tables ─────────────────────────────────────────────────────
  output$metrics_table <- DT::renderDataTable({
    req(pipeline_results())
    res <- pipeline_results()
    if (!is.null(res$evaluation$aggregated)) {
      DT::datatable(as.data.frame(res$evaluation$aggregated),
                    options = list(scrollX = TRUE, pageLength = 20))
    }
  })

  output$best_models_table <- DT::renderDataTable({
    req(pipeline_results())
    res <- pipeline_results()
    if (!is.null(res$evaluation$best)) {
      DT::datatable(as.data.frame(res$evaluation$best),
                    options = list(scrollX = TRUE, pageLength = 20))
    }
  })

  output$comp_metrics_table <- DT::renderDataTable({
    req(pipeline_results())
    res <- pipeline_results()
    if (!is.null(res$comp_metrics_summary)) {
      DT::datatable(as.data.frame(res$comp_metrics_summary),
                    options = list(scrollX = TRUE))
    }
  })

  # ── Plot gallery (load PNGs from output directory) ──────────────────────
  output$plot_gallery <- renderUI({
    req(pipeline_results())
    viz_dir <- file.path(PIPELINE_ROOT, input$output_directory, "visualizations")
    if (!dir.exists(viz_dir)) {
      viz_dir <- file.path(PIPELINE_ROOT, input$output_directory)
    }
    pngs <- list.files(viz_dir, pattern = "\\.png$", full.names = TRUE)
    if (length(pngs) == 0) return(h4("No plots found in output directory."))

    plot_tags <- lapply(pngs, function(p) {
      tagList(
        h4(tools::file_path_sans_ext(basename(p))),
        tags$img(src = paste0("data:image/png;base64,",
                              base64enc::base64encode(p)),
                 style = "max-width:100%; border:1px solid #ddd; margin-bottom:20px;")
      )
    })
    do.call(tagList, plot_tags)
  })

  # ── Download all results as ZIP ─────────────────────────────────────────
  output$download_results_zip <- downloadHandler(
    filename = function() paste0("metamodel_results_", format(Sys.Date(), "%Y%m%d"), ".zip"),
    content  = function(file) {
      out_dir <- file.path(PIPELINE_ROOT, input$output_directory)
      if (!dir.exists(out_dir)) {
        showNotification("Output directory not found.", type = "error")
        return()
      }
      files_to_zip <- list.files(out_dir, recursive = TRUE, full.names = TRUE)
      zip(file, files = files_to_zip)
    }
  )

  # ── Pop weights upload ──────────────────────────────────────────────────
  observeEvent(input$pop_weight_upload, {
    req(input$pop_weight_upload)
    stable_dir <- file.path(PIPELINE_ROOT, "shiny_app", "data")
    if (!dir.exists(stable_dir)) dir.create(stable_dir, recursive = TRUE)
    dest <- file.path(stable_dir, input$pop_weight_upload$name)
    file.copy(input$pop_weight_upload$datapath, dest, overwrite = TRUE)
    fp <- file_paths_stable()
    fp[["__pop_weights__"]] <- normalizePath(dest, winslash = "/")
    file_paths_stable(fp)
  })
}

# =============================================================================
# Launch
# =============================================================================
shinyApp(ui = ui, server = server)
