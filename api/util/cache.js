const mcache = require("memory-cache");

const { distanceBetweenCoordinates } = require("./distance.js");

let weatherCache = (duration) => {
  return (req, res, next) => {
    let reqLat = req.params.lat;
    let reqLon = req.params.lon;
    let key = `weather-${reqLat}-${reqLon}`;
    let cachedBody = mcache.get(key);

    // Server identical location if available
    if (cachedBody) {
      res.send(JSON.parse(cachedBody));
      return;
    } else {
      // Serve nearby location if available
      if (mcache.keys().length > 0) {
        console.log(mcache.keys());
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
    let reqLat = req.params.lat;
    let reqLon = req.params.lon;
    let key = `mapshot-${reqLat}-${reqLon}`;
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
