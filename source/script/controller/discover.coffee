'use strict'

define ['underscore'], (_) ->
  
  class DiscoverController
              
    # Controller dependencies
    @$inject: ['$filter']
    
    # List of paragraph displayed
    paragraphs: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param filter [Object] Angular's filter factory
    constructor: (filter) -> 
      document.title = filter('i18n') 'titles.discover'
      # make a deep copy because we'll modifies images
      @paragraphs = (_.extend {}, p for p in conf.texts.discover)
      # compiles directive in content
      for paragraph in @paragraphs
        paragraph.content = paragraph.content.replace /image\//g, "#{conf.rootPath}image/"
      
    # return back without full page reload
    back: =>
      window.history.back()