library(caret)
library(parallel)
#--------------------------------------------------------
#----------Distribution of training labels---------------
#--------------------------------------------------------
# first run the qmd file
train_df <- train$images |> as.data.frame()
train_df$labels <- train$labels |> as.factor()

ggplot(train_df, aes(labels, fill = labels)) +
  geom_bar() +
  labs(fill = "digit")


#----------------------------------------------------------
#-----------Pixel intensity representation-----------------
#----------------------------------------------------------
train_df_long <- train_df |>
  pivot_longer(-labels, names_to = "covariate", values_to = "intensity")
ggplot(train_df_long) +
  geom_histogram(aes(intensity), bins = 30, fill = "#2C7FB8", color = "white", alpha = 0.8)


#------------------------------------------------------------
#----------------distribution of mnist training--------------
#------------------------------------------------------------

# take the train images from the slides .qmd file
# normalized pixel values and apply t-SNE
library("Rtsne")
# tsne_results <- Rtsne(
#   train_images,
#   dim = 2,
#   perplexity = 30,
#   max_iter = 1000
# )
# df_tsne <- tibble(Dim1 = tsne_results$Y[, 1],
#                   Dim2 = tsne_results$Y[, 2],
#                   digit = train_df$labels)
#
# saveRDS(df_tsne, "ml/df_tsne.rds")
df_tsne <- readRDS("ml/df_tsne.rds")
ggplot(df_tsne, aes(Dim1, Dim2, color = digit)) +
  geom_point(alpha = .8)

#----------------------------------------------------------
#----------------------------KNN---------------------------
#----------------------------------------------------------
# cl <- makePSOCKcluster(15)
# registerDoParallel(cl)
# knn_trainControl <- trainControl(
#   method = "cv",
#   number = 5
# )
# train_knn <- train(
#   labels ~ .,
#   train_df,
#   method = "knn",
#   metric = "Accuracy",
#   trControl = knn_trainControl
# )
# saveRDS(train_knn, "train_knn")

# knn_train <- readRDS("train_knn")
# plot(train_knn)
#
# knn_prediction <- predict(train_knn, newdata = test_images)
# print(knn_prediction)

# saveRDS(train_knn, "ml/train_knn.rds")
# stopCluster(cl)

# knn_train <- readRDS("train_knn")
# plot(train_knn)
#
# knn_prediction <- predict(train_knn, newdata = test_images)
# print(knn_prediction)

#----------------------------------------------------------
#----------------------------A multilayer Network----------
#----------------------------------------------------------
library(keras)
library(reticulate)

###### Neural network with dropout regularization
nn_dropout_model <- keras_model_sequential()
# ## network architecture with regularization
nn_dropout_model |>
  layer_dense(
    units = 256, activation = "relu",
    input_shape = c(784)
  ) |>
  layer_dropout(rate = .4) |>
  layer_dense(units = 128, activation = "relu") |>
  layer_dropout(rate = .3) |>
  layer_dense(units = 10, activation = "softmax")



summary(nn_dropout_model)

# fully connected(dense) feedforward neural network
# | Layer Type      | Units | Activation | Regularization | Notes               |
# |-----------------|-------|------------|----------------|---------------------|
# | Dense           | 256   | ReLU       | None           | input_shape = 784   |
# | Dropout         | -     | -          | rate = 0.4     |                     |
# | Dense           | 128   | ReLU       | None           |                     |
# | Dropout         | -     | -          | rate = 0.3     |                     |
# | Dense (output)  | 10    | Softmax    | None           | 10-class classification |


# minimize the cross-entropy function, backpropagation
nn_dropout_model |>
  compile(
    loss = "categorical_crossentropy",
    optimizer = optimizer_rmsprop(),
    metrics = c("accuracy")
  )

# pre-process and supply data
x_train <- array_reshape(train_images, c(60000, 784))
x_test <- array_reshape(test_images, c(10000, 784))
y_train <- to_categorical(train$labels, 10)
y_test <- to_categorical(test$labels, 10)
nn_dropout_hist <- nn_dropout_model |>
  fit(
    x_train,
    y_train,
    epochs = 30,
    batch_size = 128,
    validation_split = .2
  )

plot(nn_dropout_hist)

accuracy_check <- function(pred, test_labels) {
  mean(to_categorical(drop(as.numeric(pred)), 10) == drop(test_labels))
}
nn_drop_pred_class <- k_argmax(predict(nn_dropout_model, x_test))
nn_dropout_accu <- accuracy_check(nn_drop_pred_class, y_test)
nn_dropout_accu

#### function to get confusion matrix
confu_mat <- function(pred_classes, test_labels){
  confusionMatrix(
    factor(drop(as.numeric(pred_classes)), levels = 0:9),
    drop(test_labels)
  )
}
## ggplot function to represent the heatmap
cm_ggplot <- function(conf_mat, type) {
  cm_df <- as.data.frame(conf_mat$table)
  ggplot(cm_df, aes(Prediction, Reference, fill = Freq)) +
    geom_tile(color = "gray50") +
    geom_text(aes(label = Freq), color = "red", size = 4) +
    #scale_fill_gradient(low = "white", high = "steelblue") +
    scale_fill_viridis_c(option = "magma", direction = -1) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, face = "bold"),
      axis.text.y = element_text(face = "bold"),
      panel.grid = element_blank()
    )+
    labs(
      # title = paste("Confusion matrix heatmap - ", type),
      x = "Predicted label",
      y = "True label",
      fill = "Count"
    )
}
# nn_dropout_conf_mat <- confu_mat(nn_drop_pred_class, test_labels)
# saveRDS(nn_dropout_conf_mat, "nn_dropout_conf_mat")
nn_dropout_conf_mat <- readRDS("nn_dropout_conf_mat")
cm_ggplot(nn_dropout_conf_mat, type = "nn_dropout")


#-----------------------------------------------------------------------------------
#-----------------Neural network with ridge regularization--------------------------
#-----------------------------------------------------------------------------------
# adds a penalty proportional to the sqaure of the weights
nn_ridge_model <- keras_model_sequential() |>
  layer_dense(
    units = 256, activation = "relu", input_shape = ncol(x_train),
    kernel_regularizer = regularizer_l2(l = .01)
  ) |>
  layer_dense(units = 128, activation = "relu", regularizer_l2(l = .01)) |>
  layer_dense(units = 10, activation = "softmax")

summary(nn_ridge_model)

nn_ridge_model |> compile(
  loss = "categorical_crossentropy",
  optimizer = optimizer_rmsprop(),
  metrics = c("accuracy")
)

nn_ridge_hist <- nn_ridge_model |> fit(
  x_train,
  y_train,
  epochs = 30,
  batch_size = 128,
  validation_split = .2
)

plot(nn_ridge_hist)
nn_ridge_pred_class <- k_argmax(predict(nn_ridge_model, x_test))
nn_ridge_accu <-  accuracy_check(nn_ridge_pred_class, y_test)
nn_ridge_accu

# | Step                  | Description                                           |
# |-----------------------|-------------------------------------------------------|
# | Model Initialization  | Created a sequential model with 3 dense layers        |
# | First Dense Layer     | 256 units, ReLU activation, input shape = number of features, L2 regularization (λ = 0.001) |
# | Second Dense Layer    | 128 units, ReLU activation, L2 regularization (λ = 0.001) |
# | Output Layer         | 10 units, Softmax activation (multi-class classification) |
# | Model Compilation    | Loss: categorical crossentropy, Optimizer: RMSprop, Metric: accuracy |
# | Model Training       | 35 epochs, batch size 128, 20% validation split       |


#-----------NN ridge confusion matrix------------------------
nn_ridge_conf_mat <- confu_mat(nn_ridge_pred_class, test_labels)
# saveRDS(nn_ridge_conf_mat, "nn_ridge_conf_mat")
nn_ridge_conf_mat <- readRDS("nn_ridge_conf_mat")
cm_ggplot(nn_ridge_conf_mat, type = "nn_ridge")


#-----------------------------------------------------------------------------------
#-----------------Neural network with lasso regularization--------------------------
#-----------------------------------------------------------------------------------
### adds a penalty proportional to the absolute value of the weights
nn_lasso_model <- keras_model_sequential() |>
  layer_dense(
    units = 256, activation = "relu", input_shape = ncol(x_train),
    kernel_regularizer = regularizer_l1(l = .01)
  ) |>
  layer_dense(units = 128, activation = "relu", regularizer_l1(l = .01)) |>
  layer_dense(units = 10, activation = "softmax")

summary(nn_lasso_model)

nn_lasso_model |> compile(
  loss = "categorical_crossentropy",
  optimizer = optimizer_rmsprop(),
  metrics = c("accuracy")
)

nn_lasso_hist <- nn_lasso_model |> fit(
  x_train,
  y_train,
  epochs = 30,
  batch_size = 128,
  validation_split = .2
)

plot(nn_lasso_hist)

nn_lasso_pred_class <- k_argmax(predict(nn_lasso_model, x_test)) 
nn_lasso_accu <- accuracy_check(nn_lasso_pred_class, y_test)
nn_lasso_accu

#-----------NN lasso confusion matrix------------------------
nn_lasso_conf_mat <- confu_mat(nn_lasso_pred_class, test_labels)
#saveRDS(nn_lasso_conf_mat, "nn_lasso_conf_mat")
nn_lasso_conf_mat <- readRDS("nn_ridge_conf_mat")
cm_ggplot(nn_lasso_conf_mat, type = "nn_lasso")



#--------------------------------------------------------------------------------
#-----------------------multinomial logistic regression--------------------------
# multinomial logistic regression = single Dense layer with softmax
mlogit_model <- keras_model_sequential() |>
  layer_dense(
    units = 10,
    activation = "softmax",
    input_shape = ncol(x_train)
  )
mlogit_model |> compile(
  loss = "categorical_crossentropy",
  optimizer = optimizer_rmsprop(),
  metrics = "accuracy"
)

mlogit_hist <- mlogit_model |> fit(
  x_train,
  y_train,
  epochs = 30,
  batch_size = 128,
  validation_split = 0.2
)

plot(mlogit_hist)

mlogit_pred_classes <-  k_argmax(predict(mlogit_model, x_test)) 
mlogit_acc <- accuracy_check(mlogit_pred_classes, y_test)
mlogit_acc
# higher than reported in the book, I would think this comes from the normalization of features

#-----------NN multinomial confusion matrix------------------------
mlogit_conf_mat <- confu_mat(mlogit_pred_classes, test_labels)
# saveRDS(mlogit_conf_mat, "mlogit_conf_mat")
mlogit_conf_mat <- readRDS("mlogit_conf_mat")
cm_ggplot(mlogit_conf_mat, type = "mlogit")

