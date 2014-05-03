_ = require 'underscore'
utils = require 'hyperion/util/model'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
Field = require 'hyperion/model/Field'
ItemType = require 'hyperion/model/ItemType'
{rollDices, selectItemWithin, countPoints, sum, 
distance, removeFromMap, addAction, hasSharedPosition, 
damageDreadnought, logResult, checkMission} = require './common'
{isTargetable} = require './visibility'
{moveCapacities} = require './constants'
                  
# Sum elements of an array
#
# @param arr [Array<Number>] numbers to sum
# @return the sum of array elements
sum = (arr) =>
  _.reduce arr, ((memo, num) => memo+num), 0
            
# Compute the current close range capacity of a given character, taking into account its equipment
# Equiped melta bomb will be removed
# If other attackant has assault blad e equiped, remove a dice
#
# @param actor [Item] marine or alien for which cc is computed
# @patam other [Item] opponent in this assault
# @return the close range capacity used
computeCc = (actor, other) ->
  result = {}
  _.extend result, actor.weapons[0]?.cc or {}
  
  if actor.equipment? and 'pistolBolters' in actor.equipment
    result.w = (result.w or 0) + 1
  if actor.equipment? and 'meltaBomb' in actor.equipment
    console.log "#{actor.name or actor.kind} (#{actor.squad.name}) uses melta bomb"
    result.r = (result.r or 0) + 2
    # can only be used once
    actor.equipment.splice actor.equipment.indexOf('meltaBomb'), 1
  if other.equipment? and ('toDeath' in other.equipment or ('assaultBlades' in other.equipment and other.x isnt actor.x and other.y isnt actor.y))
    # malus if other has assault blade and in diagonal
    # malus if other has toDeath special equipment
    if result.w > 1
      result.w--
    else if result.r > 1
      result.r--
  result
  
# Marine ranged attack
# Effect depends on the equiped weapon
class AssaultRule extends Rule

  # Assault allowed if actor can reach its target
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] empty parameter array, or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    # inhibit if waiting for deployment or other squad
    if actor.squad?.deployZone? or actor.squad?.activeSquad? and actor.squad.activeSquad isnt actor.squad.name
      return callback null, null 
    # deny if actor cannot attack anymore. 
    return callback null, null unless not actor.dead and actor.ccNum >= 1 and actor.weapons[0].cc?
    # deny unless target is an item
    return callback null, null unless target?.type?.id in ['alien', 'marine']
    # check visibility
    isTargetable actor, target, 0, (err, reachable) =>
      return callback err, null if err? or reachable is null
      isDreadnought = actor.kind is 'dreadnought' and actor.revealed
      # if actor is dreadnought, all part must be tested
      candidates = [actor]
      candidates = candidates.concat actor.parts if isDreadnought
      reachable = false
      hasBlade = actor.equipment? and 'assaultBlades' in actor.equipment
      # target must be at distance 1 and not on diagonal (unless having assault blades)
      for candidate in candidates when 1 is distance(candidate, target) and hasBlade or (target.x is candidate.x or target.y is candidate.y)
        reachable = true 
        break
      callback null, if reachable then [] else null

  # Resolve shoot damaged and apply them on targeted items
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback results [Array] damages for each concerned targets:
  # - x [Number] the target x coordinate
  # - y [Number] the target x coordinate
  # - damages [Number] attack strength
  # - loss [Number] number of life point lost
  # - dead [Boolean] true if target doed
  execute: (actor, target, params, context, callback) =>
    isDreadnought = actor.kind is 'dreadnought' and actor.revealed
  
    # Process assault resolution on given target
    process = (target) =>
      # get fields above attackers to check base
      Field.where('mapId', actor.map.id).where('x').in([actor.x, target.x]).where('y').in([actor.y, target.y]).exec (err, fields) =>
        return callback err if err?
        # deny assault if target or actor is in base
        return callback null, null if _.find(fields, (f) -> f.x is actor.x and f.y is actor.y).typeId[0..4] is 'base-'
        return callback null, null if _.find(fields, (f) -> f.x is target.x and f.y is target.y).typeId[0..4] is 'base-'
        
        # get near items to check shared position
        selectItemWithin actor.map.id, actor, {x:actor.x+1, y:actor.y+1}, (err, items) =>
          # abort if sharing tile with a squadmate
          return callback new Error "sharedPosition" if hasSharedPosition(items)
          # for dreadnought, abort if under a door
          return callback new Error "underDoor" if isDreadnought and actor.underDoor
    
          # action history
          effects = [
            [actor, _.pick actor, 'ccNum', 'rcNum', 'moves', 'life', 'dead', 'usedWeapons', 'log']
            [target, _.pick target, 'life', 'dead', 'log']
          ]
    
          # consume an attack
          actor.ccNum--
          # consume an attack if all weapons were used
          actor.rcNum-- unless actor.rcNum is 0 or actor.equipment? and 'toDeath' in actor.equipment
          actor.usedWeapons = []
          actor.squad.actions--
          actor.squad.firstAction = false
          # consume remaining moves if a move is in progress
          if 0 < actor.moves < moveCapacities[actor.weapons[0].id]
            actor.moves = 0 
            actor.squad.actions--
          # removes special equipment once used
          if actor.equipment? and 'toDeath' in actor.equipment
            actor.equipment.splice actor.equipment.indexOf('toDeath'), 1
          
          # roll dices for both actor and target, always take first weapon for close combat
          actorAttack = sum rollDices computeCc(actor, target), _.any actor.equipment, (equip) -> equip in ['digitalWeapons', 'bionicArm']
          targetAttack = sum rollDices computeCc(target, actor), _.any target.equipment, (equip) -> equip in ['digitalWeapons', 'bionicArm']
          console.log "#{actor.name or actor.kind} (#{actor.squad.name}) assault "+
            "#{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: "+
            "#{actorAttack} vs #{targetAttack}"
              
          # attack equality: it's a draw
          resultActor = 
            at: {x: actor.x, y: actor.y}
            loss: 0
            dead: false
            damages: targetAttack
            kind: 'assault'
          
          resultTarget = 
            at: {x: target.x, y: target.y}
            loss: 0
            dead: false
            damages: actorAttack
            kind: 'assault'
          
          end = (err, results) =>
            return callback err if err?
            logResult actor, resultActor
            logResult target, resultTarget
            addAction 'assault', actor, effects, @, (err) =>
              callback err, results
              
          if actorAttack is targetAttack
            # it's a draw
            return end null, [resultActor, resultTarget]
          else
            # wound is for the lowest attack
            if actorAttack < targetAttack
              wounded = actor
              winner = target
              result = resultActor
            else 
              wounded = target
              winner = actor
              result = resultTarget
              
            diff = Math.abs actorAttack-targetAttack
            result.loss = if wounded.life >= diff then diff else wounded.life
            wounded.life -= result.loss
            console.log "#{wounded.name or wounded.kind} (#{wounded.squad.name}) wounded !"
                  
            # dreadnought specific case: arbitrary remove an heavy weapon
            damageDreadnought wounded, result.loss
        
            unless wounded.life is 0
              return end null, [resultActor, resultTarget]
            
            # mortal wound !
            result.dead = true
            console.log "#{wounded.name or wounded.kind} (#{wounded.squad.name}) died !!"
            
            countPoints winner, wounded, @, (err) => 
              return end err if err?
              checkMission winner.squad, 'attack', @, [target: wounded, result:result], (err) =>
                return end err if err?
                removeFromMap wounded, @, (err) =>
                  end err, [resultActor, resultTarget]
    
    # is a target is a part, apply damages on the main object
    if target.main?
      return target.main.fetch (err, target) =>
        return callback err if err?
        process target
    # no part: apply on initial target
    process target

module.exports = new AssaultRule 'attack'