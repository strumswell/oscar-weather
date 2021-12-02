const fetch = require("node-fetch");
const { OscarUsage } = require("./usage.js");
const OWM_KEY = process.env.OWM_KEY;
/**
 * Get OpenWeatherMap forecaste for location
 * @async
 * @param {*} query - Query object containing lat and lon key-value
 * @returns OWM OneCall API result
 */
async function getForecast(query) {
  const lat = query.lat;
  const lon = query.lon;

  if (!isNaN(lat) && !isNaN(lon)) {
    let weatherData = await fetch(
      "https://api.openweathermap.org/data/2.5/onecall?lat=" +
        lat +
        "&lon=" +
        lon +
        "&appid=" +
        OWM_KEY +
        "&units=metric" +
        "&deviceid=null&token=null&mode=main&lang=de",
      {
        headers: {
          Accept: "*/*",
          "Accept-Encodung": "gzip, deflate, br",
          Connection: "keep-alive",
          "User-Agent": "openweather/15 CFNetwork/1325.0.1 Darwin/21.1.0",
        },
      }
    );
    OscarUsage.update(OWM_KEY);
    return await weatherData.json();
  } else {
    return { error: "Please provide correct lat/ lon values!" };
  }
}

exports.getForecast = getForecast;
