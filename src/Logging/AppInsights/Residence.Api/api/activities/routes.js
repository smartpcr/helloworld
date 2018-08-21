const routes = require("express").Router();
const activities = [
    {
        "id": "1",
        "name": "Bingo",
        "date": "Wednesdays @ 6pm",
        "description": "Come join us for an exciting game of Bingo with great prizes"
    },
    {
        "id": "2",
        "name": "Shuffleboard Competition",
        "date": "Saturdays @ 3pm",
        "description": "Meet us at the Shuffleboard court with your partner or come and make a new friend"
    }
];

routes.get("/", (req, res) => {
    res.status(200).json(activities);
});

routes.post("/", (req, res) => {
    var activity = req.body;

    var maxId = 1;
    if (!activity.id) {
        for (item in activities) {
            if (activities[item].id > maxId) {
                maxId = activities[item].id;
            }
        }
    }
    activity.id = maxId + 1;
    activities.push(activity);

    res.status(201).json(activity);
});

routes.delete("/:id", (req, res) => {
    var id = req.params.id; 
    var index = activities.findIndex(activity => activity.id === id);
    activities.splice(index, 1);
    res.status(204);
})

module.exports = routes;