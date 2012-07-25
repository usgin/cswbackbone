root = exports ? this
Backbone = root.Backbone
$ = root.$
$.support.cors = true
OpenLayers = root.OpenLayers
OpenLayers.ImgPath = "/style/ol/img/"

class Application extends Backbone.View
  el: '#app'
  
  mapEl: "map-area"
  
  appJade: new root.Jade '/templates/search-app.jade'
  
  router: new root.SearchRouter()
  
  render: ->
    @$el.append @appJade.content {}
    @$mapEl = $ "##{@mapEl}"
    @generateSearchMap()
    return @
    
  events:
    "click #hide-map-area": "toggleSearchMap"
    "click #define-map-area": "activateBoxControl"
    "hover #define-map-area": "highlightBboxButton"
    "click #clear-map-area": "clearBbox"
    "click #search-button": "logSearch"
    'keyup #search-bar': 'keycheck'

  toggleSearchMap: (evt, hideBboxButton = true) ->
    @$mapEl.slideToggle 'slow', ->
      text = if $(this).is ':visible' then 'Hide Search Area' else 'Show Search Area'      
      $('#hide-map-area span').html text
      $('#define-map-area').slideToggle 'fast' if hideBboxButton and not $('#define-map-area span').html().match /^Defined Area/
      $('#map-arrow').toggleClass 'down-arrow up-arrow'            
      return
    return
    
  generateSearchMap: ->
    # Default map controls
    controls = [
      new OpenLayers.Control.Navigation { zoomWheelEnabled: false }
      new OpenLayers.Control.Zoom()
      new OpenLayers.Control.ArgParser()
      new OpenLayers.Control.Attribution()
      new OpenLayers.Control.LayerSwitcher()      
    ]
    
    # Generate the map
    @searchMap = map = new OpenLayers.Map {
      div: @mapEl
      theme: null
      projection: new OpenLayers.Projection 'EPSG:3857'
      maxExtent: new OpenLayers.Bounds -20037508.34,-20037508.34,20037508.34,20037508.34
      maxResolution: 156543.0339
      controls: controls
    }
    
    # Create layers
    gmaps = new OpenLayers.Layer.Google 'Google Street Map', { isBaseLayer: true }
    map.addLayer gmaps
    boxLayer = new OpenLayers.Layer.Vector 'Search Area'
    map.addLayer boxLayer
    resultLayer = new OpenLayers.Layer.Vector 'Result Area'
    map.addLayer resultLayer
    
    # Center the map over North America
    map.setCenter new OpenLayers.LonLat(-10684062.064102, 4676723.1379492), 3       
    
    # Control for drawing a bounding box    
    boxControl = new OpenLayers.Control.DrawFeature( 
      boxLayer, 
      OpenLayers.Handler.RegularPolygon, 
      { 
        name: "boxControl",
        handlerOptions: { sides: 4, irregular: true }, 
        featureAdded: @newBoundingBox
      }    
    )
    map.addControl boxControl
    boxControl.deactivate()
    return
    
  activateBoxControl: (evt) ->
    # Adjust button text
    $(evt.currentTarget).children('span').html 'Define A Search Area'
    $(evt.currentTarget).children('span').toggleClass 'invisible' if $(evt.currentTarget).children('span').hasClass 'invisible'
    $(evt.currentTarget).children('div').addClass 'hidden'
    
    # Highlight the button during its use
    $(evt.currentTarget).toggleClass 'action-button-highlight'
    
    # Show the map if it is hidden
    root.searchApp.toggleSearchMap(null, false) if root.searchApp.$mapEl.css('display') is 'none'
    
    # Disable the clear bbox button
    $('#clear-map-area').slideToggle 'fast' if $('#clear-map-area').is(':visible')
    
    # Adjust the map and activate the box-drawing control
    @searchMap.getLayersByName('Search Area')[0].destroyFeatures()
    @searchMap.getControlsBy('name', 'boxControl')[0].activate()
    return
    
  highlightBboxButton: (evt) ->
    if $('#define-map-area span').text().match /^Defined Area/
      $(evt.currentTarget).children('span').toggleClass 'invisible'
      $(evt.currentTarget).children('div').toggleClass 'hidden'
    return
    
  newBoundingBox: (feature, changeHighlight = true) ->
    # Redefine Bounding Box in Decimal Degrees
    geoProj = new OpenLayers.Projection 'EPSG:4326'
    root.searchApp.currentBbox = bounds = feature.geometry.clone().getBounds()
    bounds.transform root.searchApp.searchMap.getProjectionObject(), geoProj
    
    # Adjust UI button
    bbox = bounds.toBBOX(4).split ','
    text = "N: #{bbox[3]}, S: #{bbox[1]}, E: #{bbox[0]}, W: #{bbox[2]}"        
    $('#define-map-area span').html "Defined Area: #{text}"    
    $('#define-map-area').toggleClass 'action-button-highlight' if changeHighlight
    $('#define-map-area div').addClass 'hidden'      
    $('#define-map-area span').toggleClass 'invisible' if $('#define-map-area span').hasClass 'invisible'
    
    # Enable the clear bbox button
    $('#clear-map-area').slideToggle 'fast' if not $('#clear-map-area').is(':visible')
    
    # Disable the Box-drawing control so you can navigate
    root.searchApp.searchMap.getControlsBy('name', 'boxControl')[0].deactivate()
    return
  
  clearBbox: (event) ->
    # Remove the feature from the map
    @searchMap.getLayersByName('Search Area')[0].destroyFeatures()
    
    # Remove the currentBbox
    @currentBbox = null
    
    # Adjust Buttons
    $('#clear-map-area').slideToggle 'fast'
    $('#define-map-area span').html "Define A Search Area"
    $('#define-map-area').slideToggle 'fast' if not @$mapEl.is ':visible'
    return
    
  keycheck: (event) ->
      @logSearch() if event.keyCode is 13
      return
  
  logSearch: ->
    frag = if root.searchApp.currentBbox? then "#{$('#search-bar').val()}/bbox=#{root.searchApp.currentBbox.toBBOX()}" else "#{$('#search-bar').val()}"
    @router.navigate frag, { trigger: true }
    return
    
  performSearch: (evt, start = 1) ->    
    # Generate keyword array and OGC Filter - Doesn't use the BBOX yet
    keywords = $('#search-bar').val().split ' '
    ogcFilter = root.Utils.buildFilter keywords, root.searchApp.currentBbox or null
    
    # Perform the CSW Request, success is called upon retrieval of records
    results = new root.IsoMetadataSet null, { ogcFilter: ogcFilter }
    
    # Indicate that a search is occurring
    $('#refresher').toggleClass 'hidden'
    $('#results').toggleClass 'hidden'
    
    # Remove any actions, hide the title, details
    root.searchApp.currentActions.$el.empty() if root.searchApp.currentActions?
    root.searchApp.detailsView.closePopup() if root.searchApp.detailsView?
    $('#tools-title').addClass 'hidden'
    
    results.fetch {
      start: start
      success: (set, xmlResponse) ->
        # Show the total number of results
        $('#result-count').removeClass 'hidden'
        $('#result-count').html "#{set.totalRecords} total results"
        
        # Show the paginator
        $('#paginator').removeClass 'hidden'
        root.searchApp.paginator.undelegateEvents() if root.searchApp.paginator?
        root.searchApp.paginator = new root.Paginator { collection: set }
        root.searchApp.paginator.render()
        
        # Show the results themselves in the results block
        root.searchApp.populateSearchResults set               
        
        # Remove the search indicator
        $('#refresher').toggleClass 'hidden'
        $('#results').toggleClass 'hidden'
        return
      error: (set, options, xhr) ->
        console.log xhr
        $('#refresher').html 'There was a problem performing the search'
        return
    }
    return
    
  populateSearchResults: (metadataSet) ->
    @currentResults = new root.ResultsView { collection: metadataSet }
    @currentResults.render()
    return

# Here is the application entry point.
$(document).ready ->
  # Create and render the application
  root.searchApp = app = new Application()
  app.render()
  
  # Start the history logger
  Backbone.history.start()


    