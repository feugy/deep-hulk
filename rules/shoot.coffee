_ = require 'underscore'
async = require 'async'
utils = require 'hyperion/util/model'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{rollDices, selectItemWithin, sum, countPoints, removeFromMap, addAction, hasSharedPosition, damageDreadnought} = require './common'
{isTargetable, hasObstacle, tilesOnLine, untilWall} = require './visibility'
{moveCapacities} = require './constants'

# Tells wether a given item can be a target or not. 
#
# @param target [Item] the tested item
# @return true if this target is an alien or a marine.
hasTargetType = (target) ->
  target?.type?.id in ['marine', 'alien']
  
# loads log entry type
logEntry = null
ItemType.findCached ['logEntry'], (err, classes) => 
  console.error "Failed to load logEntry type from shoot rule: #{err}" if err?
  logEntry = classes[0]
        
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
    # inhibit if wanting for deployment
    return callback null, null if actor.squad?.deployZone?
    # deny if actor cannot attack anymore, or if target isnt a field
    return callback null, false unless not actor.dead and actor.rcNum >= 1 and target?.mapId?
    callback null, [name: 'weaponIdx', type:'integer', min: 0, max: actor.weapons.length-1]

  # Resolve shoot damaged and apply them on targeted tiles
  #
  # @param actor [Item] the concerned actor
  # @param target [Field] the concerned field
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback results [Array] for each target hit: a logEntry item
  execute: (actor, target, params, context, callback) =>
    # get near items to check shared position
    selectItemWithin actor.map.id, actor, {x:actor.x+1, y:actor.y+1}, (err, items) =>
      return callback err, null if err?
      # abort if sharing tile with a squadmate
      return callback new Error "sharedPosition" if hasSharedPosition items
      # check that selected weapon as range combat
      weapon = actor.weapons[params.weaponIdx]
      return callback 'closeCombatWeapon', null unless weapon?.rc?
      # check that this weapon was not already used
      used = JSON.parse actor.usedWeapons
      return callback 'alreadyUsed', null if params.weaponIdx in used
      # now check visibility 
      isTargetable actor, target, params.weaponIdx, (err, reachable) =>
        return callback err, null if err?
        # silentely stop if not reachable with this weapon
        return callback null, null unless reachable?
       
        # action history
        effects = [[actor, _.pick actor, 'id', 'ccNum', 'rcNum', 'moves', 'usedWeapons']]
        effects[0][1].log = actor.log.concat()
        
        end = (err, results) =>
          return callback err if err?
          addAction 'shoot', actor, effects, @, (err) =>
            callback err, results
   
        # get used weapons to store this new one
        used.push params.weaponIdx
        # consume an attack if all weapons were used
        if used.length is actor.weapons.length
          actor.rcNum--
          used = []
          actor.squad.actions--
        actor.ccNum-- if actor.ccNum > 0 
        actor.usedWeapons = JSON.stringify used
        
        # consume remaining moves if a move is in progress
        unless actor.moves is moveCapacities[weapon.id] or actor.moves is 0
          actor.moves = 0
          actor.squad.actions--
          
        # roll dices
        dices = rollDices weapon.rc
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
              async.each targets, (t, next) =>
                t.fetch (err, t) =>
                  return next err if err?
                  return next() if not hasTargetType(t) or hasObstacle(target, t, targets)?
                  damages = if t.x is target.x and t.y is target.y then center else around 
                  console.log "hit on target #{t.name or t.kind} (#{t.squad.name or 'alien'}) at #{t.x}:#{t.y}: #{damages}"
                  @_applyDamage actor, t, damages, effects, (err, result) =>
                    results.push result
                    next err
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
              async.each positions, (pos, next) =>
                # and find potential target at position
                target = _.find items, (item) -> item.x is pos.x and item.y is pos.y and hasTargetType item
                return next() unless target? and not reachable.equals target
                target.fetch (err, target) =>
                  return next err if err?
                  console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: #{damages}"
                  @_applyDamage actor, target, damages, effects, (err, result) =>
                    results.push result
                    next err
              , (err) =>
                end err, results 
                
          when 'autoCannon'
            # multiple target allowed: extract them from actor
            targets = []
            if actor.currentTargets?
              targets = (x:parseInt(coord[0...coord.indexOf ':']), y:parseInt(coord[coord.indexOf(':')+1..]) for coord in actor.currentTargets.split ',')
            # add the target to list of current targets, unless already present
            targets.push x:target.x, y:target.y if not actor.currentTargets? or -1 is actor.currentTargets.indexOf "#{target.x}:#{target.y}"
            actor.currentTargets = null
            results = []
            
            # split damages on selected target, keeping the order
            damages = sum dices
            allocateDamages = () =>
              # quit when no target remains
              return end null, results unless targets.length > 0
              # select the first remaining target
              selectItemWithin actor.map.id, targets.splice(0, 1)[0], (err, targets) =>
                return end err if err?
                target = _.find targets, hasTargetType
                # no character found: proceed next target
                return allocateDamages() unless target?
                target.fetch (err, target) =>
                  return end err if err?
                  @_applyDamage actor, target, damages, effects, (err, result) =>
                    return end err if err?
                    if target.life is 0
                      # target terminated: allocate remaining damages to next
                      result.damages = target.armor+result.loss
                      console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: #{result.damages}"
                      damages -= result.damages
                    else if result.loss > 0
                      # target wounded: no more damages to allocate
                      console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: #{target.armor+result.loss}"
                      damages = 0
                    else if targets.length > 0
                      # no wound and remaining target: consider we never aim at this one
                      result.damages = 0
                    else
                      # no wond and last target
                      console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: #{damages}"
                      
                    # process next target
                    results.push result
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
                console.log "hit on target #{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: #{damages}"
                @_applyDamage actor, target, damages, effects, (err, result) =>
                  end err, [result]
      
  # Apply given damages on a target
  # Will remove target if dead, and make points computations
  #
  # @param actor [Item] the shooting actor
  # @param target [Item] the hitten target
  # @param damage [Number] damage performed by actor's weapon
  # @param effects [Array<Array>] for each modified model, an array with the modified object at first index
  # and an object containin modified attributes and their previous values at second index (must at least contain id).
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback result [Object] a logEntry item
  _applyDamage: (actor, target, damages, effects, callback) =>
    # is a target is a part, apply damages on the main object
    if target.main?
      return target.main.fetch (err, target) =>
        return callback err if err?
        @_applyDamage actor, target, damages, effects, callback
        
    result = new Item
      id: utils.generateId()
      type: logEntry
      x: target.x
      y: target.y
      fx: actor.x
      fy: actor.y
      loss: 0
      dead: false
      damages: damages
      map: actor.map
      kind: 'shoot'
    @saved.push result
    actor.log.push result
    
    # apply damages on target
    if damages > target.armor
      effects.push [target, _.pick target, 'id', 'life', 'dead', 'weapons']
      @saved.push target unless target in @saved
      points = damages-target.armor
      result.loss = if target.life >= points then points else target.life
      target.life -= result.loss
      console.log "#{target.name or target.kind} (#{target.squad.name}) hit by #{result.loss} !"
      
    # dreadnought specific case: arbitrary remove an heavy weapon
    damageDreadnought target, result.loss
    
    return callback null, result unless target.life is 0
    # target is dead !
    result.dead = true
    # add points to actor and removes points from target
    countPoints actor, target, @, (err) => 
      return callback err if err?
      removeFromMap target, @, (err) =>
        console.log "#{target.name or target.kind} (#{target.squad.name}) died !!"
        callback err, result
      
module.exports = new ShootRule 'shoot'