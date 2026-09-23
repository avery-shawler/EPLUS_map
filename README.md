#######################################################################
####### NM EPLUS Elk Occupied Acreage — Interactive Shiny Map #########
##### created by Avery Shawler for Western Landowners Alliance ########
#######################################################################

## contact: avery@westernlandowners.org
## last updated: September 23, 2026

This interactive R Shiny application maps Game Management Unit (GMU) and county boundaries 
alongside EPLUS authorization metrics using `leaflet` and `sf`. 
The application is hosted on **Posit Connect Cloud** and is fully automated to deploy via **GitHub**.

---
###################################################
#### 1. The Data Pipeline & Processing Scripts ####
###################################################

The data pipeline consists of extracting raw data from state sources, 
downloading public spatial layers, and merging them using **3 pre-processing R scripts**. 

### Raw Data Sources
1. **Landowner PDF List:** 
Landowner registration tables extracted from the official New Mexico Department of Game and Fish (NMDGF) 
[2026 E-PLUS Landowner List PMZ PDF](https://wildlife.dgf.nm.gov/download/eplus-landowner-list-pmz-updated-08-10-2026/?wpdmdl=55621&refresh=6ab3a223655ab1790157347).

2. **NMDGF ArcGIS Portal:** 
Exact ranch parcel polygons gathered from the NMDGF [ArcGIS Experience Builder Map]
(https://experience.arcgis.com/experience/6079aed4c8c347dd924111e8bfb91861).

### Execution Order
Before running the main `app.R` script, you **must run the following three scripts in order** 
to compile your local data assets (requires internet access; script `02` takes a few minutes due to spatial overlays):

1. **`R/01_prepare_eplus_data.R`**: 
Parses, cleans, and dedupes the raw EPLUS text extracts.

2. **`R/02_get_spatial_layers.R`**: 
Queries public feature servers for GMUs, queries US Census `tigris` for counties, 
extracts public Unit-Wide (UW) ranch polygons from the NMDGF Feature Server, 
and calculates the BLM land ownership intersections.

3. **`R/03_build_final_layers.R`**: Combines spatial overlays, 
processes area-weighted estimates for Ranch-Only (RO) assignments, 
and exports finalized datasets to the `data/` folder.

---
########################################################
#### 2.  Critical Data-Quality & Parser Corrections ####
########################################################

> **Important Data Version Alert:** 
If you pulled numbers from the first project delivery for legislator- or public-facing work, 
please **re-pull them using the updated data in this folder.**

The initial PDF parser only recognized purely numeric GMU codes (e.g., `2-20000`). 
It silently dropped or misallocated New Mexico's **10 lettered GMU subunits** (*5A, 5B, 6A, 6C, 16A, 16C, 16D, 16E, 21A, 21B*) 
and compound boundary codes (*16B/22-#####*). This undercounted the true footprint by ~385 ranches and ~438,000 acres. 

**All files in this workspace have been regenerated with a corrected parser.** 
Every record's acreage now parses cleanly with 0 unmatched rows outside of the PDF's introductory text:

| Metric | Originally Reported | Corrected & Verified |
| :--- | :--- | :--- |
| **Authorization Rows** | 1,977 | **2,373** |
| **Unique Ranches (Deduped)** | 1,909 | **2,288** |
| **Unique GMU Codes** | 20 | **31** *(including 10 lettered subunits + 1 compound)* |
| **Total Deduped Elk Occupied Acreage** | 2,072,901 | **2,510,379** |

*Note on Double Counting:* 
85 ranches hold authorizations across multiple PDF tables (e.g., both "Base and SCR Pool" and "Habitat Incentives"). 
Summing rows naively yields **2,701,953 acres**. True unique acreage is **2,510,379 acres**. 
The "By Authorization Type" map layer intentionally leaves these un-deduped across types so each authorization tier 
displays its true economic total.

## Other important things to note about the source data in this map ##
**1. County per ranch, from the ArcGIS Experience Builder app **
Turned out to be findable after all: the Experience Builder app's Network
tab, filtered to `FeatureServer`, revealed a public, anonymous-query-enabled
feature service: `EPLUS_Active_Ranches_2026_view`, layer 1
(`https://services2.arcgis.com/CjbW1bVhK4dB3WOa/arcgis/rest/services/EPLUS_Active_Ranches_2026_view/FeatureServer/1`).
It publishes **actual ranch parcel polygons** — not just points — with a
`unit_ranch_number` field that matches the PDF's Unit-Ranch Number exactly.
1,306 ranches downloaded (capped at the server's 1,000-record limit, so two
paginated requests), spatially joined against Census county boundaries in
Python (`shapely`/`STRtree`, centroid-in-polygon with intersection-area
fallback for the 44 ranches whose parcel straddles a county line).

Cross-validated against the PDF: of the 1,306 polygons, 1,300 matched a
Unit-Ranch Number in this PMZ list, all with **identical acreage** — the 6
that didn't match belong to a compound unit code (`16B/22`) that turns out
to be genuinely outside this PDF's Primary Management Zone scope, not a
matching error. Result: `data/eplus_ranch_county_join.csv`.

**The catch:** this feature service only covers **unit-wide (UW) ranches** —
1,306 of them, ~26% of statewide elk occupied acreage. NMDGF's own PDF says
outright that "the Department does not publish maps for ranch-only
ranches," and ranch-only (RO) ranches are ~74% of the acreage, so no
published boundary exists for most of it. If your NMDGF contact can share
an internal RO ranch boundary layer, that's the one gap left to close.

**2. What covers the other 74% — area-weighted GMU-to-county apportionment**
`02_get_spatial_layers.R` computes an **area-weighted GMU-to-county
crosswalk** (intersects GMU polygons with county polygons, apportions by
area share) for every ranch that isn't in the exact-match layer above —
overwhelmingly RO ranches. `03_build_county_blended.R` combines the two:
exact acreage where we have real boundaries, apportioned estimate for the
rest, and computes `pct_of_county_total_verified` per county so the app (and
anyone reading it) can see exactly how much of each county's number is
ground-truth vs. estimate. The map's county popups surface this automatically.

**3. GMU boundaries and NM county boundaries**
Both public, both wired up in `02_get_spatial_layers.R`:
  - GMU: live feature service at NM Natural Heritage Program's GIS host,
    layer described as NMDGF's official Big Game Management Units
    (Title 19.30.4 NMAC). Cross-reference / alternate vintage:
    https://www.wildlife.state.nm.us/?p=5207 (2017 shapefile/KMZ download).
  - Counties: `tigris::counties(state = "NM")` (US Census TIGER/Line).

**4. % private land per county/GMU, and % private land enrolled**
Built from the BLM "New Mexico Surface Ownership" dataset, published via NM
RGIS (gstore.unm.edu) — a statewide surface-ownership polygon layer
distinguishing federal/state/tribal/local vs. private surface ownership.
`02_get_spatial_layers.R` intersects this with the GMU and county polygons
to get `pct_private_land`. `03_build_final_layers.R` then computes
`pct_private_land_enrolled = EPLUS elk occupied acreage / private acres`
— this doesn't require ranch-level polygons (which we don't have), just the
already-known EPLUS acreage totals and the spatially-derived private-acreage
denominator.

**5. Elk core / non-core range**
I couldn't find a published, open statewide NMDGF elk core-range dataset —
what's publicly available is herd-specific research (e.g., USGS/WGA Corridor
Mapping Team GPS-collar studies for a few herds like Santa Ana and Tesuque
Pueblo), not a comprehensive core/non-core layer for the whole state. This is
very plausibly an internal NMDGF habitat layer. `app.R` is wired to display
it automatically (`data/spatial/elk_core_range.gpkg`, with a `range_class`
field of "Core"/"Non-core") the moment you obtain it from the department —
no code changes needed.

**An important data-quality note baked into the numbers**

85 ranches receive authorizations under more than one of the PDF's three
tables (e.g., both "Base and SCR Pool" and "Habitat Incentives"). Elk
Occupied Acreage is a per-ranch attribute, so it's listed identically on each
of that ranch's rows. Naively summing every row in the PDF gives
**2,701,953 acres**; deduping to one row per ranch (correct for "total
acreage" and "by ranch class" layers) gives **2,510,379 acres**. The "by
authorization type" layer intentionally does *not* dedupe across types,
since a ranch legitimately contributes to more than one authorization-type
total if it holds more than one type of authorization.

---
################################################
#### 3.  Project Architecture & File Paths ####
###############################################

To keep the application working smoothly across both your local desktop environment and the Connect Cloud server,
**all data must be referenced using relative paths**. Never use absolute paths (e.g., `/Users/averyshawler/...`) or 
leading root slashes (e.g., `/data/...`).

Ensure your local directory is structured exactly like this:
```text
EPLUS_map/
│── app.R              # Main Shiny Script (Contains Package Loads, UI, and Server logic)
│── manifest.json      # Cloud deployment blueprint (Required by Connect Cloud)
│── .gitignore         # Filters out heavy R cache files from uploading to GitHub
├── R/                 # Source data-prep scripts
│   ├── 01_prepare_eplus_data.R
│   ├── 02_get_spatial_layers.R
│   └── 03_build_final_layers.R
└── data/              # All production scripts and spatial data layers
    ├── eplus_ranch_level_deduped.csv
    ├── eplus_all_authorizations.csv
    ├── gmu_summary.csv
    ├── eplus_ranch_county_join.csv
    └── spatial/
        ├── gmu_boundaries.gpkg
        └── nm_counties.gpkg
```

---
#################################################
#### 4. Core Spatial Research & Methodology ####
################################################

The interactive layers inside `app.R` resolve four fundamental spatial questions:

1. **County Apportionment Per Ranch (Exact Match):** 
Extracted via network calls to the anonymous-query-enabled feature service `EPLUS_Active_Ranches_2026_view` (Layer 1) 
on the NMDGF ArcGIS server. It houses actual parcel polygons for **Unit-Wide (UW) ranches** (~26% of statewide enrollment). 
Parcels straddling county lines were processed via a Python centroid-in-polygon layout with intersection fallback 
(`data/eplus_ranch_county_join.csv`).

2. **Ranch-Only (RO) Allocation (Area-Weighted Estimate):** 
Because NMDGF explicitly hides boundary maps for Ranch-Only (RO) designations (~74% of enrollment), 
`02_get_spatial_layers.R` calculates an area-weighted GMU-to-county crosswalk. 
It blends exact boundaries with area-proportional tracking estimates. 
The app populates `pct_of_county_total_verified` inside county map pop-ups so users can see the exact breakdown of ground-truth vs. estimated data.

3. **Private Land & Enrollment Proportions:** 
Sourced from the BLM *New Mexico Surface Ownership* dataset via NM RGIS. 
The pipeline intersects this layer with county and GMU shapes to establish the baseline private acreage denominator, 
calculating exactly how much available private land is actively enrolled in EPLUS.

4. **Elk Core Range Fallback:** 
No open, statewide core-range habitat layer exists publicly. However, `app.R` is explicitly pre-wired to map it automatically
(`data/spatial/elk_core_range.gpkg`, requiring a `range_class` field marked "Core" or "Non-core") 
the moment you secure internal data files from your NMDGF agency contact—**no code adjustments required.**

---
###################################################
#### 5. Editing the Map & Automated Publishing ####
###################################################

We have enabled **Automatically publish on push** via GitHub. Y
ou no longer need to run manual local connection scripts, handle tokens, or deploy from the RStudio console.

### Step 1: Make and Test Edits Locally
1. Edit your code inside `app.R` or replace data sheets in your `data/` folder.
2. Click **Run App** in RStudio to thoroughly verify your changes locally.

### Step 2: Push to GitHub to Update the Live Web App
Open the **Terminal** tab in RStudio (located right next to your console panel) and run these three standard Git lines:

```bash
# 1. Stage your code adjustments and updated data records
git add app.R data/

# 2. Document what you changed
git commit -m "Updated mapping data metrics for August 2026"

# 3. Push changes live to your online profile (Triggers Connect Cloud build)
git push origin main
```

> **Terminal Password Requirement:** 
When running `git push`, the terminal will prompt you for your Username (`avery-shawler`) and Password. 
You **cannot** use your normal login password. 
You must paste your generated **GitHub Personal Access Token (PAT)** (`ghp_...`). 
The cursor will stay completely still and hidden while pasting—this is expected security behavior. 
Just paste it and hit `Enter`.

Connect Cloud will automatically capture your push, 
spin up a secure Linux container, 
download a server-compatible release of **`terra` (1.9+)**, 
and update your live tracking map web link in less than 60 seconds.

*Note on New Packages:* 
If you add a brand new R package library to your script, 
run `rsconnect::writeManifest()` in your **Console** followed by `git add -f manifest.json` in your **Terminal** before pushing, 
so the server knows to install your new package!

---
#############################################################
#### 6. Embedding in an ArcGIS StoryMap (Recommendation) ####
#############################################################

Keep this visualization hosted as an independent R Shiny application on Connect Cloud and 
**embed it cleanly into your ArcGIS StoryMap using a native iframe/embed block**. 


## Reasons for keeping this map as a standalone R Shiny app on Posit Connect Cloud 
## rather than trying to recreate the same map in Esri's ArcGIS Online for the StoryMap:

  - All the derived metrics here (deduped totals, apportioned county
    acreage, %-private, %-enrolled) are computations, not static
    attributes — much easier to keep data accurate and update in R code than to
    maintain as several distinct separately-computed static Esri feature layers and 
    joins across multiple ArcGIS Online maps.
    
  - When NMDGF issues next year's landowner list PDF, you re-run three R
    scripts, push to GitHub, and the embedded StoryMap asset updates itself instantly. 
    (— versus re-doing potentially several ArcGIS Online layer publishes/joins.)
    
  - You keep full control of the color scales, toggles, and layer logic
    described in this app, which native StoryMap map blocks don't offer.
    
  - Trade-off: an embedded Shiny app depends on a hosting service staying up
    (Posit Connect Cloud free tier sleeps/has usage caps of 5 apps) — for a public-facing,
    legislator-visible map, a paid tier or Shiny Server on agency
    infrastructure is worth budgeting for over the free tier.

If StoryMap-native layers are a hard requirement (e.g., IT policy against
external iframes), the fallback is: run the three R scripts here to produce
`gmu_final.csv`/`county_final.csv`, join them to the boundary shapefiles in
ArcGIS Pro, publish as hosted feature layers with graduated-color renderers,
and add each as its own toggleable map layer in the StoryMap. That reproduces
the map but loses the single-app dropdown UX and needs to be redone by hand
each update cycle.
