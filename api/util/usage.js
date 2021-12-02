class OscarUsage {
  static stats = {};

  /**
   * Update apikey usage for external service
   * @param {String} apiKey - Used API keys
   */
  static update(apiKey) {
    const currentTime = new Date().getTime();
    if (OscarUsage.stats[apiKey]) {
      // key already tracked
      const delta = currentTime - OscarUsage.stats["currentFrame"];
      if (delta >= 3600000) {
        // older than 1h
        OscarUsage.stats[apiKey]["currentFrame"] = currentTime;
        OscarUsage.stats[apiKey]["calls"] = 1;
      } else {
        // within 1h
        OscarUsage.stats[apiKey]["calls"] += 1;
      }
    } else {
      // don't know this key...
      OscarUsage.stats[apiKey] = {
        currentFrame: currentTime,
        calls: 1,
      };
    }
  }
}

exports.OscarUsage = OscarUsage;
