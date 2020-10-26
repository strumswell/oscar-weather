const puppeteer = require("puppeteer");
const path = require("path")

async function getMapshot(query) {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  page.setViewport({ width: 512, height: 512 });
  await page.goto(
    `http://${process.env.INTERNAL_ADRESS}:3000/api/v2/webpage/index.html?lat=` +
      query.lat +
      "&lon=" +
      query.lon +
      "&map=" +
      (query.map ? query.map : 4) +
      "&color=" +
      (query.color ? query.color : 8) +
      `&key=${process.env.API_KEY}`,
    { waitUntil: "networkidle0" }
  );
  let file =  path.join(__dirname, '../') + "/img/" + Date.now() + "_" + query.lat + "_" + query.lon + ".jpeg";
  await page.screenshot({
    path: file,
    type: "jpeg",
  });
  await browser.close();
  return file;
}

exports.getMapshot = getMapshot;