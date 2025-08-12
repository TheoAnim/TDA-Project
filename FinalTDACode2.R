# --- 1. Setup ---
# Load necessary libraries
library(tidyverse)
library(furrr)
library(future)
library(patchwork)
library(ripserr)
library(BayesTDA)
library(mvtnorm)

set.seed(9743650)
plan(multisession, workers = 15) # Set up parallel processing

# --- 2. Data Loading and Preprocessing ---

# Load the MNIST dataset
# Ensure the "mnist_dataset" RDS file is in your working directory.
mnist <- readRDS("mnist_dataset")

# Prepare data for a specified digit
prepare_digit_data <- function(digit, n_samples = 10) {
  images <- mnist$train$images
  labels <- mnist$train$labels
  digit_indices <- which(labels == digit) |> head(n_samples)

  lapply(digit_indices, \(i) {
    # Normalize pixel values to the [0, 1] range
    matrix(images[i, ], nrow = 28, byrow = TRUE) / 255
  })
}

# --- 3. Persistence Diagram Calculation ---

# Function to compute persistence diagrams from cubical complexes
get_persistence_diagrams <- function(image_list) {
  future_map(image_list, ~ {
    ripserr::cubical(1 - .x, dim = 1) |>
      as_tibble() |>
      filter(dimension == 1, is.finite(death)) |>
      mutate(persistence = death - birth) |>
      select(dimension, birth, persistence)
  }, .options = furrr_options(seed = TRUE))
}
# get_persistence_diagrams <- function(image_list) {
#   future_map(image_list, ~ {
#     ripserr::cubical(.x, dim = 1) |>
#       as_tibble() |>
#       filter(dimension == 1, is.finite(death)) |>
#       mutate(persistence = death - birth) |>
#       select(dimension, birth, persistence)
#   }, .options = furrr_options(seed = TRUE))
# }

# --- 4. Prior and Posterior Calculation ---

# Define a very weak (uninformative) prior
uninformative_prior_params <- list(
  weights = c(1),
  means = list(c(0.5, 0.5)),
  sigmas = c(1)
)

# Function to calculate posterior intensity on a grid
calculate_posterior_data <- function(grid_points, observed_pds, prior_params, noise_sigma, alpha, sigma_y) {
  pd_matrix <- observed_pds |>
    bind_rows() |>
    select(birth, persistence) |>
    as.matrix()

  if (nrow(pd_matrix) == 0) {
    return(bind_cols(grid_points, intensity = 0))
  }

  Dy_list <- split(pd_matrix, 1:nrow(pd_matrix))

  noise_params <- list(
    weights = 1,
    means = list(c(0.5, 0)),
    sigmas = noise_sigma
  )

  intensity_values <- future_map_dbl(1:nrow(grid_points), \(i) {
    p_vec <- as.numeric(grid_points[i, ])
    if (p_vec[2] < 0) {
      return(0)
    }

    BayesTDA::postIntensityPoisson(
      x = p_vec, Dy = Dy_list, alpha = alpha,
      weight.prior = prior_params$weights, mean.prior = prior_params$means,
      sigma.prior = prior_params$sigmas, sigma.y = sigma_y,
      weights.unexpected = noise_params$weights, mean.unexpected = noise_params$means,
      sigma.unexpected = noise_params$sigmas
    )
  }, .options = furrr_options(seed = TRUE, packages = c("BayesTDA", "mvtnorm")))

  intensity_values[!is.finite(intensity_values)] <- 0
  max_intensity <- max(intensity_values, na.rm = TRUE)
  if (max_intensity > 0) {
    intensity_values <- intensity_values / max_intensity
  }

  bind_cols(grid_points, intensity = intensity_values)
}

# calculate_posterior_data <- function(grid_points, observed_pds, prior_params, noise_sigma, alpha, sigma_y) {
#   pd_matrix <- observed_pds |>
#     bind_rows() |>
#     select(birth, persistence) |>
#     as.matrix()
#
#   if (nrow(pd_matrix) == 0) {
#     return(bind_cols(grid_points, intensity = 0))
#   }
#
#   Dy_list <- split(pd_matrix, 1:nrow(pd_matrix))
#
#   noise_params <- list(
#     weights = 1,
#     means = list(c(0.5, 0)),
#     sigmas = noise_sigma
#   )
#
#   intensity_values <- future_map_dbl(1:nrow(grid_points), function(i) {
#     p_vec <- as.numeric(grid_points[i, ])
#     if (p_vec[2] < 0) {
#       return(0)
#     }
#
#     BayesTDA::postIntensityPoisson(
#       x = p_vec, Dy = Dy_list, alpha = alpha,
#       weight.prior = prior_params$weights, mean.prior = prior_params$means,
#       sigma.prior = prior_params$sigmas, sigma.y = sigma_y,
#       weights.unexpected = noise_params$weights, mean.unexpected = noise_params$means,
#       sigma.unexpected = noise_params$sigmas
#     )
#   }, .options = furrr_options(seed = TRUE, packages = c("BayesTDA", "mvtnorm")))
#
#   intensity_values[!is.finite(intensity_values)] <- 0
#   max_intensity <- max(intensity_values)
#   if (max_intensity > 0) {
#     intensity_values <- intensity_values / max_intensity
#   }
#
#   bind_cols(grid_points, intensity = intensity_values)
# }

# --- 5. Execution and Plotting ---

# Create an evaluation grid for plotting
eval_grid <- expand_grid(
  birth = seq(0, 1, length.out = 25),
  persistence = seq(0, 1, length.out = 25)
)

# Function to plot the intensity
plot_intensity <- function(data, title = "") {
  ggplot(data, aes(x = birth, y = persistence)) +
    geom_raster(aes(fill = intensity), interpolate = TRUE) +
    scale_fill_viridis_c(option = "plasma", name = "Intensity", limits = c(0, 1)) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    labs(x = "Birth", y = "Persistence", title = title) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.position = "none" # Hide individual legends
    )
}

# Process all digits from 0 to 9
digits <- 0:9
# digits <- 0:3

# Map over each digit to perform the full analysis pipeline
# This list will store the final plot for each digit.
plot_list <- map(digits, ~ {
  # Define a unique title for the current digit's plot
  plot_title <- paste("Posterior Density for Digit", .x)

  # 1. Prepare data and calculate persistence diagrams
  pd_list <- prepare_digit_data(.x, n_samples = 50) |> get_persistence_diagrams()

  # 2. Calculate posterior data
  posterior_data <- calculate_posterior_data(
    grid_points = eval_grid,
    observed_pds = pd_list,
    prior_params = uninformative_prior_params,
    noise_sigma = sqrt(0.01),
    alpha = 0.99,
    # simga_y = .005
    sigma_y = .001
  )

  # 3. Generate the plot
  plot_intensity(posterior_data, title = plot_title)
})

# Arrange all plots into a 2x5 grid
wrap_plots(plot_list, ncol = 5)

# Clean up parallel workers
plan(sequential)
