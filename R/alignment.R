#' Align cells from different groups within a cds
#'
#' @description Data sets that contain cells from different groups often
#' benefit from alignment to subtract differences between them. Alignment
#' can be used to remove batch effects, subtract the effects of treatments,
#' or even potentially compare across species.
#' \code{align_cds} executes alignment and stores these adjusted coordinates.
#'
#' This function can be used to subtract both continuous and discrete batch
#' effects. For continuous effects, \code{align_cds} fits a linear model to the
#' cells' PCA or LSI coordinates and subtracts them using Limma. For discrete
#' effects, you must provide a grouping of the cells, and then these groups are
#' aligned using Batchelor, a "mutual nearest neighbor" algorithm described in:
#'
#' Haghverdi L, Lun ATL, Morgan MD, Marioni JC (2018). "Batch effects in
#' single-cell RNA-sequencing data are corrected by matching mutual nearest
#' neighbors." Nat. Biotechnol., 36(5), 421-427. doi: 10.1038/nbt.4091
#'
#' @param cds the cell_data_set upon which to perform this operation
#' @param preprocess_method a string specifying the low-dimensional space
#'   in which to perform alignment, currently either PCA or LSI. Default is
#'   "PCA".
#' @param residual_model_formula_str NULL or a string model formula specifying
#'   any effects to subtract from the data before dimensionality reduction.
#'   Uses a linear model to subtract effects. For non-linear effects, use
#'   alignment_group. Default is NULL.
#' @param alignment_group String specifying a column of colData to use for
#'  aligning groups of cells. The column specified must be a factor.
#'  Alignment can be used to subtract batch effects in a non-linear way.
#'  For correcting continuous effects, use residual_model_formula_str.
#'  Default is NULL.
#' @param alignment_k The value of k used in mutual nearest neighbor alignment
#' @param verbose Whether to emit verbose output during dimensionality
#'   reduction
#' @param ... additional arguments to pass to limma::lmFit if
#'   residual_model_formula is not NULL
#' @return an updated cell_data_set object
#' @export
align_cds <- function(cds,
                      preprocess_method = c("PCA", "LSI"),
                      alignment_group=NULL,
                      alignment_k=20,
                      residual_model_formula_str=NULL,
                      verbose=FALSE,
                      ...){
  assertthat::assert_that(
    tryCatch(expr = ifelse(match.arg(preprocess_method) == "",TRUE, TRUE),
             error = function(e) FALSE),
    msg = "preprocess_method must be one of 'PCA' or 'LSI'")
  preprocess_method <- match.arg(preprocess_method)

  preproc_res <- reducedDims(cds)[[preprocess_method]]

  if (!is.null(residual_model_formula_str)) {
    if (verbose) message("Removing residual effects")
    X.model_mat <- Matrix::sparse.model.matrix(
      stats::as.formula(residual_model_formula_str),
      data = colData(cds),
      drop.unused.levels = TRUE)

    fit <- limma::lmFit(Matrix::t(preproc_res), X.model_mat, ...)
    beta <- fit$coefficients[, -1, drop = FALSE]
    beta[is.na(beta)] <- 0
    preproc_res <- Matrix::t(as.matrix(Matrix::t(preproc_res)) -
                               beta %*% Matrix::t(X.model_mat[, -1]))
  }

  if(!is.null(alignment_group)) {
    message(paste("Aligning cells from different batches using Batchelor.",
                  "\nPlease remember to cite:\n\t Haghverdi L, Lun ATL,",
                  "Morgan MD, Marioni JC (2018). 'Batch effects in",
                  "single-cell RNA-sequencing data are corrected by matching",
                  "mutual nearest neighbors.' Nat. Biotechnol., 36(5),",
                  "421-427. doi: 10.1038/nbt.4091"))
    corrected_PCA = batchelor::fastMNN(as.matrix(preproc_res),
                                       batch=colData(cds)[,alignment_group],
                                       k=alignment_k,
                                       cos.norm=FALSE,
                                       pc.input = TRUE)
    preproc_res = corrected_PCA$corrected
    cds <- add_citation(cds, "MNN_correct")
  }

  reducedDims(cds)[["Aligned"]] <- as.matrix(preproc_res)

  cds
}
