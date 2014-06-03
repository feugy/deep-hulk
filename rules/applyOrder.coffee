_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
{heavyWeapons} = require './constants'
{addAction, makeState} = require './common'

# Apply an order at turn start
class ApplyOrderRule extends Rule

  # Only applies on squad and one of its marine.
  # Ask for a possible order within squad available orders
  # 
  # @param actor [Item] the concerned squad
  # @param marine [Item] the concerned marine
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (squad, marine, context, callback) =>
    # inhibit if waiting for deployment or other squad
    unless squad.type.id is 'squad' and marine.type?.id is 'marine' and 
        not squad.waitTwist and marine in squad.members and squad.orders?.length > 0 and squad.firstAction
      return callback null, null 
    callback null, [
      name: 'order'
      type: 'string'
      within: squad.orders
    ]

  # Apply the order on the squad (or possibly the selected marine).
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array of awaited parametes: equipment choosen.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (squad, marine, {order}, context, callback) =>
    log = 
      id: squad.id
      name: squad.name
      kind: 'order'
      used: order
    message = order
    
    switch order
      when 'fireAtWill'
        # double shoots
        for member in squad.members when not member.dead
          member.rcNum *= 2
      when 'goGoGo'
        # double moves
        for member in squad.members when not member.dead
          member.moves *= 2
      when 'bySections'
        # double moves and shoot and store as equipment to be restricted further
        for member in squad.members when not member.dead
          member.moves *= 2
          member.rcNum *= 2
          member.equipment.push order
      when 'heavyWeapon'
        # check that marine isn't dead and has heavy weapon, and double moves and shoots
        return callback new Error "notHeavyWeapon #{marine.name}" unless not marine.dead and marine.weapons[0].id in heavyWeapons
        marine.moves *= 2
        marine.rcNum *= 2
        order.marine = marine.id
      when 'photonGrenade', 'toDeath'
        # photonGrenade and toDeath are stored as equipement to be applied further
        for member in squad.members when not member.dead
          member.equipment.push order
      else
        # unknown order ?!
        message = null
    
    # removes from inventory
    squad.orders.splice squad.orders.indexOf(order), 1
    squad.firstAction = false
    
    # add in history for replay and other players
    effects = [makeState squad.game, 'events']
    squad.game.events.push log
    addAction 'order', squad, effects, @, (err) => callback err, message
  
module.exports = new ApplyOrderRule()