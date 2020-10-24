let accessCheck = (req, res, next) => {
  if (req.params.key !== process.env.API_KEY) {
    res.status(401).send({ status: "Unauthorized! Please provide an API key." });
  }
  next();
};

exports.accessCheck = accessCheck;
