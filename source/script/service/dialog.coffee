'use strict'

define [
  'jquery'
  'underscore'
  'app'
  'text!template/dialog.html'
], ($, _, app, template) ->
  
  # Dialog Class
  class Dialog
                  
    # Controller scope, injected within constructor, and that contains:
    # @param title [String] displayed title
    # @param message [String] displayed message (may contains HTML content)
    # @param onClose [Expresion] closure handler. May return false to cancel closure. Also invoked after button action.
    # @param buttons [Array] list of buttons, must contain 
    # @option buttons label [String] displayed label
    # @option buttons result [Expression] result used in the current promise to distinguish buttons
    # @option buttons onClick [Expression] optionnal executed expression on click, executed before closure. Return false to cancel closure
    # @option buttons classes [String] May contain multiple classes (space separated) applied to button (optionnal)
    scope: null
    
    # JQuery enriched element
    $el: null
    
    # Link to Angular's animation provider
    animate: null
    
    # Promise running while dialog is opened
    dfd: null
    
    # Result used in the current promise
    result: null
    
    # Controller constructor: bind methods and attributes to current scope
    #
    # @param scope [Object] dialog own scope
    # @param element [Object] dialog template root element
    # @param compile [Object] Angular directive compiler
    # @param animate [Object] Angular's animation provider
    # @param q [Object] Angular's promise implementation
    constructor: (@scope, template, compile, @animate, q) ->
      @dfd = q.defer()
      @$el = $ compile(template) @scope
      @result = null
      
      # click handler for button
      @scope.close = (result, index) =>
        # identify clicked button
        button = @scope.buttons[index] if index >= 0
        closure = true
        if button?.onClick?
          closure = @scope.$eval button.onClick
        unless closure is false
          @result = result
          @close()
          
    # opens the dialog by adding it into body with ng-show animation
    #
    # @param done [Function] optional animation end callback
    # @return the current promise, that will ends with dialog closure.
    open: (done = ->) =>
      $('body').append @$el
      @animate.addClass @$el, 'ng-show', =>
        @$el.find('.modal-dialog .btn').first().focus()
        done()
      @dfd.promise
      
    # closes the dialog with animation.
    # closure may be cancelled by closure scope expression
    #
    # @param done [Function] optional animation end callback
    close: (done = ->) =>
      closure = true
      # invoke closure callback
      if @scope.onClose?
        closure = @scope.$eval @scope.onClose
      # cancel if necessary
      return if closure is false
      # ends current promise
      @dfd.resolve @result
      # hides element and remove it
      @animate.removeClass @$el, 'ng-show', =>
        @$el.remove()
        done()
        
  # Dialog provider
  app.factory '$dialog', ['$rootScope', '$compile', '$animate', '$q', (rootScope, compile, animate, q) ->
      # Creates a new `Dialog` with the specified title, message and buttons, and default template.
      messageBox: (title, message, buttons) -> 
        scope = rootScope.$new()
        scope.title = title
        scope.message = message
        scope.buttons = buttons
        new Dialog scope, template, compile, animate, q
    ]
      
  