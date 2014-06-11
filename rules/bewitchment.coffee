_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{useTwist, rollDices, removeFromMap, makeState} = require './common'
{alienCapacities, moveCapacities} = require './constants'

# "bewitchment" twist rule: for selected marine, try to corrupt it to a chaos marine
class BewitchmentRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist is 'bewitchment'
      return callback null, null 
      
    # select living marines that are not commander on the map
    Item.where('map', squad.map.id).where('type', 'marine')
        .where('dead', false).where('isCommander', false).exec (err, marines) =>
      return callback err if err?
      params = []

      if marines.length > 0
        params.push
          name: 'target'
          type: 'object'
          within: marines
      return callback null, params

  # Throw a red dice, on a 3, replace target marine by a chaos marine with bolter
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
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

    # fetch marine target and its squad
    Item.findCached [params.target], (err, [target]) =>
      err = new Error "No marine with id #{params.target}" if not err? and not target?
      return callback err if err?
      Item.findCached [target.squad], (err, [targetSquad]) =>
        return callback err if err?
        
        # corruption failed... 
        unless rollDices(r:1) >= 3 
          console.log "applied twist #{twist} on #{target.name} (#{targetSquad.name}) but failed"
          return useTwist twist, game, targetSquad, [], @, callback
        
        console.log "applied twist #{twist} on #{target.name} (#{targetSquad.name}) with success"
              
        # place a new chaos marine instead
        ItemType.findCached ['alien'], (err, [Alien]) =>
          return callback err if err?
          
          # creates alien, in two phase to have an history entry
          kind = 'chaosMarine'
          alien = new Item 
            type: Alien
            squad: squad
            kind: kind
            revealed: true
            dead: true
            imageNum: null
            rcNum: 1
            ccNum: 1
            moves: moveCapacities[kind]
          
          effects = [makeState(alien, 'imageNum', 'map', 'x', 'y', 'dead'), makeState target, 'dead', 'life']
        
          # now reveal and place at right position
          alien.dead = false
          alien[prop] = val for prop, val of alienCapacities[kind]
          alien[prop] = val for prop, val of _.pick target, 'map', 'x', 'y', 'doorToOpen'
            
          @saved.push alien
          squad.members.push alien
          # and make marine die, without changing any points.
          removeFromMap target, @, (err) =>
            return callback err if err?
            useTwist twist, game, targetSquad, effects, @, callback
   
module.exports = new BewitchmentRule 'twists'