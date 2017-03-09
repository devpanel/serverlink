var execFile = require('child_process').execFile;
var Client = require('node-rest-client').Client;
client = new Client();
var moment = require('moment');
var request = require('request');
var json = require('/root/serverlink/etc/devpanel.json');
console.log('config', json);
setInterval(runner, 5000);


var args = {
     headers: {
        'x-server-uuid': json.uuid,
        'x-secret-key': json.key,
    }
}

var updateTask = function(task, error, stdout, stderr, callback) {
    var options = {
    url: 'https://t737xvo6h7.execute-api.us-west-2.amazonaws.com/prod/tasks',
    method: 'PUT',
    headers: {
        'x-server-uuid': json.uuid,
        'x-secret-key': json.key,
        'Content-Type': 'application/x-www-form-urlencoded'
    },
    form: {
            task_id: task.id,
            end_time: moment().unix(),
            exit_code: 'complete',
            output: stdout
        }
    }
    if(error) {
       options.form.exit_code = 'failed';
    }

    request(options, function (error, response, body) {
        console.log('task updated');
        callback(error, response, body);
    });

}



function runner () {
        client.get("https://t737xvo6h7.execute-api.us-west-2.amazonaws.com/prod/tasks/next", args, function (data, response) {
            // parsed response body as js object

            // raw response

            if(data.task.id) {
                    console.log('task_running', data.task.id)
                    execFile(data.task.path, data.task.exec, (error, stdout, stderr) => {
                        if (error) {
                            console.log('error', error);
                            console.error('stderr', stderr);
                        };
                        console.log('calling update');
                        updateTask(data.task, error, stdout, stderr, function(error, response, body) {
                            console.log('response', body);
                        })
                        console.log('stdout', stdout);
                    });
           } else {
                console.log('stdout', data);
           }
        });
}


