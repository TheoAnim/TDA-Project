#------------------------------------------------------------#
# Load libraries & data
#------------------------------------------------------------#
library(tidyverse)
library(furrr)
library(future)
library(ripserr)
library(ranger)
library(scales)
library(caret)
library(kernlab)
library(imager)

set.seed(9743650)
plan(multisession, workers = availableCores() - 1)
mnist <- readRDS("mnist_dataset")

#------------------------------------------------------------#
# Functions to calculate topological features
#------------------------------------------------------------#

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
  # 1. Grayscale Filtration
  grayscale_features <- generate_pe_features(image_matrix, "grayscale")

  # 2. Binarize the image for subsequent filtrations
  binary_image <- ifelse(image_matrix > 0.4, 1, 0)

  # 3. Height Filtrations
  height_directions <- list(c(1, 0), c(-1, 0), c(0, 1), c(0, -1), c(1, 1), c(1, -1), c(-1, 1), c(-1, -1))
  height_features <- map_dfc(height_directions, \(dir) {
    coords <- as.matrix(expand.grid(x = 1:28, y = 1:28))
    height_field <- matrix(coords %*% dir, nrow = 28)
    filtration_matrix <- height_field * binary_image
    base_name <- paste0("h_", dir[1], "_", dir[2]) |> gsub("-", "n", x = _)
    generate_pe_features(filtration_matrix, base_name)
  })

  # 4. Dilation Filtration
  img_c <- as.cimg(binary_image)
  dilation_filt <- distance_transform(img_c, 2)
  dilation_features <- generate_pe_features(as.matrix(dilation_filt), "dilation")

  # 5. Erosion Filtration
  erosion_filt <- distance_transform(1 - img_c, 2)
  erosion_features <- generate_pe_features(as.matrix(erosion_filt), "erosion")

  # 6. Radial Filtrations
  radial_centers <- list(c(7, 7), c(14, 7), c(21, 7), c(14, 14), c(7, 14), c(7, 21), c(14, 21), c(21, 14), c(21, 21))
  radial_features <- map_dfc(radial_centers, \(center) {
    coords <- as.matrix(expand.grid(x = 1:28, y = 1:28))
    radial_field <- matrix(sqrt(rowSums(sweep(coords, 2, center, "-")^2)), nrow = 28)
    filtration_matrix <- radial_field * binary_image
    base_name <- paste0("rad_", center[1], "_", center[2])
    generate_pe_features(filtration_matrix, base_name)
  })

  # 7. Density Filtrations
  density_radii <- c(2, 4, 6)
  density_features <- map_dfc(density_radii, \(r) {
    # Use boxblur as a proxy for density
    density_filt <- boxblur(img_c, r)
    base_name <- paste0("dens_r", r)
    generate_pe_features(as.matrix(density_filt), base_name)
  })

  bind_cols(
    grayscale_features,
    height_features,
    dilation_features,
    erosion_features,
    radial_features,
    density_features
  )
}

#------------------------------------------------------------#
# Training features
#------------------------------------------------------------#

# train_indices <- 1:500
# test_indices <- 1:200
train_indices <- 1:60000
test_indices <- 1:10000

train_features <- future_map_dfr(
  train_indices,
  ~ get_all_topological_features(matrix(mnist$train$images[.x, ], nrow = 28)),
  .progress = TRUE,
  .options = furrr_options(seed = TRUE, packages = c("tidyverse", "ripserr", "imager"))
)

train_data <- train_features |>
  mutate(label = factor(mnist$train$labels[train_indices]))

plan(sequential)

nzv_cols <- nearZeroVar(train_data, saveMetrics = FALSE)
if (length(nzv_cols) > 0) {
  train_data <- train_data[, -nzv_cols]
}

#------------------------------------------------------------#
# SVM & RF
#------------------------------------------------------------#

cl <- makePSOCKcluster(15)

registerDoParallel(cl)

train_control <- trainControl(
  method = "cv", number = 10,
  summaryFunction = multiClassSummary
)

rf_model <- train(
  label ~ .,
  data = train_data,
  method = "rf",
  trControl = train_control,
  metric = "Accuracy",
  tuneGrid = expand.grid(mtry = seq(3, 7, by = 1)),
  importance = TRUE,
  nodesize = 1
)
# print(rf_model)
# mtry = 5

svm_model <- train(
  label ~ .,
  data = train_data,
  method = "svmRadial",
  trControl = train_control, preProcess = c("center", "scale"),
  # tuneLength = 5,
  tuneGrid = expand.grid(
    C = 2^seq(0, 10, by = 2),
    sigma = seq(.01, .1, by = .02)
  ),
  metric = "Accuracy"
)
# print(svm_model)
# s = .07, C = 4

#------------------------------------------------------------#
# Model comparison
#------------------------------------------------------------#

model_comparison <- resamples(list(RandomForest = rf_model, SVM = svm_model))
summary(model_comparison)
dotplot(model_comparison)

stopCluster(cl)

plan(multisession, workers = availableCores() - 1)

test_features <- future_map_dfr(
  test_indices,
  ~ get_all_topological_features(matrix(mnist$test$images[.x, ], nrow = 28)),
  .progress = TRUE,
  .options = furrr_options(seed = TRUE, packages = c("tidyverse", "ripserr", "imager"))
)

predictions <- predict(svm_model, newdata = test_features)
results <- tibble(
  true_label = factor(mnist$test$labels[test_indices]),
  predicted_label = predictions
)

final_accuracy <- mean(results$true_label == results$predicted_label, na.rm = TRUE)
print(paste("Final Test Set Accuracy (Random Forest):", percent(final_accuracy, accuracy = 0.1)))

plan(sequential)

rf_importance <- varImp(rf_model, scale = FALSE)
svm_importance <- filterVarImp(
  x = train_data[, -which(names(train_data) == "label")],
  y = train_data$label
)

#------------------------------------------------------------#
# Save imporant results
#------------------------------------------------------------#

saveRDS(train_data, "rdss/all_features_train_data.rds")
saveRDS(test_features, "rdss/all_features_test_data.rds")
saveRDS(rf_model, "rdss/all_features_rf_model.rds")
saveRDS(svm_model, "rdss/all_features_svm_model.rds")
