stopifnot(packageVersion("SpaDES") >= "1.0.3.9001")

defineModule(sim, list(
  name="cropReprojectLccAge",
  description="A translator module. Crops and reprojects the Land cover classification from 2005 to
  a smaller, cropped RasterLayer, defined by ext, and with new projection defined by newCRS",
  keywords=c("translator", "lcc05", "Land Cover Classification", "vegetation"),
  childModules=character(),
  authors=c(person(c("Eliot", "J","B"), "McIntire", email="emcintir@nrcan.gc.ca", role=c("aut", "cre"))),
  version=numeric_version("0.0.6"),
  spatialExtent=raster::extent(rep(NA_real_, 4)),
  timeframe=as.POSIXlt(c(NA, NA)),
  timeunit=NA_character_,
  citation=list("citation.bib"),
  documentation=list("README.txt", "cropReprojectLccAge.Rmd"),
  reqdPkgs=list("raster","rgeos", "parallel","sp", "archivist"),
  parameters=rbind(
    defineParameter("useCache", "logical", TRUE, NA, NA, desc="Should slow raster and sp functions use cached versions to speedup repeated calls"),
    defineParameter(".plotInitialTime", "numeric", NA_real_, NA, NA, desc="Initial time for plotting"),
    defineParameter(".plotInterval", "numeric", NA_real_, NA, NA, desc="Interval between plotting"),
    defineParameter(".saveInitialTime", "numeric", NA_real_, NA, NA, desc="Initial time for saving"),
    defineParameter(".saveInterval", "numeric", NA_real_, NA, NA, desc="Interval between save events")),
  inputObjects=data.frame(objectName=c("lcc05", "age", "inputMapPolygon"),
                          objectClass=c("RasterLayer", "RasterLayer", "SpatialPolygons"),
                          other=rep(NA_character_, 3L), stringsAsFactors=FALSE),
  outputObjects=data.frame(objectName=c("vegMapLcc", "ageMapInit"),
                          objectClass=c("RasterLayer", "RasterLayer"),
                          other=rep(NA_character_, 2L), stringsAsFactors=FALSE)
))

doEvent.cropReprojectLccAge = function(sim, eventTime, eventType, debug=FALSE) {
  if (eventType=="init") {

    # do stuff for this event
    sim <- sim$cropReprojectLccCacheFunctions(sim)
    sim <- sim$cropReprojectLccInit(sim)

    # schedule future event(s)
  } else {
    warning(paste("Undefined event type: '", events(sim)[1, "eventType", with=FALSE],
                  "' in module '", events(sim)[1, "moduleName", with=FALSE], "'", sep=""))
  }
  return(invisible(sim))
}

### template initilization
cropReprojectLccInit = function(sim) {
  lcc05CRS <- CRS("+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0 +lon_0=-95 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs")
  inputMapPolygonLcc05 <- sim$spTransform(sim$inputMapPolygon, CRSobj=lcc05CRS)
  totalArea <- rgeos::gArea(inputMapPolygonLcc05)/1e4
  if(totalArea > 100e6) {
    stop("In the current implementation, please select another, smaller polygon",
         " (less than 100 million hectares).")
  }
  inputMapPolygon <- inputMapPolygonLcc05
  sim$vegMapLcc <- sim$crop(sim$lcc05, inputMapPolygon)
  crs(sim$vegMapLcc) <- lcc05CRS

  sim$vegMapLcc <- sim$mask(x=sim$vegMapLcc, mask=inputMapPolygon)
  setColors(sim$vegMapLcc, n=256) <- getColors(sim$lcc05)[[1]] # mask removes colors!

  #if(ncell(sim$vegMapLcc)>5e5) beginCluster(min(parallel::detectCores(),6))

    # age will not run with projectRaster directly.
    # Instead, project the vegMap to age, then crop, then project back to vegMap.
    vegMapLcc.crsAge <- sim$projectRaster(sim$vegMapLcc, crs=crs(sim$age))
    age.crsAge <- sim$crop(sim$age, sim$spTransform(sim$inputMapPolygon, CRSobj = crs(sim$age)))
    age.crsAge <- sim$mask(x=age.crsAge,
                           mask=sim$spTransform(sim$inputMapPolygon, CRSobj = crs(sim$age)))
    sim$ageMapInit <- sim$projectRaster(age.crsAge, to=sim$vegMapLcc, method="ngb")

    if (sum(!is.na(getValues(sim$ageMapInit)))==0) {
      stop("There are no age data provided with input age map")
    }
    if (sum(!is.na(getValues(sim$vegMapLcc)))==0) {
      stop("There are no vegatation data provided with input vegatation map")
    }
    setColors(sim$ageMapInit) <- colorRampPalette(c("light green", "dark green"))(50)

  #endCluster()

  return(invisible(sim))
}

cropReprojectLccCacheFunctions <- function(sim) {
  # for slow functions, add cached versions. Then use sim$xxx() throughout module instead of xxx()
  if(params(sim)$cropReprojectLccAge$useCache) {
    # Step 1 - create a location for the cached data if it doesn't already exist
    sim$cacheLoc <- file.path(cachePath(sim), "cache_cropReprojectLccAge")
    if (!dir.exists(sim$cacheLoc)) {
      createEmptyRepo(sim$cacheLoc)
    }

    # Step 2 - create a version of every function that is slow that includes the caching implicitly
    sim$mask <- function(...) {
      archivist::cache(cacheRepo=sim$cacheLoc, FUN=raster::mask, ...)
    }
    sim$crop <- function(...) {
      archivist::cache(cacheRepo=sim$cacheLoc, FUN=raster::crop, ...)
    }
    sim$projectRaster <- function(...) {
      archivist::cache(cacheRepo=sim$cacheLoc, FUN=raster::projectRaster, ...)
    }
    sim$spTransform <- function(...) {
      archivist::cache(cacheRepo=sim$cacheLoc, FUN=sp::spTransform,  ...)
    }
  } else {
    # Step 3 - create a non-caching version in case caching is not desired
    sim$mask <- raster::mask
    sim$crop <- raster::crop
    sim$projectRaster <- raster::projectRaster
    sim$spTransform <- sp::spTransform
  }

  return(invisible(sim))
}
