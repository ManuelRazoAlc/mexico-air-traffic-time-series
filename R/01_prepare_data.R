# Builds everything the poster needs from the monthly AFAC data:
# monthly and annual totals, 12-month moving averages and the yearly
# route network with coordinates.

library(dplyr)

read_project_csv <- function(path) {
  read.csv(file.path(ROOT, path), fileEncoding = "UTF-8",
           check.names = FALSE, stringsAsFactors = FALSE)
}

od <- read_project_csv("data/afac_domestic_od_monthly_2000_2025.csv")
airports <- read_project_csv("data/airport_catalog.csv")
measures <- c("flights", "passengers", "cargo_kg")

# Basic integrity checks on the raw data.
stopifnot(
  all(od$service == "REG NAC"),
  identical(sort(unique(od$year)), 2000:2025),
  all(od$month %in% 1:12),
  !anyNA(od[measures]),
  all(as.matrix(od[measures]) >= 0),
  !anyDuplicated(od[c("year", "month", "source_file", "source_sheet", "source_row")]),
  all(od$date == sprintf("%d-%02d-01", od$year, od$month))
)


# ---- Time series -----------------------------------------------------------

monthly <- aggregate(cbind(flights, passengers, cargo_kg) ~ year + month + date, od, sum)
monthly <- monthly[order(monthly$year, monthly$month), ]
monthly$date <- as.Date(monthly$date)
stopifnot(
  nrow(monthly) == 312L,
  identical(monthly$date, seq(as.Date("2000-01-01"), as.Date("2025-12-01"), by = "month"))
)

# Trailing 12-month moving average (the first 11 months are NA).
for (measure in c("flights", "passengers")) {
  monthly[[paste0(measure, "_ma12")]] <- as.numeric(
    stats::filter(monthly[[measure]], rep(1 / 12, 12), sides = 1)
  )
}

annual <- aggregate(cbind(flights, passengers, cargo_kg) ~ year, od, sum)


# ---- Route network ---------------------------------------------------------

# One row per route and year. Rows with the same origin and destination labels
# are kept apart by their source row, so no traffic is lost or double counted.
routes <- od %>%
  group_by(year, service, origin, destination, source_file, source_sheet, source_row) %>%
  summarise(across(all_of(measures), sum), .groups = "drop") %>%
  as.data.frame()

# Matches an AFAC place name to a catalog node valid in that year
# (some cities changed airports during the period).
find_node <- function(name, year) {
  if (is.na(name) || !nzchar(name)) {
    return(data.frame(node_id = "UNIDENTIFIED", latitude = NA_real_,
                      longitude = NA_real_, node_type = "unresolved"))
  }
  node <- airports[airports$afac_name == name &
                     airports$year_from <= year & airports$year_to >= year, ]
  if (nrow(node) != 1L) stop("No unique catalog match for ", name, " (", year, ")")
  node[c("node_id", "latitude", "longitude", "node_type")]
}

join_key <- function(name) ifelse(is.na(name) | !nzchar(name), "UNIDENTIFIED", name)

places <- unique(bind_rows(
  data.frame(year = routes$year, name = routes$origin),
  data.frame(year = routes$year, name = routes$destination)
))
node_lookup <- bind_rows(lapply(seq_len(nrow(places)), function(i) {
  cbind(year = places$year[i], key = join_key(places$name[i]),
        find_node(places$name[i], places$year[i]))
}))

add_node_columns <- function(table, column, prefix) {
  table$key <- join_key(table[[column]])
  lookup <- node_lookup
  renamed <- !names(lookup) %in% c("year", "key")
  names(lookup)[renamed] <- paste0(prefix, names(lookup)[renamed])
  result <- left_join(table, lookup, by = c("year", "key"), relationship = "many-to-one")
  result$key <- NULL
  stopifnot(nrow(result) == nrow(table))
  result
}

routes <- add_node_columns(routes, "origin", "origin_")
routes <- add_node_columns(routes, "destination", "destination_")
routes$has_coords <- is.finite(routes$origin_latitude) & is.finite(routes$destination_latitude)
routes$approx <- routes$origin_node_type == "approx_city" |
  routes$destination_node_type == "approx_city"
routes$self_loop <- routes$origin_node_id == routes$destination_node_id

# Sorting the two endpoints makes A-B and B-A the same connection.
routes$node_a <- pmin(routes$origin_node_id, routes$destination_node_id)
routes$node_b <- pmax(routes$origin_node_id, routes$destination_node_id)
routes$pair_id <- paste(routes$node_a, routes$node_b, sep = "__")

connections <- routes %>%
  group_by(year, pair_id, node_a, node_b) %>%
  summarise(
    flights = sum(flights), passengers = sum(passengers),
    has_coords = all(has_coords), approx = any(approx),
    self_loop = any(self_loop), .groups = "drop"
  )

nodes <- node_lookup %>% select(year, node_id, latitude, longitude, node_type) %>% distinct()
stopifnot(!anyDuplicated(nodes[c("year", "node_id")]))
for (end in c("a", "b")) {
  end_nodes <- nodes
  names(end_nodes)[-1] <- paste0(names(end_nodes)[-1], "_", end)
  names(end_nodes)[names(end_nodes) == paste0("node_id_", end)] <- paste0("node_", end)
  connections <- left_join(connections, end_nodes, by = c("year", paste0("node_", end)),
                           relationship = "many-to-one")
}
connections <- as.data.frame(connections)

network <- connections %>%
  group_by(year) %>%
  summarise(
    active_connections = sum(passengers > 0 & !self_loop),
    busy_connections = sum(passengers >= 250000 & !self_loop),
    .groups = "drop"
  ) %>%
  as.data.frame()


# ---- Checks ----------------------------------------------------------------

# The network keeps every passenger and flight from the annual totals.
network_totals <- aggregate(cbind(flights, passengers) ~ year, connections, sum)
stopifnot(isTRUE(all.equal(network_totals[c("flights", "passengers")],
                           annual[c("flights", "passengers")], check.attributes = FALSE)))

# Figures shown on the poster.
stopifnot(
  annual$passengers[annual$year == 2000] == 17762846,
  annual$passengers[annual$year == 2019] == 53531241,
  annual$passengers[annual$year == 2020] == 28236461,
  annual$passengers[annual$year == 2025] == 63534515,
  network$busy_connections[network$year == 2000] == 18L,
  network$busy_connections[network$year == 2025] == 76L
)
