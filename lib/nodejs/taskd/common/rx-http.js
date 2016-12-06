var Rx = require('rx');
var request = require('request');
var api = require('config').api;
var CryptoJS = require("crypto-js");
var querystring = require('querystring');

module.exports = {

  get : function(url, data, sessionId){

    var query = '/?' + querystring.stringify(data);
    var apiPath = url + query ;
    var authKey = CryptoJS.HmacSHA256(query, api.key).toString();

    return Rx.Observable.create(function(observer) {
      return request({
        headers : {
          'x-webenabled-signature' : ' ' + authKey
        },
        uri : apiPath,
        method : 'GET'
      }, function (err, res, body) {
        // console.log(err, body);
        if(err) return observer.onError(err);
        var res = querystring.parse(body);
        console.log(res);
        return observer.onNext({
          n : parseInt(res.n)
        });
      });

    });
  },

  post : function(url, form){

    var formStr = querystring.stringify(form);
    var authKey = CryptoJS.HmacSHA256(formStr, api.key).toString();

    return Rx.Observable.create(function(observer) {
      return request({
        headers : {
          'Content-Length': formStr.length,
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-Webenabled-Signature' : authKey
        },
        uri : url,
        body : formStr,
        method : 'POST'
      }, function (err, res, body) {
        if(err) return observer.onError(err);
        var res = querystring.parse(body);
        return observer.onNext(res);
      });
    });
  }
};
