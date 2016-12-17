
var helpTxt =
"Options: \n"+
"    -d                      Print debug messages\n" +
"    -c config_file.json     Use an alternate config file\n" +
"    -t                      Test config file and exit\n" +
"    -F                      Foreground, don't daemonize\n" +
"    -l log_file             Use the specified file as log file\n" +
"    -h                      Help. Displays this message.\n" +
"\n" ;

var configPath =  require('path').resolve(__dirname, '../config/default.json');
// var logPath =  require('path').resolve(__dirname, '../logs/log.txt');
var commandLineArgs = require('command-line-args');

var optionDefinitions = [
  { name: 'debug',      alias: 'd', type: Boolean ,  defaultValue : false },
  { name: 'config',     alias: 'c', type: String ,   defaultValue : configPath },
  { name: 'test',       alias: 't', type: Boolean ,  defaultValue : false },
  { name: 'foreground', alias: 'f', type: Boolean ,  defaultValue : false },
  { name: 'log-file',   alias: 'l', type: String ,   defaultValue : null },
  { name: 'help',       alias: 'h', type: Boolean ,  defaultValue : false }
];

module.exports = {
  helpTxt : helpTxt,
  options : commandLineArgs(optionDefinitions)
}
