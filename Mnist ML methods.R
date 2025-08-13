#--------------------------------------------------------
#----------Distribution of training labels---------------
#--------------------------------------------------------
#first run the qmd file
train_df <- train$images |> as.data.frame()
train_df$labels <- train$labels |> as.factor()

ggplot(train_df, aes(labels, fill = labels))+
  geom_bar()+
  labs(fill = "digit")


#----------------------------------------------------------
#-----------Pixel intensity representation-----------------
#----------------------------------------------------------
train_df_long <- train_df |>
  pivot_longer(-labels, names_to  = "covariate", values_to = "intensity")

ggplot(train_df_long)+
  geom_histogram(aes(intensity), bins = 30,  fill = "#2C7FB8",  color = "white", alpha = 0.8)


#------------------------------------------------------------
#----------------distribution of mnist training--------------
#------------------------------------------------------------

#take the train images from the slides .qmd file
#normalized pixel values and apply t-SNE
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
# saveRDS(df_tsne, "df_tsne")
df_tsne <- readRDS("df_tsne")
ggplot(df_tsne, aes(Dim1, Dim2, color = digit)) +
  geom_point(alpha = .8)

#----------------------------------------------------------
#----------------------------KNN---------------------------
#----------------------------------------------------------
# library(caret)
# knn_trainControl <- trainControl(method = "cv",
#                                number = 10)
# # train_knn <- train(
# #   labels ~ .,
# #   train_df,
# #   method = "knn",
# #   metric = "Accuracy",
# #   trControl = knn_trainControl
# # )
# # saveRDS(train_knn, "train_knn")
#
# knn_train <- readRDS("train_knn")
# plot(train_knn)
#
# knn_prediction <- predict(train_knn, newdata = test_images)
# print(knn_prediction)



#----------------------------------------------------------
#----------------------------A multilayer Network----------
#----------------------------------------------------------
library(keras)

######Neural network with dropout regularization
nn_dropout_model <- keras_model_sequential()
##network architecture with regularization
nn_dropout_model |>
  layer_dense(units = 256, activation = "relu",
              input_shape = c(784)) |>
  layer_dropout(rate = .4) |>
  layer_dense(units = 128, activation = "relu") |>
  layer_dropout(rate = .3) |>
  layer_dense(units = 10, activation = "softmax")
summary(nn_dropout_model)

#fully connected(dense) feedforward neural network
# | Layer Type      | Units | Activation | Regularization | Notes               |
# |-----------------|-------|------------|----------------|---------------------|
# | Dense           | 256   | ReLU       | None           | input_shape = 784   |
# | Dropout         | -     | -          | rate = 0.4     |                     |
# | Dense           | 128   | ReLU       | None           |                     |
# | Dropout         | -     | -          | rate = 0.3     |                     |
# | Dense (output)  | 10    | Softmax    | None           | 10-class classification |


#minimize the cross-entropy function, backpropagation
nn_dropout_model |>
  compile(
    loss = "categorical_crossentropy",
    optimizer = optimizer_rmsprop(),
    metrics = c("accuracy")
  )

#supply data

x_train <- array_reshape(train_images, c(60000, 784))
x_test <- array_reshape(test_images, c(10000, 784))
y_train <- to_categorical(train$labels, 10)
y_test <- to_categorical(test$labels, 10)
system.time(
  nn_dropout_hist <- nn_dropout_model |>
    fit(
      x_train,
      y_train,
      epochs = 35,
      batch_size = 128,
      validation_split = .2
    )
)

plot(nn_dropout_hist)

accuracy_check <- function(pred, test_labels){
  mean(to_categorical(drop(as.numeric(pred)) , 10) == drop(test_labels))
}

nn_dropout_accu <- k_argmax(predict(nn_dropout_model, x_test)) |> accuracy_check(y_test)
nn_dropout_accu

#-----------------------------------------------------------------------------------
#-----------------Neural network with ridge regularization--------------------------
#-----------------------------------------------------------------------------------
nn_ridge_model <- keras_model_sequential() |>
  layer_dense(units = 256, activation = "relu", input_shape = ncol(x_train),
              kernel_regularizer = regularizer_l2(l = .001)) |>
  layer_dense(units = 128, activation = "relu", regularizer_l2(l = .001)) |>
  layer_dense(units = 10, activation = "softmax")

summary(nn_reg_model)

nn_ridge_model |> compile(
  loss = "categorical_crossentropy",
  optimizer = optimizer_rmsprop(),
  metrics = c("accuracy")
)

nn_reg_hist <-   nn_ridge_model |> fit(
  x_train,
  y_train,
  epochs = 35,
  batch_size = 128,
  validation_split = .2
)

plot(nn_reg_hist)

nn_reg_accu <- k_argmax(predict(nn_ridge_model, x_test)) |> accuracy_check(y_test)
nn_reg_accu
