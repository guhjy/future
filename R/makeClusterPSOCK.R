#' Create a Parallel Socket Cluster
#'
#' @param workers The host names of workers (as a character vector) or
#'              the number of localhost workers (as a positive integer).
#' @param makeNode A function that creates a \code{"SOCKnode"}
#'   or \code{"SOCK0node"} object, which represents a connection
#'   to a worker.
#' @param ... Optional arguments passed to \code{makeNode(workers[i], ..., rank=i)} where \code{i = seq_along{workers}}.
#' @param verbose If TRUE, informative messages are outputted.
#'
#' @return An object of class \code{c("SOCKcluster", "cluster")} consisting
#'         of a list of \code{"SOCKnode"} or \code{"SOCK0node"} workers.
#'
#' @details
#' The \code{makeClusterPSOCK()} function is similar to \code{\link[parallel:makePSOCKcluster]{makePSOCKcluster}} of the \pkg{parallel} package, but provides more flexibility in controlling the setup of the system calls that launch the background R workers and how to connect to external machines.
#'
#' @example incl/makeClusterPSOCK.R
#'
#' @export
makeClusterPSOCK <- function(workers, makeNode = makeNodePSOCK, port = c("auto", "random"), ..., verbose = FALSE) {
  if (is.numeric(workers)) {
    if (length(workers) != 1L) {
      stop("When numeric, argument 'workers' must be a single value: ", length(workers))
    }
    workers <- as.integer(workers)
    if (is.na(workers) || workers < 1L) {
      stop("Number of 'workers' must be one or greater: ", workers)
    }
    workers <- rep("localhost", times = workers)
  }

  if (is.character(port)) {
    port <- match.arg(port)
    if (identical(port, "auto")) {
      port <- Sys.getenv("R_PARALLEL_PORT", NA_character_)
      port <- as.integer(port)
      if (is.na(port)) port <- 11000:11999
    } else if (identical(port, "random")) {
      port <- 11000:11999
    }
  } else {
    port <- as.integer(port)
  }
  if (length(port) == 0L) {
    stop("Argument 'post' must be of length one or more: 0")
  }
  if (length(port) > 1L) port <- sample(port, size = 1L)
  if (is.na(port) || port < 0L || port > 65535L) {
    stop("Invalid port: ", port)
  }

  cl <- vector("list", length = length(workers))
  for (ii in seq_along(cl)) {
     cl[[ii]] <- makeNode(workers[[ii]], port = port, ..., rank = ii, verbose = verbose)
  }     
  class(cl) <- c("SOCKcluster", "cluster")
  
  cl
} ## makeClusterPSOCK()


#' @param worker The host name or IP number of the machine where the worker should run.
#' @param master The host name or IP number of the master / calling machine, as known to the workers.  If NULL (default), then the default is \code{Sys.info()[["nodename"]]} unless \code{worker} is the localhost (\code{"localhost"} or \code{"127.0.0.1"}) or \code{revtunnel = TRUE} in case it is \code{"localhost"}.
#' @param port The port number of the master used to for communicating with all the workers (via socket connections).  If an integer vector of ports, then a random one among those is chosen.  If \code{"random"}, then a random port in \code{11000:11999} is chosen.  If \code{"auto"} (default), then the default is taken from environment variable \env{R_PARALLEL_PORT}, otherwise \code{"random"} is used.
#' @param timeout The timeout (in seconds) used for each sockect connection between the master and each worker (defaults to 30 days).
#' @param rscript,homogeneous The system command for launching Rscript on the worker. If \code{NULL} (default), the default is \code{"Rscript"} unless \code{homogenenous} is TRUE, which in case it is \code{file.path(R.home("bin"), "Rscript")}.  Argument \code{homogenenous} defaults to FALSE, unless \code{master} is the localhost (\code{"localhost"} or \code{"127.0.0.1"}).
#' @param rscript_args Additional arguments to \code{Rscript} (as a character vector).
#' @param methods If TRUE, then the \pkg{methods} package is also loaded.
#' @param useXDR If TRUE, the communication between master and workers, which is binary, will be use big-endian (XDR).
#' @param outfile Where to direct the \link[base:stdout]{stdout} and \link[base:stderr]{stderr} connection output from the workers.
#' @param renice A numerical 'niceness' (priority) to set for the worker processes.
#' @param rank A unique one-based index for each worker (automatically set).
#' @param rshcmd The command to be run on the master to launch a process on another host.  Only applicable if \code{machine} is not localhost.
#' @param user (optional) The user name to be used when communicating with another host.
#' @param revtunnel If TRUE, a reverse SSH tunneling is set up for each worker such that the worker R process sets up a socket connect to its local port \code{(port - rank + 1)} which then reaches the master on port \code{port}.  If FALSE, then the worker will try to connect directly to port \code{port} on \code{master}.
#' @param rshopts Additional arguments to \code{rshcmd} (as a character vector).
#' @param manual If TRUE the workers will need to be run manually.
#' @param dryrun If TRUE, nothing is set up, but a message suggesting how to launch the worker from the terminal is outputted.  This is useful for troubleshooting.
#'
#' @return \code{makeNodePSOCK()} returns a
#'         \code{"SOCKnode"} or \code{"SOCK0node"} object
#'         representing an established connection to a worker.
#'
#' @details
#' The default is to use reverse SSH tunnelling for workers
#' running on other machines.  This avoids the complication of
#' otherwise having to configure port forwarding in firewalls,
#' which often requires static IP address but which also most
#' users don't have priviligies to do themselves.
#' It also has the advantage of not having to know the internal
#' and / or the public IP address / host name of the master.
#'
#' If there is no communication between the master and a
#' worker within the \code{timeout} limit, then the corresponding
#' socket connection will be closed automatically.
#'
#' @rdname makeClusterPSOCK
#' @export
makeNodePSOCK <- function(worker = "localhost", master = NULL, port, timeout = 30*24*60*60, rscript = NULL, homogeneous = NULL, rscript_args = NULL, methods = TRUE, useXDR = TRUE, outfile = "/dev/null", renice = NA_integer_, rshcmd = "ssh", user = NULL, revtunnel = TRUE, rshopts = NULL, rank = 1L, manual = FALSE, dryrun = FALSE, verbose = FALSE) {
  localMachine <- is.element(worker, c("localhost", "127.0.0.1"))

  rshcmd <- as.character(rshcmd)
  stopifnot(length(rshcmd) >= 1L)

  rshopts <- as.character(rshopts)
  
  user <- as.character(user)
  stopifnot(length(user) <= 1L)
  
  port <- as.integer(port)
  if (is.na(port) || port < 0L || port > 65535L) {
    stop("Invalid port: ", port)
  }

  revtunnel <- as.logical(revtunnel)
  stopifnot(length(revtunnel) == 1L, !is.na(revtunnel))
  
  if (is.null(master)) {
    if (localMachine || revtunnel) {
      master <- "localhost"
    } else {
      master <- Sys.info()[["nodename"]]
    }
  }
  stopifnot(!is.null(master))

  timeout <- as.numeric(timeout)
  stopifnot(length(timeout) == 1L, !is.na(timeout), is.finite(timeout), timeout >= 0)
  
  methods <- as.logical(methods)
  stopifnot(length(methods) == 1L, !is.na(methods))

  if (is.null(homogeneous)) {
    homogeneous <- is.element(master, c("localhost", "127.0.0.1"))
  }
  homogeneous <- as.logical(homogeneous)
  stopifnot(length(homogeneous) == 1L, !is.na(homogeneous))

  if (is.null(rscript)) {
    rscript <- "Rscript"
    if (homogeneous) rscript <- file.path(R.home("bin"), rscript)
  }
  rscript <- as.character(rscript)
  stopifnot(length(rscript) >= 1L)

  rscript_args <- as.character(rscript_args)

  useXDR <- as.logical(useXDR)
  stopifnot(length(useXDR) == 1L, !is.na(useXDR))

  renice <- as.integer(renice)
  stopifnot(length(renice) == 1L)

  rank <- as.integer(rank)
  stopifnot(length(rank) == 1L, !is.na(rank))
  
  manual <- as.logical(manual)
  stopifnot(length(manual) == 1L, !is.na(manual))

  dryrun <- as.logical(dryrun)
  stopifnot(length(dryrun) == 1L, !is.na(dryrun))

  verbose <- as.logical(verbose)
  stopifnot(length(verbose) == 1L, !is.na(verbose))

  ## .slaveRSOCK() command already specified?
  if (!any(grepl("parallel:::.slaveRSOCK()", rscript_args, fixed = TRUE))) {
    rscript_args <- c(rscript_args, "-e", shQuote("parallel:::.slaveRSOCK()"))
  }
  
  if (methods) {
    rscript_args <- c("--default-packages=datasets,utils,grDevices,graphics,stats,methods", rscript_args)
  }

  ## Port that the Rscript should use to connect back to the master
  if (!localMachine && revtunnel) {
    rscript_port <- port + (rank - 1L)
  } else {
    rscript_port <- port
  }

  rscript <- paste(shQuote(rscript), collapse = " ")
  rscript_args <- paste(rscript_args, collapse = " ")
  envvars <- paste0("MASTER=", master, " PORT=", rscript_port, " OUT=", outfile, " TIMEOUT=", timeout, " XDR=", useXDR)
  
  cmd <- paste(rscript, rscript_args, envvars)

  ## Renice?
  if (!is.na(renice) && renice > 0L) {
    cmd <- sprintf("nice +%d %s", renice, cmd)
  }

  if (!localMachine) {
    ## Local commands
    rshcmd <- paste(shQuote(rshcmd), collapse = " ")
    if (length(user) == 1L) rshopts <- c("-l", user, rshopts)
    if (revtunnel) {
      rshopts <- c(sprintf("-R %d:%s:%d", rscript_port, master, port), rshopts)
    }
    rshopts <- paste(rshopts, collapse = " ")
    local_cmd <- paste(rshcmd, rshopts, worker, shQuote(cmd))
  } else {
    local_cmd <- cmd
  }
  stopifnot(length(local_cmd) == 1L)
  
  if (manual || dryrun) {
    msg <- c("----------------------------------------------------------------------", sprintf("Manually start worker #%s on %s with:", rank, sQuote(worker)), sprintf("  %s", cmd))
    if (!localMachine) {
      msg <- c(msg, "Alternatively, start it from the local machine with:", sprintf("  %s", local_cmd))
    }
    msg <- paste(c(msg, ""), collapse = "\n")
    cat(msg)
    utils::flush.console()
    if (dryrun) return(NULL)
  } else {
    if (verbose) {
      message(sprintf("Starting worker #%s on %s: %s", rank, sQuote(worker), local_cmd))
    }
    input <- if (.Platform$OS.type == "windows") "" else NULL
    system(local_cmd, wait = FALSE, input = input)
  }

  con <- socketConnection("localhost", port = port, server = TRUE, 
                 blocking = TRUE, open = "a+b", timeout = timeout)

  structure(list(con = con, host = worker, rank = rank),
            class = if (useXDR) "SOCKnode" else "SOCK0node")
} ## makeNodePSOCK()