# Coastline for the issue-8 distance-to-coast diagnostic

`ne_10m_coastline_wfs.gpkg`: Natural Earth 1:10m physical coastline (public domain, https://www.naturalearthdata.com/downloads/10m-physical-vectors/), downloaded with `rnaturalearth::ne_download(scale = 10, type = "coastline", category = "physical")` on 19 October 2026 and cropped to the WFS grid box (-87.5 to -81 E, 25 to 30.5 N) by `docs/issue8_nearshore-hybrid/check_nearshore_issue8.R`, which recreates it when it is missing.

At 1:10m the coastline resolves the large bays (Tampa Bay, Charlotte Harbor, Apalachicola Bay) 
but not every small inlet, so a distance to coast from it is good to about 1 to 2 km.
