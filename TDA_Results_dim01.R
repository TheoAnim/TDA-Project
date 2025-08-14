#------------------------------------------------------------#
# Load libraries & data
#------------------------------------------------------------#
library(tidyverse)
library(furrr)
library(future)
library(patchwork)
library(ripserr)
library(BayesTDA)
library(mvtnorm)
library(transport)
library(scales)

set.seed(9743650)
plan(multisession, workers = availableCores() - 1)
mnist <- readRDS("mnist_dataset")

#------------------------------------------------------------#
# Functions to process data
#------------------------------------------------------------#

prepare_digit_data <- function(digit, n_samples = 10) {
  images <- mnist$train$images
  labels <- mnist$train$labels
  digit_indices <- which(labels == digit) |> head(n_samples)

  lapply(digit_indices, \(i) {
    matrix(images[i, ], nrow = 28, byrow = TRUE) / 255
  })
}

get_persistence_diagrams <- function(image_list) {
  future_map(image_list, ~ {
    ripserr::cubical(1 - .x) |>
      as_tibble() |>
      filter(is.finite(death)) |>
      mutate(persistence = death - birth) |>
      select(dimension, birth, persistence)
  }, .options = furrr_options(seed = TRUE))
}

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

to_wpp <- function(post_data) {
  total_intensity <- sum(post_data$intensity, na.rm = TRUE)
  if (total_intensity == 0) total_intensity <- 1
  wpp(
    coordinates = as.matrix(post_data[1:2]),
    mass = post_data$intensity / total_intensity
  )
}

create_wpp_from_pd <- function(pd) {
  if (is.null(pd) || nrow(pd) == 0) {
    return(NULL)
  }
  wpp(
    coordinates = select(pd, birth, persistence) |> as.matrix(),
    mass = rep(1 / nrow(pd), nrow(pd))
  )
}

#------------------------------------------------------------#
# Generate posteriors
#------------------------------------------------------------#

digits <- 0:9
eval_grid <- expand_grid(birth = seq(0, 1, length.out = 28), persistence = seq(0, 1, length.out = 28))
uninformative_prior_params <- list(weights = c(1), means = list(c(0.5, 0.5)), sigmas = c(1))

generate_all_posteriors <- function(feature_dim, n_samples = 60000) {
  future_map(digits, ~ {
    pd_list <- prepare_digit_data(.x, n_samples) |> get_persistence_diagrams()
    pd_list_filtered <- map(pd_list, \(pd) filter(pd, dimension == feature_dim))

    calculate_posterior_data(
      grid_points = eval_grid,
      observed_pds = pd_list_filtered,
      prior_params = uninformative_prior_params,
      noise_sigma = sqrt(0.01),
      alpha = 0.99,
      sigma_y = 0.001
    )
  }, .options = furrr_options(seed = TRUE))
}

# posterior_list_dim0 <- generate_all_posteriors(feature_dim = 0)
# posterior_list_dim1 <- generate_all_posteriors(feature_dim = 1)

posterior_list_dim0 <- readRDS("btda/posterior_list_dim0.rds")
posterior_list_dim1 <- readRDS("btda/posterior_list_dim1.rds")

posterior_wpp_list_dim0 <- map(posterior_list_dim0, to_wpp) |> set_names(digits)
posterior_wpp_list_dim1 <- map(posterior_list_dim1, to_wpp) |> set_names(digits)

wpp_null <- wpp(coordinates = matrix(c(0, 0), nrow = 1), mass = 1)
emptiness_penalties_dim1 <- map_dbl(posterior_wpp_list_dim1, ~ transport::wasserstein(.x, wpp_null, p = 1))

#------------------------------------------------------------#
# Digit classification & results
#------------------------------------------------------------#

classify_digit_combined <- function(test_image, posteriors0, posteriors1, penalties1) {
  full_pd <- get_persistence_diagrams(list(test_image))[[1]]

  wpp_test0 <- create_wpp_from_pd(filter(full_pd, dimension == 0))
  wpp_test1 <- create_wpp_from_pd(filter(full_pd, dimension == 1))

  if (is.null(wpp_test0)) {
    return(list(predicted_digit = NA_character_, distances = rep(NA, length(posteriors0))))
  }

  dist0 <- map_dbl(posteriors0, ~ transport::wasserstein(wpp_test0, .x, p = 1))
  dist1 <- if (is.null(wpp_test1)) penalties1 else map_dbl(posteriors1, ~ transport::wasserstein(wpp_test1, .x, p = 1))

  total_dist <- dist0 + dist1
  prediction <- names(which.min(total_dist))

  list(
    predicted_digit = if (length(prediction) > 0) prediction else NA_character_,
    distances = total_dist
  )
}

mnist_test_set <- tibble(
  true_label = as.character(mnist$test$labels),
  image_matrix = map(1:nrow(mnist$test$images), ~ matrix(mnist$test$images[.x, ], nrow = 28, byrow = TRUE) / 255)
)

full_results <- mnist_test_set |>
  mutate(
    classification_output = future_map(
      image_matrix,
      ~ classify_digit_combined_revised(.x, posterior_wpp_list_dim0, posterior_wpp_list_dim1, emptiness_penalties_dim1),
      .progress = TRUE,
      .options = furrr_options(seed = TRUE, packages = c("tidyverse", "transport", "ripserr"))
    )
  ) |>
  mutate(
    predicted_label = map_chr(classification_output, "predicted_digit", .default = NA_character_)
  )

accuracy <- mean(full_results$true_label == full_results$predicted_label, na.rm = TRUE)
print(paste("Combined (0D + 1D) Classification Accuracy:", percent(accuracy, accuracy = 0.1)))

plan(sequential)

#------------------------------------------------------------#
# Save rds
#------------------------------------------------------------#

# saveRDS(posterior_list_dim0, "btda/posterior_list_dim0.rds")
# saveRDS(posterior_list_dim1, "btda/posterior_list_dim1.rds")
# saveRDS(full_results, "btda/full_tda_01_results.rds")
