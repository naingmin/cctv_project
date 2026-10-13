# Map (OpenStreetMap + flutter_map)

The mobile map uses **flutter_map** with **OpenStreetMap** raster tiles.
Google Maps is not used, which keeps the app suitable for Myanmar and free of
per-request billing.

## Configuration

```
MAP_TILE_URL=https://tile.openstreetmap.org/{z}/{x}/{y}.png
MAP_ATTRIBUTION=© OpenStreetMap contributors
```

The tile URL is abstracted behind configuration so a production deployment can
point at a self-hosted or commercial OSM-based tile provider without changing
map code. **Required OpenStreetMap attribution must always remain visible** per
the tile usage policy; do not remove it.

> The public OSM tile server is fine for development but is **not** intended for
> production-scale traffic. Switch `MAP_TILE_URL` to an appropriate provider for
> production.

## Viewport-based loading

The app must never load all CCTV records or render all markers.

```
Map moves (debounced)
   └─► GET /cctvs/map?min_lat&max_lat&min_lng&max_lng&zoom&status
          └─► MongoDB $geoWithin (2dsphere)
                 └─► lightweight markers only { id, cctv_id, lat, lng, status }
```

Markers carry no full-resolution images. Details load on demand.

## Clustering

Clustering runs **client-side over the already-bounded viewport result**, so it
never requires the full dataset in memory. At low zoom, nearby points merge into
cluster bubbles; at high zoom, individual markers appear.

## Nearby

`GET /cctvs/nearby?latitude&longitude&radius_meters` uses MongoDB `$near` so
distance is computed server-side by the database, not in Flutter.

## Current location

`geolocator` handles permissions and GPS. The app distinguishes:
permission denied, denied forever, GPS disabled, low accuracy, timeout, and
unavailable. An invalid or unavailable coordinate is never silently used.
