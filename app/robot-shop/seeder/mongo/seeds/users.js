const mongoClient = require('mongodb').MongoClient;
const mongoObjectID = require('mongodb').ObjectID;
const pino = require('pino');

const logger = pino({
    level: 'error',
    prettyPrint: true,
    useLevelLabels: true
});

// MongoDB
var db;
var usersCollection;
var mongoConnected = false;

function mongoConnect() {
    return new Promise((resolve, reject) => {
        // var mongoURL = process.env.MONGO_URL || 'mongodb://mongodb:27017/users';
        var mongoURL = process.env.MONGO_URL || 'mongodb://roboadmin:docdb3421z@robotshopdocdb-cluster.cluster-chh4lgwsalzi.us-east-1.docdb.amazonaws.com:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false';
        mongoClient.connect(mongoURL, (error, client) => {
            if(error) {
                reject(error);
                logger.error('Mongodb connection error', error)
            } else {
                db = client.db('users');
                usersCollection = db.collection('users');
                resolve('connected');
            }
        });
    });
}

function mongoLoop() {
    mongoConnect().then((r) => {
        mongoConnected = true;
        logger.info('MongoDB connected');
    }).catch((e) => {
        logger.error('ERROR', e);
        setTimeout(mongoLoop, 5);
    });
}

// seed
function seedUsers(){
    if (mongoConnected) {
        db = db.getSiblingDB('users');
        db.users.insertMany([
            {name: 'user', password: 'password', email: 'user@me.com'},
            {name: 'stan', password: 'bigbrain', email: 'stan@instana.com'},
            {name: 'partner-57', password: 'worktogether', email: 'howdy@partner.com'}
        ]);
            // unique index on the name
        db.users.createIndex(
            {name: 1},
            {unique: true}
        );
    } else {
        logger.error('MongoDB not connected', mongoClient);
    }
}

mongoLoop();
seedUsers();