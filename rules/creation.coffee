_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Map = require 'hyperion/model/Map'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
Field = require 'hyperion/model/Field'
FieldType = require 'hyperion/model/FieldType'
{maxGames, squadImages, weaponImages, alienCapacities, moveCapacities, freeGamesId} = require './constants'

# Game creation: initiate a game with its mission
class CreationRule extends Rule

  # Every player can create a few number of games.
  # They choose a name for this game, and a squad.
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    return callback null, null unless actor?._className is 'Player' and actor is target
    callback null, [
      {name: 'gameName', type: 'string'}
      {name: 'mission', type: 'string', within: ['mission-3']}
      {name: 'squad', type: 'string'}
    ]

  # Effectively creates a game, and its squads
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Array] array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [String] a summary log string
  execute: (actor, target, params, context, callback) =>
    return callback new Error "maxGames #{maxGames}" if actor.characters.length >= maxGames
    
    # get selected mission details
    Item.findCached [params.mission, freeGamesId], (err, [mission, freeGames]) =>
      return callback err if err?
      
      # check allowed squads
      squadIds = _.invoke mission.squads.split(','), 'trim'
      unless params.squad in squadIds
        return callback "Unallowed squad #{params.squad} for mission #{mission.id}"
      
      # manually create ids: better lisibility and allow bidirectionnal relationship between game and squads
      id = Math.floor Math.random()*1000000
        
      # creates a map for this game
      mapId = "map-#{id}"
      map = new Map id: mapId, kind: 'square', tileDim: 200
      @saved.push map

      # get items types
      ItemType.findCached ['squad', 'game', 'marine', 'wall', 'alien'], (err, [Squad, Game, Marine, Wall, Alien]) =>
        return callback err if err?
        # creates the game
        game = new Item id: "game-#{id}", name: params.gameName, squads: (
          # creates squads
          for i in [0...squadIds.length]
            name = squadIds[i]
            squad = new Item id: "squad-#{id}-#{i}", name: name, imageNum: squadImages[name], isAlien: name is 'alien', members:[], type: Squad
            if squadIds[i] is params.squad
              console.log "player #{actor.email} choose squad #{params.squad}"
              # save first squad into player's games
              squad.player = actor.email
              actor.characters.push squad
            
            # appart the alien squad
            if name is 'alien'
              @_createAliens squad, Alien, JSON.parse mission.aliens
              # immediateky deploy alien on map
              squad.map = map
            else
              @_createMarines squad, Marine, name
                  
            # order is important: save marine before squad
            @saved.push squad
            squad
        ), type: Game
        
        squad.game = game for squad in game.squads 
        # order is important: save game before squads
        @saved.splice 0, 0, game
        
        # get field types
        FieldType.findCached ['corridor', 'room'], (err, [Corridor, Room]) =>
          return callback err if err?
          # get map template, to perform a copy
          Field.find {mapId: mission.mapId}, (err, fields) =>
            return callback err if err?
            [minX, minY, maxX, maxY] = [null, null, null, null]
            # and fills it with template information
            for f in fields
              @saved.push new Field mapId: mapId, x:f.x, y:f.y, typeId: f.typeId, num: f.num
              # compute map dimensions
              minX = if !minX? or f.x < minX then f.x else minX
              minY = if !minY? or f.y < minY then f.y else minY
              maxX = if !maxX? or f.x > maxX then f.x else maxX
              maxY = if !maxY? or f.y > maxY then f.y else maxY
            console.log "#{fields.length} map fields copied"
            # save map dimension to further loading
            game.mapDimensions = "#{minX}:#{minY} #{maxX}:#{maxY}"
            
            Item.find {map: mission.mapId}, (err, items) =>
              return callback err if err?
              for item in items
                specific = {}
                switch item.type.id
                  when 'door'
                    specific = closed: item.closed
                  when 'deployable'
                    specific = _.pick item, 'zone', 'dimensions'
                  else
                    specific = {}
                # adds an Item copy with common and specific fields
                @saved.push new Item _.extend {
                  map: map
                  x:item.x
                  y:item.y
                  type: item.type
                  imageNum: item.imageNum or 0
                }, specific
              console.log "map walls and doors copied"
              console.log "game #{params.gameName} (#{game.id}) created by #{actor.email} (#{params.squad})"
              freeGames.games.push game
              @saved.push freeGames
              # returns game id for client redirection
              callback null, game.id

  # **private**
  # Creates and adds alien blips to alien squad, regarding the chosen mission.
  #
  # @param squad [Item] the populated squad
  # @param type [ItemType] item type to create aliens
  _createAliens: (squad, type, specs) =>
    # alien forces depends on the mission selected
    for kind, number of specs
      for i in [0...number]
        alien = new Item _.extend {}, alienCapacities[kind],
          type: type
          kind: kind
          imageNum: 0
          revealed: false
          moves: moveCapacities.blip
          squad: squad
        @saved.push alien
        squad.members.push alien
    console.log "aliens created"
    
  # **private**
  # Creates and adds a marine sergent and 4 marines to a given squad.
  #
  # @param squad [Item] the populated squad
  # @param type [ItemType] item type to create marines
  # @param name [String] the squad name used to choose marines images regarding their weapons
  _createMarines: (squad, type, name) =>
    # adds 4 marines with bolders and a sergent with bolt pistol and energetic axe
    sergent = new Item 
      type: type
      imageNum: weaponImages[name].pistolAxe
      squad: squad
      name: "sergent"
      isCommander: true
      life: 6
      armor: 2
      moves: moveCapacities.heavyBolter
      weapon: 'pistolAxe'
    @saved.push sergent
    squad.members.push sergent
        
    for i in [1..4]
      # reuse existing weapon by referencing their ids
      marine = new Item 
        type: type
        imageNum: weaponImages[name].bolter
        squad: squad
        name: "marine #{i}"
        life: 1
        armor: 2
        moves: moveCapacities.bolter
        weapon: 'bolter'
      @saved.push marine
      squad.members.push marine
    console.log "marines #{name} created"
    
# A rule object must be exported. You can set its category (constructor optionnal parameter)
module.exports = new CreationRule 'init'