_ = require 'underscore'
utils = require 'hyperion/util/model'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{rollDices, selectItemWithin, countPoints, sum, distance, removeFromMap, addAction} = require './common'
{isTargetable} = require './visibility'
{moveCapacities} = require './constants'
                  
# Sum elements of an array
#
# @param arr [Array<Number>] numbers to sum
# @return the sum of array elements
sum = (arr) =>
  _.reduce arr, ((memo, num) => memo+num), 0
          
# loads log entry type
logEntry = null
ItemType.findCached ['logEntry'], (err, classes) => 
  console.error "Failed to load logEntry type from shoot rule: #{err}" if err?
  logEntry = classes[0]
  
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
    # inhibit if wanting for deployment
    return callback null, null if actor.squad?.deployZone?
    # deny if actor cannot attack anymore. 
    return callback null, null unless not actor.dead and actor.ccNum >= 1 and actor.weapon.cc?
    # deny unless target is an item
    return callback null, null unless target?.type?.id in ['alien', 'marine']
    # check visibility
    isTargetable actor, target, (err, reachable) =>
      return callback err if err?
      # check distance and alignement
      if reachable
        reachable = 1 is distance(actor, target) and (target.x is actor.x or target.y is actor.y)
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
    selectItemWithin actor.map.id, actor, actor, (err, items) =>
      items = _.any items, (item) -> item.type.id is actor.type.id and not item.dead
      # abort if sharing tile with a squadmate
      return callback new Error "sharedPosition" if items.length is 2

      # action history
      effects = [
        [actor, _.pick actor, 'id', 'ccNum', 'rcNum', 'moves', 'life', 'dead']
        [target, _.pick target, 'id', 'life', 'dead']
      ]

      # consume an attack
      actor.ccNum--
      actor.rcNum-- if actor.rcNum > 0 
      actor.squad.actions--
      # consume remaining moves if a move is in progress
      unless actor.moves is moveCapacities[actor.weapon.id] or actor.moves is 0
        actor.moves = 0 
        actor.squad.actions--
      
      # roll dices for both actor and target
      actorAttack = sum rollDices actor.weapon.cc
      targetAttack = sum rollDices(target.weapon?.cc) or [0]
      console.log "#{actor.name or actor.kind} (#{actor.squad.name}) assault "+
        "#{target.name or target.kind} (#{target.squad.name}) at #{target.x}:#{target.y}: "+
        "#{actorAttack} vs #{targetAttack}"
        
      end = (err, results) =>
        return callback err if err?
        addAction 'assault', actor, effects, @, (err) =>
          callback err, results
    
      if actorAttack is targetAttack
        # attack equality: it's a draw
        resultActor = new Item
          id: utils.generateId()
          type: logEntry
          x: actor.x
          y: actor.y
          loss: 0
          dead: false
          damages: 0
          map: actor.map
          kind: 'assault'
        effects[0][1].log = actor.log.concat()
        actor.log.push resultActor
        
        resultTarget = new Item
          id: utils.generateId()
          type: logEntry
          x: target.x
          y: target.y
          loss: 0
          dead: false
          damages: 0
          map: target.map
          kind: 'assault'
        effects[1][1].log = target.log.concat()
        target.log.push resultTarget
        @saved.push resultActor, resultTarget
        
        return end null, [resultActor, resultTarget]
      else
        # wound is for the lowest attack
        wounded = if actorAttack < targetAttack then actor else target
        result =new Item
          id: utils.generateId()
          type: logEntry
          x: wounded.x
          y: wounded.y
          loss: 0
          dead: false
          damages: 0
          map: wounded.map
          kind: 'assault'
        effects[if actorAttack < targetAttack then 0 else 1][1].log = wounded.log.concat()
        wounded.log.push result
        @saved.push result
        
        result.damages = Math.abs actorAttack-targetAttack
        result.loss = if wounded.life >= result.damages then result.damages else wounded.life
        wounded.life -= result.loss
        console.log "#{wounded.name or wounded.kind} (#{wounded.squad.name}) wounded !"
        unless wounded.life is 0
          return end null, [result] 
        
        # mortal wound !
        result.dead = true
        winner = if actorAttack > targetAttack then actor else target
        console.log "#{wounded.name or wounded.kind} (#{wounded.squad.name}) died !!"
        
        countPoints winner, wounded, @, (err) => 
          return end err if err?
          removeFromMap wounded, @, (err) =>
            end err, [result]
      
module.exports = new AssaultRule()