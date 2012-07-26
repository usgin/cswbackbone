express = require 'express'
proxy = require './xml-proxy'

# Setup the server
server = express.createServer()

# Configure the body parser to deal with XML data
express.bodyParser.parse['application/xml'] = proxy.xmlParser

# Other general server configurations
server.configure ->  
  server.set 'view engine', 'jade'
  server.set 'view options', { layout: false }
  server.set 'views', './templates'
  server.use '/site', express.static './build/client'
  server.use '/lib', express.static './lib'
  server.use '/style', express.static './style'
  server.use '/templates', express.static './templates'
  server.use express.bodyParser()
  return

# Search Intereface
server.get '/', (req, res) ->
  res.render 'search'

# Proxy for XML requests
server.get '/proxy', proxy.xmlProxy
server.post '/proxy', proxy.xmlProxy
  
# Listen
server.listen 8002
