let accessCheck = (req, res, next) => {
  if (req.query.key !== process.env.API_KEY) {
    res.status(401).send({ error: "Unauthorized! Please provide an API key." });
  } else {
    next();
  }
};

exports.accessCheck = accessCheck;
