// Leaflet.MapkitMutant - use (Apple's) MapkitJS basemaps in Leaflet.
// See https://gitlab.com/IvanSanchez/Leaflet.MapkitMutant

L.MapkitMutant = L.Layer.extend({
  options: {
    minZoom: 3,
    maxZoom: 23,

    // 🍂option type: String = 'standard'
    // mapkit's map type. Valid values are strings 'standard' (default),
    // 'satellite' or 'hybrid'.
    type: "standard",

    // 🍂option authorizationCallback: Function
    // An autorization callback function, as described
    // in [Apple's mapkitJS documentation](https://developer.apple.com/documentation/mapkitjs/mapkit/2974045-init)
    authorizationCallback: function () {},

    // 🍂option language: String = undefined
    // A language code, as described in
    // [Apple's mapkitJS documentation](https://developer.apple.com/documentation/mapkitjs/mapkit/2974045-init).
    // By default Mapkit will use the locale setting from the web browser.

    // 🍂option opacity: Number = 1.0
    // The opacity of the MapkitMutant
    opacity: 1,

    // 🍂option debugRectangle: Boolean = false
    // Whether to add a rectangle with the bounds of the mutant to the map.
    // Only meant for debugging, most useful at low zoom levels.
    debugRectangle: false,
  },

  initialize: function (options) {
    L.Util.setOptions(this, options);

    /// TODO: Add a this._mapkitPromise, just like GoogleMutant

    mapkit.init({
      authorizationCallback: this.options.authorizationCallback,
      language: this.options.langhage,
    });
  },

  onAdd: function (map) {
    this._map = map;

    this._initMutantContainer();

    this._initMutant();

    map.on("move zoom moveend zoomend", this._update, this);
    map.on("resize", this._resize, this);
    this._resize();
  },

  onRemove: function (map) {
    map._container.removeChild(this._mutantContainer);
    this._mutantContainer = undefined;
    map.off("move zoom moveend zoomend", this._update, this);
    map.off("resize", this._resize, this);
    this._mutant.removeEventListener("region-change-end", this._onRegionChangeEnd, this);
    if (this._canvasOverlay) {
      this._canvasOverlay.remove();
    }
  },

  // Create the HTMLElement for the mutant map, and add it as a children
  // of the Leaflet Map container
  _initMutantContainer: function () {
    if (!this._mutantContainer) {
      this._mutantContainer = L.DomUtil.create("div", "leaflet-mapkit-mutant");
      this._mutantContainer.id = "_MutantContainer_" + L.Util.stamp(this._mutantContainer);
      this._mutantContainer.style.zIndex = "200"; //leaflet map pane at 400, controls at 1000
      this._mutantContainer.style.pointerEvents = "none";

      this._map.getContainer().appendChild(this._mutantContainer);
    }

    // 		this.setOpacity(this.options.opacity);
    this.setElementSize(this._mutantContainer, this._map.getSize());

    //this._attachObserver(this._mutantContainer);
  },

  // Create the mutant map inside the mutant container
  _initMutant: function () {
    if (!this._mutantContainer) return;

    var mapType = mapkit.Map.MapTypes.Standard;
    if (this.options.type === "hybrid") {
      mapType = mapkit.Map.MapTypes.Hybrid;
    } else if (this.options.type === "satellite") {
      mapType = mapkit.Map.MapTypes.Satellite;
    } else if (this.options.type === "muted") {
      mapType = mapkit.Map.MapTypes.MutedStandard;
    }

    mapkit.Map.ColorSchemes.Dark;

    var map = new mapkit.Map(this._mutantContainer, {
      visibleMapRect: this._leafletBoundsToMapkitRect(),
      showsUserLocation: false,
      showsUserLocationControl: false,

      // WTF, apple devs? other options are boolean but this is a
      // `mapkit.FeatureVisibility`. F*ck consistency, amirite?!
      showsCompass: "hidden",

      showsZoomControl: false,
      showsUserLocationControl: false,
      showsScale: false,
      showsMapTypeControl: false,
      mapType: mapType,
      colorScheme: "dark",
    });

    this._mutant = map;
    map.addEventListener("region-change-end", this._onRegionChangeEnd, this);
    map.addEventListener("region-change-start", this._onRegionChangeStart, this);

    // 🍂event spawned
    // Fired when the mutant has been created.
    this.fire("spawned", { mapObject: map });

    // Call _update once, so that it can fetch the mutant's canvas and
    // create the L.ImageOverlay
    L.Util.requestAnimFrame(this._update, this);
  },

  // Fetches the map's current *projected* (EPSG:3857) bounds, and returns
  // an instance of mapkit.MapRect
  _leafletBoundsToMapkitRect: function () {
    var bounds = this._map.getPixelBounds();
    var scale = this._map.options.crs.scale(this._map.getZoom());
    var nw = bounds.getTopLeft().divideBy(scale);
    var se = bounds.getBottomRight().divideBy(scale);

    // Map those bounds into a [[0,0]..[1,1]] range
    var projectedBounds = L.bounds([nw, se]);

    var projectedCenter = projectedBounds.getCenter();
    var projectedSize = projectedBounds.getSize();

    var result = new mapkit.MapRect(
      projectedCenter.x - projectedSize.x / 2,
      projectedCenter.y - projectedSize.y / 2,
      projectedSize.x,
      projectedSize.y
    );
    return result;
  },

  // Given an instance of mapkit.MapRect, returns an instance of L.LatLngBounds
  // This depends on the current map center, as to shift the bounds on
  // multiples of 360 in order to prevent artifacts when crossing the
  // antimeridian.
  _mapkitRectToLeafletBounds: function (rect) {
    // Ask MapkitJS to provide the lat-lng coords of the rect's corners
    var nw = new mapkit.MapPoint(rect.minX(), rect.maxY()).toCoordinate();
    var se = new mapkit.MapPoint(rect.maxX(), rect.minY()).toCoordinate();

    var lw = nw.longitude + Math.floor(rect.minX()) * 360;
    var le = se.longitude + Math.floor(rect.maxX()) * 360;

    var centerLng = this._map.getCenter().lng;

    // Shift the bounding box on the easting axis so it contains the map center
    if (centerLng < lw) {
      // Shift the whole thing to the west
      var offset = Math.floor((centerLng - lw) / 360) * 360;
      lw += offset;
      le += offset;
    } else if (centerLng > le) {
      // Shift the whole thing to the east
      var offset = Math.ceil((centerLng - le) / 360) * 360;
      lw += offset;
      le += offset;
    }

    return L.latLngBounds([L.latLng(nw.latitude, lw), L.latLng(se.latitude, le)]);
  },

  _update: function () {
    if (this._map && this._mutant) {
      this._mutant.setVisibleMapRectAnimated(this._leafletBoundsToMapkitRect(), false);
    }
  },

  _resize: function () {
    var size = this._map.getSize();
    if (this._mutantContainer.style.width === size.x && this._mutantContainer.style.height === size.y) return;
    this.setElementSize(this._mutantContainer, size);
    if (!this._mutant) return;
  },

  _onRegionChangeEnd: function (ev) {
    // console.log(ev.target.region.toString());

    if (!this._mutantCanvas) {
      this._mutantCanvas = this._mutantContainer.querySelector("canvas.syrup-canvas");
    }

    if (this._map && this._mutantCanvas) {
      // Despite the event name and this method's name, fetch the mutant's
      // visible MapRect, not the mutant's region. It uses projected
      // coordinates (i.e. scaled EPSG:3957 coordinates). This prevents
      // latitude shift artifacts.
      var bounds = this._mapkitRectToLeafletBounds(this._mutant.visibleMapRect);

      // The mutant will take one frame to re-stitch its tiles, so
      // repositioning the mutant's overlay has to take place one frame
      // after the 'region-change-end' event, in order to avoid graphical
      // glitching.

      L.Util.cancelAnimFrame(this._requestedFrame);

      this._requestedFrame = L.Util.requestAnimFrame(function () {
        if (!this._canvasOverlay) {
          this._canvasOverlay = L.imageOverlay(null, bounds);

          // Hack the ImageOverlay's _image property so that it doesn't
          // create a HTMLImageElement
          var img = (this._canvasOverlay._image = L.DomUtil.create("div"));

          L.DomUtil.addClass(img, "leaflet-image-layer");
          L.DomUtil.addClass(img, "leaflet-zoom-animated");

          // Move the mutant's canvas out of its container, and into
          // the L.ImageOverlay's _image
          this._mutantCanvas.parentElement.removeChild(this._mutantCanvas);
          img.appendChild(this._mutantCanvas);

          this._canvasOverlay.addTo(this._map);
          this._updateOpacity();
        } else {
          this._canvasOverlay.setBounds(bounds);
        }
        this._mutantCanvas.style.width = "100%";
        this._mutantCanvas.style.height = "100%";
        this._mutantCanvas.style.position = "absolute";

        if (this.options.debugRectangle) {
          if (!this.rectangle) {
            this.rectangle = L.rectangle(bounds, {
              fill: false,
            }).addTo(this._map);
          } else {
            this.rectangle.setBounds(bounds);
          }
        }
      }, this);
    }
  },

  // 🍂method setOpacity(opacity: Number): this
  // Sets the opacity of the MapkitMutant.
  setOpacity: function (opacity) {
    this.options.opacity = opacity;
    this._updateOpacity();
    return this;
  },

  _updateOpacity: function () {
    if (this._mutantCanvas) {
      L.DomUtil.setOpacity(this._mutantCanvas, this.options.opacity);
    }
  },

  _onRegionChangeStart: function (ev) {
    /// TODO: check if there's any use to this event handler, clean up
    //         console.timeStamp('region-change-start');
  },

  setElementSize: function (e, size) {
    e.style.width = size.x + "px";
    e.style.height = size.y + "px";
  },
});

L.mapkitMutant = function mapkitMutant(options) {
  return new L.MapkitMutant(options);
};
