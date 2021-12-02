const express = require("express");
const app = express();
const auth = require("./util/auth.js");
const owm = require("./util/owm.js");
const cache = require("./util/cache");
const { OscarUsage } = require("./util/usage.js");
const { AccuWeather } = require("./util/accuweather.js");
const DEBUG = false;

app.get("/api/v2/weather/forecast", auth.accessCheck, cache.responseCache("weather", 15), (req, res) => {
  owm.getForecast(req.query).then((json) => {
    res.send(json);
  });
});

app.get("/api/v2/weather/alerts", auth.accessCheck, cache.responseCache("alerts", 60), (req, res) => {
  AccuWeather.getWeatherAlerts(req.query.lat, req.query.lon).then((json) => {
    res.send(json);
  });
});

app.get("/", auth.accessCheck, (req, res) => res.send("This works!"));
app.use("/api/v2/docs", auth.accessCheck, express.static("www", { index: "docs.html" }));
app.use("/api/v2/usage", auth.accessCheck, (req, res) => res.send(OscarUsage.stats));
app.use("/api/v2/dashboard", auth.accessCheck, express.static("www", { index: "dashboard.html" }));

if (DEBUG) {
  app.listen(3000, () => {
    console.log(`Example app listening at http://localhost:3000`);
  });
}

module.exports = app; // For deta.sh deployment
