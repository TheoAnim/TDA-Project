library(tidyverse)
library(furrr)
library(future)
library(patchwork)
library(ripserr)
library(BayesTDA)
library(mvtnorm)
library(transport)

set.seed(9743650)
plan(multisession, workers = 15)

mnist <- readRDS("mnist_dataset")

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

uninformative_prior_params <- list(
  weights = c(1),
  means = list(c(0.5, 0.5)),
  sigmas = c(1)
)

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

eval_grid <- expand_grid(
  birth = seq(0, 1, length.out = 25),
  persistence = seq(0, 1, length.out = 25)
)

plot_intensity <- function(data, title = "") {
  ggplot(data, aes(x = birth, y = persistence)) +
    geom_raster(aes(fill = intensity), interpolate = TRUE) +
    scale_fill_viridis_c(option = "plasma", name = "Intensity", limits = c(0, 1)) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    labs(x = "Birth", y = "Persistence", title = title) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.position = "none"
    )
}

digits <- 0:9
# digits <- 0:3

posteriors_list <- map(digits, ~ {
  pd_list <- prepare_digit_data(.x, n_samples = 50) |> get_persistence_diagrams()
  post_data <- calculate_posterior_data(
    grid_points = eval_grid,
    observed_pds = pd_list,
    prior_params = uninformative_prior_params,
    noise_sigma = sqrt(0.01),
    alpha = 0.99,
    # simga_y = .005
    sigma_y = .001
  )
  list(post_data = post_data, digits = .x)
})

# plot_list <- map(posteriors_list, \(item) {
#   plot_title <- paste("Posterior Density for Digit", item$digits)
#   plot_intensity(data = item$post_data, title = plot_title)
# })
#
# wrap_plots(plot_list, ncol = 5)

# wasserstein distance for testpd to posterior densities

posterior_wpp_list <- future_map(posteriors_list, ~ {
  post_df <- .x$post_data
  wpp(
    coordinates = as.matrix(post_df[1:2]),
    mass = post_df$intensity / sum(post_df$intensity)
  )
}, .options = furrr_options(seed = TRUE))

names(posterior_wpp_list) <- map_chr(posteriors_list, ~ as.character(.x$digits))

# get_test_image <- \(digit) {
#   test_indices <- which(mnist$test$labels == digit)
#
#   matrix(mnist$test$images[test_indices[1], ], nrow = 28, byrow = TRUE) / 255
# }

# test_image_8 <- get_test_image(8)
# test_pd_8 <- get_persistence_diagrams(list(test_image_8)) |> bind_rows()

mnist_test_set <- tibble(
  true_label = as.character(mnist$test$labels),
  image_matrix = map(1:nrow(mnist$test$images), ~ {
    matrix(mnist$test$images[.x, ], nrow = 28, byrow = TRUE) / 255
  })
)

create_test_wpp <- function(test_image, feature_dim = 1) {
  pd <- get_persistence_diagrams(list(test_image)) |>
    bind_rows() |>
    filter(dimension == feature_dim)

  # If the diagram has no points, return NULL instead of trying to create a wpp object.
  if (nrow(pd) == 0) {
    return(NULL)
  }

  wpp(
    coordinates = select(pd, birth, persistence) |> as.matrix(),
    mass = rep(1 / nrow(pd), nrow(pd))
  )
}

classify_digit_from_image <- function(test_image, posteriors) {
  wpp_test <- create_test_wpp(test_image)

  # If create_test_wpp returned NULL, we can't classify. Return NA.
  if (is.null(wpp_test)) {
    return(list(predicted_digit = NA_character_, distances = rep(NA, length(posteriors))))
  }

  w_distances <- map_dbl(posteriors, ~ transport::wasserstein(a = wpp_test, b = .x, p = 1))
  prediction <- names(which.min(w_distances))

  list(
    predicted_digit = prediction,
    distances = w_distances
  )
}

# test_image_8 <- get_test_image(8)
# test_images_all <- map(0:10000, get_test_image)
# names(test_images_all) <- 0:10000
test_images_all <- map(0:9, get_test_image)
names(test_images_all) <- 0:9


# classification_result <- classify_digit_from_image(
#   test_image = test_image_8,
#   posteriors = posterior_wpp_list
# )

full_results <- mnist_test_set |>
  mutate(
    classification_output = future_map(
      image_matrix,
      ~ classify_digit_from_image(.x, posterior_wpp_list),
      .progress = TRUE,
      .options = furrr_options(seed = TRUE)
    )
  ) |>
  mutate(
    predicted_label = map_chr(classification_output, "predicted_digit", .default = NA_character_)
  )

accuracy <- mean(
  full_results$true_label == full_results$predicted_label,
  na.rm = TRUE
)

plan(sequential)
