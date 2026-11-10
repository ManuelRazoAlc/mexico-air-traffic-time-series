# Installs the exact package versions from renv.lock into a project library
# (.r-library/), without touching your global R library. Needs internet once.
#   RStudio:  source("install_packages.R")
#   Terminal: Rscript install_packages.R

local({
  sourced <- Filter(Negate(is.null), lapply(sys.frames(), function(x) x$ofile))
  if (length(sourced)) {
    script <- tail(sourced, 1)[[1]]
  } else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    script <- if (length(arg)) sub("^--file=", "", arg[1]) else "install_packages.R"
    script <- gsub("~+~", " ", script, fixed = TRUE)
  }
  root <- dirname(normalizePath(script, mustWork = TRUE))
  project_lib <- file.path(root, ".r-library", paste0("R-", getRversion()), R.version$platform)
  dir.create(project_lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(project_lib, .libPaths()))

  if (!requireNamespace("renv", quietly = TRUE)) {
    install.packages("renv", lib = project_lib, repos = "https://cloud.r-project.org")
  }
  renv::load(project = root, quiet = TRUE)
  renv::restore(project = root, library = project_lib,
                lockfile = file.path(root, "renv.lock"), prompt = FALSE)

  # Confirm that the installed versions match the lockfile.
  locked <- renv::lockfile_read(file.path(root, "renv.lock"))$Packages
  installed <- installed.packages(lib.loc = project_lib)
  stopifnot(all(names(locked) %in% rownames(installed)))
  for (pkg in names(locked)) {
    stopifnot(package_version(installed[pkg, "Version"]) ==
                package_version(locked[[pkg]]$Version))
  }
  message("Packages installed. Restart R and run make_poster.R.")
})
