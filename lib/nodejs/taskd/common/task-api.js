var querystring = require('querystring');
var api = require('./config').api;
var rxHttp = require('./rx-http');

module.exports = {

  getSession : function(){

    var form = {
      op: 1,
      v : api.version,
      U : api.uid,
      t : (new Date).getTime()
    };

    return rxHttp.post(api.url, form).map(function(res){

      if(res._s !== '0'){
        return { success : false };
      }

      return { success : true, session : {
        id : res._S, pollInterval : res.P, errInterval : res.E
      }};

    });
  },

  getMessage : function(sessionId){

    var data = {
      N : 5,
      op : 2,
      _S: sessionId
    };

    return rxHttp.get(api.url, data).map(function(res){
      //console.log(res);
      return res;
    });

  }
}
