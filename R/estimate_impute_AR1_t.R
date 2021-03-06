#' @title Fit Student's t AR(1) model to time series with missing values and/or outliers
#'
#' @description Estimate the parameters of a univariate Student's t AR(1) 
#'              model to fit the given time series with missing values and/or outliers. 
#'              For multivariate time series, the function will perform a 
#'              number of indidivual univariate fittings without attempting 
#'              to model the correlations among the time series.
#'              If the time series does not contain missing values, the 
#'              maximum likelihood (ML) estimation is done via the iterative
#'              EM algorithm until converge is achieved.
#'              With missing values, the stochastic EM algorithm is employed 
#'              for the estimation (currently the maximum number of iterations
#'              will be executed without attempting to check early converge).
#'
#' @inheritParams fit_AR1_Gaussian
#' @param return_condMean_Gaussian Logical value indicating if the conditional mean and covariance matrix of the 
#'                                 time series (excluding the leading and trailing missing values) given the observed 
#'                                 data are to be returned (default is \code{FALSE}).
#' @param fast_and_heuristic Logical value indicating whether a heuristic but fast method is to be used to 
#'                           estimate the parameters of the Student's t AR(1) model (default is \code{TRUE}).
#' @param n_chain Positive integer indicating the number of the parallel Markov chains in the stochastic 
#'                EM method (default is \code{10}).
#' @param n_thin  Positive integer indicating the sampling period of the Gibbs sampling in the stochastic 
#'                EM method (default is \code{1}). Every \code{n_thin}-th samples is used. This is aimed 
#'                to reduce the dependence of the samples.
#' @param K Positive number controlling the values of the step sizes in the stochastic EM method 
#'          (default is \code{30}).
#' 
#' @return If the argument \code{y} is a univariate time series (i.e., coercible to a numeric vector), then this 
#'         function will return a list with the following elements:
#' \item{\code{phi0}}{The estimate for \code{phi0} (real number).}
#' \item{\code{phi1}}{The estimate for \code{phi1} (real number).}
#' \item{\code{sigma2}}{The estimate for \code{sigma^2} (positive number).}
#' \item{\code{nu}}{The estimate for \code{nu} (positive number).}
#' \item{\code{phi0_iterates}}{Numeric vector with the estimates for \code{phi0} at each iteration
#'                            (returned only when \code{return_iterates = TRUE}).}
#' \item{\code{phi1_iterates}}{Numeric vector with the estimates for \code{phi1} at each iteration
#'                            (returned only when \code{return_iterates = TRUE}).}
#' \item{\code{sigma2_iterates}}{Numeric vector with the estimates for \code{sigma^2} at each iteration
#'                              (returned only when \code{return_iterates = TRUE}).}
#' \item{\code{nu_iterate}}{Numeric vector with the estimates for \code{nu} at each iteration
#'                          (returned only when \code{return_iterates = TRUE}).}
#' \item{\code{f_iterates}}{Numeric vector with the objective values at each iteration
#'                          (returned only when \code{return_iterates = TRUE}).}
#' \item{\code{cond_mean_y_Gaussian}}{Numeric vector (of same length as argument \code{y}) with the conditional mean of the 
#'                                    time series (excluding the missing values at the head and tail) given the observed data based 
#'                                    on Gaussian AR(1) model (returned only when \code{return_condMean_Gaussian = TRUE}).}
#' \item{\code{index_miss}}{Indices of missing values imputed.}
#' \item{\code{index_outliers}}{Indices of outliers detected/corrected.}
#'
#' If the argument \code{y} is a multivariate time series (i.e., with multiple columns and coercible to a numeric matrix), 
#' then this function will return a list with each element as in the case of univariate \code{y} corresponding to each
#' of the columns (i.e., one list element per column of \code{y}), with the following additional elements that combine the 
#' estimated values in a convenient vector form:
#' \item{\code{phi0_vct}}{Numeric vector (with length equal to the number of columns of \code{y})
#'                        with the estimates for \code{phi0} for each of the univariate time series.}
#' \item{\code{phi1_vct}}{Numeric vector (with length equal to the number of columns of \code{y})
#'                        with the estimates for \code{phi1} for each of the univariate time series.}
#' \item{\code{sigma2_vct}}{Numeric vector (with length equal to the number of columns of \code{y})
#'                        with the estimates for \code{sigma2} for each of the univariate time series.}
#' \item{\code{nu_vct}}{Numeric vector (with length equal to the number of columns of \code{y})
#'                      with the estimates for \code{nu} for each of the univariate time series.}
#' 
#' @author Junyan Liu and Daniel P. Palomar
#' 
#' @seealso \code{\link{impute_AR1_t}}, \code{\link{fit_AR1_Gaussian}}
#' 
#' @references 
#' J. Liu, S. Kumar, and D. P. Palomar, "Parameter estimation of heavy-tailed AR model with missing 
#' data via stochastic EM," IEEE Trans. on Signal Processing, vol. 67, no. 8, pp. 2159-2172, 15 April, 2019. 
#'
#' @examples 
#' library(imputeFin)
#' data(ts_AR1_t) 
#' y_missing <- ts_AR1_t$y_missing
#' fitted <- fit_AR1_t(y_missing)
#' 
#' @import zoo
#' @import MASS
#' @import stats
#' @export
fit_AR1_t <- function(y, random_walk = FALSE, zero_mean = FALSE, fast_and_heuristic = TRUE, remove_outliers = FALSE, outlier_prob_th = 1e-3, 
                         verbose = TRUE,
                         return_iterates = FALSE, return_condMean_Gaussian = FALSE,
                         tol = 1e-8, maxiter = 100, n_chain = 10, n_thin = 1, K = 30) {
  # error control
  if (!is.matrix(try(as.matrix(y), silent = TRUE))) stop("\"y\" must be coercible to a vector or matrix.")
  if (tol <= 0) stop("\"tol\" must be greater than 0.")
  if (maxiter < 1) stop("\"maxiter\" must be greater than 1.")
  if (round(n_chain)!=n_chain | n_chain<=0) stop("\"n_chain\" must be a positive integer.")
  if (round(n_thin)!=n_thin | n_thin<=0) stop("\"n_thin\" must be a positive integer.")
  if (round(K)!=K | K<=0) stop("\"K\" must be a positive integer.")
  
  # manage multiple columns
  if (NCOL(y) > 1) {
    estimation_list <- apply(y, MARGIN = 2, FUN = fit_AR1_t, random_walk, zero_mean, fast_and_heuristic, remove_outliers, outlier_prob_th, verbose = FALSE,
                                                             return_iterates, return_condMean_Gaussian, tol, maxiter, n_chain, n_thin, K)
    phi0_vct   <- unlist(lapply(estimation_list, function(x) x$phi0))
    phi1_vct   <- unlist(lapply(estimation_list, function(x) x$phi1))
    sigma2_vct <- unlist(lapply(estimation_list, function(x) x$sigma2))
    nu_vct     <- unlist(lapply(estimation_list, function(x) x$nu))
    # output messages
    if (verbose)
      for (i in 1:length(estimation_list))
        message(names(estimation_list)[i], ": ", 
                length(estimation_list[[i]]$index_miss), " inner missing values and ", 
                length(estimation_list[[i]]$index_outliers), " outliers detected.")
    return(c(estimation_list, list("phi0_vct"   = phi0_vct,
                                   "phi1_vct"   = phi1_vct,
                                   "sigma2_vct" = sigma2_vct,
                                   "nu_vct"     = nu_vct)))
  }
  
  #
  #   code for y single-column
  #
  # error control
  if (!is.numeric(y)) stop("\"y\" only allows numerical or NA values.")
  if (sum(!is.na(y)) < 5L) stop("Each time series in \"y\" must have at least 5 observations.")
  y_name <- colnames(y)
  y <- as.numeric(y)
  
  # outlier detection and substitution with NAs
  if(remove_outliers) {
    fitted_with_outliers <- if (!any_inner_NA(y)) fit_AR1_t_complete(y[!is.na(y)], random_walk, zero_mean, return_iterates, tol, maxiter)
                            else fit_AR1_t(y, random_walk, zero_mean, fast_and_heuristic, remove_outliers = FALSE, outlier_prob_th, verbose = FALSE,
                                           return_iterates, return_condMean_Gaussian, tol, maxiter, n_chain, n_thin, K)
    idx_outliers <- find_outliers_AR1_t(y, fitted_with_outliers, outlier_prob_th)
    if (!is.null(idx_outliers))
      y[idx_outliers] <- NA  # substitute outliers with NAs
  }
  
  # remove the missing values at the head and tail of the time series since they do not affect the estimation result
  index_obs <- which(!is.na(y))
  y <- y[min(index_obs):max(index_obs)]
  idx_offset <- min(index_obs) - 1L
  index_obs <- which(!is.na(y))
  
  # estimation (after possibly setting outliers to NA)
  if (!anyNA(y))   # trivial case with no NAs
    results <- fit_AR1_t_complete(y, random_walk, zero_mean, return_iterates, tol, maxiter)
  else {
    # if there are NAs find the missing blocks
    n <- index_obs <- index_miss <- n_obs <- y_obs <- delta_index_obs <- n_block <- n_in_block <- 
        first_index_in_block <- last_index_in_block <- previous_obs_before_block <- next_obs_after_block <- NULL
    list2env(findMissingBlock(y), envir = environment())
    
    if (fast_and_heuristic)
      results <- fit_AR1_t_heuristic(y, index_miss, random_walk, zero_mean, return_iterates, return_condMean_Gaussian, tol, maxiter)
    else {
      # initialize the estimates and some parameters
      phi0 <- phi1 <- sigma2 <- nu <- gamma <- c()
      estimation_Gaussian <- fit_AR1_Gaussian(y, random_walk, zero_mean, verbose = FALSE, return_condMeanCov = TRUE)
      phi0[1]   <- estimation_Gaussian$phi0
      phi1[1]   <- estimation_Gaussian$phi1
      sigma2[1] <- estimation_Gaussian$sigma2
      nu[1]     <- 3
      y_samples <- matrix(estimation_Gaussian$cond_mean_y, n, n_chain)
      tau_samples <- matrix(NA, n, n_chain)
      s <- s_approx <- rep(0, 7)  # approximations of the sufficient statistics
      
      # loop
      for (k in 1:maxiter) {
        # draw realizations of the missing values from their posterior distribution
        for (j in 1:n_chain) {
          sample <- sampling_latent_variables(y_sample_init = y_samples[, j], n_thin, n_block, n_in_block,
                                              first_index_in_block, last_index_in_block, previous_obs_before_block, next_obs_after_block,
                                              phi0[k], phi1[k], sigma2[k], nu[k])
          y_samples[, j] <- sample$y
          tau_samples[, j] <- sample$tau
        }
        # # Daniel: try to implement loop above in parallel
        # lmd <- t(sapply(1:n_chain, FUN = function(k) {
        #   Ut <- eigen(cov(X[-c(t0[k]:t1[k]), ]), symmetric = TRUE)$vectors
        #   colMeans((X[c(t0[k]:t1[k]), , drop = FALSE] %*% Ut)^2)
        # }))
        
        # approximate the sufficient statistics
        if (k <= K)
          gamma[k] <- 1
        else
          gamma[k] <- 1/(k - K)
        
        s[1] <- sum(log(tau_samples[2:n,]) - tau_samples[2:n,]) / n_chain
        s[2] <- sum(tau_samples[2:n,] * y_samples[2:n,]^2) / n_chain
        s[3] <- sum(tau_samples[2:n,] ) / n_chain
        s[4] <- sum(tau_samples[2:n,] * y_samples[1:(n-1),]^2) / n_chain
        s[5] <- sum(tau_samples[2:n,] * y_samples[2:n,]) / n_chain
        s[6] <- sum(tau_samples[2:n,] * y_samples[2:n,] * y_samples[1:(n - 1),]) / n_chain
        s[7] <- sum(tau_samples[2:n,] * y_samples[1:(n-1),]) / n_chain
        s_approx <- s_approx + gamma[k] * (s - s_approx)
        
        # update the estimates
        if (!random_walk && !zero_mean) {
          phi1[k+1] <- ( s_approx[3] * s_approx[6] - s_approx[5] * s_approx[7] ) / ( s_approx[3] * s_approx[4] -  s_approx[7]^2 )
          phi0[k+1] <- (s_approx[5] - phi1[k+1] * s_approx[7] ) / s_approx[3]
        } else if (random_walk && !zero_mean){
          phi1[k+1] <- 1
          phi0[k+1] <- (s_approx[5] -  s_approx[7] ) / s_approx[3]
        } else if (!random_walk && zero_mean){
          phi1[k+1] <- s_approx[6] / s_approx[4] 
          phi0[k+1] <- 0
        } else{
          phi1[k+1] <- 1
          phi0[k+1] <- 0
        }
        sigma2[k+1] <- (s_approx[2] + phi0[k+1]^2 * s_approx[3] + phi1[k+1]^2 * s_approx[4] - 2 * phi0[k+1] * s_approx[5]
                        - 2 * phi1[k+1] * s_approx[6] + 2 * phi0[k+1] * phi1[k+1] * s_approx[7]) / (n - 1)
        
        f_nu <- function(nu, n, s_approx1)
          return(-sum(0.5 * nu * s_approx1 +  (0.5 * nu * log(0.5 * nu) - lgamma(0.5 * nu)) * (n - 1)))
        
        optimation_result <- optimize(f_nu, c(1e-6, 1e6), n, s_approx[1])
        nu[k + 1] <- optimation_result$minimum
      }
      
      # collect results to return
      results <- list("phi0"   = phi0[k + 1],
                      "phi1"   = phi1[k + 1],
                      "sigma2" = sigma2[k + 1],
                      "nu"     = nu[k + 1])
      if (return_iterates) 
        results <- c(results, list("phi0_iterates"   = phi0,
                                   "phi1_iterates"   = phi1,
                                   "sigma2_iterates" = sigma2,
                                   "nu_iterates"     = nu))
      if(return_condMean_Gaussian)
        results <- c(results, list("cond_mean_y_Gaussian" = estimation_Gaussian$cond_mean_y))
    }
  }
  results <- c(results, list("index_miss" = if (sum(is.na(y)) == 0) NULL
                                            else which(is.na(y)) + idx_offset))  
  if(!remove_outliers) idx_outliers <- NULL
  results <- c(results, list("index_outliers" = if(is.null(idx_outliers)) NULL
                                                else idx_outliers + idx_offset))
  # output message
  if (verbose)
    message(y_name, ": ", 
            length(results$index_miss), " inner missing values and ", 
            length(results$index_outliers), " outliers detected.") 
  return(results)
}





#' @title Impute missing values of time series based on a Student's t AR(1) model
#'
#' @description Impute inner missing values (excluding leading and trailing ones) 
#'              of time series by drawing samples from the conditional distribution 
#'              of the missing values given the observed data based on a Student's t 
#'              AR(1) model as estimated with the function \code{\link{fit_AR1_t}}. 
#'              Outliers can be detected and removed.
#'
#' @inheritParams impute_AR1_Gaussian
#' @inheritParams fit_AR1_t
#' @param n_burn Positive integer controlling the length of the burn-in period of the Gibb sampling 
#'               (default is \code{100}). The first \code{(n_burn * n_thin)} samples generated will 
#'               be ignored.
#' 
#' @return By default (i.e., for \code{n_samples = 1} and \code{return_estimates = FALSE}), 
#'         the function will return an imputed time series of the same class and dimensions 
#'         as the argument \code{y} with one new attribute recording the locations of missing 
#'         values (the function \code{\link{plot_imputed}} will make use of such information
#'         to indicate the imputed values), as well as locations of outliers removed.
#'         
#'         If \code{n_samples > 1}, the function will return a list consisting of \code{n_sample} 
#'         imputed time series with names: y_imputed.1, y_imputed.2, etc.
#'         
#'         If \code{return_estimates = TRUE}, in addition to the imputed time series \code{y_imputed}, 
#'         the function will return the estimated model parameters:
#'         \item{\code{phi0}}{The estimate for \code{phi0} (numeric scalar or vector depending 
#'                            on the number of time series).}
#'         \item{\code{phi1}}{The estimate for \code{phi1} (numeric scalar or vector depending 
#'                            on the number of time series).}
#'         \item{\code{sigma2}}{The estimate for \code{sigma2} (numeric scalar or vector depending 
#'                              on the number of time series).}
#'         \item{\code{nu}}{The estimate for \code{nu} (numeric scalar or vector depending 
#'                          on the number of time series).}
#'
#' @author Junyan Liu and Daniel P. Palomar
#' 
#' @seealso \code{\link{plot_imputed}}, \code{\link{fit_AR1_t}}, \code{\link{impute_AR1_Gaussian}}
#' 
#' @references 
#' J. Liu, S. Kumar, and D. P. Palomar, "Parameter estimation of heavy-tailed AR model with missing 
#' data via stochastic EM," IEEE Trans. on Signal Processing, vol. 67, no. 8, pp. 2159-2172, 15 April, 2019. 
#' 
#' @examples
#' library(imputeFin)
#' data(ts_AR1_t) 
#' y_missing <- ts_AR1_t$y_missing
#' y_imputed <- impute_AR1_t(y_missing)
#' plot_imputed(y_imputed)
#' 
#' @import zoo
#' @import MASS
#' @import stats
#' @export
impute_AR1_t <- function(y, n_samples = 1,
                         random_walk = FALSE, zero_mean = FALSE, 
                         fast_and_heuristic = TRUE, remove_outliers = FALSE, outlier_prob_th = 1e-3,
                         verbose = TRUE, return_estimates = FALSE,
                         tol = 1e-8,  maxiter = 100, K = 30, 
                         n_burn = 100, n_thin = 50) {
  # error control
  if (!is.matrix(try(as.matrix(y), silent = TRUE))) stop("\"y\" must be coercible to a vector or matrix.")
  if (round(n_samples)!=n_samples | n_samples<=0) stop("\"n_samples\" must be a positive integer.")
  if (round(n_burn)!=n_burn | n_burn<=0) stop("\"n_burn\" must be a positive integer.")
  if (round(n_thin)!=n_thin | n_thin<=0) stop("\"n_thin\" must be a positive integer.")
  
  # manage multiple columns
  if (NCOL(y) > 1) {
    results_list <- lapply(c(1:NCOL(y)), FUN = function(i) { 
      impute_AR1_t(y[, i, drop = FALSE], n_samples, random_walk, zero_mean, fast_and_heuristic, remove_outliers, outlier_prob_th, verbose = FALSE,
                   return_estimates, tol, maxiter, K, n_burn, n_thin) 
      })
    names(results_list) <- colnames(y)
    if (n_samples == 1 && !return_estimates) {  # return directly a matrix like y
      results <- do.call(cbind, results_list)
      attr(results, "index_miss")     <- lapply(results_list, FUN = function(res) attr(res, "index_miss"))
      attr(results, "index_outliers") <- lapply(results_list, FUN = function(res) attr(res, "index_outliers"))
    } else if (n_samples == 1 && return_estimates) {
      results <- do.call(mapply, c("FUN" = cbind, results_list, "SIMPLIFY" = FALSE))
      attr(results$y_imputed, "index_miss")     <- lapply(results_list, FUN = function(res) attr(res$y_imputed, "index_miss"))
      attr(results$y_imputed, "index_outliers") <- lapply(results_list, FUN = function(res) attr(res$y_imputed, "index_outliers"))
    } else {
      results <- do.call(mapply, c("FUN" = cbind, results_list, "SIMPLIFY" = FALSE))
      index_miss_list     <- lapply(results_list, FUN = function(res) attr(res$y_imputed.1, "index_miss"))
      index_outliers_list <- lapply(results_list, FUN = function(res) attr(res$y_imputed.1, "index_outliers"))
      for (i in 1:n_samples) {
        attr(results[[i]], "index_miss")     <- index_miss_list
        attr(results[[i]], "index_outliers") <- index_outliers_list
      }
      if (return_estimates) {
        results$phi0   <- as.vector(results$phi0)
        results$phi1   <- as.vector(results$phi1)
        results$sigma2 <- as.vector(results$sigma2)
        results$nu     <- as.vector(results$nu)
      }
    }
    # output messages
    if (verbose)
      for (i in 1:length(results_list))
        message(names(results_list)[i], ": ", 
                length(attr(results_list[[i]], "index_miss")), " inner missing values imputed and ", 
                length(attr(results_list[[i]], "index_outliers")), " outliers detected and corrected.")
    return(results)
  }  
  
  #
  #   code for y single-column
  #
  # error control
  if (!is.numeric(y)) stop("\"y\" only allows numerical or NA values.")
  if (sum(!is.na(y)) < 5) stop("Each time series in \"y\" must have at least 5 observations.")
  
  y_attrib <- attributes(y)
  y_name <- colnames(y)  
  y <- as.numeric(y)
  y_imputed <- matrix(rep(y, times = n_samples), ncol = n_samples)

  if (remove_outliers) {
    fitted <- fit_AR1_t(y, random_walk, zero_mean, fast_and_heuristic, remove_outliers = TRUE, outlier_prob_th = outlier_prob_th, verbose = FALSE, 
                        tol = tol, maxiter = maxiter, K = K)
    if (!is.null(index_outliers <- fitted$index_outliers))
      y[index_outliers] <- NA
  }  
  
  # imputation
  if (!any_inner_NA(y)) {  # trivial case with no inner NAs: do nothing
    if (return_estimates && !remove_outliers) 
      fitted <- fit_AR1_t(y, random_walk, zero_mean, fast_and_heuristic, remove_outliers = FALSE, verbose = FALSE, tol = tol, maxiter = maxiter, K = K)
  } else {
    fitted <- fit_AR1_t(y, random_walk, zero_mean, fast_and_heuristic, remove_outliers = FALSE, verbose = FALSE, 
                        return_condMean_Gaussian = TRUE, tol = tol,  maxiter = maxiter, K = K)
    index_obs <- which(!is.na(y))
    index_obs_min <- min(index_obs)
    index_miss_middle <- which(is_inner_NA(y))
    if (length(index_miss_middle) > 0) {
      y_middle <- y[min(index_obs):max(index_obs)]  # ignore the missing values at the head and tail
      index_miss_deleted <- index_miss_middle - (index_obs_min - 1)
      n <- index_obs <- index_miss <- n_obs <- y_obs <- delta_index_obs <- n_block <- n_in_block <- 
        first_index_in_block <- last_index_in_block <- previous_obs_before_block <- next_obs_after_block <- NULL
      list2env(findMissingBlock(y_middle), envir = environment())
      y_middle_tmp <- fitted$cond_mean_y_Gaussian
      for (i in 1:n_burn) {
        sample <- sampling_latent_variables(y_middle_tmp, n_thin = 1, n_block, n_in_block,
                                            first_index_in_block, last_index_in_block, previous_obs_before_block, next_obs_after_block,
                                            fitted$phi0, fitted$phi1, fitted$sigma2, fitted$nu) 
        y_middle_tmp <- sample$y
      }
      # sample every n_thin-th sample
      for (j in 1:n_samples) {
        sample <- sampling_latent_variables(y_middle_tmp, n_thin, n_block, n_in_block,
                                            first_index_in_block, last_index_in_block, previous_obs_before_block, next_obs_after_block,
                                            fitted$phi0, fitted$phi1, fitted$sigma2, fitted$nu) 
        y_imputed[index_miss_middle, j] <- sample$y[index_miss_deleted]
      }
    }
  }
  
  # prepare results
  index_miss <- which(is_inner_NA(y))
  if (length(index_miss) == 0) index_miss <- NULL
  if(!remove_outliers) index_outliers <- NULL
  if (n_samples == 1) {
    attributes(y_imputed) <- y_attrib
    attr(y_imputed, "index_miss") <- index_miss
    attr(y_imputed, "index_outliers") <- index_outliers
    results <- if (!return_estimates) y_imputed else list("y_imputed" = y_imputed)
  } else {
    y_imputed <-lapply(split(y_imputed, col(y_imputed)), FUN = function(x) { attributes(x) <- y_attrib
                                                                             attr(x, "index_miss") <- index_miss
                                                                             attr(x, "index_outliers") <- index_outliers
                                                                             return(x) })
    results <- c("y_imputed" = y_imputed)
  }
  if (return_estimates)  results <- c(results, list("phi0"   = fitted$phi0,
                                                    "phi1"   = fitted$phi1,
                                                    "sigma2" = fitted$sigma2,
                                                    "nu"     = fitted$nu))
  # output message
  if (verbose)
    message(y_name, ": ", 
            length(index_miss), " missing values imputed and ", 
            length(index_outliers), " outliers detected and corrected.") 
  return(results)
}




# Sampling the latent variables y and tau from the conditional distribution via Gibbs sampling.
#   y_sample_init: a vector of real numbers indicating the initialization for y.
#   n_burn:  a positive integer indicating controling the length of the burn-in period of the Gibb sampling. The first (n_burn * n_thin) samples generated will be ignored.
#   n_thin:  a positive integer indicating the sampling period of Gibbs sampling. After then burn-in perid, every n_thin-th sample is used. This is aimed to reduce the dependence of the samples.
#   n_block: a positive integer indicating the number of the missing blocks.
#   n_in_block: a positive integer indicating the numbers of the missing values in each block.
#   first_index_in_block: a vector of positive integers consisting of  the indexes of the first missing value in each missing block.
#   last_index_in_block: a vector of positive integers consisting of  the indexes of the last missing value in each missing block.
#   previous_obs_before_block: a vector of real numbers consisting of the observed values before each missing block.
#   next_obs_after_block: a vector of real numbers consisting of the observed values after each missing block.
#   phi0: a real number, a parameter of the student's t AR(1) model.
#   phi1: a real number, a parameter of the student's t AR(1) model.
#   sigma2: a positive number, a parameter of the student's t AR(1) model.
#   nu: a positive number indicating the degree of freedom, a parameter of the student's t AR(1) model.
#' @import MASS
sampling_latent_variables <- function(y_sample_init, n_thin, n_block, n_in_block,
                                    first_index_in_block, last_index_in_block, previous_obs_before_block, next_obs_after_block,
                                    phi0, phi1, sigma2, nu) {
  n <- length(y_sample_init)
  tau_tmp <- vector(length = n)
  y_tmp <-  y_sample_init
  
  max_n_in_block <- max( n_in_block ) # maximum number of missing values in the blocks
  phi1_exponential <- phi1^( 0:(max_n_in_block + 1) )
  sum_phi1_exponential <- cumsum(phi1_exponential)
  
  for(j in 1:n_thin){
    # sample tau
    for (i_tau in 2:n) {
      tau_tmp[i_tau] <- rgamma(n = 1, shape = 0.5 * nu + 0.5,
                               rate = 0.5 * ( (y_tmp[i_tau] - phi0 - phi1 * y_tmp[i_tau - 1])^2 / sigma2 + nu) )
    }
    # sample y
    for (d in 1:n_block )  {
      n_in_d_block <- n_in_block[d] # number of missing values in the d-th missing block
      mu_cd <- ( sum_phi1_exponential[1:(n_in_d_block + 1)] * phi0 
                 + phi1_exponential[2:(n_in_d_block + 2)] *  previous_obs_before_block[d] )
      mu1 <- mu_cd[1:n_in_d_block]
      mu2 <- mu_cd[n_in_d_block + 1]
      
      sigma_cd <- matrix( nrow = n_in_d_block + 1, ncol = n_in_d_block + 1)
      
      for(i in 1 : (n_in_d_block + 1) ){
        if(i == 1){ sigma_cd[1, 1] <- sigma2/tau_tmp[ first_index_in_block[d] ]
        } else {
          sigma_cd[i, i] <- sigma_cd[ i - 1, i - 1 ] * phi1^2 + sigma2/tau_tmp[ first_index_in_block[d] + i - 1]
        }
        
        if( i != n_in_d_block + 1){
          sigma_cd[ i, (i + 1) : (n_in_d_block + 1)] <- sigma_cd[ i, i ] * phi1_exponential[ 2:(n_in_d_block + 1 - i + 1) ]
          sigma_cd[ (i + 1) : (n_in_d_block + 1), i ] <- sigma_cd[ i, i ] * phi1_exponential[ 2:(n_in_d_block + 1 - i + 1) ]
        }
      }
      sigma11 <- sigma_cd[ 1 : n_in_d_block, 1 : n_in_d_block]
      sigma12 <- sigma_cd[ 1 : n_in_d_block, n_in_d_block + 1]
      sigma22 <- sigma_cd[ n_in_d_block + 1, n_in_d_block + 1]
      
      mu_d <- mu1 + sigma12 / sigma22  * ( next_obs_after_block[d] - mu2 )
      sigma_d <- sigma11 - sigma12 %*% t( sigma12 )/sigma22  
      
      y_tmp[ first_index_in_block[d] : last_index_in_block[d]] <- MASS::mvrnorm( n = 1, mu = mu_d, Sigma = sigma_d )
    }
  }
  return(list("y" = y_tmp, 
              "tau" = tau_tmp))
}




#  estimate the parameters of a Student's t AR(1) model from a complete time series
#  y: numeric vector.
fit_AR1_t_complete <- function(y, random_walk = FALSE, zero_mean = FALSE, 
                               return_iterates = FALSE,
                               tol = 1e-10,  maxiter = 1000) {
  if (anyNA(y)) stop("Function fit_AR1_t_complete() cannot accept NAs.")
  
  phi0 <- phi1 <- sigma2 <- nu <- c()
  #estimation_Gaussian <- fit_AR1_Gaussian(y, random_walk, zero_mean, verbose = FALSE, return_condMeanCov = FALSE)
  estimation_Gaussian <- fit_AR1_Gaussian_complete(y, random_walk, zero_mean)
  
  phi0[1] <- estimation_Gaussian$phi0
  phi1[1] <- estimation_Gaussian$phi1
  sigma2[1] <- estimation_Gaussian$sigma2
  nu[1] <- 3
  n <- length(y)
  tmp <- (y[-1] - phi0[1] - phi1[1] * y[-n])^2/sigma2[1]
  exp_tau <- vector( length = n )
  
  if (return_iterates) {
    f = vector()
    f[1] = sum( log(  gamma( 0.5 * (nu[1] + 1) )/gamma( 0.5 * nu[1] )/sqrt( pi * nu[1] * sigma2[1] ) )
                + - 0.5 * (nu[1] + 1) * log( (y[-1] - phi0[1] - phi1[1] * y[-n])^2/sigma2[1]/nu[1] + 1 ) ) 
  }

  for ( k in 1:maxiter) {
    exp_tau = (nu[k] + 1)/( nu[k] + tmp )
    s_tau = sum( exp_tau )
    s_tau_y2 = sum( exp_tau * y[-1] )
    s_tau_y1 = sum( exp_tau * y[-n] )
    s_tau_y1y2 = sum( exp_tau * y[-n] * y[-1] )
    s_tau_y1y1 = sum( exp_tau * y[-n] * y[-n] )
  
    if (!random_walk && !zero_mean) {
      phi1[k+1] <- (s_tau * s_tau_y1y2 - s_tau_y2 * s_tau_y1 )/(s_tau * s_tau_y1y1 - s_tau_y1^2)
      phi0[k+1] <- (s_tau_y2 - phi1[k+1] * s_tau_y1)/s_tau
    } else if (random_walk && !zero_mean){
      phi1[k+1] <- 1
      phi0[k+1] <- (s_tau_y2 - s_tau_y1)/s_tau
    } else if (!random_walk && zero_mean){
      phi1[k+1] <- s_tau_y1y2 / s_tau_y1y1 
      phi0[k+1] <- 0
    } else{
      phi1[k+1] <- 1
      phi0[k+1] <- 0
    }
    sigma2[k+1] = sum( exp_tau * (y[-1] - phi0[k+1] - phi1[k+1] * y[-n])^2 )/(n - 1)
    tmp = (y[-1] - phi0[k+1] - phi1[k+1] * y[-n])^2/sigma2[k+1]
    
    # minus log-likelihood about nu,  with mu and sigma fixed as mu[k+1] and sigma[k+1]
    f_nu = function( nu){
      f_nu = - sum ( - 0.5 * (nu + 1) * log( nu + tmp)
                     + lgamma ( 0.5*(nu + 1) ) - lgamma (0.5*nu) + 0.5 * nu * log(nu ) )
      return( f_nu )
    }
    
    opt_rst = optimise ( f_nu, c(1e-6, 1e6) )
    nu[k+1] = opt_rst$minimum
    
#    g[k] = sum( log(  gamma( 0.5 * (nu[k] + 1) )/gamma( 0.5 * nu[k] )/sqrt( pi * nu[k] * sigma[k+1] ) )
#                + - 0.5 * (nu[k] + 1) * log( tmp/nu[k] + 1 ) )   
    if (return_iterates) f[k+1] = sum( log(  gamma( 0.5 * (nu[k+1] + 1) )/gamma( 0.5 * nu[k+1] )/sqrt( pi * nu[k+1] * sigma2[k+1] ) )
                   - 0.5 * (nu[k+1] + 1) * log( tmp/nu[k+1] + 1 ) ) 
    
    if (abs(phi0[k + 1] - phi0[k]) <= tol * (abs(phi0[k + 1]) + abs(phi0[k]))/2
        && abs(phi1[k + 1] - phi1[k]) <= tol * (abs(phi1[k + 1]) + abs(phi1[k]))/2
        && abs(sigma2[k + 1] - sigma2[k]) <= tol * (abs(sigma2[k + 1]) + abs(sigma2[k]))/2
        && KLgamma(nu[k]/2, nu[k]/2, nu[k+1]/2, nu[k+1]/2) <= tol) 
        ## && abs(nu[k + 1] - nu[k]) <= tol * (abs(nu[k + 1]) + abs(nu[k]))/2) 
    break
    
  }
  
  results <- list("phi0" = phi0[k+1], 
                  "phi1" = phi1[k+1], 
                  "sigma2" = sigma2[k+1], 
                  "nu" = nu[k+1])
  if (return_iterates) 
    results <- c(results, list("phi0_iterate" = phi0,
                               "phi1_iterate" = phi1,
                               "sigma2_iterate" = sigma2,
                               "nu_iterate" = nu,
                               "f_iterate" = f))
  return(results)
}




#  heuristic method to estimate the parameters of a Student's t AR(1) model from a incomplete time series
#  y: numeric vector.
fit_AR1_t_heuristic <- function(y, index_miss, random_walk = FALSE, zero_mean = TRUE,
                                return_iterates = FALSE, return_condMean_Gaussian = FALSE,
                                tol = 1e-10,  maxiter = 1000) {
  # initialize the estimates and some parameters
  phi0 <- phi1 <- sigma2 <- nu <- gamma <- c()
  estimation_Gaussian <- fit_AR1_Gaussian(y, random_walk, zero_mean, verbose = FALSE, return_condMeanCov = return_condMean_Gaussian)
  phi0[1] <- estimation_Gaussian$phi0
  phi1[1] <- estimation_Gaussian$phi1
  sigma2[1] <- estimation_Gaussian$sigma2
  nu[1] <- 3
    
  index_miss_p <- c(0, index_miss, length(y) + 1)
  delta_index_miss_p <- diff(index_miss_p)
  index_delta_index_miss_p <- which(delta_index_miss_p > 2)
  n_obs_block <- length(index_delta_index_miss_p)  # number of observation blocks with more than 1 sample
  n_in_obs_block <- delta_index_miss_p[index_delta_index_miss_p] - 1  # number of observed samples in each qualified observation block
  m <- 0
  y_obs2 <- y_obs1 <- c()
  for (i in 1:n_obs_block) {
    y_obs1[(m + 1):(m + n_in_obs_block[i] - 1)] <- y[(index_miss_p[index_delta_index_miss_p[i]] + 1):(index_miss_p[index_delta_index_miss_p[i] + 1] - 2)]
    y_obs2[(m + 1):(m + n_in_obs_block[i] - 1)] <- y[(index_miss_p[index_delta_index_miss_p[i]] + 2):(index_miss_p[index_delta_index_miss_p[i] + 1] - 1)]
    m <- m + n_in_obs_block[i] - 1
  }
  n_y_obs1 <- length(y_obs1)
  
  tmp <- (y_obs2 - phi0[1] - phi1[1] * y_obs1)^2/sigma2[1]
  exp_tau <- vector( length = n_y_obs1 )
  
  if (return_iterates) {
    f = vector()
    f[1] = sum( log(  gamma( 0.5 * (nu[1] + 1) )/gamma( 0.5 * nu[1] )/sqrt( pi * nu[1] * sigma2[1] ) )
                + - 0.5 * (nu[1] + 1) * log( (y_obs2 - phi0[1] - phi1[1] * y_obs1)^2/sigma2[1]/nu[1] + 1 ) ) 
  }
  
  for ( k in 1:maxiter) {
    exp_tau = (nu[k] + 1)/( nu[k] + tmp )
    s_tau = sum( exp_tau )
    s_tau_y2 = sum( exp_tau * y_obs2 )
    s_tau_y1 = sum( exp_tau * y_obs1 )
    s_tau_y1y2 = sum( exp_tau * y_obs1 * y_obs2 )
    s_tau_y1y1 = sum( exp_tau * y_obs1 * y_obs1 )
    
    if (!random_walk && !zero_mean) {
      phi1[k+1] <- (s_tau * s_tau_y1y2 - s_tau_y2 * s_tau_y1 )/(s_tau * s_tau_y1y1 - s_tau_y1^2)
      phi0[k+1] <- (s_tau_y2 - phi1[k+1] * s_tau_y1)/s_tau
    } else if (random_walk && !zero_mean){
      phi1[k+1] <- 1
      phi0[k+1] <- (s_tau_y2 - s_tau_y1)/s_tau
    } else if (!random_walk && zero_mean){
      phi1[k+1] <- s_tau_y1y2 / s_tau_y1y1 
      phi0[k+1] <- 0
    } else{
      phi1[k+1] <- 1
      phi0[k+1] <- 0
    }
    sigma2[k+1] = sum( exp_tau * (y_obs2 - phi0[k+1] - phi1[k+1] * y_obs1)^2 )/n_y_obs1
    tmp = (y_obs2 - phi0[k+1] - phi1[k+1] * y_obs1)^2/sigma2[k+1]
    
    # minus log-likelihood about nu,  with mu and sigma fixed as mu[k+1] and sigma[k+1]
    f_nu = function( nu){
      f_nu = - sum ( - 0.5 * (nu + 1) * log( nu + tmp)
                     + lgamma ( 0.5*(nu + 1) ) - lgamma (0.5*nu) + 0.5 * nu * log(nu ) )
      return( f_nu )
    }
    
    opt_rst = optimise ( f_nu, c(1e-6, 1e6) )
    nu[k+1] = opt_rst$minimum
    
    #    g[k] = sum( log(  gamma( 0.5 * (nu[k] + 1) )/gamma( 0.5 * nu[k] )/sqrt( pi * nu[k] * sigma[k+1] ) )
    #                + - 0.5 * (nu[k] + 1) * log( tmp/nu[k] + 1 ) )   
    if (return_iterates) f[k+1] = sum( log(  gamma( 0.5 * (nu[k+1] + 1) )/gamma( 0.5 * nu[k+1] )/sqrt( pi * nu[k+1] * sigma2[k+1] ) )
                                - 0.5 * (nu[k+1] + 1) * log( tmp/nu[k+1] + 1 ) ) 
    
    if (abs(phi0[k + 1] - phi0[k]) <= tol * (abs(phi0[k + 1]) + abs(phi0[k]))/2
        && abs(phi1[k + 1] - phi1[k]) <= tol * (abs(phi1[k + 1]) + abs(phi1[k]))/2
        && abs(sigma2[k + 1] - sigma2[k]) <= tol * (abs(sigma2[k + 1]) + abs(sigma2[k]))/2
        && KLgamma(nu[k]/2, nu[k]/2, nu[k+1]/2, nu[k+1]/2) <= tol) 
       # && abs(nu[k + 1] - nu[k]) <= tol * (abs(nu[k + 1]) + abs(nu[k]))/2) 
      break
    }

    results <- list("phi0" = phi0[k+1], 
                    "phi1" = phi1[k+1], 
                    "sigma2" = sigma2[k+1], 
                    "nu" = nu[k+1])
    if (return_iterates) 
      results <- c(results, list("phi0_iterate" = phi0,
                                 "phi1_iterate" = phi1,
                                 "sigma2_iterate" = sigma2,
                                 "nu_iterate" = nu,
                                 "f_iterate" = f))

    if(return_condMean_Gaussian)
      results <- c(results, list("cond_mean_y_Gaussian" = estimation_Gaussian$cond_mean_y))
    return(results)
}
  

# KL_divergence of gamma distributions  
# https://stats.stackexchange.com/questions/11646/kullback-leibler-divergence-between-two-gamma-distributions  
KLgamma <- function(shape1, rate1, shape2, rate2) {
  h <- function(shape1, rate1, shape2, rate2)
    - shape2/ rate2 / shape1 - 1/rate1 * log(shape1) - lgamma(1/rate1) + (1/rate1-1)*(psigamma(1/rate2) + log(shape2))
  return(h(shape2,1/rate2,shape2,1/rate2) - h(shape1,1/rate1,shape2,1/rate2))
}

  
