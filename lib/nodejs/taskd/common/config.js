var defaultConfigPath =  require('path').resolve(__dirname, '../config/default.json');
var commandLineArgs = require('command-line-args');

var optionDefinitions = [{
  name: 'config', alias: 'c', type: String , defaultOption: defaultConfigPath
}];

var options = commandLineArgs(optionDefinitions)
var configPath = options.config || defaultConfigPath;

var fs = require('fs');
var path = require('path').resolve(__dirname, '../config/default.json');
module.exports = JSON.parse(fs.readFileSync(configPath, 'utf8'));
