const fetch = require("node-fetch");

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
        process.env.OWM_API_KEY +
        "&units=metric"
    );
    return await weatherData.json()
  } else {
    return { error: "Please provide correct lat/ lon values!" };
  }
}

exports.getForecast = getForecast;
