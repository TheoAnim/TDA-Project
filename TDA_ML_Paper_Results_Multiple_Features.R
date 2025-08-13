library(tidyverse)
library(furrr)
library(future)
library(ripserr)
library(ranger)
library(scales)
library(imager)
library(caret)
library(kernlab)
library(doParallel)

set.seed(9743650)
plan(multisession, workers = availableCores() - 1)
mnist <- readRDS("mnist_dataset")

persistent_entropy <- function(dgm) {
  if (nrow(dgm) == 0) {
    return(0)
  }

  persistence <- dgm$death - dgm$birth
  total_persistence <- sum(persistence, na.rm = TRUE)

  if (total_persistence == 0) {
    return(0)
  }

  p <- persistence / total_persistence
  p <- p[p > 0 & !is.na(p)]

  if (length(p) == 0) {
    return(0)
  }

  -sum(p * log(p))
}

generate_pe_features <- function(filtration_matrix, base_name) {
  dgm <- cubical(filtration_matrix, dim = 1) |>
    as_tibble() |>
    filter(is.finite(death))

  pe0 <- persistent_entropy(filter(dgm, dimension == 0))
  pe1 <- persistent_entropy(filter(dgm, dimension == 1))

  tibble(
    "{base_name}_pe0" := pe0,
    "{base_name}_pe1" := pe1
  )
}

get_all_topological_features <- function(image_matrix) {
  # 1. Grayscale Filtration (Sublevel-set on raw pixels)
  grayscale_features <- generate_pe_features(image_matrix, "grayscale")

  # 2. Binarize the image for subsequent filtrations
  binary_image <- ifelse(image_matrix > 0.4, 1, 0)

  # 3. Height Filtrations (on binarized image)
  directions <- list(c(1, 0), c(-1, 0), c(0, 1), c(0, -1))
  height_features <- map_dfc(directions, \(dir) {
    # Create a filtration field based on the direction
    coords <- as.matrix(expand.grid(x = 1:28, y = 1:28))
    height_field <- matrix(coords %*% dir, nrow = 28)

    # Apply the binary mask
    filtration_matrix <- height_field * binary_image

    base_name <- paste0("h_", dir[1], "_", dir[2]) |> gsub("-", "n", x = _)
    generate_pe_features(filtration_matrix, base_name)
  })

  # 4. Dilation Filtration (on binarized image)
  # Distance from non-digit pixels (0s) to the nearest digit pixel (1)
  dilation_filt <- distance_transform(as.cimg(binary_image == 0), 1)
  dilation_features <- generate_pe_features(as.matrix(dilation_filt), "dilation")

  # Combine all features into a single row
  bind_cols(grayscale_features, height_features, dilation_features)
}

train_indices <- 1:500
test_indices <- 1:1000
# train_indices <- 1:60000
# test_indices <- 1:10000

train_features <- future_map_dfr(
  train_indices,
  ~ get_all_topological_features(matrix(mnist$train$images[.x, ], nrow = 28)),
  .progress = TRUE,
  .options = furrr_options(seed = TRUE, packages = c("tidyverse", "ripserr", "imager"))
)

train_data <- train_features |>
  mutate(label = factor(mnist$train$labels[train_indices]))

plan(sequential)

cl <- makePSOCKcluster(15)

registerDoParallel(cl)

train_control <- trainControl(
  method = "repeatedcv",
  number = 10,
  repeats = 1,
  summaryFunction = multiClassSummary
)


rf_grid <- expand.grid(
  .mtry = c(2, 4, 8),
  .splitrule = "gini",
  .min.node.size = 1
)

rf_model <- train(
  label ~ .,
  data = train_data,
  method = "ranger",
  trControl = train_control,
  tuneGrid = rf_grid,
  metric = "Accuracy"
)

print(rf_model)

svm_model <- train(
  label ~ .,
  data = train_data,
  method = "svmRadial",
  trControl = train_control,
  preProcess = c("center", "scale"),
  tuneLength = 5,
  metric = "Accuracy"
)

print(svm_model)

model_comparison <- resamples(list(RandomForest = rf_model, SVM = svm_model))
summary(model_comparison)
dotplot(model_comparison)
stopCluster(cl)

plan(multisession, workers = availableCores() - 1)

test_features <- future_map_dfr(
  test_indices,
  ~ get_all_topological_features(matrix(mnist$train$images[.x, ], nrow = 28)),
  .progress = TRUE,
  .options = furrr_options(seed = TRUE, packages = c("tidyverse", "ripserr", "imager"))
)

predictions <- predict(rf_model, newdata = test_features)

results <- tibble(
  true_label = factor(mnist$test$labels[test_indices]),
  predicted_label = predictions
)

final_accuracy <- mean(results$true_label == results$predicted_label, na.rm = TRUE)
print(paste("Final Test Set Accuracy (Random Forest):", percent(final_accuracy, accuracy = 0.1)))

plan(sequential)
