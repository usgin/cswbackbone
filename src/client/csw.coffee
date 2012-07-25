root = exports ? this

$ = if exports? then require 'jquery' else root.$
_ = if exports? then require 'underscore' else root._
Utils = if exports? then require('./utils').Utils else root.Utils

defaultReqParams =
  service: 'CSW'
  version: '2.0.2'
  outputSchema: 'http://www.isotc211.org/2005/gmd' 
  elementSetName: 'full'

root.csw = {}

root.csw.getRecords = (rootUrl, options, limit=10, start=1, ogcFilter=null) ->
  
  ogcFilter = Utils.filterToXML ogcFilter if ogcFilter and not _.isString ogcFilter
  
  reqParams =
    request: 'GetRecords'
    resultType: 'results'
    maxRecords: limit
    startPosition: start
    
  if ogcFilter?
    reqParams.constraint = ogcFilter.replace '<?xml version="1.0"?>', ''
    reqParams.constraintLanguage = 'FILTER'
  
  params =
    url: rootUrl
    type: 'GET'
    dataType: 'xml'
    data: _.extend defaultReqParams, reqParams
  return $.ajax _.extend params, options
  
root.csw.getRecordById = (rootUrl, id, options) ->

  reqParams =
    request: 'GetRecordById'
    id: id
    
  params =
    url: rootUrl
    type: 'GET'
    dataType: 'xml'
    data: _.extend defaultReqParams, reqParams
  return $.ajax _.extend params, options

# jQuery plugin to help find things in ISO documents      
$.fn.iso = (attribute) ->
  
  contactProperties =
    Name: '/gmd:individualName/gco:CharacterString/text()' 
    OrganizationName: '/gmd:organisationName/gco:CharacterString/text()'
    ContactInformation:
      array: false
      context: '/gmd:contactInfo/gmd:CI_Contact'
      properties:
        Phone: '/gmd:phone/gmd:CI_Telephone/gmd:voice/gco:CharacterString/text()'
        email: '/gmd:address/gmd:CI_Address/gmd:electronicMailAddress/gco:CharacterString/text()'
        Address:
          array: false
          context: '/gmd:address/gmd:CI_Address'
          properties:
            Street: '/gmd:deliveryPoint/gco:CharacterString/text()'
            City: '/gmd:city/gco:CharacterString/text()'
            State: '/gmd:administrativeArea/gco:CharacterString/text()'
            Zip: '/gmd:postalCode/gco:CharacterString/text()'          
  xpaths =
    id: '/gmd:fileIdentifier/gco:CharacterString/text()'
    title: '/gmd:identificationInfo//gmd:citation/gmd:CI_Citation/gmd:title/gco:CharacterString/text()'
    description: '/gmd:identificationInfo//gmd:abstract/gco:CharacterString/text()'
    publicationDate: '/gmd:identificationInfo//gmd:citation/gmd:CI_Citation/gmd:date/gmd:CI_Date/gmd:date/gco:DateTime/text()'
    modifiedDate: '/gmd:dateStamp/gco:DateTime/text()'
    extent:
      array: false
      context: '/gmd:identificationInfo////gmd:EX_Extent/gmd:geographicElement/gmd:EX_GeographicBoundingBox'
      properties:
        WestBound: '/gmd:westBoundLongitude/gco:Decimal/text()'
        EastBound: '/gmd:eastBoundLongitude/gco:Decimal/text()'
        SouthBound: '/gmd:southBoundLatitude/gco:Decimal/text()'
        NorthBound: '/gmd:northBoundLatitude/gco:Decimal/text()'
    keywords:
      array: true 
      context: '/gmd:identificationInfo//gmd:descriptiveKeywords/gmd:MD_Keywords'
      properties:
        keywords: '/gmd:keyword/gco:CharacterString/text()'
        type: '/gmd:type/gmd:MD_KeywordTypeCode/@codeListValue'
        thesaurus: '/gmd:thesaurusName/gmd:CI_Citation/gmd:title/gco:CharacterString/text()'
    authors:
      array: true
      context: '/gmd:identificationInfo//gmd:citation/gmd:CI_Citation/gmd:citedResponsibleParty/gmd:CI_ResponsibleParty'
      properties: contactProperties
    distributors:
      array: true
      context: '/gmd:distributionInfo/gmd:MD_Distribution/gmd:distributor/gmd:MD_Distributor/gmd:distributorContact/gmd:CI_ResponsibleParty'
      properties: contactProperties
    links:
      array: true
      context: '/gmd:distributionInfo/gmd:MD_Distribution/gmd:transferOptions/gmd:MD_DigitalTransferOptions/gmd:onLine/gmd:CI_OnlineResource'
      properties:
        URL: '/gmd:linkage/gmd:URL/text()'
        Description: '/gmd:description/gco:CharacterString/text()'
        ServiceType: '/gmd:protocol/gco:CharacterString/text()'
        Name: '/gmd:name/gco:CharacterString/text()'
        #LayerId:
        #Distributor:
        
  resolveProperties = (context, properties) ->
    result = {}
    for prop, propLookup of properties
      result[prop] = xPathResolver $(context), propLookup
    return result
  
  xPathResolver = (context, lookup) ->
    if _.isString lookup then return xPath context, lookup
    else if _.isObject lookup
      context = xPath context, lookup.context
      output = ( resolveProperties con, lookup.properties for con in context )
      switch output.length
        when 0 then return null
        when 1
          if lookup.array then return output
          else return output[0]
        else return output
    else return null
      
  xPath = (context, xpath) ->
    toSelector = (xpathSegment) ->
      ns = xpathSegment.split(':')[0]
      ele = xpathSegment.split(':')[1]
      return "#{ ns }\\:#{ ele }, #{ ele }"
      
    segments = xpath.split('/')
    segments.splice 0, 1 if segments[0] is ''
    find = false
    for segment, index in segments
      if segment is ''
        find = true        
      else if find
        context = context.find toSelector segment
        find = false
      else if segment.slice(0, 1) is '@'
        return context.attr segment.slice 1
      else if segment is 'text()'
        if context.length > 1 then return ( $(item).text() for item in context )          
        else return context.text()
      else
        context = context.children toSelector segment
    return context
      
  # Do something if the requested attribute is defined in the above xPaths object...  
  if attribute in (attr for attr, lookup of xpaths)
    result = xPathResolver this, xpaths[attribute]
    if attribute is 'extent'
      for prop, value of result
        result[prop] = parseFloat value
    return result
    
  else
    return null
    
