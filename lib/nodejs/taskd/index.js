#!/usr/bin/env node
var taskApi = require('./common/task-api');
taskApi.getSession().subscribe(function (session) {
	console.log("Session created =>", session);
	if(session.id){
		taskApi.getMessage(session.id).subscribe(function(message){
			console.log("message list =>", message);
			require('./common/task-exec');

		});
	}

});
