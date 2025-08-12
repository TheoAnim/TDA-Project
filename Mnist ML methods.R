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
library(caret)
knn_trainControl <- trainControl(method = "cv",
                               number = 10)
# train_knn <- train(
#   labels ~ .,
#   train_df,
#   method = "knn",
#   metric = "Accuracy",
#   trControl = knn_trainControl
# )
# saveRDS(train_knn, "train_knn")

knn_train <- readRDS("train_knn")
plot(train_knn)

knn_prediction <- predict(train_knn, newdata = test_images)
print(knn_prediction)
