root = exports ? this

$ = if exports? then require 'jquery' else root.$
_ = if exports? then require 'underscore' else root._
Backbone = if exports? then require 'backbone' else root.Backbone
csw = if exports? then require('./csw').csw else root.csw

config = 
  cswRootUrl: 'http://catalog.usgin.org/geoportal/csw'

class root.IsoMetadata extends Backbone.Model

  cswRootUrl: config.cswRootUrl
  
  sync: (method, model, options) ->
    if method is 'read'
      return csw.getRecordById @cswRootUrl, @id or '', options
      
  parse: (response) ->
    record = if response.nodeName is 'gmd:MD_Metadata' then response else $(response).find 'gmd\\:MD_Metadata, MD_Metadata'  
    $rec = $ record
    
    # Adding the real ID attribute can drop records from a collection if ID's are duplicated in your shitty metadata
    #   Let Backbone manage ID automagically instead and just record the fileIdentifier
    @fileId = $rec.iso('id')
    
    # Assemble the GetRecordByID URL for this metadata record
    @getRecordByIdUrl = "#{@cswRootUrl}?request=GetRecordById&id=#{@fileId}&service=CSW&version=2.0.2&outputSchema=#{encodeURIComponent 'http://www.isotc211.org/2005/gmd'}&elementSetName=full"
    
    # Assemble attributes from the XML doc
    attributes =
      xml: record      
      Title: $rec.iso 'title'
      Description: $rec.iso 'description'
      GeographicExtent: $rec.iso 'extent'
      PublicationDate: $rec.iso 'publicationDate'
      ModifiedDate: $rec.iso 'modifiedDate'
      Keywords: $rec.iso 'keywords'
      Authors: $rec.iso 'authors'
      Distributors: $rec.iso 'distributors'
      Links: $rec.iso 'links'
      
    # Create a sensible list of all the keywords. These are FUBARed in general.
    keywordList = []
    for keywordSet in attributes.Keywords or []
      if _.isArray keywordSet.keywords
        for keyword in keywordSet.keywords
          keywordBits = keyword.split ','
          for word in keywordBits
            keywordList.push word.trim() if word.trim() not in keywordList
      else
        keywordBits = keywordSet.keywords.split ','
        for word in keywordBits
          keywordList.push word.trim() if word.trim() not in keywordList      
    attributes.keywordList = keywordList
    
    # Prettify FUBARed Dates
    dateFromCrud = (crud) ->
      dateBits = crud.split('T')[0].split('-')      
      theDate = new Date(dateBits[0], dateBits[1], dateBits[2])
      return theDate.toDateString()
    attributes.pubDate = dateFromCrud attributes.PublicationDate
    attributes.modDate = dateFromCrud attributes.ModifiedDate
    
    # Attempt transform links into "actions"
    actions = []
    
    guessExpressions =
      'OGC:WMS': [ /request=getcapabilities/i, /service=wms/i ]
      'OGC:WFS': [ /request=getcapabilities/i, /service=wfs/i ]
      'OGC:WCS': [ /request=getcapabilities/i, /service=wcs/i ]
      'ESRI': [ /\/rest\/services\/.*\/mapserver$/i ]
      'USGIN-REPO': [ /repository\.usgin\.org/i ]
      'FILE': [ /\/[^\/]*\.[^\/]{3,4}$/ ]
        
    guessActionType = (url) ->      
      for serviceType, expressions of guessExpressions
        valid = _.all expressions, (expression) ->
          return url.match(expression) isnt null  
        return serviceType if valid
      return null
    
    buildAction = (type, label, url, order, anchor = true, className = null) ->
      action =
        type: type
        label: label
        url: url
        anchor: anchor
        className: className
        order: order
      actions.push action
      return
      
    # Loop through links and build an "action"      
    for link in attributes.Links or []
      type = if link.ServiceType not in ( key for key, value of guessExpressions ) then guessActionType link.URL else link.ServiceType      
      switch type
        when 'OGC:WMS'
          buildAction type, 'WMS Capabilities', link.URL, 8
          buildAction type, 'Add WMS to Map', link.URL, 1, false, 'add-wms'          
        when 'OGC:WFS'
          buildAction type, 'WFS Capabilities', link.URL, 9
          buildAction type, 'Preview Data Table', link.URL, 5, false, 'preview-data'
        when 'OGC:WCS'
          buildAction type, 'WCS Capabilities', link.URL, 10
        when 'ESRI'
          buildAction type, 'ESRI Service Endpoint', link.URL, 11
          buildAction type, 'Add to ArcMap', "#{link.URL}?f=lyr&v=9.3", 4
          buildAction type, 'Add ESRI Service to Map', link.URL, 3, false, 'add-esri'
        when 'USGIN-REPO'
          buildAction type, 'USGIN Doc Repository', link.URL, 6 
        #when 'FILE' 
        else # Any other link is treated the same as a Downloadable File
          buildAction type, link.Name or 'Downloadable File', link.URL, 7
    
    # Sort the Actions
    attributes.Actions = _.sortBy actions, (action) ->
      return action.order
    
    # Find a simplified single author name
    if attributes.Authors? and attributes.Authors.length > 0
      name = attributes.Authors[0].Name
      orgName = attributes.Authors[0].OrganizationName
      if name? and name not in [ '', 'Missing', 'No Name Was Given' ]
        attributes.authorName = name
      else if orgName? and orgName not in [ '', 'Missing', 'No Name Was Given' ]
        attributes.authorName = orgName
      else
        attributes.authorName = 'No Author Was Provided'
    else
      attributes.authorName = 'No Author Was Provided'
    return attributes
    
  getBounds: ( destinationProjection = null )->
    # Construct an OpenLayers.Bounds for this result
    geoExtent = @get('GeographicExtent')
    bounds = null
    if geoExtent
      bounds = new OpenLayers.Bounds geoExtent.WestBound, geoExtent.SouthBound, geoExtent.EastBound, geoExtent.NorthBound
      bounds.transform(new OpenLayers.Projection('EPSG:4326'), destinationProjection) if destinationProjection?
    return bounds    
    
class root.IsoMetadataSet extends Backbone.Collection

  model: root.IsoMetadata
  
  cswRootUrl: config.cswRootUrl       
  
  initialize: (models, options) ->
    @ogcFilter = options.ogcFilter if options and options.ogcFilter
    return
    
  sync: (method, model, options) ->
    if method is 'read'
      limit = options.limit ? 10
      start = options.start ? 1
      ogcFilter = model.ogcFilter ? null
      return csw.getRecords @cswRootUrl, options, limit, start, ogcFilter 
        
  parse: (response) ->
    results = $(response).find 'csw\\:SearchResults, SearchResults'
    @nextRecord = results.attr 'nextRecord'
    @totalRecords = results.attr 'numberOfRecordsMatched'
    @xmlResponse = response
    records = ( record for record in results.find 'gmd\\:MD_Metadata, MD_Metadata' )
    return records
    
      
  