# Healthcare Comorbidity Example - Data Generation Script
# Generates synthetic data for 16 person types representing all combinations of 4 chronic conditions

set.seed(42)

# Define the 4 chronic conditions
# Each person type is a binary combination of: Diabetes, Cardiovascular, Mental Health, Chronic Pain
# person_idx 1-16 represents all 2^4 = 16 combinations

generate_healthcare_comorbidity_data <- function(n_per_type = 10) {

  # Condition flags for each person type (binary encoding)
  conditions <- expand.grid(
    diabetes = c(0, 1),
    cardiovascular = c(0, 1),
    mental_health = c(0, 1),
    chronic_pain = c(0, 1)
  )
  conditions$person_idx <- 1:16

  # Condition descriptions
  condition_names <- c(
    "Healthy baseline (no conditions)",
    "Diabetes only",
    "Cardiovascular only",
    "Diabetes + Cardiovascular",
    "Mental health only",
    "Diabetes + Mental health",
    "Cardiovascular + Mental health",
    "Diabetes + Cardiovascular + Mental health",
    "Chronic pain only",
    "Diabetes + Chronic pain",
    "Cardiovascular + Chronic pain",
    "Diabetes + Cardiovascular + Chronic pain",
    "Mental health + Chronic pain",
    "Diabetes + Mental health + Chronic pain",
    "Cardiovascular + Mental health + Chronic pain",
    "All four conditions"
  )

  # Count conditions per person type
  conditions$n_conditions <- with(conditions, diabetes + cardiovascular + mental_health + chronic_pain)

  # Generate data
  data_list <- list()

  for (i in 1:16) {
    cond <- conditions[i, ]

    for (obs in 1:n_per_type) {
      # Base characteristics vary by condition burden
      base_adherence <- 0.75 - 0.05 * cond$n_conditions + rnorm(1, 0, 0.08)
      base_lifestyle <- 65 - 8 * cond$n_conditions + rnorm(1, 0, 10)
      base_visits <- 2 + 1.5 * cond$n_conditions + rnorm(1, 0, 1)

      # Intervention intensities (0 if condition not present, otherwise vary)
      diabetes_int <- ifelse(cond$diabetes == 1, runif(1, 0.2, 0.9), 0)
      cardio_int <- ifelse(cond$cardiovascular == 1, runif(1, 0.2, 0.9), 0)
      mental_int <- ifelse(cond$mental_health == 1, runif(1, 0.2, 0.9), 0)
      pain_int <- ifelse(cond$chronic_pain == 1, runif(1, 0.2, 0.9), 0)

      # Clamp predictors
      medication_adherence <- pmax(0.1, pmin(0.99, base_adherence + rnorm(1, 0, 0.05)))
      visit_frequency <- pmax(1, pmin(12, round(base_visits + rnorm(1, 0, 0.5))))
      lifestyle_score <- pmax(10, pmin(95, base_lifestyle + rnorm(1, 0, 5)))

      # --- OUTCOMES ---

      # Quality of Life (0-100)
      # Base QoL decreases with conditions, but interventions help
      qol_base <- 85 - 12 * cond$n_conditions
      qol_intervention_effect <- 8 * (diabetes_int * cond$diabetes +
                                       cardio_int * cond$cardiovascular +
                                       mental_int * cond$mental_health * 1.2 +  # mental health has bigger QoL impact
                                       pain_int * cond$chronic_pain * 1.3)      # pain has biggest QoL impact
      qol_adherence_effect <- 15 * (medication_adherence - 0.5)
      qol_lifestyle_effect <- 0.2 * (lifestyle_score - 50)
      quality_of_life <- pmax(10, pmin(100,
                                        qol_base + qol_intervention_effect + qol_adherence_effect +
                                        qol_lifestyle_effect + rnorm(1, 0, 4)))

      # Hospitalization Risk (0-1)
      # Base risk increases with conditions, interventions and adherence reduce it
      hosp_base <- 0.05 + 0.08 * cond$n_conditions
      hosp_intervention_effect <- -0.05 * (diabetes_int * cond$diabetes +
                                            cardio_int * cond$cardiovascular * 1.5 +  # cardio interventions most protective
                                            mental_int * cond$mental_health +
                                            pain_int * cond$chronic_pain)
      hosp_adherence_effect <- -0.15 * (medication_adherence - 0.5)
      hosp_visit_effect <- -0.01 * (visit_frequency - 4)  # more visits = lower risk
      hospitalization_risk <- pmax(0.01, pmin(0.85,
                                               hosp_base + hosp_intervention_effect +
                                               hosp_adherence_effect + hosp_visit_effect + rnorm(1, 0, 0.03)))

      # Annual Cost (dollars)
      # Base cost increases with conditions, effective interventions are cost-efficient
      cost_base <- 3000 + 4500 * cond$n_conditions
      cost_intervention <- 2000 * (diabetes_int * cond$diabetes +
                                    cardio_int * cond$cardiovascular +
                                    mental_int * cond$mental_health +
                                    pain_int * cond$chronic_pain)
      # Poor adherence and more hospitalizations increase costs
      cost_adherence_penalty <- 5000 * (1 - medication_adherence)
      cost_hospitalization <- 25000 * hospitalization_risk
      cost_visits <- 150 * visit_frequency
      annual_cost <- pmax(1500, cost_base + cost_intervention + cost_adherence_penalty +
                           cost_hospitalization + cost_visits + rnorm(1, 0, 800))

      # Mortality Risk (5-year probability)
      # Base risk increases with conditions and age-proxy (lifestyle inversely related)
      mort_base <- 0.02 + 0.04 * cond$n_conditions
      mort_intervention_effect <- -0.025 * (diabetes_int * cond$diabetes +
                                             cardio_int * cond$cardiovascular * 1.8 +  # cardio most important
                                             mental_int * cond$mental_health * 0.5 +
                                             pain_int * cond$chronic_pain * 0.3)
      mort_adherence_effect <- -0.08 * (medication_adherence - 0.5)
      mort_lifestyle_effect <- -0.002 * (lifestyle_score - 50)
      mortality_risk <- pmax(0.005, pmin(0.6,
                                          mort_base + mort_intervention_effect +
                                          mort_adherence_effect + mort_lifestyle_effect + rnorm(1, 0, 0.015)))

      # Create row
      row <- data.frame(
        person_idx = i,
        diabetes_intervention = round(diabetes_int, 3),
        cardio_intervention = round(cardio_int, 3),
        mental_intervention = round(mental_int, 3),
        pain_intervention = round(pain_int, 3),
        medication_adherence = round(medication_adherence, 3),
        visit_frequency = visit_frequency,
        lifestyle_score = round(lifestyle_score, 1),
        quality_of_life = round(quality_of_life, 1),
        hospitalization_risk = round(hospitalization_risk, 3),
        annual_cost = round(annual_cost, 0),
        mortality_risk = round(mortality_risk, 4)
      )

      data_list[[length(data_list) + 1]] <- row
    }
  }

  # Combine all rows
  data <- do.call(rbind, data_list)

  return(data)
}

# Generate and save data
healthcare_data <- generate_healthcare_comorbidity_data(n_per_type = 10)

# Save to CSV
write.csv(healthcare_data,
          "examples/healthcare/healthcare_data.csv",
          row.names = FALSE)

cat("Generated healthcare comorbidity data:\n")
cat(sprintf("  Total rows: %d\n", nrow(healthcare_data)))
cat(sprintf("  Person types: %d\n", length(unique(healthcare_data$person_idx))))
cat(sprintf("  Observations per type: %d\n", nrow(healthcare_data) / 16))

# Print summary by condition burden
cat("\nSummary by comorbidity burden:\n")
healthcare_data$n_conditions <- ceiling(healthcare_data$person_idx / 4) - 1
aggregate(cbind(quality_of_life, hospitalization_risk, annual_cost, mortality_risk) ~
            cut(person_idx, breaks = c(0, 1, 5, 11, 15, 16),
                labels = c("0 conditions", "1 condition", "2 conditions", "3 conditions", "4 conditions")),
          data = healthcare_data, FUN = mean)
