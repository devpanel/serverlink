var fs = require('fs');
var options = require('./cmd-args').options;
var log = console.log, error = console.error;


if(options['log-file']){

  var stdout = fs.createWriteStream(options['log-file']);
  process.stdout.write = process.stderr.write = stdout.write.bind(stdout);

}

module.exports = {

  debug : function(){
    options.debug && log.apply(console, arguments);
  },
  print : function(){
    log.apply(console, arguments);
  },
  error : function(){
    log.apply(console, arguments);
  }

}
