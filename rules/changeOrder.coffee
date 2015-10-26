_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
{useTwist} = require './common'
{orders} = require './constants'

# "combatPlan", "newOrder" twist rule: marine players must change (or add) one of their orders
# Used by both Alien to choose a victim (newOrder) and marines to set their new order
class ChangeOrderRule extends Rule

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
    return callback null, null unless squad.waitTwist and squad.twist in ['newOrder', 'combatPlan']
      
    if squad.isAlien
      # choose a victim within marine squads that do not have all their orders
      callback null, if squad.twist is 'combatPlan' then [] else [
        name: 'squad'
        type: 'string'
        within: (other.name for other in game.squads when not other.isAlien and other.orders.length < 4)
      ]
    else 
      # choose another order
      params = []
      if squad.twist is 'combatPlan'
        params.push 
          name: 'removedOrder'
          type: 'string'
          within: squad.orders
          
      params.push
        name: 'selectedOrder'
        type: 'string'
        within: _.difference orders[squad.name], squad.orders
      callback null, params

  # For combatPlan, all marines that do not have 4 orders must choose another one
  # For newOrder, only a single selected marine must pick an additionnal order.
  #
  # For marines, just add or replace an order.
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
    if squad.isAlien
      # for alien, indicates to marines that they must change (or add) an order
      console.log "applied twist #{twist}"
      concerned = squad
      for other in game.squads
        # release unconcerned squad
        other.waitTwist = false
        # for marine squad that is elligible to change
        if not other.isAlien and other.orders.length < 4 and (not params.squad? or other.name is params.squad)
          console.log "#{other.name} affected by #{twist}"
          other.twist = twist
          # still waiting
          other.waitTwist = true
          concerned = other if other.name is params.squad
          
      return useTwist twist, game, concerned, [], @, false, callback
    
    else
      # for marines, change or add selected order
      if params.removedOrder?
        console.log "removes order #{params.removedOrder} from #{squad.name}"
        squad.orders.splice squad.orders.indexOf(params.removedOrder), 1
      # add new order and release from waiting
      squad.orders.push params.selectedOrder
      squad.waitTwist = false
      squad.twist = null
      console.log "add new order #{params.selectedOrder} to #{squad.name}"
      callback null, 'ordersChanged'
      
module.exports = new ChangeOrderRule 'twists'