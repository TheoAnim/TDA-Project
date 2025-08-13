# library(tidyverse)
# library(furrr)
# library(future)
# library(ripserr)
# library(ranger)
# library(scales)
#
# set.seed(9743650)
# plan(multisession, workers = availableCores() - 1)
# mnist <- readRDS("mnist_dataset")
#
# persistent_entropy <- function(dgm) {
#   if (nrow(dgm) == 0) {
#     return(0)
#   }
#
#   persistence <- dgm$death - dgm$birth
#   total_persistence <- sum(persistence)
#
#   if (total_persistence == 0) {
#     return(0)
#   }
#
#   p <- persistence / total_persistence
#   p <- p[p > 0]
#
#   -sum(p * log(p))
# }
#
# get_topological_features <- function(image_matrix) {
#   # Binarize the image for cubical homology
#   # binary_image <- ifelse(image_matrix > 0.4, 1, 0)
#
#   directions <- list(
#     c(1, 0), c(-1, 0), c(0, 1), c(0, -1),
#     c(1, 1), c(1, -1), c(-1, 1), c(-1, -1)
#   )
#
#   features <- map_dfc(directions, \(dir) {
#     # Create the height filtration
#     dgm <- cubical(image_matrix, direction = dir, dim = 1) |>
#       as_tibble() |>
#       filter(is.finite(death))
#
#     pe0 <- persistent_entropy(filter(dgm, dimension == 0))
#     pe1 <- persistent_entropy(filter(dgm, dimension == 1))
#
#     col_name_pe0 <- paste0("pe0_", dir[1], "_", dir[2]) |> gsub("-", "n", x = _)
#     col_name_pe1 <- paste0("pe1_", dir[1], "_", dir[2]) |> gsub("-", "n", x = _)
#
#     tibble(
#       !!col_name_pe0 := pe0,
#       !!col_name_pe1 := pe1
#     )
#   })
#
#   return(features)
# }
#
# train_indices <- 1:100
# test_indices <- 1:100
#
# train_features <- future_map_dfr(
#   train_indices,
#   ~ get_topological_features(matrix(mnist$train$images[.x, ], nrow = 28)),
#   .progress = TRUE,
#   .options = furrr_options(seed = TRUE)
# )
#
# train_data <- train_features |>
#   mutate(label = factor(mnist$train$labels[train_indices]))
#
# model <- ranger(
#   formula = label ~ .,
#   data = train_data,
#   num.trees = 500,
#   importance = "impurity"
# )
#
#
# test_features <- future_map_dfr(
#   test_indices,
#   ~ get_topological_features(matrix(mnist$test$images[.x, ], nrow = 28)),
#   .progress = TRUE,
#   .options = furrr_options(seed = TRUE)
# )
#
# predictions <- predict(model, data = test_features)
#
# results <- tibble(
#   true_label = factor(mnist$test$labels[test_indices]),
#   predicted_label = predictions$predictions
# )
#
# accuracy <- mean(results$true_label == results$predicted_label, na.rm = TRUE)
# print(paste("Feature-Based TDA Accuracy:", percent(accuracy, accuracy = 0.1)))
#
# plan(sequential)
