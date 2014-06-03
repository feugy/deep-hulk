_ = require 'underscore'
async = require 'async'
utils = require 'hyperion/util/model'
Rule = require 'hyperion/model/Rule'
Field = require 'hyperion/model/Field'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{rollDices, selectItemWithin, sum, countPoints, 
removeFromMap, addAction, hasSharedPosition, 
damageDreadnought, logResult, makeState} = require './common'
{checkMission} = require './missionUtils'
{isTargetable, hasObstacle, tilesOnLine, untilWall} = require './visibility'
{moveCapacities} = require './constants'

# Tells wether a given item can be a target or not. 
#
# @param target [Item] the tested item
# @return true if this target is an alien or a marine.
hasTargetType = (target) ->
  target?.type?.id in ['marine', 'alien'] and not target?.dead and not target?.immune
        
# Marine ranged attack
# Effect depends on the equiped weapon
class ShootRule extends Rule

  # Shoot allowed if actor can reach target (only fields can be targeted)
  # 
  # @param actor [Item] the concerned actor
  # @param target [Field] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    # inhibit if waiting for deployment or other squad
    if actor.squad?.deployZone? or actor.squad?.waitTwist or actor.squad?.activeSquad? and actor.squad.activeSquad isnt actor.squad.name
      return callback null, null 
    # deny if actor cannot attack anymore, or if target isnt a field
    return callback null, false unless not actor.dead and actor.rcNum >= 1 and target?.mapId?
    callback null, [
      {name: 'weaponIdx', type:'integer', min: 0, max: actor.weapons.length-1}
      {name: 'multipleTargets', type:'string', numMin: 0, numMax:20}
    ]

  # Resolve shoot damaged and apply them on targeted tiles
  #
  # @param actor [Item] the concerned actor
  # @param target [Field] the concerned field
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback results [Array] for each object involved: a result object
  execute: (actor, target, params, context, callback) =>
    # get near items to check shared position
    selectItemWithin actor.map.id, actor, {x:actor.x+1, y:actor.y+1}, (err, items) =>
      return callback err, null if err?
      isDreadnought = actor.kind is 'dreadnought' and actor.revealed
      # for dreadnought, abort if under a door
      return callback new Error "underDoor" if isDreadnought and actor.underDoor
      # abort if sharing tile with a squadmate
      return callback new Error "sharedPosition" if hasSharedPosition items
      # get fields above attackers to check base
      Field.where('mapId', actor.map.id).where('x', actor.x).where('y', actor.y).exec (err, [field]) =>
        return callback err if err?
        # deny shoot if actor is in base
        return callback null, null if field.typeId[0..4] is 'base-'
        
        # check that selected weapon as range combat
        weapon = actor.weapons[params.weaponIdx]
        return callback new Error 'closeCombatWeapon', null unless weapon?.rc?
        # check that this weapon was not already used
        return callback new Error 'alreadyUsed', null if params.weaponIdx in actor.usedWeapons
        # now check visibility 
        isTargetable actor, target, params.weaponIdx, (err, reachable) =>
          return callback err, null if err?
          # silentely stop if not reachable with this weapon
          return callback null, null unless reachable?
         
          # action history
          effects = [makeState actor, 'ccNum', 'rcNum', 'moves', 'log', 'usedWeapons']
          
          end = (err, resultAndTargets) =>
            return callback err if err?
            results = _.map resultAndTargets, (o) -> o.result
            logResult actor, results
            addAction 'shoot', actor, effects, @, (err) =>
              return callback err if err?
              checkMission actor.squad, 'attack', resultAndTargets, @, (err) =>
                callback err, results
     
          actor.squad.firstAction = false
          # consume close conbat if not already consumed during shoot with first weapon
          actor.ccNum-- unless actor.ccNum is 0 or actor.usedWeapons.length > 0 or actor.equipment? and 'toDeath' in actor.equipment
          # store this new weapon in used one
          actor.usedWeapons.push params.weaponIdx
          # consume an attack if all weapons were used, or equipmed with combined weapon (can only shoot once)
          if actor.usedWeapons.length is actor.weapons.length or actor.equipment? and 'combinedWeapon' in actor.equipment
            actor.usedWeapons = []
          actor.rcNum-- if actor.usedWeapons.length is 0
          
          # if consumming all range attacks and having by section order, then reduce moves
          if actor.rcNum is 0 and actor.equipment? and 'bySections' in actor.equipment
            actor.moves /= 2
            actor.equipment.splice actor.equipment.indexOf('bySections'), 1
          # removes special equipment once used
          if actor.equipment? and 'toDeath' in actor.equipment
            actor.equipment.splice actor.equipment.indexOf('toDeath'), 1
            
          # consume remaining moves if a move is in progress
          if 0 < actor.moves < moveCapacities[weapon.id]
            actor.moves = 0
            
          # roll dices, with re-roll if an equipment allows it
          dices = rollDices weapon.rc, _.any actor.equipment, (equip) -> equip in ['bionicEye', 'digitalWeapons', 'targeter']
          console.log "#{actor.name or actor.kind} (#{actor.squad.name or 'alien'}) shoot with #{weapon.id} at #{target.x}:#{target.y}: #{dices.join ','}"
          
          # depending on the weapon
          switch weapon.id
            when 'missileLauncher'
              # tiles near target are also hit
              selectItemWithin actor.map.id, {x:target.x-1, y:target.y-1}, {x:target.x+1, y:target.y+1}, (err, targets) =>
                return end err if err?
                # on center, sum dices, around, use the highest
                center = sum dices
                around = _.max dices
                results = []
                # Store damaged target to avoid hitting same dreadnought multiple times in the same shoot
                hitten = []
                async.each targets, (t, next) =>
                  t.fetch (err, t) =>
                    return next err if err?
                    return next() if not hasTargetType(t) or hasObstacle(target, t, targets)?
                    # edge case: target is shooter. Use modified actor instead fetched value
                    t = actor if t.id is actor.id
                    damages = if t.x is target.x and t.y is target.y then center else around 
                    # for another edge case, specify center position and damages
                    @_applyDamage actor, t, damages, effects, hitten, (err, result) =>
                      if result?
                        results.push target: t, result: result
                        console.log "hit on target #{t.name or t.kind} (#{t.squad.name or 'alien'}) at #{t.x}:#{t.y}: #{result.loss} (#{result.damages}), died ? #{result.dead}"
                      next err
                    , damages: center, x: target.x, y: target.y
                , (err) =>
                  end err, results
                  
            when 'flamer' 
              # all tiles on the line are hit.
              untilWall actor.map.id, reachable, target, (err, target, items) =>
                return end err if err?
                # get the hit positions
                positions = tilesOnLine reachable, target
                damages = sum dices
                results = []
                # Store damaged target to avoid hitting same dreadnought multiple times in the same shoot
                hitten = []
                async.each positions, (pos, next) =>
                  # and find potential target at position
                  target = _.find items, (item) -> item.x is pos.x and item.y is pos.y and hasTargetType item
                  return next() unless target? and not reachable.equals target
                  target.fetch (err, target) =>
                    return next err if err?
                    @_applyDamage actor, target, damages, effects, hitten, (err, result) =>
                      if result?
                        results.push target: target, result: result
                        console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: #{result.loss} (#{result.damages}), died ? #{result.dead}"
                      next err
                , (err) =>
                  end err, results
                  
            when 'autoCannon'
              # multiple target allowed: extract them from parmaeters
              targets = (x:+(coord[0...coord.indexOf ':']), y:+(coord[coord.indexOf(':')+1..]) for coord in params.multipleTargets)
              # add the target to list of current targets, unless already present
              results = []
              # Store damaged target to avoid hitting same dreadnought multiple times in the same shoot
              hitten = []
                
              # split damages on selected target, keeping the order
              damages = sum dices
              allocateDamages = () =>
                # quit when no target remains
                return end null, results unless targets.length > 0
                # select objects between actor and target to check visibility
                target = targets.splice(0, 1)[0]
                selectItemWithin actor.map.id, actor, target, (err, items) =>
                  return end err if err?
                  target = _.find items, (item) -> hasTargetType(item) and item.x is target.x and item.y is target.y
                  # no character found, or not targetable: proceed next target
                  return allocateDamages() unless target? and isTargetable(actor, target, params.weaponIdx, items)?
                  target.fetch (err, target) =>
                    return end err if err?
                    @_applyDamage actor, target, damages, effects, hitten, (err, result) =>
                      return end err if err?
                      return allocateDamages() unless result?
                      if target.life is 0
                        # target terminated: allocate remaining damages to next
                        result.damages = target.armor+result.loss
                        damages -= result.damages
                      else if result.loss > 0
                        # target wounded: no more damages to allocate
                        damages = 0
                      else if targets.length > 0
                        # no wound and remaining target: consider we never aim at this one
                        result.damages = 0
                      # else no wound and last target
                      
                      console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}:  #{result.loss} (#{result.damages}), died ? #{result.dead}" 
                      # process next target
                      results.push target: target, result: result
                      allocateDamages()
                  
              allocateDamages()
              
            else 
              # all other weapons hit a single tile in any direction
              selectItemWithin actor.map.id, target, (err, targets) =>
                return end err if err?
                target = _.find targets, hasTargetType
                return end err, [] unless target?
                target.fetch (err, target) =>
                  return end err if err?
                  damages = sum dices
                  @_applyDamage actor, target, damages, effects, [], (err, result) =>
                    console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}:  #{result.loss} (#{result.damages}), died ? #{result.dead}" 
                    end err, [target: target, result: result]
      
  # Apply given damages on a target
  # Will remove target if dead, and make points computations
  #
  # @param actor [Item] the shooting actor
  # @param target [Item] the hitten target
  # @param damage [Number] damage performed by actor's weapon
  # @param effects [Array<Array>] for each modified model, an array with the modified object at first index
  # and an object containin modified attributes and their previous values at second index (must at least contain id).
  # @param hitten [Array<Item>] store damaged target to avoid hitting same dreadnought multiple times in the same shoot
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback result [Object] an object describe shoot result
  # @param center [Object] for weapons with zone effect, store "damages", and "x" + "y" coordinate of center tile
  _applyDamage: (actor, target, damages, effects, hitten, callback, center = null) =>
    # is a target is a part, apply damages on the main object
    if target.main?
      return target.main.fetch (err, target) =>
        return callback err if err?
        @_applyDamage actor, target, damages, effects, hitten, callback, center
        
    # evaluate damages: if any part is at center, use center damages
    if center? and target.parts?
      damages = center.damages for part in target.parts when part.x is center.x and part.y is center.y
        
    # abort if target was already hitten in that shoot
    if _.any(hitten, (hit) -> hit.equals target)
      return callback null, null
    hitten.push target
      
    result = {
      at: {x: target.x, y: target.y}
      from: {x: actor.x, y: actor.y}
      loss: 0
      dead: false
      damages: damages
      kind: 'shoot'
    }
    
    # apply damages on target
    if damages > target.armor
      effects.push makeState target, 'life', 'dead', 'weapons'
      @saved.push target unless target in @saved
      points = damages-target.armor
      result.loss = if target.life >= points then points else target.life
      target.life -= result.loss
      
    # dreadnought specific case: arbitrary remove an heavy weapon
    damageDreadnought target, result.loss
    
    return callback null, result unless target.life is 0
      
    # target is dead !
    result.dead = true
    # add points to actor and removes points from target
    countPoints actor, target, @, (err) => 
      return callback err if err?
      removeFromMap target, @, (err) =>
        callback err, result
      
module.exports = new ShootRule 'attack'