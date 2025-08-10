# =====================================================
#  SMOTE sampling
# =====================================================

SMOTE <-
  function(x, y, percOver = 1400, k = 5)
           # INPUTS:
           #    x: A data frame of the predictors from training data
           #    y: A vector of response variable from training data
           #    percOver/100: Number of new instance generated for each minority instance
  #    k: Number of nearest neighbours
  {
    # find the class variable
    data <- data.frame(x, y)
    classTable <- table(y)
    numCol <- dim(data)[2]
    tgt <- length(data)

    # find the minority and majority instances
    minClass <- names(which.min(classTable))
    indexMin <- which(data[, tgt] == minClass)
    numMin <- length(indexMin)
    majClass <- names(which.max(classTable))
    indexMaj <- which(data[, tgt] == majClass)
    numMaj <- length(indexMaj)

    # move the class variable to the last column

    # if (tgt < numCol)
    # {
    #   cols <- 1:numCol
    #   cols[c(tgt, numCol)] <- cols[c(numCol, tgt)]
    #   data <- data[, cols]
    # }
    # generate synthetic minority instances
    # source("code/Data level/SmoteExs.R")
    if (percOver < 100) {
      indexMinSelect <- sample(1:numMin, round(numMin * percOver / 100))
      dataMinSelect <- data[indexMin[indexMinSelect], ]
      percOver <- 100
    } else {
      dataMinSelect <- data[indexMin, ]
    }

    newExs <- SmoteExs(dataMinSelect, percOver, k)

    # move the class variable back to original position
    # if (tgt < numCol)
    # {
    #   newExs <- newExs[, cols]
    #   data   <- data[, cols]
    # }

    # unsample for the majority intances
    newData <- rbind(data, newExs)

    return(newData)
  }
# Copyright (C) 2018 Bing Zhu
# ===================================================
# SmoteENN: Smote+ENN
# ===================================================

SmoteENN <-
  function(x, y, percOver = 1400, k1 = 5, k2 = 3, allowParallel = TRUE)
           # INPUTS
           #    x: A data frame of the predictors from training data
           #    y: A vector of response variable from training data
           #    percOver: Percent of new instance generated for each minority instance
           #    k1: Number of the nearest neighbors
           #    k2: Number of neighbours for ENN
  #  allowParallel: A logical number to control the parallel computing. If allowParallel = TRUE, the function is run using parallel techniques
  {
    # source("code/Data level/SMOTE.R")
    newData <- SMOTE(x, y, percOver, k1)
    tgt <- length(newData)
    indexENN <- ENN(tgt, newData, k2, allowParallel)
    newDataRemoved <- newData[!indexENN, ]
    return(newDataRemoved)
  }


# ===================================================
#  ENN: using ENN rule to find the noisy instances
# ===================================================

ENN <-
  function(tgt, data, k, allowParallel) {
    # find column of the target
    numRow <- dim(data)[1]
    indexENN <- rep(FALSE, numRow)

    # transform the nominal data into  binary
    # source("code/Data level/Numeralize.R")
    dataTransformed <- Numeralize(data[, -tgt])
    classMode <- matrix(nrow = numRow)
    library("RANN")
    indexOrder <- nn2(dataTransformed, dataTransformed, k + 1)$nn.idx
    if (allowParallel) {
      classMetrix <- matrix(data[indexOrder[, 2:(k + 1)], tgt], nrow = numRow)
      library("parallel")
      cl <- makeCluster(2)
      classTable <- parApply(cl, classMetrix, 1, table)
      modeColumn <- parLapply(cl, classTable, which.max)
      classMode <- parSapply(cl, modeColumn, names)
      stopCluster(cl)
      indexENN[data[, tgt] != classMode] <- TRUE
    } else {
      for (i in 1:numRow)
      {
        classTable <- table(data[indexOrder[i, ], tgt])
        classMode[i] <- names(which.max(classTable))
      }
    }
    indexENN[data[, tgt] != classMode] <- TRUE
    return(indexENN)
  }
# =========================================================
# SmoteExs: obtain Smote instances for minority instances
# =========================================================

SmoteExs <-
  function(data, percOver, k)
           # Input:
           #     data      : dataset of the minority instances
           #     percOver   : percentage of oversampling
  #     k         : number of nearest neighours
  {
    # transform factors into integer
    nomAtt <- c()
    numRow <- dim(data)[1]
    numCol <- dim(data)[2]
    dataX <- data[, -numCol]
    dataTransformed <- matrix(nrow = numRow, ncol = numCol - 1)
    for (col in 1:(numCol - 1))
    {
      if (is.factor(data[, col])) {
        dataTransformed[, col] <- as.integer(data[, col])
        nomAtt <- c(nomAtt, col)
      } else {
        dataTransformed[, col] <- data[, col]
      }
    }
    numExs <- round(percOver / 100) # this is the number of artificial instances generated
    newExs <- matrix(ncol = numCol - 1, nrow = numRow * numExs)

    indexDiff <- sapply(dataX, function(x) length(unique(x)) > 1)
    # source("code/Data level/Numeralize.R")
    numerMatrix <- Numeralize(dataX[, indexDiff])
    require("RANN")
    id_order <- nn2(numerMatrix, numerMatrix, k + 1)$nn.idx
    for (i in 1:numRow)
    {
      kNNs <- id_order[i, 2:(k + 1)]
      newIns <- InsExs(dataTransformed[i, ], dataTransformed[kNNs, ], numExs, nomAtt)
      newExs[((i - 1) * numExs + 1):(i * numExs), ] <- newIns
    }

    # get factors as in the original data.
    newExs <- data.frame(newExs)
    for (i in nomAtt)
    {
      newExs[, i] <- factor(newExs[, i], levels = 1:nlevels(data[, i]), labels = levels(data[, i]))
    }
    newExs[, numCol] <- factor(rep(data[1, numCol], nrow(newExs)), levels = levels(data[, numCol]))
    colnames(newExs) <- colnames(data)
    return(newExs)
  }

# =================================================================
# InsExs: generate Synthetic instances from nearest neighborhood
# =================================================================

InsExs <-
  function(instance, dataknns, numExs, nomAtt)
           # Input:
           #    instance : selected instance
           #    dataknns : nearest instance set
           #    numExs   : number of new intances generated for each instance
  #    nomAtt   : indicators of factor variables
  {
    numRow <- dim(dataknns)[1]
    numCol <- dim(dataknns)[2]
    newIns <- matrix(nrow = numExs, ncol = numCol)
    neig <- sample(1:numRow, size = numExs, replace = TRUE)

    # generated  attribute values
    insRep <- matrix(rep(instance, numExs), nrow = numExs, byrow = TRUE)
    diffs <- dataknns[neig, ] - insRep
    newIns <- insRep + runif(1) * diffs
    # randomly change nominal attribute
    for (j in nomAtt)
    {
      newIns[, j] <- dataknns[neig, j]
      indexChange <- runif(numExs) < 0.5
      newIns[indexChange, j] <- insRep[indexChange, j]
    }
    return(newIns)
  }
# Copyright (C) 2018 Bing Zhu
# ==============================================
#  SmoteTL: Smote sampling+TomekLinks
# ==============================================

SmoteTL <-
  function(x, y, percOver = 1400, k = 5)
           # Inputs
           #      x    : A data frame of the predictors from training data
           #      y    : A vector of response variable from training data
           #   per_over: Number of new instance generated for each minority instance
  #   k       : Number of nearest neighbors used in Smote
  {
    # source("code/Data level/SMOTE.R")
    newData <- SMOTE(x, y, percOver, k)
    tgt <- length(newData)
    indexTL <- TomekLink(tgt, newData)
    newDataRemoved <- newData[!indexTL, ]
    return(newDataRemoved)
  }


# ==========================================
#  TomekLink: find the TomekLink
# ==========================================

TomekLink <-
  function(tgt, data)
           # Inputs:
           #   form: model formula
           #   data: dataset
           # Output:
  #   logical vector indicating whether a instance is in TomekLinks
  {
    indexTomek <- rep(FALSE, nrow(data))

    # find the column of class variable
    classTable <- table(data[, tgt])

    # seperate the group
    majCl <- names(which.max(classTable))
    minCl <- names(which.min(classTable))

    # get the instances of the larger group
    indexMin <- which(data[, tgt] == minCl)
    # numMin  <- length(indexMin)


    # convert dataset in numeric matrix
    # source("code/Data level/Numeralize.R")
    dataTransformed <- Numeralize(data[, -tgt])

    # generate indicator matrix
    require("RANN")
    indexOrder1 <- nn2(dataTransformed, dataTransformed[indexMin, ], k = 2)$nn.idx
    indexTomekCa <- data[indexOrder1[, 2], tgt] == majCl
    if (sum(indexTomekCa) > 0) {
      TomekCa <- cbind(indexMin[indexTomekCa], indexOrder1[indexTomekCa, 2])

      # find nearest neighbour of potential majority instance
      indexOrder2 <- nn2(dataTransformed, dataTransformed[TomekCa[, 2], ], k = 2)$nn.idx
      indexPaired <- indexOrder2[, 2] == TomekCa[, 1]
      if (sum(indexPaired) > 0) {
        indexTomek[TomekCa[indexPaired, 1]] <- TRUE
        indexTomek[TomekCa[indexPaired, 2]] <- TRUE
      }
    }
    return(indexTomek)
  }
# ======================================================
# Numeralize: convert dataset into numeric matrix
# ======================================================

Numeralize <-
  function(data, form = NULL) {
    if (!is.null(form)) {
      tgt <- which(names(data) == as.character(form[[2]]))
      dataY <- data[drop = FALSE, , tgt]
      dataX <- data[, -tgt]
    } else {
      dataX <- data
    }
    numRow <- dim(dataX)[1]
    # numCol      <- dim(dataX)[2]
    indexOrder <- sapply(dataX, is.ordered)
    indexMultiValue <- sapply(dataX, nlevels) > 2
    indexNominal <- !indexOrder & indexMultiValue
    numerMatrixNames <- NULL
    if (all(indexNominal)) {
      numerMatrix <- NULL
    } else {
      numerMatrix <- dataX[drop = FALSE, , !indexNominal]
      numerMatrixNames <- colnames(numerMatrix)
      numerMatrix <- data.matrix(numerMatrix)
      Min <- apply(numerMatrix, 2, min)
      range <- apply(numerMatrix, 2, max) - Min
      numerMatrix <- scale(numerMatrix, Min, range)[, ]
    }

    if (any(indexNominal)) {
      BiNames <- NULL
      dataNominal <- dataX[drop = FALSE, , indexNominal]
      numNominal <- sum(indexNominal)
      if (numNominal > 1) {
        dimEx <- sum(sapply(dataX[, indexNominal], nlevels))
      } else {
        dimEx <- nlevels(dataX[, indexNominal])
      }
      dataBinary <- matrix(nrow = numRow, ncol = dimEx)
      cl <- 0
      for (i in 1:numNominal)
      {
        numCat <- nlevels(dataNominal[, i])
        for (j in 1:numCat)
        {
          value <- levels(dataNominal[, i])[j]
          ind <- (dataNominal[, i] == value)
          dataBinary[, cl + 1] <- as.integer(ind)
          BiNames[cl + 1] <- paste(names(dataNominal)[i], "_", value, sep = "")
          cl <- cl + 1
        }
      }
      numerMatrix <- cbind(numerMatrix, dataBinary)
      colnames(numerMatrix) <- c(numerMatrixNames, BiNames)
    }

    if (!is.null(form)) {
      numerMatrix <- data.frame(numerMatrix)
      numerMatrix <- cbind(numerMatrix, dataY)
    }
    return(numerMatrix)
  }
