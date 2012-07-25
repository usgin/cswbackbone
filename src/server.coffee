express = require 'express'

# Setup the server
server = express.createServer()
server.set 'view engine', 'jade'
server.set 'view options', { layout: false }
server.use '/site', express.static './build/client'
server.use '/lib', express.static './lib'
server.use '/style', express.static './style'
server.use '/templates', express.static './templates'
server.set 'views', './templates'

# Routes  
server.get '/', (req, res) ->
  res.render 'search'
  
# Listen
server.listen 8002
