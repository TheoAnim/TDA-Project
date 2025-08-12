# ======================================================================================================
#  Library Packages
# ======================================================================================================

library(quarto)
library(knitr)
library(tidyverse)
library(conflicted)
library(janitor)
library(ggtda)
# library(TDAvis)
library(patchwork)
library(gganimate)
library(ggforce)
library(simplextree)
library(gifski)
library(magick)
library(ripserr)
library(reshape2)
# remotes::install_github("maroulaslab/BayesTDA") Use this if package ‘BayesTDA’ is not available for this version of R
library(BayesTDA)
library(TDAstats)
library(mvtnorm)
library(kableExtra)
library(plotly)
library(DiagrammeR)
library(transport)
library(TDA)
library(RColorBrewer)
library(furrr)
library(phutil)
library(mvtnorm)
library(TDApplied)
conflicted::conflict_prefer("filter", "dplyr")
conflicted::conflict_prefer("select", "dplyr")
conflicted::conflicts_prefer(ggtda::geom_simplicial_complex)
conflicted::conflicts_prefer(plotly::layout)
knitr::opts_chunk$set(
  comment = "#>",
  message = FALSE,
  warning = FALSE,
  cache = FALSE,
  echo = FALSE,
  tidy.opts = list(width.cutoff = 100),
  tidy = FALSE,
  fig.align = "center"
)
ggplot2::theme_set(ggplot2::theme_minimal())
ggplot2::theme_update(panel.grid.minor = ggplot2::element_blank())

# ======================================================================================================
#  Load and Preprocess MNIST
# ======================================================================================================

mnist <- readRDS(file = "mnist_dataset")

train <- mnist$train
test <- mnist$test

train_images <- train$images # Matrix of size 60,000 x 784
train_labels <- as.factor(train$labels) # Factorized labels (0-9)

test_images <- test$images # Matrix of size 10,000 x 784
test_labels <- as.factor(test$labels)

train_images <- train_images / 255
test_images <- test_images / 255

train_images_list <- lapply(1:nrow(train_images), function(i) {
  matrix(train_images[i, ], nrow = 28) |> t()
})

test_images_list <- lapply(1:nrow(test_images), function(i) {
  matrix(test_images[i, ], nrow = 28) |> t()
})

plot_digit <- \(image_list = train_images_list, image_index = NULL, image_df = NULL, melted = FALSE){
  if (!melted) {
    image_df <- melt(image_list[image_index])
    colnames(image_df) <- c("y", "x", "value")
  }
  ggplot(image_df, aes(x = x, y = y, fill = value)) +
    geom_raster() +
    scale_fill_gradient(low = "white", high = "black") +
    scale_y_reverse() +
    coord_equal() +
    theme_void() +
    theme(legend.position = "none")
}

# plot_digit(image_index = 8)
# paste0("Label: ", train$labels[8])

binarize_images <- function(images_list, threshold = 0.5) {
  lapply(images_list, function(mat) {
    ifelse(mat < threshold, 0, 1)
  })
}

train_images_binarized <- binarize_images(train_images_list)
test_images_binarized <- binarize_images(test_images_list)

# plot_digit(image_index = 8) + plot_digit(train_images_binarized, image_index = 8)

# ======================================================================================================
#  Compute Cubical Complex & Homology
# ======================================================================================================

do_cubical <- function(images) {
  future::plan(future::multisession)


  cubical_complex <- furrr::future_map(
    images,
    ~ ripserr::cubical(.x),
    .options = furrr::furrr_options(seed = 7183208)
  )

  future::plan(future::sequential)

  cubical_complex
}

cubical_list <- do_cubical(train_images_binarized[1:10])
cubical_list |> str()


# p1 <- as_persistence(cubical_list[[1]])
# p2 <- as_persistence(cubical_list[[2]])
# wasserstein_distance(p1, p2)



# ======================================================================================================
#  Gemini code
# ======================================================================================================
#
# set.seed(9743650)
#
# # Set up parallel processing
# plan(multisession)
#
# # --- 1. Data Loading and Preprocessing ---
#
# # Load the MNIST dataset
# # Ensure you have the 'mnist_dataset.rds' file in your working directory
# mnist <- readRDS("mnist_dataset")
#
# # Function to binarize images
# binarize_images <- function(images_list, threshold = 0.5) {
#   lapply(images_list, function(mat) {
#     (mat > threshold) * 1
#   })
# }
#
# # Prepare 50 sample data for digits 0 and 1
# prepare_digit_data <- function(digit, n_samples = 50) {
#   # Extract images and labels
#   images <- mnist$train$images
#   labels <- mnist$train$labels
#
#   # Get indices for the specified digit
#   digit_indices <- which(labels == digit) |> head(n_samples)
#
#   # Create a list of matrices for the images
#   image_list <- lapply(digit_indices, function(i) {
#     matrix(images[i, ], nrow = 28, byrow = TRUE)
#   })
#
#   # Binarize the images
#   binarize_images(image_list)
# }
#
# # Get binarized images for digits 0 and 1
# images_0 <- prepare_digit_data(0)
# images_1 <- prepare_digit_data(1)
#
# # --- 2. Persistence Diagram Calculation ---
#
# # Function to compute persistence diagrams from cubical complexes
# get_persistence_diagrams <- function(image_list) {
#   future_map(image_list, ~ {
#     cubical_homology <- ripserr::cubical(.x, dim = 1)
#     as_tibble(cubical_homology) |>
#       filter(dimension == 1, is.finite(death)) |>
#       mutate(persistence = death - birth) |>
#       select(dimension, birth, persistence)
#   }, .options = furrr_options(seed = TRUE))
# }
#
# # Calculate persistence diagrams for both digits
# pd_list_0 <- get_persistence_diagrams(images_0)
# pd_list_1 <- get_persistence_diagrams(images_1)
#
#
# # --- 3. Prior and Posterior Calculation ---
#
# # Define a uniform prior
# # This prior is uninformative, placing equal weight across the diagram
# uniform_prior_params <- list(
#   weights = c(1),
#   means = list(c(1, 1)), # Centered in the middle of the potential space
#   sigmas = c(1) # Large variance for uniformity
# )
#
# # Function to calculate posterior data
# calculate_posterior_data <- function(grid_points, observed_pds, prior_params, noise_sigma, alpha, sigma_y) {
#   # Combine all observed diagrams into a matrix of points
#   pd_matrix <- observed_pds |>
#     bind_rows() |>
#     select(birth, persistence) |>
#     as.matrix()
#
#   # Split the matrix into a list of row vectors
#   Dy_list <- split(pd_matrix, 1:nrow(pd_matrix))
#
#   noise_params <- list(
#     weights = 1,
#     means = list(c(0.5, 0)),
#     sigmas = noise_sigma
#   )
#
#   intensity_values <- apply(grid_points, 1, function(p) {
#     if (p["persistence"] < 0) {
#       return(0)
#     }
#     BayesTDA::postIntensityPoisson(
#       x = as.numeric(p), Dy = Dy_list, alpha = alpha,
#       weight.prior = prior_params$weights, mean.prior = prior_params$means,
#       sigma.prior = prior_params$sigmas, sigma.y = sigma_y,
#       weights.unexpected = noise_params$weights, mean.unexpected = noise_params$means,
#       sigma.unexpected = noise_params$sigmas
#     )
#   })
#
#   intensity_values[!is.finite(intensity_values)] <- 0
#   bind_cols(grid_points, intensity = intensity_values / max(intensity_values))
# }
#
# # --- 4. Execution and Plotting ---
#
# # Create an evaluation grid for plotting
# eval_grid <- expand_grid(
#   birth = seq(0, 2, length.out = 100),
#   persistence = seq(0, 2, length.out = 100)
# )
#
# # Calculate posterior for digit 0
# posterior_data_0 <- calculate_posterior_data(
#   eval_grid, pd_list_0, uniform_prior_params,
#   noise_sigma = sqrt(0.1), alpha = 1.0, sigma_y = 0.1
# )
#
# # Calculate posterior for digit 1
# posterior_data_1 <- calculate_posterior_data(
#   eval_grid, pd_list_1, uniform_prior_params,
#   noise_sigma = sqrt(0.1), alpha = 1.0, sigma_y = 0.1
# )
#
# # Function to plot the intensity
# plot_intensity <- function(data, title = "") {
#   ggplot(data, aes(x = birth, y = persistence)) +
#     geom_raster(aes(fill = intensity), interpolate = TRUE) +
#     scale_fill_viridis_c(option = "plasma", name = "Intensity", limits = c(0, 1)) +
#     coord_cartesian(xlim = c(0, 2), ylim = c(0, 2), expand = FALSE) +
#     labs(x = "Birth", y = "Persistence", title = title) +
#     theme_minimal() +
#     theme(plot.title = element_text(hjust = 0.5))
# }
#
# # Generate plots
# p_post_0 <- plot_intensity(posterior_data_0, title = "Posterior Density for Digit 0")
# p_post_1 <- plot_intensity(posterior_data_1, title = "Posterior Density for Digit 1")
#
# # Display plots side-by-side
# p_post_0 | p_post_1
#
# plan(sequential)


set.seed(9743650)

# Set up parallel processing
plan(multisession, workers = 15)

# --- 1. Data Loading and Preprocessing ---

# Load the MNIST dataset
mnist <- readRDS("mnist_dataset")

# Prepare data for digits 0 and 1
prepare_digit_data <- function(digit, n_samples = 10) {
  images <- mnist$train$images
  labels <- mnist$train$labels
  digit_indices <- which(labels == digit) |> head(n_samples)
  lapply(digit_indices, function(i) {
    matrix(images[i, ], nrow = 28, byrow = TRUE)
  })
}

# Get grayscale images for digits 0 and 1
images_0 <- prepare_digit_data(0)
images_1 <- prepare_digit_data(1)

# --- 2. Persistence Diagram Calculation ---

# Function to compute persistence diagrams from cubical complexes
get_persistence_diagrams <- function(image_list) {
  future_map(image_list, ~ {
    # Use ripserr::cubical for correct homology of image data.
    # We invert the image (1 - .x) to perform a sublevel-set filtration.
    ripserr::cubical(1 - .x, dim = 1) |>
      as_tibble() |>
      filter(dimension == 1, is.finite(death)) |>
      mutate(persistence = death - birth) |>
      select(dimension, birth, persistence)
  }, .options = furrr_options(seed = TRUE))
}

# Calculate persistence diagrams for both digits
pd_list_0 <- get_persistence_diagrams(images_0)
pd_list_1 <- get_persistence_diagrams(images_1)

# all_pd_0 <- bind_rows(pd_list_0) %>%
#   mutate(death = birth + persistence)
#
# # Combine and prepare data for digit 1
# all_pd_1 <- bind_rows(pd_list_1) %>%
#   mutate(death = birth + persistence)
#
# # Plot persistence diagrams
# ggplot(all_pd_0, aes(x = birth, y = death)) +
#   geom_point(alpha = 0.6) +
#   labs(title = "Persistence Diagram - Digit 0", x = "Birth", y = "Death")
#
# ggplot(all_pd_1, aes(x = birth, y = death)) +
#   geom_point(alpha = 0.6) +
#   labs(title = "Persistence Diagram - Digit 1", x = "Birth", y = "Death")


# --- 3. Prior and Posterior Calculation ---

# Define a very weak (uninformative) prior to let the data dominate.
uninformative_prior_params <- list(
  weights = c(1),
  means = list(c(0.5, 0.5)),
  sigmas = c(1) # Large variance makes the prior diffuse/flat.
)

# Function to calculate posterior data (EFFICIENT PARALLELIZED VERSION)
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

  intensity_values <- future_map_dbl(1:nrow(grid_points), function(i) {
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
  max_intensity <- max(intensity_values)
  if (max_intensity > 0) {
    intensity_values <- intensity_values / max_intensity
  }

  bind_cols(grid_points, intensity = intensity_values)
}

# --- 4. Execution and Plotting ---

# Create an evaluation grid for plotting
eval_grid <- expand_grid(
  birth = seq(0, 1, length.out = 50),
  persistence = seq(0, 1, length.out = 50)
)

# Calculate posterior for digit 0
# NOTE: We use an extremely small sigma.y to make the likelihood very strong.
posterior_data_0 <- calculate_posterior_data(
  eval_grid, pd_list_0, uninformative_prior_params,
  noise_sigma = sqrt(0.01), alpha = 0.99, sigma_y = 0.005
)

# Calculate posterior for digit 1
posterior_data_1 <- calculate_posterior_data(
  eval_grid, pd_list_1, uninformative_prior_params,
  noise_sigma = sqrt(0.01), alpha = 0.99, sigma_y = 0.005
)

# Function to plot the intensity
plot_intensity <- function(data, title = "") {
  ggplot(data, aes(x = birth, y = persistence)) +
    geom_raster(aes(fill = intensity), interpolate = TRUE) +
    scale_fill_viridis_c(option = "plasma", name = "Intensity", limits = c(0, 1)) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    labs(x = "Birth", y = "Persistence", title = title) +
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5))
}

# Generate plots
p_post_0 <- plot_intensity(posterior_data_0, title = "Posterior Density for Digit 0")
p_post_1 <- plot_intensity(posterior_data_1, title = "Posterior Density for Digit 1")

# Display plots side-by-side
p_post_0 | p_post_1

# Clean up parallel workers
plan(sequential)
