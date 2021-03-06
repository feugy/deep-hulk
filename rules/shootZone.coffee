Rule = require 'hyperion/model/Rule'
Field = require 'hyperion/model/Field'
{selectItemWithin} = require './common'
{isTargetable, tilesOnLine, untilWall, hasObstacle} = require './visibility'

parseTargetParams = (params, tiles) ->
  if params.multipleTargets?
    # each target is comma separated, x and y coordinates separated by ':' themseves
    for target in params.multipleTargets
      coord = target.split ':'
      tiles.push x: +coord[0], y: +coord[1]
      
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
    # inhibit if waiting for deployment or other squad
    if actor.squad?.deployZone? or actor.squad?.activeSquad? and actor.squad.activeSquad isnt actor.squad.name
      return callback null, null 
    # deny if actor cannot attack anymore. 
    return callback null, null unless actor.rcNum >= 1 
    # deny unless on same map
    return callback null, null unless target?.mapId is actor.map?.id
    callback null, [
      {name: 'weaponIdx', type:'integer', min: 0, max: actor.weapons.length-1}
      {name: 'multipleTargets', type:'string', numMin: 0, numMax:20}
    ]
      
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
    # get fields above attacker to check base
    Field.where('mapId', actor.map.id).where('x', actor.x).where('y', actor.y).exec (err, [field]) =>
      return callback err if err?
      # deny shoot if actor is in base
      return callback null, null if field.typeId[0..4] is 'base-'
      
      selectItemWithin actor.map.id, actor, target, (err, items) =>
        return callback err, null if err?
        # check that selected weapon as range combat
        weapon = actor.weapons[params.weaponIdx]
        return callback 'closeCombatWeapon', null unless weapon?.rc?
        # check that this weapon was not already used
        return callback null, null if params.weaponIdx in actor.usedWeapons
        
        result = 
          weapon: weapon.id
          tiles: []
          obstacle: null
          
        reachable = isTargetable actor, target, params.weaponIdx, items
        unless reachable?
          # add autoCannon already selected targets
          parseTargetParams params, result.tiles
          # target not reachable: returns obstacle (with character blocking visibility)
          result.obstacle = hasObstacle actor, target, items, true
          return callback null, result
          
        tiles = [x:target.x, y:target.y]
        switch result.weapon
          when 'missileLauncher'
            # tiles near target are also hit
            return Field.where('mapId', actor.map.id).where('x').gte(target.x-1).where('x').lte(target.x+1)
                .where('y').gte(target.y-1).where('y').lte(target.y+1).exec (err, fields) =>
              return callback err if err?
              selectItemWithin actor.map.id, {x:target.x-1, y:target.y-1}, {x:target.x+1, y:target.y+1}, (err, items) =>
                return callback err if err?
                result.tiles = (x:tile.x, y:tile.y for tile in fields when not hasObstacle(target, tile, items)?)
                callback null, result
                
          when 'flamer' 
            # all tiles on the line are hit.
            return untilWall actor.map.id, reachable, target, (err, target, items) =>
              return callback err if err?
              result.tiles = tilesOnLine reachable, target
              callback null, result
            
          when 'autoCannon'
            # display also previous targets, stored as string in currentTargets
            parseTargetParams params, tiles
            
        result.tiles = tiles
        callback null, result
  
module.exports = new ShootZoneRule 'hints'