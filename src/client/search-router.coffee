root = exports ? this
Backbone = root.Backbone

class root.SearchRouter extends Backbone.Router
  routes:
    ':keywords': 'keywordSearch'
    ':keywords/bbox=:bbox': 'spatialSearch'
  
  keywordSearch: (keywords) ->
    # Set the search bar to have the right keywords and perform the search
    $('#search-bar').val unescape keywords
    root.searchApp.performSearch()
    return
    
  spatialSearch: (keywords, bbox) ->
    # Set the search bar to have the right keywords
    $('#search-bar').val unescape keywords
    
    # Deal with the bbox...
    sides = bbox.split(',')
    bounds = new OpenLayers.Bounds sides[0], sides[1], sides[2], sides[3]
    
    # Reproject the bounds to map projection, create feature
    geoProj = new OpenLayers.Projection 'EPSG:4326'
    bounds.transform geoProj, root.searchApp.searchMap.getProjectionObject()      
    feature = new OpenLayers.Feature.Vector bounds.toGeometry()
    
    # First remove any existing features, then add the feature to the map's vector layer
    searchLayer = root.searchApp.searchMap.getLayersByName('Search Area')[0]
    searchLayer.destroyFeatures()
    searchLayer.addFeatures [ feature ]
    
    # Call the routine to update the UI and the currentBbox information
    root.searchApp.newBoundingBox feature, false
    
    # Perform the search
    root.searchApp.performSearch()
    return