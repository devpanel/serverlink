var fs = require('fs');
var options = require('./cmd-args').options;
module.exports = JSON.parse(fs.readFileSync(options.config, 'utf8'));
