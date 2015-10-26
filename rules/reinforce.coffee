_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{selectItemWithin, addAction, makeState} = require './common'
{hasObstacle, findNextDoor} = require './visibility'

# Blip reinforcement rule. Only possible for alien
class ReinforceRule extends Rule

  # Only applies for aliens that have possible reinforcements.
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameters (zone, x, y, and rank), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    return callback null, null unless squad.type?.id is 'squad' and squad.isAlien and squad.supportBlips > 0 and not squad.waitTwist
    # no more reinforcement !
    return callback null, null unless _.filter(squad.members, (m) -> m.isSupport and not m.map?).length
    callback null, [
      # x coordinate for deployement
      name: 'x'
      type: 'integer'
    ,
      # y coordinate for deployement
      name: 'y'
      type: 'integer'
    , 
      # deployed blip within squad members
      name: 'rank'
      type: 'integer'
      min: 0
      max: squad.members.length-1
    ]

  # Checks that the chosen coordinates are within expected tiles, 
  # and that chosen blips is nor visible, not already deployed.
  # If so, deployed the blip.
  #
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, squad, params, context, callback) =>
    # checks that blip is undeployed
    blip = squad.members[params.rank]
    return callback new Error "notReinforcement" if blip.map? or not blip.isSupport
    # get reinforcement tiles
    Item.where('map', squad.map.id).where('type', 'reinforcement').exec (err, tiles) =>
      return callback err if err?
      # check reinforcement position
      return callback new Error "notInZone" unless _.findWhere tiles, x:params.x, y:params.y
      
      # checks that blip will not be visible
      selectItemWithin squad.map.id, (err, items) =>
        return callback err if err?
        for item in items 
          if item?.type?.id is 'marine' and item?.dead is false
            return callback new Error "positionVisible" unless hasObstacle(item, params, items)?
          else if item?.type?.id is 'alien'
            return callback new Error "sharedReinforce" if item.x is params.x and item.y is params.y
        
        # action history
        effects = [makeState blip, 'x', 'y', 'map', 'doorToOpen']
        
        # At last, reinforce blip
        blip.map = squad.map
        blip.x = params.x
        blip.y = params.y
        # cannot move yet
        blip.moves = 0
        blip.rcNum = 0
        blip.ccNum = 0
        blip.usedWeapons = []
        blip.isSupport = false
        
        # decrement reinforcement counter
        squad.supportBlips--
        
        # search for door to open
        blip.doorToOpen = findNextDoor params, items
        
        @saved.push blip
        addAction 'reinforce', blip, effects, @, callback
  
module.exports = new ReinforceRule 'blips'