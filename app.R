#### Instructions ####
## instead of pressing the 'Run App' button, run code block 1 separately, then run code blocks 2-4 

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
# Load pre-built layers (run R/01, R/02, R/03, R/04 first — see README)
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
# core_range_path <- "data/spatial/elk_core_range.gpkg"
# has_core_range  <- file.exists(core_range_path)
# if (has_core_range) {
#   core_range <- st_read(core_range_path, quiet = TRUE) %>% st_transform(4326)
# }

#### old code below - might delete later ####

# # Metric choices shown in the dropdown, mapped to column names -------------
# metric_choices <- c(
#   "Total elk occupied acreage"                         = "total_elk_occupied_acreage",
#   "Elk occupied acreage \u2014 Base ranches"            = "acreage_Base",
#   "Elk occupied acreage \u2014 SCR ranches"             = "acreage_SCR",
#   "Acreage \u2014 Base and SCR Pool authorizations"     = "acreage_Base and SCR Pool",
#   "Acreage \u2014 Habitat Incentives authorizations"    = "acreage_Habitat Incentives",
#   "Acreage \u2014 Special Management Ranch authorizations" = "acreage_Special Management Ranches",
#   "% private land"                                      = "pct_private_land",
#   "% private land enrolled in EPLUS (elk occupied)"     = "pct_private_land_enrolled"
# )
# 
# pct_metrics <- c("pct_private_land", "pct_private_land_enrolled")

#### new updated code for new map layout ####
# -----------------------------------------------------------------------------
# Layer definitions, grouped exactly as requested:
#   Group 1 — EPLUS-enrolled ranch elk occupied acreage: Total / Base / SCR
#   Group 2 — Percent private land per county/GMU: all private / EPLUS-enrolled
# Each has a short hover description (shown as a native tooltip on the label).
# -----------------------------------------------------------------------------
acreage_layers <- list(
  list(value = "total_elk_occupied_acreage",
       label = "Total acres (Base + SCR)",
       descr = "Total EPLUS elk occupied acreage across all enrolled ranches (Base + SCR)."),
  list(value = "acreage_Base",
       label = "Base ranch acres",
       descr = "Elk occupied acreage on Base ranches only \u2014 ranches that receive at least one whole authorization through the acreage-based allocation formula."),
  list(value = "acreage_SCR",
       label = "SCR ranch acres",
       descr = "Elk occupied acreage on SCR (Small Contributing Ranch) ranches only \u2014 ranches too small for a guaranteed whole authorization; they compete yearly in a random draw for up to one authorization.")
)

pct_layers <- list(
  list(value = "pct_private_land",
       label = "% of total area (GMU or county) that is private land",
       descr = "Percent of the total area (GMU or county) that is privately owned (vs. federal, state, tribal, or local public land)."),
  list(value = "pct_private_land_enrolled",
       label = "% of private land enrolled in EPLUS (elk occupied acres)",
       descr = "EPLUS elk occupied acreage as a percent of the GMU/county's total private land acreage.")
)

all_layers <- c(acreage_layers, pct_layers)
metric_label_lookup <- setNames(sapply(all_layers, `[[`, "label"), sapply(all_layers, `[[`, "value"))
acreage_values <- sapply(acreage_layers, `[[`, "value")
pct_values     <- sapply(pct_layers, `[[`, "value")

radio_choice_names <- function(layer_list) {
  lapply(layer_list, function(x) tags$span(title = x$descr, x$label))
}

# =============================================================================
# 2. USER INTERFACE (UI)
# =============================================================================
map_tab <- tabPanel(
  "Map",
  tags$head(
    tags$style(HTML("
      .leaflet-tile-container {
        filter: grayscale(100%) brightness(110%) contrast(90%);
      }
      .app-header { padding: 12px 20px 4px 20px; }
      .app-header h2 { margin-bottom: 4px; }
      .app-header p.subtitle { color: #444; font-size: 0.92em; max-width: 900px; }
      .app-header p.uwro-note { color: #555; font-size: 0.85em; max-width: 900px; font-style: italic; }
      .controls-panel h5 { margin-top: 14px; margin-bottom: 4px; font-weight: 600; }
      .key-box {
        padding: 10px 20px; background: #f7f5f0; border-top: 1px solid #ddd;
        font-size: 0.82em; color: #333;
      }
      .key-box b { margin-right: 4px; }
      .key-box .footnote { display:block; margin-top: 6px; font-style: italic; }
    "))
  ),
  div(class = "app-header",
      h2("EPLUS Map"),
      p(class = "subtitle",
        strong("Elk Private Lands Use (EPLUS) Program, "),
        "This map shows information from private land elk authorizations for deeded acres", 
        "enrolled in EPLUS within the Primary Management Zone for the April 1, 2026 \u2013 March 31, 2027 Hunting Season",
        tags$a(href = "https://wildlife.dgf.nm.gov/hunting/maps/eplus/", target = "_blank",
               "More on the EPLUS program on the New Mexico Department of Wildlife website \u2192"))
  ),
  sidebarLayout(
    sidebarPanel(
      width = 3, class = "controls-panel",
      selectInput("geo", "GMU or County",
                  choices = c("Game Management Unit (GMU)" = "gmu", "County*" = "county")),
      h5("EPLUS elk occupied acreage"),
      radioButtons("acreage_metric", label = NULL,
                   choiceNames = radio_choice_names(acreage_layers),
                   choiceValues = acreage_values,
                   selected = "total_elk_occupied_acreage"),
      h5("Percentages"),
      radioButtons("pct_metric", label = NULL,
                   choiceNames = radio_choice_names(pct_layers),
                   choiceValues = pct_values,
                   selected = character(0))
    ),
    mainPanel(
      width = 9,
      leafletOutput("map", height = "600px")
    )
  ),
  div(class = "key-box",
      strong("Key: "),
      tags$b("GMU"), "= Game Management Unit.  ",
      tags$b("Base"), "= Base ranches receive at least one whole authorization through the acreage-based allocation formula.  ",
      tags$b("SCR"), "= Small Contributing Ranches are too small to receive at least one whole authorization through the acreage-based allocation formula; SCRs compete yearly in a random draw, weighted on the ranch's ranch score, and may draw up to one authorization per year.",
      tags$b("UW"), "= A Unit-Wide authorization is valid on that ranch, other unit-wide ranches, other private land with written permission, and legally accessible public land within the unit.",
      tags$b("RO"), "= A Ranch-Only authorization is valid only on that specific ranch's deeded acres. NMDGF publishes ranch boundary maps for UW ranches only — RO ranch boundaries are not publicly available, which is why some layers below rely on an estimate rather than a verified boundary (see the *County note below).",
      tags$span(class = "footnote",
                "* County acreage figures blend verified county assignment for Unit-Wide (UW) ranches ",
                "(ranch boundaries, spatially joined to county lines) with an area-weighted ",
                "estimate for Ranch-Only (RO) ranches, whose boundaries NMDGF does not publish. Each ",
                "county's map tooltip shows what share of its total is verified vs. estimated. See the ",
                "Data Sources tab for detail.")
  )
)

data_sources_tab <- tabPanel(
  "Data Sources",
  div(style = "padding: 20px; max-width: 900px;",
      h3("Data Sources"),
      tags$ol(
        tags$li(
          strong("2026-2027 EPLUS Landowner List (PMZ), NMDGF PDF"), " \u2014 ",
          tags$a(href = "https://wildlife.dgf.nm.gov/download/eplus-landowner-list-pmz-updated-08-10-2026/?wpdmdl=55621&refresh=6ab3a223655ab1790157347",
                 target = "_blank", "download link"),
          p("Parsed to extract, per ranch: Unit-Ranch Number, Game Management Unit (derived from ",
            "the digits/letters before the hyphen in the Unit-Ranch Number), ranch class (Base or ",
            "SCR), Elk Occupied Acreage, and authorization type (Base and SCR Pool / Habitat ",
            "Incentives / Special Management Ranches). Ranches holding more than one authorization ",
            "type are de-duplicated before summing acreage, so totals aren't inflated by a ranch ",
            "appearing on more than one of the PDF's three tables.")
        ),
        tags$li(
          strong("NMDGF EPLUS Unit-Wide Ranches, ArcGIS Online interactive map"), " \u2014 ",
          tags$a(href = "https://experience.arcgis.com/experience/6079aed4c8c347dd924111e8bfb91861",
                 target = "_blank", "interactive map"),
          p("This map's underlying public feature service (EPLUS_Active_Ranches_2026_view) ",
            "has ranch parcel data for Unit-Wide (UW) ranches. This data ",
            "was spatially joined to county boundaries to get a verified, ground-truth ",
            "ranch \u2192 county assignment for the ~26% of statewide elk occupied acreage that is ",
            "on UW ranches. Ranch-Only (RO) ranches \u2014 the remaining ~74% of acreage \u2014 are not ",
            "published on this map, so their county totals are estimated instead (see the County* ",
            "note in the map's Key).")
        ),
        tags$li(
          strong("New Mexico county boundaries"), " \u2014 US Census TIGER/Line, via the R ",
          tags$a(href = "https://cran.r-project.org/package=tigris", target = "_blank", "tigris"),
          " package.",
          p("Used as the polygon layer for every County-level map view, and as the target ",
            "geometry for the ranch-to-county spatial join and the GMU-to-county area-weighted ",
            "apportionment described above.")
        ),
        tags$li(
          strong("Game Management Unit (GMU) boundaries"), " \u2014 NM Natural Heritage Program / ",
          "NMDGF live feature service, cross-referenced with NMDGF's ",
          tags$a(href = "https://www.wildlife.state.nm.us/?p=5207", target = "_blank",
                 "official GMU shapefile/KMZ download"),
          p("Used as the polygon layer for every GMU-level map view, and to compute the ",
            "GMU-to-county area overlap used for apportioning Ranch-Only ranch acreage to counties.")
        ),
        tags$li(
          strong("Land ownership / management (public vs. private land)"), " \u2014 BLM New Mexico ",
          "Surface Ownership dataset, published via ",
          tags$a(href = "https://gstore.unm.edu/apps/rgis/", target = "_blank",
                 "New Mexico RGIS"),
          p("A statewide polygon layer distinguishing federal, state, tribal, and local ",
            "government land from privately owned land. Intersected with the GMU and county ",
            "polygons to compute the \"% of total area (GMU or county) that is private land\" layer, and combined with EPLUS elk ",
            "occupied acreage to compute \"% of private land enrolled in EPLUS (elk occupied acres)\".")
        )
      )
  )
)

ui <- navbarPage(
  title = "NM EPLUS Map",
  map_tab,
  data_sources_tab
)

# =============================================================================
# 3. SERVER LOGIC
# =============================================================================
server <- function(input, output, session) {
  
  current_sf <- reactive({
    if (input$geo == "gmu") gmu_map else county_map
  })
  
  # Only one metric is ever active across BOTH radio groups at a time —
  # picking one clears the other, so the two groups behave like a single
  # mutually-exclusive layer picker even though they're visually separated
  # under their own subheadings.
  active_metric <- reactiveVal("total_elk_occupied_acreage")
  
  observeEvent(input$acreage_metric, {
    req(input$acreage_metric)
    active_metric(input$acreage_metric)
    updateRadioButtons(session, "pct_metric", selected = character(0))
  }, ignoreInit = TRUE)
  
  observeEvent(input$pct_metric, {
    req(input$pct_metric)
    active_metric(input$pct_metric)
    updateRadioButtons(session, "acreage_metric", selected = character(0))
  }, ignoreInit = TRUE)
  
  output$map <- renderLeaflet({
    leaflet() %>%
      addProviderTiles(providers$OpenStreetMap) %>%
      setView(lng = -106.1, lat = 34.4, zoom = 6)
  })
  
  observe({
    dat <- current_sf()
    col <- active_metric()
    if (!col %in% names(dat)) return()
    vals <- dat[[col]]
    
    is_pct <- col %in% pct_values
    
    # Fixed, shared domains within each layer group so switching between
    # Total/Base/SCR — or between the two percent layers — uses the SAME
    # color scale, making them directly comparable at a glance.
    if (is_pct) {
      domain <- c(0, 100)
      palette_name <- "BuPu"
    } else {
      domain <- range(c(dat$total_elk_occupied_acreage, dat$acreage_Base, dat$acreage_SCR),
                      na.rm = TRUE)
      palette_name <- "YlOrBr"
    }
    
    pal <- colorNumeric(palette = palette_name, domain = domain, na.color = "#f0f0f0")
    
    label_fmt <- function(x) {
      if (is_pct) paste0(round(x, 1), "%") else comma(round(x))
    }
    
    id_field <- if (input$geo == "gmu") "gmu" else "county"
    title_field <- if (input$geo == "gmu") "GMU" else "County*"
    
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
      metric_label_lookup[[col]],
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
      addLegend(position = "bottomright", pal = pal,
                values = vals[!is.na(vals)],   # <- drop NA so no grey "NA" swatch in the legend
                title = metric_label_lookup[[col]],
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
}

# =============================================================================
# 4. RUN APPLICATION
# =============================================================================
shinyApp(ui, server)


#########################################################################################
####### below is the old code - will delete later once I get new code up and running #####
#########################################################################################
# 
# # =============================================================================
# # 2. USER INTERFACE (UI)
# # =============================================================================
# # -----------------------------------------------------------------------------
# ui <- fluidPage(
#   # tags$head(tags$style(HTML("
#   #   html, body {height:100%;}
#   #   #map {height: calc(100vh - 90px);}
#   #   .controls {padding: 10px 16px; background:#f7f5f0; border-bottom:1px solid #ddd;}
#   # "))),
#   tags$head(
#     tags$style(HTML("
#       .leaflet-tile-container {
#         filter: grayscale(100%) brightness(110%) contrast(90%);
#       }
#     "))
#   ),
#   div(class = "controls",
#       fluidRow(
#         column(3, selectInput("geo", "Geography",
#                                choices = c("Game Management Unit (GMU)" = "gmu",
#                                            "County (area-apportioned, see notes)" = "county"))),
#         column(5, selectInput("metric", "Layer", choices = metric_choices,
#                                selected = "total_elk_occupied_acreage"))
#         # ,
#        # column(4, checkboxInput("show_core", "Show elk core / non-core range (if available)",
#        #                         value = FALSE))
#       )
#   ),
#   leafletOutput("map")
# )
# 
# # =============================================================================
# # 3. SERVER LOGIC
# # =============================================================================
# server <- function(input, output, session) {
# 
#   current_sf <- reactive({
#     if (input$geo == "gmu") gmu_map else county_map
#   })
# 
#   output$map <- renderLeaflet({
#     leaflet() %>%
#       addProviderTiles(providers$OpenStreetMap) %>%
#       setView(lng = -106.1, lat = 34.4, zoom = 6)
#   })
# 
#   observe({
#     dat <- current_sf()
#     col <- input$metric
#     vals <- dat[[col]]
# 
#     is_pct <- col %in% pct_metrics
#     pal <- colorNumeric(
#       palette = if (is_pct) "BuPu" else "YlOrBr",
#       domain  = vals, na.color = "#f0f0f0"
#     )
# 
#     label_fmt <- function(x) {
#       if (is_pct) paste0(round(x, 1), "%") else comma(round(x))
#     }
# 
#     id_field <- if (input$geo == "gmu") "gmu" else "county"
#     title_field <- if (input$geo == "gmu") "GMU" else "County"
# 
#     # County acreage layers are a blend of real ranch boundaries (unit-wide
#     # ranches NMDGF publishes) and an area-weighted estimate for the rest
#     # (mostly ranch-only ranches with no published boundary) — flag it.
#     verified_note <- if (input$geo == "county" && "pct_of_county_total_verified" %in% names(dat) &&
#                           col %in% c("total_elk_occupied_acreage", "acreage_Base", "acreage_SCR")) {
#       sprintf("<br/><em>%s%% ranch-boundary verified, rest is area-weighted estimate</em>",
#               round(dat$pct_of_county_total_verified, 0))
#     } else ""
# 
#     labels <- sprintf(
#       "<strong>%s %s</strong><br/>%s: %s%s",
#       title_field, dat[[id_field]],
#       names(metric_choices)[metric_choices == col],
#       ifelse(is.na(vals), "no data", label_fmt(vals)),
#       verified_note
#     ) %>% lapply(htmltools::HTML)
# 
#     leafletProxy("map", data = dat) %>%
#       clearShapes() %>%
#       clearControls() %>%
#       addPolygons(
#         fillColor = ~pal(vals),
#         fillOpacity = 0.75,
#         color = "#555555", weight = 1,
#         label = labels,
#         highlightOptions = highlightOptions(weight = 2, color = "#222", bringToFront = TRUE)
#       ) %>%
#       addLegend(position = "bottomright", pal = pal, values = vals,
#                 title = names(metric_choices)[metric_choices == col],
#                 labFormat = if (is_pct) labelFormat(suffix = "%") else labelFormat(big.mark = ","))
#   })
# 
#   # observe({
#   #   proxy <- leafletProxy("map")
#   #   proxy %>% clearGroup("core_range")
#   #   if (isTRUE(input$show_core) && has_core_range) {
#   #     pal_core <- colorFactor(c("#1b7837", "#d9d9d9"), domain = core_range$range_class)
#   #     proxy %>%
#   #       addPolygons(data = core_range, group = "core_range",
#   #                   fillColor = ~pal_core(range_class), fillOpacity = 0.5,
#   #                   color = "#333", weight = 0.5,
#   #                   label = ~range_class)
#   #   }
#   # })
#   
#   observeEvent(input$geo, {
#     dat <- current_sf()
#     
#     # Filter metric choices to only those that exist in the active dataset's column names
#     valid_choices <- metric_choices[metric_choices %in% names(dat)]
#     
#     updateSelectInput(session, "metric", 
#                       choices = valid_choices,
#                       selected = if(input$metric %in% valid_choices) input$metric else valid_choices[1])
#   })
# }
# 
# # =============================================================================
# # 4. RUN APPLICATION
# # =============================================================================
# shinyApp(ui, server)
