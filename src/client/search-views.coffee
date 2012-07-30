root = exports ? this
Backbone = root.Backbone

# View backed by an IsoMetadataSet Collection
class root.ResultsView extends Backbone.View
  el: '#results'
  
  render: ->
    resultList = @$el
    resultList.empty()
    @collection.forEach (result) ->
      resultView = new root.ResultView { model: result }
      resultList.append resultView.render().el
      return
    return @
    
# View backed by an IsoMetadata Model
class root.ResultView extends Backbone.View
  #tagName: 'dt'
  
  className: 'result-container'
  
  jade: new root.Jade '/templates/result.jade'

  render: ->
    @$el.append @jade.content @model.toJSON()
    return @
    
  events: 
    'click .keyword': 'addKeywordToSearch'
    'click': 'showActions'
    
  addKeywordToSearch: (evt) ->
    $('#search-bar').val $(evt.currentTarget).html()
    frag = if root.searchApp.currentBbox? then "#{$('#search-bar').val()}/bbox=#{root.searchApp.currentBbox.toBBOX()}" else "#{$('#search-bar').val()}"
    root.searchApp.router.navigate frag, { trigger: true }
    return      
    
  showActions: (evt) ->
    # Only show actions if a keyword/author was NOT clicked
    return if $(evt.target).hasClass 'keyword'
    root.searchApp.currentActions.undelegateEvents() if root.searchApp.currentActions?
    root.searchApp.currentActions = actions = new root.ActionsView { model: @model, ele: $ evt.currentTarget }
    actions.render()
    
    # Hide details if they're up
    $('#details-popup .close-popup').click() if $('#details-popup').is(':visible')
      
# View backed by an IsoMetadata Model    
class root.ActionsView extends Backbone.View
  el : '#left-sidebar'
  
  jade: new root.Jade '/templates/actions.jade'  
  
  initialize: (options) ->
    @resultEle = options.ele
    
  render: ->    
    # Pointers from result
    $('.pointer').addClass 'hidden'
    @resultEle.find('.pointer').removeClass 'hidden'
    
    # Show the Title
    #$('#tools-title').removeClass 'hidden'
    
    # Action Content
    @$el.empty()    
    @$el.append @jade.content { actions: @model.get('Actions'), xmlUrl: @model.getRecordByIdUrl }
    
    ## Alignment of the action content
    # First put the sidebar at its default location
    $('#left-sidebar').css 'top', 0
    
    # Pointer location
    pointerTop = @resultEle.find('.pointer').position().top
    pointerHeight = @resultEle.find('.pointer').outerHeight()
    pointerMiddle = pointerTop + ( pointerHeight / 2 )
    
    # Sidebar metrics
    sidebarTop = @$el.position().top
    sidebarHeight = @$el.outerHeight()
    
    # Centered sidebar location / offset
    idealSidebarTop = pointerMiddle - ( sidebarHeight / 2 )
    idealSidebarBottom = pointerMiddle + ( sidebarHeight /2 )    
    
    # Correct offsets so that sidebar doesn't run outside its allocated area
    resultsTop = $('#results').position().top
    resultsHeight = $('#results').outerHeight()
    resultsBottom = resultsTop + resultsHeight
    
    if idealSidebarTop < resultsTop
      idealSidebarTop = resultsTop
    else if idealSidebarBottom > resultsBottom
      idealSidebarTop = resultsBottom - sidebarHeight
    
    # Calculate the ideal offset for the sidebar
    idealOffset = idealSidebarTop - sidebarTop    
    
    # Apply the offset
    $('#left-sidebar').css 'top', idealOffset    
    return @
    
  events:
    'click .show-on-map': 'showOnMap'
    'click .full-description': 'viewDetails'
    'click .contact-distributor': 'viewDistributors'
    'click .add-wms': 'addWms'    
    'click .add-esri': 'addEsri'
    'click .preview-data': 'previewData'
    
  showOnMap: (evt) ->
    # Show the map if it is hidden
    root.searchApp.toggleSearchMap(null) if root.searchApp.$mapEl.css('display') is 'none'
    
    # Get map and layer references
    map = root.searchApp.searchMap
    resultLayer = map.getLayersByName('Result Area')[0]
    
    # Construct an OpenLayers.Bounds for this result
    bounds = @model.getBounds map.getProjectionObject()
    style = 
      fillColor: '#EDF8FA'    # in search.less = @header-color
      fillOpacity: 0.4
      strokeColor: '#277E8E'  # in search.less = @text-emphasis-color            
    feature = new OpenLayers.Feature.Vector bounds.toGeometry(), null, style 
    
    # Remove existing features and add this one
    resultLayer.destroyFeatures()
    resultLayer.addFeatures [ feature ]
    
    # Zoom the map to this feature
    map.zoomToExtent bounds
    return
    
  viewDetails: (evt) ->
    @details = new root.DetailsView { model: @model }
    @details.render()
    return
    
  viewDistributors: (evt) ->
    @details = new root.DetailsView { model: @model }
    @details.render('distributors')
    return
    
  addWms: (evt) ->
    title = "#{@model.get('Title')} WMS"
    map = root.searchApp.searchMap
    bounds = @model.getBounds map.getProjectionObject()
     
    # Perform a GetCapabilities request in order to find out the layers that we've got.
    opts =
      type: 'GET'
      url: $(evt.currentTarget).attr 'link'
      success: (data, status, xhr) ->
        format = new OpenLayers.Format.WMSCapabilities()
        capabilities = format.read(data).capability
        wmsOptions = 
          transparent: true
          layers: ( layer.name for layer in capabilities.layers when layer.name? and layer.name isnt '' ).join ','
        layerOptions =
          isBaseLayer: false
          #singleTile: true
        wmsLayer = new OpenLayers.Layer.WMS title, capabilities.request.getmap.href, wmsOptions, layerOptions
        map.addLayer wmsLayer
        map.zoomToExtent bounds
      error: (xhr, status, error) ->
        console.log xhr
        console.log status
        console.log error
      
    $.xmlProxy opts      
    return 
    
  previewData: (evt) ->
    title = "#{@model.get('Title')} Data Preview"
    detailsView = @details
    
    # WFS GetCapabilities starts things off
    opts =
      type: 'GET'
      url: $(evt.currentTarget).attr 'link'
      success: (data, status, xhr) ->
        capFormat = new OpenLayers.Format.WFSCapabilities()
        capabilities = capFormat.read(data)        
        
        # Generate the information we'll need about featureTypes -- specifically, column names        
        desFormat = new OpenLayers.Format.WFSDescribeFeatureType()
        describeFeatureUrl = capabilities.operationsMetadata.DescribeFeatureType.dcp.http.get[0].url
        getFeatureUrl = capabilities.operationsMetadata.GetFeature.dcp.http.get[0].url
        opts =
          type: 'GET'
          url: "#{describeFeatureUrl}request=DescribeFeatureType&service=WFS"
          success: (data, success, xhr) ->
            described = desFormat.read(data)
            buildFeatureType = (type) ->
              featureType =
                prefix: described.targetPrefix
                ns: described.targetNamespace
                name: type.typeName
                columnNames: ( col.name for col in type.properties )
            featureTypes = ( buildFeatureType type for type in described.featureTypes )
            
            # Render the tabs for each available featureType. The click triggers a GetFeature request to populate the table.
            tableModel = new Backbone.Model { Title: title, featureTypes: featureTypes, url: getFeatureUrl }
            detailsView = new root.DetailsView { model: tableModel }
            detailsView.render('preview')
            $('#feature-type-tabs li:first-child').click()
        $.xmlProxy opts         
        return
    $.xmlProxy opts
    return
    
  addEsri: (evt) ->
    # Build the ESRI Layer
    reqOptions =
      transparent: true
    layerOptions =
      isBaseLayer: false
      #singleTile: true
    title = "#{@model.get('Title')} ESRI"
    url = "#{$(evt.currentTarget).attr('link')}/export"
    esriLayer = new OpenLayers.Layer.ArcGIS93Rest title, url, reqOptions, layerOptions 
    
    # Add the Layer to the map and zoom to it
    map = root.searchApp.searchMap
    map.addLayer esriLayer
    map.zoomToExtent @model.getBounds map.getProjectionObject()
    return
    
class root.DetailsView extends Backbone.View
  el: '#details-popup'
  
  fullJade: new root.Jade '/templates/details.jade'
  distributorJade: new root.Jade '/templates/distributor-details.jade'
  previewJade: new root.Jade '/templates/preview-popup.jade'
  tableJade: new root.Jade '/templates/preview-table.jade'
  
  initialize: (options) ->
    root.searchApp.detailsView = @
  
  render: ( type = 'full' ) ->
    # Build the popup content
    @$el.empty()
    switch type
      when 'full' then jade = @fullJade
      when 'distributors' then jade = @distributorJade
      when 'preview' then jade = @previewJade
    @$el.append jade.content @model.toJSON()
    @$el.removeClass 'hidden'
    
    # Move the popup to default position
    @$el.css 'top', 0
    @$el.css 'left', 0
    
    # Align the width of the details popup
    mainWidth = $('#main-container').width()    
    detailWidth = @$el.width()
    @$el.css 'left', ( mainWidth / 2 ) - ( detailWidth / 2 )
    
    ## Align the height of the details popup
    # Gather page metrics
    resultsTop = $('#results').position().top
    resultsHeight = $('#results').outerHeight()
    resultsBottom = resultsTop + resultsHeight
    sidebarTop = $('#left-sidebar').position().top
    sidebarHeight = $('#left-sidebar').outerHeight()
    sidebarMiddle = sidebarTop + ( sidebarHeight / 2 )
    
    # Gather popup metrics    
    popupHeight = @$el.outerHeight()
    idealPopupTop = sidebarMiddle - ( popupHeight / 2 )
    
    # Adjust ideal top to fit in the window appropriately
    if idealPopupTop < resultsTop
      idealPopupTop = resultsTop + 20
    else if idealPopupTop + popupHeight > resultsBottom
      idealPopupTop = resultsBottom - ( popupHeight + 20 )
    
    # Place the popup's top
    @$el.css 'top', idealPopupTop
    return @  
    
  events:
    'click .close-popup': 'closePopup'
    'click .type-tab': 'getFeatures'
    
  closePopup: (evt) ->
    @$el.addClass 'hidden'
    @undelegateEvents()
  
  getFeatures: (evt) ->
    tableJade = @tableJade
    # First highlight the tab that was clicked
    $('.type-tab').removeClass 'selected-tab'
    $(evt.currentTarget).addClass 'selected-tab'
    
    # Perform a GetFeature request
    
    # This XML request needs to be fed through a proxy, but I don't want to deal with the proxy on ALL OpenLayers requests
    #   So, the OpenLayers.ProxyHost is set and removed within here
    OpenLayers.ProxyHost = '/proxy?url='
    
    featureType = _.find @model.get('featureTypes'), (type) ->
      return $(evt.currentTarget).attr('typeName') is "#{type.prefix}:#{type.name}"
    protocol = new OpenLayers.Protocol.WFS {
      url: @model.get 'url'
      featureType: featureType.name
      featureNS: featureType.ns
      maxFeatures: 10
    }
    result = protocol.read {       
      callback: (response) ->
        OpenLayers.ProxyHost = ''
        
        # Have to adjust features so that attributes are in the same order as the columns
        orderedFeature = (feature) ->
          attributes = []
          for col in featureType.columnNames
            attr = if feature.attributes[col]? then feature.attributes[col] else 'null'
            attributes.push attr
          return attributes
          
        tableContent = tableJade.content { columns: featureType.columnNames, features: ( orderedFeature feature for feature in response.features ) }
        $('#preview-table').empty()
        $('#preview-table').append tableContent
        return 
    }    
    
    return
    
class root.Paginator extends Backbone.View
  el: '#paginator'
  
  jade: new root.Jade '/templates/paginator.jade'
  
  render: -> 
    previous = if @collection.nextRecord > 11 then 10 else 0
    if parseInt(@collection.nextRecord) is 0 then next = 0
    else 
      toGo = @collection.totalRecords - @collection.nextRecord + 1
      next = if toGo > 10 then 10 else toGo
    
    context =
      previous: previous
      next: next
    
    @$el.empty()
    @$el.append @jade.content context
    return @

  events:
    'click #paginator-previous': 'previousResults'
    'click #paginator-next': 'nextResults'
    
  previousResults: ->
    root.searchApp.performSearch null, @collection.nextRecord - 20
    return
    
  nextResults: ->
    root.searchApp.performSearch null, @collection.nextRecord
    return