'use strict'

define [
  'underscore'
  'app'
], (_, app) ->
  
  app.factory 'players', ['atlas', (atlas) ->
    new PlayersService atlas
  ]
    
  # Player service will manage other player names and connection status
  class PlayersService
  
    # Link to Atlas service
    atlas: null
    
    _pending: []
    
    _players: {}
    
    # @param atlas [Object] Atlas service
    constructor: (@atlas) ->
      @_pending = []
      @_invoke = _.debounce @_invoke, 100
      @_players = {}
      
    getPlayerName: (email) =>
      # replace players by their email
      unless _.isString email
        email = email?.email
        
      unless email in @_pending
        @_pending.push email
        @_invoke()
        
      @_players[email] = email: email unless email of @_players
      @_friendlyName @_players[email]
      
    _friendlyName: (player) =>
      player.firstName or player.email
      
    _invoke: =>
      @atlas.getPlayers @_pending.concat(), (err, players) =>
        return console.error err if err?
        @_players[player.email] = player for player in players
      
      @_pending = []