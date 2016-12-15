var fs = require('fs');
var options = require('./cmd-args').options;
var configValues = JSON.parse(fs.readFileSync(options.config, 'utf8'));

module.exports = {

  test : function(){

    try {

      /** Check if file exists */
      if (!fs.existsSync(options.config)) {
        throw new Error('Config file "' + options.config + '" does not exist');
      }

      /** Check if valid json */
      try {
        var config = JSON.parse(fs.readFileSync(options.config, 'utf8'));
      } catch(err) {
        throw new Error('Config file "' + options.config + '" is not a valid json');
      }

      /** Validate keys & their format */
      var validate = require("validate.js");

      validate.validators.isString = function(value) {
        if(!validate.isString(value)){
          return "is not string";
        }
      };

      var constraints = {
        "api.version": {
          presence: true,
          isString : true
        },
        "api.url" : {
          presence: true,
          url : true
        },
        "api.uid" : {
          presence: true,
          isString : true
        },
        "api.key" : {
          presence: true,
          isString : true
        }
      };

      var errors = validate(config, constraints, {format: "flat"});
      if(errors) throw new Error(errors);


    } catch(err) {
      console.log(err.message);
      return false;
    }

    return true;

  },
  api : configValues.api
}
