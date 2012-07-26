root = exports ? this

OpenLayers = if exports? then require('openlayers').OpenLayers else root.OpenLayers
jade = if exports? then require 'jade' else root.require 'jade'
$ = if exports? then require 'jquery' else root.$

class Utils
  buildFilter: (keywords, bbox = null, asXml = true ) ->  
    oneWord = (keyword) ->
      opts =
        type: OpenLayers.Filter.Comparison.LIKE
        property: 'AnyText'
        value: keyword
      return new OpenLayers.Filter.Comparison opts
    
    keywordsClause = ->
      opts =
        type: OpenLayers.Filter.Logical.AND
        filters: (oneWord keyword for keyword in keywords)
      return new OpenLayers.Filter.Logical opts
      
    bboxClause = ->
      opts =
        type: OpenLayers.Filter.Spatial.BBOX
        value: bbox
        property: 'apiso:BoundingBox'
        projection: 'EPSG:4326'
      return new OpenLayers.Filter.Spatial opts
    
    if bbox?
      filterOpts =
        type: OpenLayers.Filter.Logical.AND
        filters: [ keywordsClause(), bboxClause() ]
      ogcFilter = new OpenLayers.Filter.Logical filterOpts
    else
      ogcFilter = keywordsClause()
          
    if asXml then return @filterToXML ogcFilter
    else return ogcFilter
  
  filterToXML: (ogcFilter) ->  
    xml = new OpenLayers.Format.XML()
    writer = new OpenLayers.Format.Filter { version: '1.1.0' }
    return xml.write writer.write ogcFilter
    
root.Utils = new Utils()

class root.Jade
  constructor: (@url) ->
    that = @
    options =
      url: @url
      async: false
      success: (result) ->
        that.jadeFn = jade.compile(result)
        return
    $.ajax options
  content: (context) ->
    return @jadeFn context
    
$.xmlProxy = (options) ->
  proxyBase = '/proxy?url='
  options.url = "#{proxyBase}#{encodeURIComponent(options.url)}"
  $.ajax options
  return