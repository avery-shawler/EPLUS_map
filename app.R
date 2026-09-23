# =============================================================================
# 1. LOAD PACKAGES & DATA (Runs once when the app launches)
# =============================================================================
library(shiny)
library(leaflet)
library(sf)
library(dplyr)
library(readr)
library(scales)
library(rsconnect)


# -----------------------------------------------------------------------------
# Load pre-built layers (run R/01, R/02, R/03 first — see README)
# -----------------------------------------------------------------------------
gmu_bounds    <- st_read("data/spatial/gmu_boundaries.gpkg", quiet = TRUE) %>% st_transform(4326)
county_bounds <- st_read("data/spatial/nm_counties.gpkg", quiet = TRUE) %>% st_transform(4326)

gmu_data    <- read_csv("data/gmu_final.csv", show_col_types = FALSE) %>% mutate(gmu = as.character(gmu))
county_data <- read_csv("data/county_final.csv", show_col_types = FALSE)

gmu_map    <- gmu_bounds %>% left_join(gmu_data, by = "gmu")
county_map <- county_bounds %>% left_join(county_data, by = "county")

# Optional: elk core / non-core range. NMDGF does not publish this as an open
# dataset (see README) — if you obtain it, drop a GeoPackage at this path with
# a "range_class" field ("Core"/"Non-core") and it will appear as a layer.
# 
# core_range_path <- "/Users/averyshawler/Library/CloudStorage/Dropbox-WesternLandownersA/Avery Shawler/mapping projects/EPLUS_Anabella_Aug 2026/EPLUS_map/data/spatial/elk_core_range.gpkg"
# has_core_range  <- file.exists(core_range_path)
# if (has_core_range) {
#   core_range <- st_read(core_range_path, quiet = TRUE) %>% st_transform(4326)
# }

# Metric choices shown in the dropdown, mapped to column names -------------
metric_choices <- c(
  "Total elk occupied acreage"                         = "total_elk_occupied_acreage",
  "Elk occupied acreage \u2014 Base ranches"            = "acreage_Base",
  "Elk occupied acreage \u2014 SCR ranches"             = "acreage_SCR",
  "Acreage \u2014 Base and SCR Pool authorizations"     = "acreage_Base and SCR Pool",
  "Acreage \u2014 Habitat Incentives authorizations"    = "acreage_Habitat Incentives",
  "Acreage \u2014 Special Management Ranch authorizations" = "acreage_Special Management Ranches",
  "% private land"                                      = "pct_private_land",
  "% private land enrolled in EPLUS (elk occupied)"     = "pct_private_land_enrolled"
)

pct_metrics <- c("pct_private_land", "pct_private_land_enrolled")

# =============================================================================
# 2. USER INTERFACE (UI)
# =============================================================================
# -----------------------------------------------------------------------------
ui <- fluidPage(
  # tags$head(tags$style(HTML("
  #   html, body {height:100%;}
  #   #map {height: calc(100vh - 90px);}
  #   .controls {padding: 10px 16px; background:#f7f5f0; border-bottom:1px solid #ddd;}
  # "))),
  tags$head(
    tags$style(HTML("
      .leaflet-tile-container {
        filter: grayscale(100%) brightness(110%) contrast(90%);
      }
    "))
  ),
  div(class = "controls",
      fluidRow(
        column(3, selectInput("geo", "Geography",
                               choices = c("Game Management Unit (GMU)" = "gmu",
                                           "County (area-apportioned, see notes)" = "county"))),
        column(5, selectInput("metric", "Layer", choices = metric_choices,
                               selected = "total_elk_occupied_acreage"))
        # ,
       # column(4, checkboxInput("show_core", "Show elk core / non-core range (if available)",
       #                         value = FALSE))
      )
  ),
  leafletOutput("map")
)

# =============================================================================
# 3. SERVER LOGIC
# =============================================================================
server <- function(input, output, session) {

  current_sf <- reactive({
    if (input$geo == "gmu") gmu_map else county_map
  })

  output$map <- renderLeaflet({
    leaflet() %>%
      addProviderTiles(providers$OpenStreetMap) %>%
      setView(lng = -106.1, lat = 34.4, zoom = 6)
  })

  observe({
    dat <- current_sf()
    col <- input$metric
    vals <- dat[[col]]

    is_pct <- col %in% pct_metrics
    pal <- colorNumeric(
      palette = if (is_pct) "BuPu" else "YlOrBr",
      domain  = vals, na.color = "#f0f0f0"
    )

    label_fmt <- function(x) {
      if (is_pct) paste0(round(x, 1), "%") else comma(round(x))
    }

    id_field <- if (input$geo == "gmu") "gmu" else "county"
    title_field <- if (input$geo == "gmu") "GMU" else "County"

    # County acreage layers are a blend of real ranch boundaries (unit-wide
    # ranches NMDGF publishes) and an area-weighted estimate for the rest
    # (mostly ranch-only ranches with no published boundary) — flag it.
    verified_note <- if (input$geo == "county" && "pct_of_county_total_verified" %in% names(dat) &&
                          col %in% c("total_elk_occupied_acreage", "acreage_Base", "acreage_SCR")) {
      sprintf("<br/><em>%s%% ranch-boundary verified, rest is area-weighted estimate</em>",
              round(dat$pct_of_county_total_verified, 0))
    } else ""

    labels <- sprintf(
      "<strong>%s %s</strong><br/>%s: %s%s",
      title_field, dat[[id_field]],
      names(metric_choices)[metric_choices == col],
      ifelse(is.na(vals), "no data", label_fmt(vals)),
      verified_note
    ) %>% lapply(htmltools::HTML)

    leafletProxy("map", data = dat) %>%
      clearShapes() %>%
      clearControls() %>%
      addPolygons(
        fillColor = ~pal(vals),
        fillOpacity = 0.75,
        color = "#555555", weight = 1,
        label = labels,
        highlightOptions = highlightOptions(weight = 2, color = "#222", bringToFront = TRUE)
      ) %>%
      addLegend(position = "bottomright", pal = pal, values = vals,
                title = names(metric_choices)[metric_choices == col],
                labFormat = if (is_pct) labelFormat(suffix = "%") else labelFormat(big.mark = ","))
  })

  # observe({
  #   proxy <- leafletProxy("map")
  #   proxy %>% clearGroup("core_range")
  #   if (isTRUE(input$show_core) && has_core_range) {
  #     pal_core <- colorFactor(c("#1b7837", "#d9d9d9"), domain = core_range$range_class)
  #     proxy %>%
  #       addPolygons(data = core_range, group = "core_range",
  #                   fillColor = ~pal_core(range_class), fillOpacity = 0.5,
  #                   color = "#333", weight = 0.5,
  #                   label = ~range_class)
  #   }
  # })
  
  observeEvent(input$geo, {
    dat <- current_sf()
    
    # Filter metric choices to only those that exist in the active dataset's column names
    valid_choices <- metric_choices[metric_choices %in% names(dat)]
    
    updateSelectInput(session, "metric", 
                      choices = valid_choices,
                      selected = if(input$metric %in% valid_choices) input$metric else valid_choices[1])
  })
}

# =============================================================================
# 4. RUN APPLICATION
# =============================================================================
shinyApp(ui, server)
