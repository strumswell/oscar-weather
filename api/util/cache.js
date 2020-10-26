const mcache = require("memory-cache");

const { distanceBetweenCoordinates } = require("./distance.js");

let weatherCache = (duration) => {
  return (req, res, next) => {
    let reqLat = req.query.lat;
    let reqLon = req.query.lon;
    let key = `weather-${reqLat}-${reqLon}`;
    let cachedBody = mcache.get(key);

    // Server identical location if available
    if (cachedBody) {
      res.send(JSON.parse(cachedBody));
      return;
    } else {
      // Serve nearby location if available
      if (mcache.keys().length > 0) {
        for (let currentKey of mcache.keys()) {
          let keyData = currentKey.split("-");
          if (keyData[0] == "weather") {
            let cords = { lat: keyData[1], lon: keyData[2] };
            let distance = distanceBetweenCoordinates(reqLat, reqLon, cords.lat, cords.lon);
            if (distance < 2) {
              res.send(JSON.parse(mcache.get(currentKey)));
              return;
            }
          }
        }
      }
    }
    // Unknown location
    res.sendResponse = res.send;
    res.send = (body) => {
      mcache.put(key, body, duration * 60000);
      res.sendResponse(body);
    };
    next();
  };
};

let mapshotCache = (duration) => {
  return (req, res, next) => {
    let reqLat = req.query.lat;
    let reqLon = req.query.lon;
    let reqMapType = req.query.map;
    let reqRadarColor = req.query.color;

    let key = `mapshot-${reqLat}-${reqLon}-${reqMapType}-${reqRadarColor}`;
    let cachedBody = mcache.get(key);

    // Server identical location if available
    if (cachedBody) {
      res.sendFile(cachedBody);
      return;
    }

    // Unknown location
    res.sendResponse = res.sendFile;
    res.sendFile = (body) => {
      mcache.put(key, body, duration * 60000);
      res.sendResponse(body);
    };
    next();
  };
};

exports.weatherCache = weatherCache;
exports.mapshotCache = mapshotCache;
