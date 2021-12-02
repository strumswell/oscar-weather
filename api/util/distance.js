/**
 * Get distance between two coordinates in km
 * @param {Double} lat1 - Latitude of location 1
 * @param {Double} lon1 - Longitude of location 1
 * @param {Double} lat2 - Latitude of location 1
 * @param {Double} lon2 - Longitude of location 2
 * @returns Distance in km
 */
function distanceBetweenCoordinates(lat1, lon1, lat2, lon2) {
  const earthRadiusKm = 6371;
  let dLat = (lat2 - lat1) * (Math.PI / 180);
  let dLon = (lon2 - lon1) * (Math.PI / 180);
  lat1 = (lat1 * Math.PI) / 180;
  lat2 = (lat2 * Math.PI) / 180;

  let a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.sin(dLon / 2) * Math.sin(dLon / 2) * Math.cos(lat1) * Math.cos(lat2);
  let c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

exports.distanceBetweenCoordinates = distanceBetweenCoordinates;
