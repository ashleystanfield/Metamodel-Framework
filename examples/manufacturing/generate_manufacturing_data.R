# Manufacturing Queueing Example - Data Generation Script
# Generates synthetic data for 16 product types based on queueing theory

set.seed(42)

# Product types: 2^4 = 16 combinations of:
# - Complexity: Simple, Moderate, Complex, Custom (2 bits encoded)
# - Volume: Low, High (1 bit)
# - Priority: Standard, Express (1 bit)

generate_manufacturing_queueing_data <- function(n_per_type = 10) {

  # Define product types
  product_types <- data.frame(
    person_idx = 1:16,
    complexity = rep(c("Simple", "Simple", "Moderate", "Moderate",
                       "Complex", "Complex", "Custom", "Custom"), each = 2),
    volume = rep(c("Low", "High"), 8),
    priority = rep(c("Standard", "Express"), 8)
  )

  # Complexity factors
  complexity_factor <- c(Simple = 1, Moderate = 1.5, Complex = 2.5, Custom = 3.5)

  data_list <- list()

  for (i in 1:16) {
    prod <- product_types[i, ]
    cf <- complexity_factor[prod$complexity]
    is_high_volume <- prod$volume == "High"
    is_express <- prod$priority == "Express"

    for (obs in 1:n_per_type) {

      # --- PRODUCTION LINE PREDICTORS ---
      # Arrival rate: higher for high volume, varies by complexity
      base_arrival <- ifelse(is_high_volume, 25, 10)
      arrival_rate <- round(base_arrival / cf + rnorm(1, 0, 2), 1)
      arrival_rate <- pmax(2, arrival_rate)

      # Service rate: depends on complexity and equipment
      base_service <- 15 / cf
      service_rate <- round(base_service + rnorm(1, 0, 1.5), 1)
      service_rate <- pmax(arrival_rate + 1, service_rate)  # ensure stability

      # WIP inventory: related to traffic intensity (rho = arrival/service)
      rho <- arrival_rate / service_rate
      wip_base <- arrival_rate * rho / (1 - rho + 0.1)  # M/M/1 approximation
      wip_inventory <- round(pmax(1, wip_base + rnorm(1, 0, 3)))

      # --- JOB SHOP SCHEDULING PREDICTORS ---
      # Number of operations: more for complex products
      num_operations <- round(pmax(1, pmin(10, 2 * cf + rnorm(1, 0, 0.8))))

      # Setup time: longer for complex products and express priority
      setup_base <- 10 * cf
      setup_adjustment <- ifelse(is_express, -5, 0)  # express has faster setup
      setup_time <- round(pmax(5, setup_base + setup_adjustment + rnorm(1, 0, 5)), 1)

      # Due date tightness: express has tighter deadlines
      ddt_base <- ifelse(is_express, 0.75, 0.45)
      due_date_tightness <- round(pmin(0.95, pmax(0.15, ddt_base + rnorm(1, 0, 0.1))), 2)

      # --- MAINTENANCE PREDICTORS ---
      # Machine age: varies (older machines for standard products)
      age_base <- ifelse(is_express, 3, 6)
      machine_age <- round(pmax(0.5, age_base + rnorm(1, 0, 2)), 1)

      # Maintenance interval: shorter for complex, longer for simple
      maint_base <- 200 / cf
      maintenance_interval <- round(pmax(50, maint_base + rnorm(1, 0, 30)))

      # Technician availability: higher for express priority
      tech_base <- ifelse(is_express, 0.9, 0.75)
      technician_availability <- round(pmin(0.99, pmax(0.5, tech_base + rnorm(1, 0, 0.08))), 2)

      # --- SUPPLY CHAIN PREDICTORS ---
      # Supplier lead time: longer for custom/complex
      lead_base <- 3 * cf
      supplier_lead_time <- round(pmax(1, lead_base + rnorm(1, 0, 2)), 1)

      # Inventory level: higher for high volume production
      inv_base <- ifelse(is_high_volume, 500, 150)
      inventory_level <- round(pmax(50, inv_base + rnorm(1, 0, 50)))

      # Demand variability: higher for custom products
      var_base <- 0.2 + 0.1 * (cf - 1)
      demand_variability <- round(pmin(0.9, pmax(0.1, var_base + rnorm(1, 0, 0.08))), 2)

      # --- OUTCOMES ---

      # Cycle time (hours): Based on Little's Law and queueing theory
      # L = lambda * W => W = L / lambda
      processing_time <- num_operations * (60 / service_rate)  # minutes per operation
      queue_time <- wip_inventory * (60 / service_rate)
      setup_total <- setup_time * num_operations
      express_speedup <- ifelse(is_express, 0.7, 1.0)
      cycle_time <- round((processing_time + queue_time + setup_total) / 60 * express_speedup +
                           rnorm(1, 0, 0.5), 1)
      cycle_time <- pmax(0.5, cycle_time)

      # Throughput (units/day): service rate adjusted for maintenance and availability
      effective_capacity <- service_rate * technician_availability * 8  # 8-hour shift
      maint_downtime_factor <- 1 - (8 / maintenance_interval)  # fraction lost to maintenance
      throughput <- round(pmax(5, effective_capacity * pmax(0.7, maint_downtime_factor) +
                                rnorm(1, 0, 5)))

      # On-time delivery (proportion): depends on due date tightness and cycle time predictability
      baseline_otd <- 0.85
      tightness_penalty <- -0.3 * due_date_tightness
      variability_penalty <- -0.2 * demand_variability
      express_bonus <- ifelse(is_express, 0.1, 0)
      on_time_delivery <- round(pmin(0.99, pmax(0.5,
                                                 baseline_otd + tightness_penalty + variability_penalty +
                                                 express_bonus + rnorm(1, 0, 0.05))), 3)

      # Unit cost (dollars): complexity drives cost, express is premium
      material_cost <- 20 * cf
      labor_cost <- (setup_time + processing_time / num_operations) * 0.5
      overhead <- 15 * cf
      express_premium <- ifelse(is_express, 25, 0)
      volume_discount <- ifelse(is_high_volume, -10, 0)
      unit_cost <- round(material_cost + labor_cost + overhead + express_premium +
                          volume_discount + rnorm(1, 0, 5), 2)
      unit_cost <- pmax(20, unit_cost)

      # Create row
      row <- data.frame(
        person_idx = i,
        arrival_rate = arrival_rate,
        service_rate = service_rate,
        wip_inventory = wip_inventory,
        num_operations = num_operations,
        setup_time = setup_time,
        due_date_tightness = due_date_tightness,
        machine_age = machine_age,
        maintenance_interval = maintenance_interval,
        technician_availability = technician_availability,
        supplier_lead_time = supplier_lead_time,
        inventory_level = inventory_level,
        demand_variability = demand_variability,
        cycle_time = cycle_time,
        throughput = throughput,
        on_time_delivery = on_time_delivery,
        unit_cost = unit_cost
      )

      data_list[[length(data_list) + 1]] <- row
    }
  }

  # Combine all rows
  data <- do.call(rbind, data_list)

  return(data)
}

# Generate and save data
manufacturing_data <- generate_manufacturing_queueing_data(n_per_type = 10)

# Save to CSV
write.csv(manufacturing_data,
          "examples/manufacturing/manufacturing_data.csv",
          row.names = FALSE)

cat("Generated manufacturing queueing data:\n")
cat(sprintf("  Total rows: %d\n", nrow(manufacturing_data)))
cat(sprintf("  Product types: %d\n", length(unique(manufacturing_data$person_idx))))
cat(sprintf("  Observations per type: %d\n", nrow(manufacturing_data) / 16))

# Print summary
cat("\nOutcome summary:\n")
print(summary(manufacturing_data[, c("cycle_time", "throughput", "on_time_delivery", "unit_cost")]))
