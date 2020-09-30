var express = require("express");
var app = express();
var puppeteer = require("puppeteer");
var fs = require('fs');

var options = {
  index: "index.html",
};

app.use("/webpage", express.static("www", options));

async function getMapshot(lat, lon) {
  const browser = await puppeteer.launch();

  const page = await browser.newPage();
  page.setViewport({ width: 512, height: 512});
  await page.goto(
    "http://localhost:3000/webpage/index.html?lat=" + lat + "&lon=" + lon,
    { waitUntil: "networkidle0" }
  );
  let file = __dirname + "/img/" + Date.now() + "_" + lat + "_" + lon + ".jpeg";
  await page.screenshot({
    path: file,
    type: 'jpeg'
  });

  await browser.close();
  return file;
}

app.get("/mapshot/:lat/:lon/mapshot.png", function (req, res) {
  getMapshot(req.params.lat, req.params.lon).then((file) => {
      console.log(new Date() + " INC");
    res.sendFile(file);
  });
});

app.listen(3000, function () {
  console.log("Listening on 3000");
});
