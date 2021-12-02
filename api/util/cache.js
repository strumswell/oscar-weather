const mcache = require("memory-cache");
const { distanceBetweenCoordinates } = require("./distance.js");

/**
 * Express middleware for caching API responses in memory
 * @param {String} topic - Topic for cache key, e.g., weather, alert, ...
 * @param {Int} duration - Caching duration in minutes
 */
let responseCache = (topic, duration) => {
  return (req, res, next) => {
    let reqLat = req.query.lat;
    let reqLon = req.query.lon;
    let key = `${topic}-${reqLat}-${reqLon}`;
    let cachedBody = mcache.get(key);

    // Server identical location if available
    if (cachedBody) {
      res.send(JSON.parse(cachedBody));
      //console.log("Served from cache.");
      return;
    } else {
      // Serve nearby location if available
      if (mcache.keys().length > 0) {
        for (let currentKey of mcache.keys()) {
          let keyData = currentKey.split("-");
          if (keyData[0] == topic) {
            let cords = { lat: keyData[1], lon: keyData[2] };
            let distance = distanceBetweenCoordinates(reqLat, reqLon, cords.lat, cords.lon);
            if (distance < 2) {
              res.send(JSON.parse(mcache.get(currentKey)));
              //console.log("Served from cache. (Nearby location)");
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

exports.responseCache = responseCache;
