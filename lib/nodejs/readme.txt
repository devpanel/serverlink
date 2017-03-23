This document is for taskd written in nodejs. It have some dependencies, which are following:-

1) etc/devpanel.json   file have information about server like uuid, key etc..  (path is important)
2) i have installed the code with root as user so its path be like:-

      /root/serverlink/paas-provisioner/docker/vhostctl.sh  (path)

it could be like /opt/serverlink/paas-provisioner/docker/vhostctl.sh

3)go to lib/nodejs  and run command 

"sudo npm install --save"
 
It will install all node modules from package.json there.

4)for running task runner:
 
Go to->   /root/serverlink/lib/nodejs

 For debug run(we can see console there):

	i)start:-
 	
		a)sudo node runner.js
	ii) stop :- 
		a) ctrl + c

 For forever running:-
	i)start:-
		a) npm install forever -g
 		b) forever start runner.js
	ii)stop:-
		a) forever stop runner.js
	iii)restart:-
		a) forever restart runner.js




After running task runner:-

	It will start seeking for task in every 5 sec. from SQS according to server info   "etc/devpanel.json",  
        run the command with arguments according to task parameters and update the task info to dynamo db. 
	
	if task "complete" exit_code to db in update request, the next task under that activity  pushed to SQS.

	if task "failed" exit_code to db in update request, activity status failed and SNS notification will be pushed to HTTPS end point of devpanel.

	if task was last in activity then a SNS notification will be pushed to HTTPS end point of devpanel (activity success or failed).


=====================================================================================

After running, check task in db on basis of id:-

there are 3 error handling fields in a task:-

1) "stderr": "/root/serverlink/lib/nodejs/scripts/date.sh: line 2: Date: Thu Mar 23 22:52:08 UTC 2017: command not found\n",
  
2) "stdout": Running: /root/serverlink/lib/nodejs/scripts/date.sh 139.59.18.183",
3) "running_error": {
    "code": "ENOENT",
    "syscall": "spawn sbin/ssh-bootstrap"
  },





 
	
 



