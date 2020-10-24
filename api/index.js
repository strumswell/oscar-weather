require("dotenv").config();
const express = require("express");
const app = express();
const puppeteer = require("puppeteer");
const fetch = require("node-fetch");
const { weatherCache, mapshotCache } = require("./util/cache");
const { accessCheck } = require("./util/authentication");
const wwwOptions = {
  index: "index.html",
};

app.use("/api/v2/webpage/:key", accessCheck, express.static("www", wwwOptions));

app.get("/mapshot/:lat/:lon/mapshot.jpeg", mapshotCache(15), (req, res) => {
  getMapshot(req.params.lat, req.params.lon).then((file) => {
    res.sendFile(file);
  });
});

app.get("/api/v2/mapshot/:lat/:lon/:type/:color/:key/mapshot.jpeg", accessCheck, mapshotCache(15), (req, res) => {
  getMapshot(req.params.lat, req.params.lon, req.params.type, req.params.color).then((file) => {
    res.sendFile(file);
  });
});

app.get("/api/v2/weather/:lat/:lon/:key", accessCheck, weatherCache(10), (req, res) => {
  fetch(
    "https://api.openweathermap.org/data/2.5/onecall?lat=" +
      req.params.lat +
      "&lon=" +
      req.params.lon +
      "&appid=" +
      process.env.OWM_API_KEY +
      "&units=metric"
  )
    .then((res) => res.json())
    .then((json) => {
      res.send(json);
    });
});

app.listen(3000, function () {
  console.log("Listening on 3000");
});

async function getMapshot(lat, lon, type, color) {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  page.setViewport({ width: 512, height: 512 });
  await page.goto(
    `http://localhost:3000/api/v2/webpage/${process.env.API_KEY}/index.html?lat=` +
      lat +
      "&lon=" +
      lon +
      "&mapType=" +
      (type ? type : 4) +
      "&radarColor=" +
      (color ? color : 8),
    { waitUntil: "networkidle0" }
  );
  let file = __dirname + "/img/" + Date.now() + "_" + lat + "_" + lon + ".jpeg";
  await page.screenshot({
    path: file,
    type: "jpeg",
  });
  await browser.close();
  return file;
}
