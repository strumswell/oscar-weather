require("dotenv").config();
const express = require("express");
const app = express();
const wwwOptions = {
  index: "index.html",
};
const puppeteer = require("puppeteer");
const fetch = require("node-fetch");
const apicache = require("apicache");
const cache = apicache.middleware;

app.use(cache("15 minutes"));
app.use("/webpage", express.static("www", wwwOptions));

app.get("/mapshot/:lat/:lon/mapshot.jpeg", function (req, res) {
  getMapshot(req.params.lat, req.params.lon).then((file) => {
    res.sendFile(file);
  });
});

app.get("/weather/:lat/:lon/:key", (req, res) => {
  if (req.params.key == process.env.API_KEY) {
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
  } else {
    res
      .status(401)
      .send({ status: "Unauthorized! Please provide an API key." });
  }
});

app.listen(3000, function () {
  console.log("Listening on 3000");
});

async function getMapshot(lat, lon) {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  page.setViewport({ width: 512, height: 512 });
  await page.goto(
    "http://localhost:3000/webpage/index.html?lat=" + lat + "&lon=" + lon,
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
