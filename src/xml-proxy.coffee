root = exports

request = require 'request'

# Parser for application/xml POSTs
# Modeled from https://github.com/senchalabs/connect/blob/1.9.1/lib/middleware/bodyParser.js
exports.xmlParser = (req, options, fn) ->
  buf = ''
  req.setEncoding 'utf8'
  req.on 'data', (chunk) ->
    buf += chunk
    return
  req.on 'end', ->
    req.body = buf if buf.length 
    fn()
    return
  return

# Super simple HTTP proxy for GET/POST through cross-domain XML requests
exports.xmlProxy = (req, res) ->
  # Get the requested URL
  url = req.param 'url', null
  if not url?
    res.status 400
    res.send 'Bad Request. No URL specified.'
    return
  
  # Result depends on the request method  
  switch req.method.toUpperCase()
    when 'GET'
      proxyResponse = request.get(url)
      proxyResponse.pipe res
      return
    
    when 'POST'
      options =
        url: url
        body: req.body
      proxyResponse = request.post(options)
      proxyResponse.pipe res
      return
      
    else
      res.status 405
      res.send "Method Not Allowed: #{req.method.toUpperCase()}"
      return      
