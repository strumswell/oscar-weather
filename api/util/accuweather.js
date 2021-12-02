const fetch = require("node-fetch");
const mcache = require("memory-cache");
const { OscarUsage } = require("./usage.js");
const { distanceBetweenCoordinates } = require("./distance.js");

class AccuWeather {
  static apikey = process.env.AW_KEY;
  static headers = {
    Accept: "*/*",
    "Accept-Encodung": "gzip, deflate, br",
    Connection: "keep-alive",
    "User-Agent": "AccuWeather AccuSwiftSDK Web Request Client/1.0 -- iOSApp",
  };

  /**
   * Get Accuweather location key for further API calls
   * @async
   * @param {String} lat - Latitude of weather location
   * @param {String} lon - Longitude of weather location
   * @returns Location key of coordinates
   */
  static async getLocationKey(lat, lon) {
    const key = `geopos-${lat}-${lon}`; // cache key for location
    const cachedLocKey = mcache.get(key);

    // TODO: Integrate this caching capability into a new Cache class together with the response cache for routes
    // Let's consult the cache...
    if (cachedLocKey) {
      return cachedLocKey;
    } else {
      // Check for very nearby geopos
      if (mcache.keys().length > 0) {
        for (let currentKey of mcache.keys()) {
          let keyData = currentKey.split("-"); // split to get topic, lat, and lon of key
          if (keyData[0] == "geopos") {
            let cords = { lat: keyData[1], lon: keyData[2] };
            let distance = distanceBetweenCoordinates(lat, lon, cords.lat, cords.lon);
            // cached location within 2km of request location
            if (distance < 2) {
              return cachedLocKey;
            }
          }
        }
      }
    }

    // No cache value, let's ask API :)
    const geoposition = await fetch(
      "https://api.accuweather.com/locations/v1/cities/geoposition/search?q=" +
        lat +
        "," +
        lon +
        "&apikey=" +
        AccuWeather.apikey +
        "&language=de&details=true",
      { headers: AccuWeather.headers }
    );
    const result = await geoposition.json();
    if (result["Key"] == null) return ""; // someting went wrong
    OscarUsage.update(AccuWeather.apikey);
    mcache.put(key, result["Key"]);
    return result["Key"];
  }

  /**
   * Get weather alerts for location
   * @async
   * @param {String} lat - Latitude of weather location
   * @param {String} lon - Longitude of weather location
   * @returns Weather alerts array
   */
  static async getWeatherAlerts(lat, lon) {
    if (isNaN(lat) && isNaN(lon)) return { error: "Please provide correct lat/ lon values!" };
    const locationKey = await AccuWeather.getLocationKey(lat, lon);
    const weatherAlerts = await fetch(
      "https://api.accuweather.com/alerts/v1/" +
        locationKey +
        "?apikey=" +
        AccuWeather.apikey +
        "&language=de&locationOffset=1.0",
      { headers: AccuWeather.headers }
    );
    OscarUsage.update(AccuWeather.apikey);
    return await weatherAlerts.json();
  }
}

exports.AccuWeather = AccuWeather;
