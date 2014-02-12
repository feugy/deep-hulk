Rule = require 'hyperion/model/Rule'
Field = require 'hyperion/model/Field'
{selectItemWithin} = require './common'
{isTargetable, tilesOnLine, untilWall, hasObstacle} = require './visibility'

# The ShootZoneRule rule highlight damage zone of a given ranged weapon
# it also give the visibility line, even if target is not reachable
class ShootZoneRule extends Rule

  # Do not compute unless character has remaining shoot and ranged weapon
  # Only applicable:
  # - if no deployment in progress, 
  # - if actor has range combat weapon and enought attacks, 
  # - and if target is a field on the same map
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    # inhibit if wanting for deployment
    return callback null, null if actor.squad?.deployZone?
    # deny if actor cannot attack anymore. 
    return callback null, null unless actor.rcNum >= 1 and actor.weapon.rc? 
    # deny unless on same map
    return callback null, null unless target?.mapId is actor.map?.id
    callback null, []
      
  # Returns tiles that are involved in the shoot, depending on the character weapon
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] detailed results:
  # @option callback result tiles [Array] array of targeted map coordinates. Empty to indicate that target isn't reachable
  # @option callback result obstacle [Object] if target isn't reachable, map coordinates of obstacle
  # @option callback result weapon [String] id of the used weapon
  execute: (actor, target, params, context, callback) =>
    selectItemWithin actor.map.id, actor, target, (err, items) =>
      return callback err, null if err?
      result = 
        weapon: actor.weapon.id
        tiles: []
        obstacle: null
        
      unless isTargetable actor, target, items
        # target not reachable: returns obstacle (with character blocking visibility)
        result.obstacle = hasObstacle actor, target, items, true
        return callback null, result
        
      switch actor.weapon.id
        when 'missileLauncher'
          # tiles near target are also hit
          Field.where('mapId', actor.map.id).where('x').gte(target.x-1).where('x').lte(target.x+1)
              .where('y').gte(target.y-1).where('y').lte(target.y+1).exec (err, fields) ->
            return callback err if err?
            selectItemWithin actor.map.id, {x:target.x-1, y:target.y-1}, {x:target.x+1, y:target.y+1}, (err, items) =>
              return callback err if err?
              result.tiles = (x:tile.x, y:tile.y for tile in fields when not hasObstacle(target, tile, items)?)
              callback null, result
              
        when 'flamer' 
          # all tiles on the line are hit.
          untilWall actor.map.id, actor, target, (err, target, items) =>
            return callback err if err?
            result.tiles = tilesOnLine actor, target
            callback null, result
          
        else 
          # just returns tile
          result.tiles = [x:target.x, y:target.y]
          callback null, result
  
module.exports = new ShootZoneRule 'hints'