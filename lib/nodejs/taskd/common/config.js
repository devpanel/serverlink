// process.argv.forEach(function (val, index, array) {
//   console.log(index + ': ' + val);
// });


var fs = require('fs');
var path = require('path').resolve(__dirname, '../config/default.json');
module.exports = JSON.parse(fs.readFileSync(path, 'utf8'));
