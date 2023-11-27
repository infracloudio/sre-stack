const mongoose = require('mongoose')

const { Schema } = mongoose;
var mongoURL= process.env.MONGO_URL || 'mongodb://roboadmin:docdb3421z@robotshopdocdb-cluster.cluster-chh4lgwsalzi.us-east-1.docdb.amazonaws.com:27017/?replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false';
var usersSchema = new Schema({ any: {} });
var usersSchema = new Schema({ any: Schema.Types.Mixed });
var users = mongoose.model('users', usersSchema)

mongoose.connect(
    mongoURL,
    {
        useNewUrlParser: true, 
    }
).then(
    ()=> {
        console.log('MongoDb connected')
    }
).catch(
    (err) => {
        console.log(err)
    }
);

const seedUsers = [
    {name: 'user', password: 'password', email: 'user@me.com'},
    {name: 'stan', password: 'bigbrain', email: 'stan@instana.com'},
    {name: 'partner-57', password: 'worktogether', email: 'howdy@partner.com'}
];

const seedDB = async () => {
    await users.insertMany(seedUsers).then(
        function(){
            console.log('user data inserted')
        }
    ).catch(
        function(error){
            console.log(error)
        }
    )
    // unique index on the name
    await usersSchema.index(
        {name: 1},
        {unique: true}
    )
    var usersData = await users.find({});
    if (usersData) {
        console.log(JSON.stringify(usersData, null, 4))
    }
};

seedDB().then(
    () => {
        mongoose.connection.close();
    }
)