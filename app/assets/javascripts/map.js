// Leaflet maps for elements with a data-map attribute. Plain JS, no framework:
// the server renders everything else.
(function () {
  "use strict";

  var COLOURS = { direct: "#1d6b5a", near: "#2f5f86", walkable: "#8a7350" };
  var ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

  function popupFor(point) {
    var element = document.createElement(point.url ? "a" : "span");
    element.textContent = point.name;
    if (point.url) element.href = point.url;
    return element;
  }

  function initMap(container) {
    var data = JSON.parse(container.getAttribute("data-map"));
    // On touch screens one-finger drags scroll the page instead of panning
    // the map; the zoom buttons and pinch still work.
    var map = L.map(container, { scrollWheelZoom: false, dragging: !L.Browser.mobile });
    var bounds = [];

    L.tileLayer(data.tiles, { maxZoom: 19, attribution: ATTRIBUTION }).addTo(map);

    if (data.footprint) {
      var outline = L.polygon(data.footprint, { color: "#123f47", weight: 2, fillOpacity: 0.25 }).addTo(map);
      bounds.push(outline.getBounds().getNorthEast(), outline.getBounds().getSouthWest());
    }

    (data.properties || []).forEach(function (point) {
      L.circleMarker([point.lat, point.lon], {
        radius: 8, color: "#ffffff", weight: 2, fillOpacity: 1,
        fillColor: COLOURS[point.category] || "#123f47"
      }).bindPopup(popupFor(point)).addTo(map);
      bounds.push([point.lat, point.lon]);
    });

    if (data.measurement) {
      var line = L.polyline([data.measurement.from, data.measurement.to], {
        color: "#c4542b", weight: 3, dashArray: "6 6"
      }).addTo(map);
      line.bindTooltip(data.measurement.label, { permanent: true, direction: "center", className: "map-label" });
      L.circleMarker(data.measurement.to, { radius: 5, color: "#c4542b", fillOpacity: 1 }).addTo(map);
      bounds.push(data.measurement.from, data.measurement.to);
    }

    if (bounds.length > 1) {
      map.fitBounds(bounds, { padding: [40, 40], maxZoom: data.maxZoom || 17 });
    } else if (bounds.length === 1) {
      map.setView(bounds[0], data.maxZoom || 16);
    } else {
      map.setView(data.center, data.zoom || 12);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (typeof L === "undefined") return;
    Array.prototype.forEach.call(document.querySelectorAll("[data-map]"), initMap);
  });
})();
