/**
 * Express middleware for API access authentication
 * @param {*} req - Request
 * @param {*} res - Response
 * @param {*} next
 */
let accessCheck = (req, res, next) => {
  if (req.query.key !== process.env.OSCAR_KEY) {
    res.status(401).send({ error: "Unauthorized! Please provide an API key." });
  } else {
    next();
  }
};

exports.accessCheck = accessCheck;
