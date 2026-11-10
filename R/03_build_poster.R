# Puts the poster together and saves it as an A1 portrait PDF (poster.pdf).
# The poster text is in Spanish because it was presented in class.

# ---- Header ----------------------------------------------------------------

header <- ggplot() +
  annotate("text", x = 0.002, y = 0.90, label = "MÉXICO DESDE EL AIRE",
           hjust = 0, vjust = 1, size = 17, fontface = "bold", color = col_text) +
  annotate("text", x = 0.005, y = 0.66,
           label = "Un cuarto de siglo de transformación del transporte aéreo nacional",
           hjust = 0, vjust = 1, size = 9, color = col_muted) +
  annotate("segment", x = 0.005, xend = 0.998, y = 0.50, yend = 0.50,
           linewidth = 0.5, color = col_border) +
  annotate("text", x = 0.005, y = 0.41,
           label = paste0(
             "Entre 2000 y 2025, México pasó de transportar 17.76 a 63.53 millones de pasajeros nacionales al año.\n",
             "Cuatro momentos muestran cómo cambiaron sus conexiones aéreas y cómo la pandemia interrumpió su evolución.\n"
           ),
           hjust = 0, vjust = 1, size = 9, lineheight = 1.1, color = col_text) +
  text_canvas(margin(10, 5, 10, 5))


# ---- Four maps -------------------------------------------------------------

maps <- wrap_plots(
  lapply(map_years, function(year) {
    route_map(year, size = 24) +
      theme(plot.title = element_text(size = 24, face = "bold"),
            plot.subtitle = element_text(size = 21),
            plot.margin = margin(8, 4, 8, 4))
  }),
  ncol = 2
)


# ---- Side panel with the two key figures -----------------------------------

busy_2000 <- network$busy_connections[network$year == 2000]
busy_2025 <- network$busy_connections[network$year == 2025]
drop_2020 <- 100 * (annual$passengers[annual$year == 2020] /
                      annual$passengers[annual$year == 2019] - 1)

key_figures <- ggplot() +
  annotate("text", x = 0.07, y = 0.80, label = "CONEXIONES\nDE ALTO TRÁFICO",
           hjust = 0, vjust = 1, size = 6.3, fontface = "bold", lineheight = 1.1, color = col_text) +
  annotate("text", x = 0.07, y = 0.74, label = sprintf("%d a %d", busy_2000, busy_2025),
           hjust = 0, vjust = 1, size = 14, fontface = "bold", color = col_gold) +
  annotate("text", x = 0.07, y = 0.69,
           label = "Conexiones con al menos 250 mil\npasajeros anuales.\nComparación: 2000 y 2025.",
           hjust = 0, vjust = 1, size = 5, lineheight = 1.25, color = col_muted) +
  annotate("segment", x = 0.07, xend = 0.93, y = 0.53, yend = 0.53,
           linewidth = 0.5, color = col_border) +
  annotate("text", x = 0.07, y = 0.40, label = "CAÍDA DE PASAJEROS\nEN 2020",
           hjust = 0, vjust = 1, size = 6.3, fontface = "bold", lineheight = 1.1, color = col_text) +
  annotate("text", x = 0.07, y = 0.34, label = sprintf("%.1f%%", drop_2020),
           hjust = 0, vjust = 1, size = 14, fontface = "bold", color = "#FF877B") +
  annotate("text", x = 0.07, y = 0.29,
           label = "Disminución anual de pasajeros\nnacionales respecto a 2019.",
           hjust = 0, vjust = 1, size = 5, lineheight = 1.25, color = col_muted) +
  text_canvas(margin(10, 0, 10, 0))

maps_row <- wrap_plots(maps, key_figures, ncol = 2, widths = c(4.4, 1))


# ---- Time series with two historical events --------------------------------

# Context only: the dashed lines mark when each event happened, they do not
# measure its effect.
events <- data.frame(
  date = as.Date(c("2009-05-01", "2020-03-01")),
  height = c(5.0, 5.5),
  panel = "Pasajeros · millones",
  label = c("2009\nCrisis e influenza A(H1N1)", "2020\nPandemia de COVID-19")
)

series <- time_series_plot(size = 21) +
  labs(
    title = "LA HISTORIA DETRÁS DE LAS CONEXIONES",
    subtitle = "Evolución mensual de pasajeros y vuelos nacionales, 2000-2025.",
    caption = "Línea fina: datos mensuales. Línea gruesa: tendencia suavizada de 12 meses."
  ) +
  theme(plot.title = element_text(size = 25, face = "bold"),
        plot.subtitle = element_text(size = 19),
        axis.text = element_text(size = 17),
        strip.text = element_text(size = 19, face = "bold"),
        plot.caption = element_text(size = 15)) +
  # Lines go in both panels; labels only in the passengers panel.
  geom_vline(data = events["date"], aes(xintercept = date), inherit.aes = FALSE,
             color = "#708596", linetype = "dashed", linewidth = 0.45, alpha = 0.8) +
  geom_text(data = events, aes(x = date, y = height, label = label), inherit.aes = FALSE,
            hjust = 0, vjust = 0, size = 5.2, lineheight = 1.1, fontface = "bold",
            color = "#D3E7EC")


# ---- Footer ----------------------------------------------------------------

footer <- ggplot() +
  annotate("segment", x = 0.005, xend = 0.995, y = 0.92, yend = 0.92,
           linewidth = 0.5, color = col_border) +
  annotate("text", x = 0.005, y = 0.72, label = "Elaborado por: Manuel Razo Alcántara",
           hjust = 0, vjust = 1, size = 5.5, color = col_text) +
  annotate("text", x = 0.005, y = 0.32,
           label = paste("Fuente: AFAC, servicio regular nacional (2000-2025).",
                         "Las conexiones suman ambos sentidos y las curvas son esquemáticas."),
           hjust = 0, vjust = 1, size = 5.5, color = col_muted) +
  text_canvas()


# ---- Layout and export -----------------------------------------------------

content <- (header / maps_row / map_legend() / series / footer) +
  plot_layout(heights = c(3.2, 15.2, 1.7, 10.9, 1.5))

# Narrow side margins, then save at A1 size (594 x 841 mm).
poster <- wrap_plots(plot_spacer(), content, plot_spacer(), ncol = 3,
                     widths = c(0.59, 22.21, 0.59))

save_pdf(poster, "poster.pdf", width = 23.39, height = 33.11)
