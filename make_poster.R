# Builds poster.pdf from the data in data/.
#   RStudio:  open the .Rproj and run source("make_poster.R")
#   Terminal: Rscript make_poster.R

local({
  # Find this script's folder so it runs from any working directory.
  sourced <- Filter(Negate(is.null), lapply(sys.frames(), function(x) x$ofile))
  if (length(sourced)) {
    script <- tail(sourced, 1)[[1]]
  } else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    script <- if (length(arg)) sub("^--file=", "", arg[1]) else "make_poster.R"
    script <- gsub("~+~", " ", script, fixed = TRUE)
  }
  ROOT <- dirname(normalizePath(script, mustWork = TRUE))

  # Use the project library created by install_packages.R, if it exists.
  project_lib <- file.path(ROOT, ".r-library", paste0("R-", getRversion()), R.version$platform)
  if (dir.exists(project_lib)) .libPaths(c(project_lib, .libPaths()))

  needed <- c("dplyr", "ggplot2", "patchwork", "sf")
  missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Missing packages: ", paste(missing, collapse = ", "),
         ". Run install_packages.R first and restart R.", call. = FALSE)
  }

  env <- environment()
  for (step in c("01_prepare_data.R", "02_plot_functions.R", "03_build_poster.R")) {
    sys.source(file.path(ROOT, "R", step), envir = env, keep.source = FALSE)
  }
  message("Poster saved to ", file.path(ROOT, "poster.pdf"))
})
