# Plot building blocks for the poster: theme, maps, time series and legend.

library(ggplot2)
library(sf)
library(patchwork)

# ---- Palette and theme -----------------------------------------------------

col_background <- "#050D17"
col_land <- "#122638"
col_border <- "#31516A"
col_text <- "#EEF4F6"
col_muted <- "#99ADBC"
col_gold <- "#FFB94B"
col_cyan <- "#43DDE6"
col_minor_route <- "#527E92"
font_family <- "sans"

poster_theme <- function(size = 12) {
  theme_minimal(base_size = size, base_family = font_family) +
    theme(
      plot.background = element_rect(fill = col_background, color = NA),
      panel.background = element_rect(fill = col_background, color = NA),
      panel.grid.major = element_line(color = "#263A4B", linewidth = .25),
      panel.grid.minor = element_blank(),
      text = element_text(color = col_text),
      strip.text = element_text(color = col_text, face = "bold"),
      axis.text = element_text(color = col_muted),
      legend.background = element_rect(fill = col_background, color = NA),
      legend.key = element_rect(fill = col_background, color = NA),
      legend.text = element_text(color = col_muted),
      plot.title = element_text(face = "bold", color = col_text),
      plot.subtitle = element_text(color = col_muted),
      plot.caption = element_text(color = col_muted, hjust = 0),
      plot.margin = margin(10, 14, 10, 14)
    )
}

# Empty canvas used for text-only blocks (header, legend, side panel, footer).
text_canvas <- function(margins = margin(0, 0, 0, 0)) {
  list(
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE),
    theme_void(),
    theme(
      plot.background = element_rect(fill = col_background, color = NA),
      panel.background = element_rect(fill = col_background, color = NA),
      plot.margin = margins
    )
  )
}

save_pdf <- function(plot, file, width, height) {
  # Paint every panel of a patchwork layout with the dark background.
  if (inherits(plot, "patchwork")) {
    plot <- plot & theme(plot.background = element_rect(fill = col_background, color = NA))
  }
  ggsave(file.path(ROOT, file), plot,
         device = grDevices::pdf, useDingbats = FALSE,
         width = width, height = height, units = "in",
         bg = col_background, limitsize = FALSE)
}


# ---- Base map --------------------------------------------------------------

# The INEGI GeoJSON uses ITRF2008 (EPSG:6365), but GDAL does not pick it up
# automatically, so the CRS is set by hand before projecting.
albers <- "+proj=aea +lat_1=17.5 +lat_2=29.5 +lat_0=24 +lon_0=-102 +datum=WGS84 +units=m +no_defs"
mexico <- st_read(file.path(ROOT, "data/inegi_states.geojson"), quiet = TRUE)
mexico <- st_set_crs(mexico, NA)
mexico <- st_set_crs(mexico, 6365)
mexico <- st_transform(st_make_valid(mexico), albers)
mexico <- st_simplify(mexico, dTolerance = 1000, preserveTopology = TRUE)

map_years <- c(2000, 2019, 2020, 2025)
busy_threshold <- 250000
# One line-width scale for all years so the four maps are comparable.
max_passengers <- max(connections$passengers)

bbox <- st_bbox(mexico)
x_limits <- c(bbox["xmin"] - 100000, bbox["xmax"] + 100000)
y_limits <- c(bbox["ymin"] - 120000, bbox["ymax"] + 150000)


# ---- Connection curves -----------------------------------------------------

project_endpoints <- function(connection) {
  ends <- data.frame(lon = c(connection$longitude_a, connection$longitude_b),
                     lat = c(connection$latitude_a, connection$latitude_b))
  st_coordinates(st_transform(st_as_sf(ends, coords = c("lon", "lat"), crs = 4326), albers))
}

# Quadratic Bezier curve between two airports. The control point is pushed
# sideways by 23% of the distance. The shape is schematic, not a flight path.
bezier_curve <- function(connection, n_points = 65, bend = .23) {
  xy <- project_endpoints(connection)
  start <- xy[1, ]
  end <- xy[2, ]
  if (sqrt(sum((end - start)^2)) == 0) return(NULL)
  control <- (start + end) / 2 + c(-(end - start)[2], (end - start)[1]) * bend
  t <- seq(0, 1, length.out = n_points)
  data.frame(
    x = (1 - t)^2 * start[1] + 2 * (1 - t) * t * control[1] + t^2 * end[1],
    y = (1 - t)^2 * start[2] + 2 * (1 - t) * t * control[2] + t^2 * end[2],
    pair_id = connection$pair_id, year = connection$year, passengers = connection$passengers
  )
}

drawable <- connections[connections$year %in% map_years &
                          connections$has_coords & !connections$self_loop, ]
curves <- do.call(rbind, lapply(seq_len(nrow(drawable)), function(i) bezier_curve(drawable[i, ])))

# Check that every curve starts and ends exactly on its two airports.
endpoint_ok <- lapply(split(curves, paste(curves$year, curves$pair_id)), function(curve) {
  connection <- connections[connections$year == curve$year[1] &
                              connections$pair_id == curve$pair_id[1], ]
  error <- max(abs(as.matrix(curve[c(1, nrow(curve)), c("x", "y")]) -
                     project_endpoints(connection)))
  error < .001
})
stopifnot(all(unlist(endpoint_ok)))


# ---- Map for one year ------------------------------------------------------

map_titles <- c("2000" = "El punto de partida", "2019" = "Antes de la pandemia",
                "2020" = "El impacto de COVID-19", "2025" = "Un nuevo panorama")

route_map <- function(year, size = 12) {
  lines <- curves[curves$year == year & curves$passengers > 0, ]
  lines$width <- .08 + 1.55 * sqrt(lines$passengers / max_passengers)
  lines <- lines[order(lines$passengers), ]
  busy <- lines[lines$passengers >= busy_threshold, ]
  minor <- lines[lines$passengers < busy_threshold, ]

  p <- ggplot() + geom_sf(data = mexico, fill = col_land, color = col_border, linewidth = .16)

  if (nrow(minor)) {
    p <- p + geom_path(data = minor, aes(x, y, group = pair_id, linewidth = width),
                       color = col_minor_route, alpha = .21, lineend = "round")
  }

  # Busy routes get a glow: the same curve drawn four times, wide and faint
  # underneath, thin and bright on top.
  if (nrow(busy)) {
    p <- p +
      geom_path(data = busy, aes(x, y, group = pair_id, linewidth = width * 5),
                color = col_gold, alpha = .035, lineend = "round") +
      geom_path(data = busy, aes(x, y, group = pair_id, linewidth = width * 2.4),
                color = col_gold, alpha = .10, lineend = "round") +
      geom_path(data = busy, aes(x, y, group = pair_id, linewidth = width),
                color = col_gold, alpha = .82, lineend = "round") +
      geom_path(data = busy, aes(x, y, group = pair_id, linewidth = width * .27),
                color = "#FFF6DC", alpha = .72, lineend = "round")
  }

  # Airports as solid dots, approximate city locations as hollow circles.
  shown <- connections[connections$year == year & connections$pair_id %in% unique(lines$pair_id), ]
  airport_points <- unique(rbind(
    data.frame(id = shown$node_a, lon = shown$longitude_a,
               lat = shown$latitude_a, type = shown$node_type_a),
    data.frame(id = shown$node_b, lon = shown$longitude_b,
               lat = shown$latitude_b, type = shown$node_type_b)
  ))
  airport_points <- st_transform(st_as_sf(airport_points, coords = c("lon", "lat"), crs = 4326), albers)

  totals <- annual[annual$year == year, ]
  stats <- network[network$year == year, ]

  p +
    geom_sf(data = airport_points, aes(shape = type), color = "#D3E7EC", fill = col_background,
            size = .65, stroke = .22) +
    scale_shape_manual(values = c(airport = 16, approx_city = 1)) +
    scale_linewidth_identity() +
    coord_sf(crs = albers, xlim = x_limits, ylim = y_limits, expand = FALSE, datum = NA) +
    poster_theme(size) +
    theme(axis.text = element_blank(), axis.title = element_blank(),
          panel.grid = element_blank(), legend.position = "none") +
    labs(
      title = paste(year, map_titles[[as.character(year)]], sep = " - "),
      subtitle = paste0(sprintf("%.2f millones de pasajeros", totals$passengers / 1e6),
                        " · ", stats$active_connections, " conexiones")
    )
}


# ---- Monthly time series ---------------------------------------------------

time_series_plot <- function(size = 12) {
  series <- rbind(
    data.frame(date = monthly$date, value = monthly$passengers / 1e6,
               trend = monthly$passengers_ma12 / 1e6,
               panel = "Pasajeros · millones", measure = "passengers"),
    data.frame(date = monthly$date, value = monthly$flights / 1000,
               trend = monthly$flights_ma12 / 1000,
               panel = "Vuelos · miles", measure = "flights")
  )
  ggplot(series, aes(date, value, color = measure)) +
    geom_line(linewidth = .3, alpha = .48) +
    geom_line(aes(y = trend), linewidth = .9, na.rm = TRUE) +
    facet_wrap(~panel, ncol = 1, scales = "free_y") +
    scale_color_manual(values = c(passengers = col_gold, flights = col_cyan), guide = "none") +
    scale_x_date(breaks = as.Date(paste0(seq(2000, 2025, 5), "-01-01")),
                 date_labels = "%Y", expand = expansion(mult = c(.01, .06))) +
    labs(x = NULL, y = NULL) +
    poster_theme(size)
}


# ---- Map legend ------------------------------------------------------------

map_legend <- function() {
  ggplot() +
    annotate("text", x = 0.025, y = 0.89, label = "CÓMO LEER LOS MAPAS",
             hjust = 0, vjust = 1, size = 6.3, fontface = "bold", color = col_text) +
    annotate("text", x = 0.025, y = 0.65,
             label = paste("Cada curva conecta dos destinos. Su grosor aumenta con el número de",
                           "pasajeros transportados durante el año, sumando ambos sentidos."),
             hjust = 0, vjust = 1, size = 5.8, color = col_muted) +
    annotate("segment", x = 0.045, xend = 0.105, y = 0.27, yend = 0.27,
             linewidth = 1.5, color = col_minor_route, lineend = "round") +
    annotate("text", x = 0.12, y = 0.27, label = "Menos de 250 mil pasajeros",
             hjust = 0, vjust = 0.5, size = 5.3, color = col_text) +
    annotate("segment", x = 0.52, xend = 0.58, y = 0.27, yend = 0.27,
             linewidth = 1.5, color = col_gold, lineend = "round") +
    annotate("text", x = 0.595, y = 0.27, label = "250 mil pasajeros o más",
             hjust = 0, vjust = 0.5, size = 5.3, color = col_text) +
    text_canvas(margin(2, 12, 2, 12))
}
