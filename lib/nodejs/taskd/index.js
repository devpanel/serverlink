#!/usr/bin/env node

var options = require('./common/cmd-args').options;
var helpTxt = require('./common/cmd-args').helpTxt;

if(options.help){
	return console.log(helpTxt);
}

if(options.test){
	return require('./common/config').test();
}


var taskApi = require('./common/task-api');
taskApi.getSession().subscribe(function (response) {

	if(!response.success){
		return console.log('Failed to create session');
	}

	var session  = response.session;
	console.log("Session created =>", session);

	if(session.id){
		taskApi.getMessage(session.id).subscribe(function(message){
			console.log("message list =>", message);
			require('./common/task-exec');

		});
	}

});
