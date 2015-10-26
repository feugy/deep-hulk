_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ItemType = require 'hyperion/model/ItemType'
{useTwist} = require './common'
{alienCapacities, moveCapacities} = require './constants'

# "AlienSpecialForces" twist rule: add two random reinforcements
class AlienSpecialForcesRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist is 'alienSpecialForces'
      return callback null, null 
    callback null, []

  # Add two more reinforcement in squad.
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
    console.log "applied twist #{twist}"
     
    # cannot spawn genestealer or dreadnought
    kinds = (kind for kind of alienCapacities when not (kind in ['genestealer', 'dreadnought']))
    # get Alien item type
    ItemType.findCached ['alien'], (err, [Alien]) =>
      return callback err if err?
      for i in [0...2]
        # random kind !
        kind = kinds[Math.floor Math.random()*kinds.length]
        # creates alien as reinforcement
        alien = new Item _.extend {}, alienCapacities[kind],
          type: Alien
          kind: kind
          imageNum: 0
          revealed: false
          moves: moveCapacities.blip
          squad: squad
          isSupport: true
        
        @saved.push alien
        console.log "create special alien force #{alien.kind}"
        squad.members.push alien
        
      useTwist twist, game, squad, [], @, callback
  
module.exports = new AlienSpecialForcesRule 'twists'