require("dotenv").config();
const express = require("express");
const app = express();
const owm = require("./util/owm.js");
const mapshotter = require("./util/mapshotter.js");
const cache = require("./util/cache");
const auth = require("./util/authentication");

app.listen(3000, function () {
  console.log("Listening on 3000");
});

/*
 *   N E W   R O U T E S
 */
app.use("/api/v2/webpage", auth.accessCheck, express.static("www", { index: "index.html" }));
app.use("/api/v2/docs", express.static("www", { index: "docs.html" }));

app.get("/api/v2/weather/forecast", auth.accessCheck, cache.weatherCache(15), (req, res) => {
  owm.getForecast(req.query).then((json) => {
    res.send(json);
  });
});

app.get("/api/v2/mapshot", auth.accessCheck, cache.mapshotCache(10), (req, res) => {
  mapshotter.getMapshot(req.query).then((file) => {
    res.sendFile(file);
  });
});

/*
 *   L E G A C Y   R O U T E
 */
app.get("/n1f387no1mynf81ge8qomeh781237nro-124j192/mapshot/:lat/:lon/mapshot.jpeg", function (req, res) {
  mapshotter.getMapshot({ lat: req.params.lat, lon: req.params.lon }).then((file) => {
    res.sendFile(file);
  });
});
