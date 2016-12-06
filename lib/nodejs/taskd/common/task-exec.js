var exec = require('child_process').exec;
var cmd = 'pwd';

exec(cmd, function(error, stdout, stderr) {
  // command output is in stdout
  console.log(error, stdout, stderr);
});
