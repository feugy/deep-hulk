'use strict'

define [
  'underscore'
  'app'
], (_, app) ->
  
  app.factory 'players', ['atlas', (atlas) ->
    new PlayersService atlas
  ]
  
  # @param player [Object] a player object from server
  # @return first name or last name or email
  friendlyName = (player) ->
    player.firstName or player.lastName or player.email
    
  # Player service will manage other player names and connection status
  class PlayersService
  
    # Link to Atlas service
    atlas: null
    
    # List of emails to consult on server
    _pending: []
    
    # Root object used to return server's result
    # We need to use this as reference holder, or angular won't figured when 
    # server has sent response
    # Not used as cache (cache in internally maintain by atlas itself
    _players: {}
    
    # Builds the Player service
    # @param atlas [Object] Atlas service
    constructor: (@atlas) ->
      @_pending = []
      # waits during 50ms before getting players
      @_invoke = _.debounce @_invoke, 50
      @_players = {}
      
    # Retrieve player friendly name. 
    # Always ask to server, but uses atlas's cache mecanism
    #
    # @param email [String|Player] email or whole player account from which to get friendly name
    # @return the friendly name, as a reference that will be updated when response will be available
    getPlayerName: (email) =>
      # replace players by their email
      unless _.isString email
        email = email?.email
        
      # put in queue if not already
      unless email in @_pending
        @_pending.push email
        @_invoke()
        
      # immediately returns a reference that will be updated lately
      @_players[email] = email: email unless email of @_players
      friendlyName @_players[email]
      
    # Retrieve player connection status at this instant. 
    # Always ask to server, but uses atlas's cache mecanism
    #
    # @param email [String|Player] email or whole player account from which to get connection status
    # @return connection status, as a reference that will be updated when response will be available
    isPlayerConnected: (email) =>
      # replace players by their email
      unless _.isString email
        email = email?.email
        
      # put in queue if not already
      unless email in @_pending
        @_pending.push email
        @_invoke()
        
      # immediately returns a reference that will be updated lately
      @_players[email] = connected: false unless email of @_players
      @_players[email].connected
      
    # **private**
    # Search for players on the server.
    # When answers will be ready, @_players inner variable will be updated, 
    # and Angular will refresh displayed values
    _invoke: =>
      @atlas.getPlayers @_pending.concat(), (err, players) =>
        return console.error err if err?
        @_players[player.email] = player for player in players
      @_pending = []