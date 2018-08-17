const routes = require("express").Router();
const users = require("./users.js");

routes.post("/login", (req, res) => {
    const foundUser = users.find(user => user.username === req.body.username);
    if (foundUser) {
        delete foundUser.password;
        res.status(200).json(foundUser);
    } else {
        res.sendStatus(404);
    }
});

module.exports = routes;