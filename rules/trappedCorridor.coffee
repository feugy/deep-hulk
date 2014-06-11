_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
Field = require 'hyperion/model/Field'
shoot = require './shoot'
{makeState, enrichAction, useTwist} = require './common'
{orders} = require './constants'

# "trappedCorridor and mine" twist rule: shoot on a marine in a corridor or 
# fire with missile launcher on a marine (not a sergent)
class TrappedCorridorRule extends Rule

  # Always appliable on alien squad if it has the relevant twist
  # 
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (game, squad, context, callback) =>
    # inhibit if waiting for deployment or other squad
    return callback null, null unless squad.isAlien and squad.waitTwist and squad.twist in ['trappedCorridor', 'mine']
    
    # select living marines on the map
    Item.where('map', squad.map.id).where('type', 'marine')
        .where('dead', false).exec (err, marines) =>
      return callback err if err?
      params = []
        
      # mine can be anywhere
      if squad.twist is 'mine'
        # only keeps marines
        candidates = _.where marines, isCommander: false
        if candidates.length > 0
          params.push
            name: 'target'
            type: 'object'
            within: candidates
        return callback null, params
      
      # trappedCorridor is only in corridors
      [unused, lowX, lowY, upX, upY] = game.mapDimensions.match /^(.*):(.*) (.*):(.*)$/
      # select all fields
      Field.where('mapId', squad.map.id)
          .where('x').gte(+lowX).lte(+upX)
          .where('y').gte(+lowY).lte(+upY).exec (err, fields) =>
        return callback err if err?    
        
        # only keeps those who are in corridors
        candidates = _.filter marines, (marine) ->
          _.findWhere(fields, {x: marine.x, y:marine.y})?.typeId is 'corridor'

        if candidates.length > 0
          params.push
            name: 'target'
            type: 'object'
            within: candidates
        callback null, params

  # Performs a shoot on the selected target: use a temporary fake actor equiped with relevant weapon.
  #
  # @param actor [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    twist = squad.twist
    
    # no target found
    unless params.target?
      return useTwist twist, game, squad, [], @, callback
    
    # fetch marine target
    Item.findCached [params.target], (err, [target]) =>
      err = new Error "No marine with id #{params.target}" if not err? and not target?
      return callback err if err?
      Item.fetch [squad.trap, target], (err, [trap, target]) =>
        return callback err if err?
      
        console.log "applied twist #{twist} on #{target.name} (#{target.squad.name})"    
        # use the trap actor to shoot, at same position to avoid walls
        trap.x = target.x
        trap.y = target.y
        
        # performs a shoot with this actor
        shoot.saved = []
        shoot.removed = []
        # use missile launcher for mine, laser for trapped corridor
        weaponIdx = if twist is 'mine' then 1 else 0
        shoot.execute trap, target, {weaponIdx: weaponIdx}, {}, (err, results) =>
          return callback err if err?
          @saved = @saved.concat shoot.saved
          @removed = @removed.concat shoot.removed
          
          # undo modification to alien squad regarding actions
          squad.firstAction = true
          trap.usedWeapons = []
          
          # release other squad from waiting
          other.waitTwist = false for other in game.squads
    
          # enrich history action added by shoot to add twist information
          effects = [makeState game, 'events']
          game.events.push 
            name: target.squad.name
            kind: 'twist'
            used: twist
          enrichAction squad, effects, callback
      
module.exports = new TrappedCorridorRule 'twists'