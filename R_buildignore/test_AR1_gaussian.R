library(imputeFin)
library(xts)

# generate the complete time series
phi0 <- 0
phi1 <- 1
sigma2 <- 0.01 
n <- 300
n_miss <- 30 
n_drop <- 100
n_total <- n + n_drop
data <- vector(length = n_total)
epsilon <- vector(length = n_total)  # innovations
data[1] <- 0
for (i in 2:n_total) {
  epsilon[i] <- rnorm(1, 0, sqrt(sigma2)) 
  data[i] <- phi0 + phi1 * data[i - 1] + epsilon[i]
}
data <- data[(n_drop + 1):n_total]  # drop the first n_drop to reduce the influence of initial point
y_orig <- xts(data,  seq(as.Date("2016-01-01"), length = n, by = "days"))

# creat missing values
index_miss <- sort(sample(2:(n - 1), n_miss))
y <- y_orig
y[index_miss] <- NA

# test the estimation function
estimation_result <- estimateAR1Gaussian(y, random_walk = FALSE, zero_mean = FALSE, ftol = 1e-10,  
                                         maxiter = 1000, output_iterates = TRUE)
layout(matrix(c(1, 2, 3, 4)), heights = c(1,1,1,1))
par(mar = c(4, 5, 0.1, 0.5))
n_iter <- length(estimation_result$phi0_iterate)
plot(1:n_iter,estimation_result$phi0_iterate, pch=19, cex = 0.8,  cex.lab = 1.5, cex.axis = 1.2, xaxt="n",  xlab =" ", type='o', col = "green",   ylab = expression(phi[0]))
plot(1:n_iter,estimation_result$phi1_iterate,  pch=19, cex.lab = 1.5, cex.axis = 1.2, xaxt="n",  xlab =" ",type='o', col = "green", lty = 1,  ylab = expression(phi[1]))
plot(1:n_iter,estimation_result$sigma2_iterate, pch=19, cex.lab = 1.5, cex.axis = 1.2, xaxt="n",  xlab =" ",type='o', col = "green",    ylab = expression(sigma^2) )
plot(1:n_iter,estimation_result$f_iterate, pch=19, cex.lab = 1.5, cex.axis = 1.2,  type='o',col = "green",  xlab ="Iteration k", ylab = "obj" )


# test the imputation function
param = list("phi0" = phi0,
             "phi1" = phi1,
             "sigma2" = sigma2)
imputation_result <- imputeAR1Gaussian(y, n_sample = 1, param = NULL, random_walk = FALSE, zero_mean = TRUE)
y_imputed <- imputation_result$y_imputed
layout(1, heights = 1)
par(mar=c(4, 5, 4, 5))
plot(1:n, y_imputed, type = 'o', pch = 19,  ylab = 'y')
points(index_miss, y_imputed[index_miss, 1], col = 'red', pch = 19)
legend( x="topright", col = c("black", "red"), pch = c(19, 19), legend = c("observed values", "imputed values"))